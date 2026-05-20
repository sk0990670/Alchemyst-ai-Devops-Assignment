###############################################################################
# outputs.tf
# Values printed after `terraform apply` so you know where everything is.
###############################################################################

output "caller_public_ip" {
  description = "Public IP of the API gateway (caller-worker) VM"
  value       = aws_instance.caller.public_ip
}

output "caller_public_dns" {
  description = "Public DNS hostname of the caller-worker VM"
  value       = aws_instance.caller.public_dns
}

output "inference_private_ip" {
  description = "Private IP of the inference-worker VM (only reachable inside the VPC)"
  value       = aws_instance.inference.private_ip
}

output "api_endpoint" {
  description = "Full URL of the JSON inference API"
  value       = "http://${aws_instance.caller.public_ip}:3111/v1/chat/completions"
}

output "curl_example" {
  description = "Ready-to-run curl command to test the API"
  value       = <<-EOT
    curl -X POST http://${aws_instance.caller.public_ip}:3111/v1/chat/completions \
      -H "Content-Type: application/json" \
      -d '{
        "messages": [
          {"role": "user", "content": "What is 2 + 2?"}
        ]
      }'
  EOT
}

output "ssh_caller_vm" {
  description = "SSH command to connect to the caller VM"
  value       = "ssh -i Batch12.pem ubuntu@${aws_instance.caller.public_ip}"
}

output "ssh_inference_vm" {
  description = "SSH command to connect to the inference VM (via caller VM as jump host)"
  value       = "ssh -i Batch12.pem -J ubuntu@${aws_instance.caller.public_ip} ubuntu@${aws_instance.inference.private_ip}"
}

output "vpc_id" {
  description = "VPC ID"
  value       = aws_vpc.main.id
}
