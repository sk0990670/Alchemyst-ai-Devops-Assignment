###############################################################################
# instances.tf
# EC2 instances:
#   1. caller-vm    → public subnet,  t3.micro,  runs TypeScript caller-worker
#   2. inference-vm → private subnet, t3.medium, runs Python inference-worker
#
# Each VM is bootstrapped via a user_data shell script that:
#   - Installs required runtimes (Node.js / Python)
#   - Installs the iii CLI
#   - Clones the repo
#   - Installs worker dependencies
#   - Creates a systemd service so the worker starts on boot
###############################################################################

###############################################################################
# Caller Worker VM  (public subnet — API gateway)
###############################################################################
resource "aws_instance" "caller" {
  ami                         = var.ami_id
  instance_type               = var.caller_instance_type
  subnet_id                   = aws_subnet.public.id
  vpc_security_group_ids      = [aws_security_group.api_gateway.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = true

  # 20 GB root disk — enough for Node deps
  root_block_device {
    volume_size           = 20
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  # Bootstrap script runs once on first boot
  user_data = templatefile(
    "${path.module}/user_data/caller_setup.sh",
    {
      inference_private_ip = aws_instance.inference.private_ip
      iii_ws_port          = var.iii_ws_port
      iii_http_port        = var.iii_http_port
    }
  )

  # Ensure inference VM exists first so we have its private IP
  depends_on = [
    aws_instance.inference,
    aws_nat_gateway.nat,
  ]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-caller-vm"
    Role = "api-gateway"
  })
}

###############################################################################
# Inference Worker VM  (private subnet — model host)
###############################################################################
resource "aws_instance" "inference" {
  ami                         = var.ami_id
  instance_type               = var.inference_instance_type
  subnet_id                   = aws_subnet.private.id
  vpc_security_group_ids      = [aws_security_group.inference.id]
  key_name                    = var.key_pair_name
  associate_public_ip_address = false   # NO public IP — lives in private subnet

  # 30 GB root disk — Gemma GGUF model is ~270 MB, plus Python/torch deps (~5 GB)
  root_block_device {
    volume_size           = 30
    volume_type           = "gp3"
    delete_on_termination = true
    encrypted             = true
  }

  user_data = templatefile(
    "${path.module}/user_data/inference_setup.sh",
    {
      iii_ws_port = var.iii_ws_port
    }
  )

  depends_on = [aws_nat_gateway.nat]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-inference-vm"
    Role = "inference"
  })
}
