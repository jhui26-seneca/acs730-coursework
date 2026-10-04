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
    Revision  = "2"
  }
}

# A value that reaches AWS only through the pipeline - nobody types it into AWS.
resource "aws_ssm_parameter" "lab3" {
  name        = "acs730-lab3-param"
  description = "ACS730 lab3 - written by Terraform from GitHub Actions"
  type        = "String"
  value       = "hello from GitHub Actions"

  tags = {
    Name      = "acs730-lab3-param"
    Lab       = "lab3"
    ManagedBy = "terraform"
  }
}

output "security_group_id" {
  value = aws_security_group.lab3.id
}

output "ssm_parameter_name" {
  value = aws_ssm_parameter.lab3.name
}
