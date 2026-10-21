# Assignment 2 Task 6: one timed instance per run, launched by Terraform the same way for both approaches,
# so the two boot-to-ready numbers share the same two clock positions. Driven by scripts/boot-to-ready.sh.
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
    key          = "assign2/timing/terraform.tfstate"
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

variable "mode" {
  description = "ansible = stock Amazon Linux 2023, configured afterwards by the role; golden = newest acs730-assign2-golden-* AMI"
  type        = string

  validation {
    condition     = contains(["ansible", "golden"], var.mode)
    error_message = "mode must be ansible or golden."
  }
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnet" "default_a" {
  vpc_id            = data.aws_vpc.default.id
  availability_zone = "us-east-1a"
  default_for_az    = true
}

# The web security group from ../main.tf: port 80 from inside the VPC only, no port 22.
data "aws_security_group" "web" {
  name   = "acs730-assign2-sg"
  vpc_id = data.aws_vpc.default.id
}

# Same stock image the web servers and the Packer build start from.
data "aws_ami" "stock" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["al2023-ami-2023.*-kernel-6.1-x86_64"]
  }
}

# Looked up only in golden mode, so the ansible run works before any AMI exists.
data "aws_ami" "golden" {
  count       = var.mode == "golden" ? 1 : 0
  most_recent = true
  owners      = ["self"]

  filter {
    name   = "name"
    values = ["acs730-assign2-golden-*"]
  }
}

resource "aws_instance" "b2r" {
  ami                    = var.mode == "golden" ? data.aws_ami.golden[0].id : data.aws_ami.stock.id
  instance_type          = "t3.micro"
  subnet_id              = data.aws_subnet.default_a.id
  vpc_security_group_ids = [data.aws_security_group.web.id]
  iam_instance_profile   = "LabInstanceProfile"

  metadata_options {
    http_tokens = "required"
  }

  tags = {
    Name = "acs730-assign2-b2r-${var.mode}"
    # ansible: joins role_web so the role can converge it; golden: kept out of the inventory group.
    Role = var.mode == "ansible" ? "web" : "golden"
  }
}

output "instance_id" {
  value = aws_instance.b2r.id
}

output "ami_id" {
  value = aws_instance.b2r.ami
}
