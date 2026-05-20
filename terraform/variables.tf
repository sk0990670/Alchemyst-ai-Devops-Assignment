###############################################################################
# variables.tf
# All tuneable knobs in one place. Override via terraform.tfvars or -var flags.
###############################################################################

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-south-1"
}

variable "project_name" {
  description = "Prefix used in all resource names and tags"
  type        = string
  default     = "devops-iii"
}

variable "common_tags" {
  description = "Tags applied to every resource"
  type        = map(string)
  default = {
    Project     = "devops-iii-assignment"
    Environment = "dev"
    ManagedBy   = "terraform"
  }
}

###############################################################################
# Networking
###############################################################################
variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string
  default     = "10.0.0.0/16"
}

variable "public_subnet_cidr" {
  description = "CIDR for the public subnet (caller-worker / API gateway)"
  type        = string
  default     = "10.0.1.0/24"
}

variable "private_subnet_cidr" {
  description = "CIDR for the private subnet (inference-worker)"
  type        = string
  default     = "10.0.2.0/24"
}

###############################################################################
# EC2
###############################################################################
variable "ami_id" {
  description = "Ubuntu 22.04 LTS AMI ID. Defaults to us-east-1 value. Change if using another region."
  type        = string
  default     = "ami-0f58b397bc5c1f2e8"   # Ubuntu 22.04 LTS — ap-south-1 (Mumbai)
}

variable "caller_instance_type" {
  description = "EC2 instance type for the caller-worker (API gateway)"
  type        = string
  default     = "t3.micro"      # 1GB RAM — fine for TypeScript caller worker   # free-tier eligible
}

variable "inference_instance_type" {
  description = "EC2 instance type for the inference-worker (needs ≥ 4 GB RAM for Gemma)"
  type        = string
  default     = "c7i-flex.large"  # 4GB RAM — safe headroom for Gemma GGUF + torch
}

variable "key_pair_name" {
  description = "Name of an existing EC2 Key Pair to SSH into instances"
  type        = string
  # No default — you MUST supply this. Create one with:
  #   aws ec2 create-key-pair --key-name devops-key --query 'KeyMaterial' --output text > devops-key.pem
}

variable "your_ip_cidr" {
  description = "Your local public IP in CIDR notation for SSH access (e.g. 203.0.113.42/32)"
  type        = string
  # No default — fill in terraform.tfvars. Find your IP at: https://checkip.amazonaws.com
}

###############################################################################
# iii engine / workers
###############################################################################
variable "iii_http_port" {
  description = "HTTP port the iii engine listens on (for POST /v1/chat/completions)"
  type        = number
  default     = 3111
}

variable "iii_ws_port" {
  description = "WebSocket/RPC port the iii engine uses for inter-worker communication"
  type        = number
  default     = 49134
}
