# Assignment 2 target. Based on lab6/terraform/main.tf (lab6/ is left unchanged), with:
# two web servers instead of one, assign2 names and tags, its own state key, and no IP outputs
# (no IP address may appear in any committed file, and pipeline logs show outputs).
terraform {
  required_version = "~> 1.10"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }

  backend "s3" {
    bucket       = "acs730-tfstate-572751986246"
    key          = "assign2/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"

  default_tags {
    tags = {
      Course     = "ACS730"
      Assignment = "assign2"
      ManagedBy  = "terraform"
    }
  }
}

variable "web_count" {
  description = "How many web servers the dynamic inventory should discover"
  type        = number
  default     = 2

  validation {
    condition     = var.web_count >= 1 && var.web_count <= 3
    error_message = "web_count must be between 1 and 3."
  }
}

data "aws_caller_identity" "current" {}

data "aws_vpc" "default" {
  default = true
}

# One fixed AZ: t3 types are not offered in every us-east-1 AZ.
data "aws_subnet" "default_a" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "us-east-1a"
  default_for_az    = true
}

# al2023-ami-2023.* (not al2023-ami-*): the wider pattern also matches the minimal image, which has no SSM agent.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-x86_64"]
  }
}

# Web servers: HTTP from inside the VPC only (for the workstation's curl). No port 22.
resource "aws_security_group" "web" {
  name        = "acs730-assign2-sg"
  description = "ACS730 assign2 web servers - HTTP from inside the default VPC, no SSH"
  vpc_id      = data.aws_vpc.default.id

  ingress {
    description = "HTTP from inside the default VPC only"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = [data.aws_vpc.default.cidr_block]
  }

  egress {
    description = "All outbound (SSM agent, dnf, S3)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "acs730-assign2-sg" }
}

# Used by Packer in Session 2, so Packer never creates its own temporary group with port 22.
resource "aws_security_group" "packer" {
  name        = "acs730-assign2-packer-sg"
  description = "ACS730 assign2 Packer build - no ingress at all, SSM only"
  vpc_id      = data.aws_vpc.default.id

  egress {
    description = "All outbound (SSM agent, dnf)"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "acs730-assign2-packer-sg" }
}

# The SSM transfer bucket is created by scripts/create-ssm-bucket.sh (AWS CLI): the Academy account
# denies an S3 read the Terraform provider makes after creating any bucket (found in Lab 6).

# The tag Role = "web" is the contract with Ansible: the inventory builds group role_web from it.
resource "aws_instance" "web" {
  count                  = var.web_count
  ami                    = data.aws_ami.al2023.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnet.default_a.id
  vpc_security_group_ids = [aws_security_group.web.id]
  iam_instance_profile   = "LabInstanceProfile"

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "acs730-assign2-web-${count.index + 1}"
    Role = "web"
  }
}

output "instance_ids" {
  value = aws_instance.web[*].id
}

output "ssm_bucket" {
  value = "acs730-assign2-ssm-${data.aws_caller_identity.current.account_id}"
}
