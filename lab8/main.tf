# Lab 8: a small web host in the default VPC, fixed after the Task 2 scan.
#  - SSH only from one /32 (var.admin_cidr; the default is a documentation address, because this
#    repository is public and my own IP doesn't belong in it)
#  - root volume encrypted, IMDSv2 required
#  - exactly one suppression: the outbound HTTPS rule (reasons at the rule)
# Plan only: nothing in lab8 is ever applied. tfsec reads the variable's default below; it does not
# load terraform.tfvars and cannot see -var, so the default is what the gate checks.
terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course    = "ACS730"
      Lab       = "lab8"
      ManagedBy = "terraform"
    }
  }
}

variable "admin_cidr" {
  description = "The single address allowed to SSH in, as a /32"
  type        = string
  default     = "203.0.113.10/32" # TEST-NET-3 documentation address, a stand-in for the admin's IP

  # Checked at plan time, not by terraform validate
  validation {
    condition     = can(cidrhost(var.admin_cidr, 0)) && endswith(var.admin_cidr, "/32")
    error_message = "admin_cidr must be a single IPv4 address in CIDR form, ending in /32."
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

resource "aws_security_group" "web" {
  name        = "acs730-lab8-sg"
  description = "ACS730 lab8 web host"
  vpc_id      = data.aws_vpc.default.id

  tags = { Name = "acs730-lab8-sg" }
}

# FIXED: SSH from one administrator address only
resource "aws_security_group_rule" "ssh_in" {
  type              = "ingress"
  description       = "SSH from the single admin address only"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = [var.admin_cidr]
  security_group_id = aws_security_group.web.id
}

# Accepted risk - author: jhui26-seneca, date: 2026-11-12, review by: 2026-12-31.
# Rule aws-ec2-no-public-egress-sgr (CRITICAL). The host must reach the Amazon Linux package
# repositories and the SSM endpoints, which have no fixed address range, so HTTPS (443) out to
# 0.0.0.0/0 stays. Only 443 is open, and only outbound: nothing on the internet can start a
# connection to the host through this rule. Production would use VPC endpoints or an egress proxy.
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group_rule" "https_out" {
  type              = "egress"
  description       = "HTTPS out for dnf package updates and the SSM agent"
  from_port         = 443
  to_port           = 443
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  vpc_security_group_ids = [aws_security_group.web.id]

  # FIXED: the root volume is encrypted at rest
  root_block_device {
    encrypted = true
  }

  # FIXED: IMDSv2 only (session tokens required)
  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required"
  }

  tags = { Name = "acs730-lab8-web" }
}
