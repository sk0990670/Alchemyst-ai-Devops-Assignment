###############################################################################
# security.tf
# Security Groups (= AWS firewall rules)
#
# Design:
#  - api-sg (caller VM)       → SSH from your IP only, port 3111 from internet
#  - inference-sg (model VM)  → SSH only from caller VM, RPC port 49134 only
#                                from caller VM. ZERO public internet inbound.
###############################################################################

###############################################################################
# Security Group — Caller Worker / API Gateway VM (public subnet)
###############################################################################
resource "aws_security_group" "api_gateway" {
  name        = "${var.project_name}-api-sg"
  description = "Caller-worker (API gateway): allow HTTP API + SSH from admin"
  vpc_id      = aws_vpc.main.id

  # ── Inbound ──────────────────────────────────────────────────────────────

  # SSH — only your machine can reach it
  ingress {
    description = "SSH from admin IP"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.your_ip_cidr]
  }

  # RPC/WebSocket from inference VM — so inference-worker can register
  # its functions with the caller's iii engine
  ingress {
    description = "iii RPC WebSocket from inference VM (private subnet)"
    from_port   = var.iii_ws_port
    to_port     = var.iii_ws_port
    protocol    = "tcp"
    cidr_blocks = [var.private_subnet_cidr]
  }

  # HTTP API — port 3111 open to the world (this is the public endpoint)
  ingress {
    description      = "iii HTTP API (POST /v1/chat/completions)"
    from_port        = var.iii_http_port
    to_port          = var.iii_http_port
    protocol         = "tcp"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # ── Outbound ─────────────────────────────────────────────────────────────
  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-api-sg"
    Role = "api-gateway"
  })
}

###############################################################################
# Security Group — Inference Worker VM (private subnet)
###############################################################################
resource "aws_security_group" "inference" {
  name        = "${var.project_name}-inference-sg"
  description = "Inference-worker: RPC only from caller VM, SSH only from caller VM"
  vpc_id      = aws_vpc.main.id

  # ── Inbound ──────────────────────────────────────────────────────────────

  # SSH — only from the caller/API VM (use it as a bastion/jump host)
  ingress {
    description     = "SSH via caller VM (bastion)"
    from_port       = 22
    to_port         = 22
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # RPC WebSocket — ONLY from the caller VM's security group
  # This is how caller-worker calls inference::run_inference
  ingress {
    description     = "iii RPC/WebSocket from caller-worker only"
    from_port       = var.iii_ws_port
    to_port         = var.iii_ws_port
    protocol        = "tcp"
    security_groups = [aws_security_group.api_gateway.id]
  }

  # ── Outbound ─────────────────────────────────────────────────────────────
  # Needed so the private VM can:
  #   - pip install (via NAT Gateway → internet)
  #   - download Gemma GGUF model from HuggingFace
  egress {
    description = "Allow all outbound (through NAT gateway)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-inference-sg"
    Role = "inference"
  })
}
