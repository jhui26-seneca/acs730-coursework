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
    key          = "lab3/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
    encrypt      = true
  }
}

provider "aws" {
  region = "us-east-1"
}

resource "aws_security_group" "lab3" {
  name        = "acs730-lab3-sg"
  description = "ACS730 lab3 - managed by Terraform through the pipeline"

  tags = {
    Name      = "acs730-lab3-sg"
    Lab       = "lab3"
    ManagedBy = "terraform"
    Revision  = "1"
  }
}

output "security_group_id" {
  value = aws_security_group.lab3.id
}
