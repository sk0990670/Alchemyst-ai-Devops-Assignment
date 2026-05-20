###############################################################################
# main.tf
# AWS Provider + Networking:
#   - VPC
#   - Public subnet  (caller-worker / API gateway VM lives here)
#   - Private subnet (inference-worker VM lives here)
#   - Internet Gateway  → routes public subnet to internet
#   - Elastic IP + NAT Gateway → lets private subnet reach internet (for installs)
#     but blocks all inbound from internet
#   - Route tables wired to the above
###############################################################################

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

###############################################################################
# Data — pick the first available AZ in the selected region
###############################################################################
data "aws_availability_zones" "available" {
  state = "available"
}

###############################################################################
# VPC
###############################################################################
resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-vpc"
  })
}

###############################################################################
# Subnets
###############################################################################

# Public subnet — caller-worker (API gateway) lives here; gets a public IP
resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = var.public_subnet_cidr
  availability_zone       = data.aws_availability_zones.available.names[0]
  map_public_ip_on_launch = true

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-subnet"
    Tier = "public"
  })
}

# Private subnet — inference-worker lives here; NO public IP, no direct internet
resource "aws_subnet" "private" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = var.private_subnet_cidr
  availability_zone = data.aws_availability_zones.available.names[0]

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-subnet"
    Tier = "private"
  })
}

###############################################################################
# Internet Gateway — gives the public subnet internet access
###############################################################################
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-igw"
  })
}

###############################################################################
# NAT Gateway — lets the private subnet reach the internet (for pip installs,
# apt, model downloads) WITHOUT being reachable from the internet
###############################################################################

# NAT needs a static public IP (Elastic IP)
resource "aws_eip" "nat" {
  domain = "vpc"

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-eip"
  })

  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat.id
  subnet_id     = aws_subnet.public.id   # NAT GW itself sits in the public subnet

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-nat-gw"
  })

  depends_on = [aws_internet_gateway.igw]
}

###############################################################################
# Route Tables
###############################################################################

# --- Public route table: 0.0.0.0/0 → Internet Gateway ---
resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-public-rt"
  })
}

resource "aws_route_table_association" "public" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

# --- Private route table: 0.0.0.0/0 → NAT Gateway ---
resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block     = "0.0.0.0/0"
    nat_gateway_id = aws_nat_gateway.nat.id
  }

  tags = merge(var.common_tags, {
    Name = "${var.project_name}-private-rt"
  })
}

resource "aws_route_table_association" "private" {
  subnet_id      = aws_subnet.private.id
  route_table_id = aws_route_table.private.id
}
