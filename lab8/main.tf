# Lab 8: a small web host in the default VPC.
# DELIBERATELY BROKEN (Task 2): SSH is open to the whole internet, the root volume is not
# encrypted, and IMDSv1 is allowed. This version exists only to be scanned; it is replaced by the
# fixed version on the same branch before merging. Plan only: nothing in lab8 is ever applied.
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

# BROKEN: SSH from anywhere on the internet
resource "aws_security_group_rule" "ssh_in" {
  type              = "ingress"
  description       = "SSH for administration"
  from_port         = 22
  to_port           = 22
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

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

  # BROKEN: root volume not encrypted, and no metadata_options (IMDSv1 allowed)
  root_block_device {
    encrypted = false
  }

  tags = { Name = "acs730-lab8-web" }
}
