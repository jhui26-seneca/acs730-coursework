# ACS730 midterm practice -- LocalStack-targeted network.
#
# Everything lives in one file on purpose: Terraform loads every .tf file in a
# directory and does not care about the names.
#
# This configuration does not currently pass `terraform validate`. Tasks 3 and 4.

variable "aws_region" {
  description = "Region to deploy into. LocalStack ignores it, but the provider still requires one."
  type        = string
  default     = "us-east-1"
}

variable "project" {
  description = "Short project name, used as a prefix for every resource name."
  type        = string
  default     = "acs730-midterm"
}

variable "environment" {
  description = "Environment this configuration represents."
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of: dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for the practice VPC."
  type        = string
  default     = "10.30.0.0/16"
}

variable "public_subnets" {
  description = "Public subnets to create, keyed by a stable name."
  type = map(object({
    cidr_block        = string
    availability_zone = string
  }))
  default = {
    web-a = {
      cidr_block        = "10.30.1.0/24"
      availability_zone = "us-east-1a"
    }
    web-b = {
      cidr_block        = "10.30.2.0/24"
      availability_zone = "us-east-1b"
    }
  }
}

variable "ingress_ports" {
  description = "TCP ports the web security group accepts."
  type        = list(number)
  default     = [80, 8000]
}

variable "ingress_cidr" {
  description = "Where inbound web traffic may come from."
  type        = string
  default     = "0.0.0.0/0"
}

variable "enable_artifact_bucket" {
  description = "Whether to create the artifact bucket. Demonstrates count as an on/off switch."
  type        = bool
  default     = true
}

variable "use_localstack" {
  description = "Point the AWS provider at LocalStack instead of real AWS."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "Where LocalStack is listening. Ignored unless use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}

provider "aws" {
  region = var.aws_region

  # LocalStack wants the shape of a credential, not a real one.
  access_key = var.use_localstack ? "test" : null
  secret_key = var.use_localstack ? "test" : null

  skip_credentials_validation = var.use_localstack
  skip_metadata_api_check     = var.use_localstack
  skip_requesting_account_id  = var.use_localstack

  s3_use_path_style = var.use_localstack

  dynamic "endpoints" {
    for_each = var.use_localstack ? [var.localstack_endpoint] : []

    content {
      ec2 = endpoints.value
      s3  = endpoints.value
      sts = endpoints.value
    }
  }

  default_tags {
    tags = local.common_tags
  }
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "${var.project}-${var.environment}"

  common_tags = {
    Project     = var.project
    Environment = var.environment
    ManagedBy   = "terraform"
  }

  artifact_bucket_name = "${local.name_prefix}-artifacts-${data.aws_caller_identity.current.account_id}"
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = {
    Name = "${local.name_prefix}-vpc"
  }
}

resource "aws_subnet" "public" {
  for_each = var.public_subnets

  vpc_id            = aws_vpc.main.id
  cidr_block        = each.value.cidr_block
  availability_zone = each.value.availability_zone

  tags = {
    Name = "${local.name_prefix}-${each.key}"
  }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = {
    Name = "${local.name_prefix}-igw"
  }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = {
    Name = "${local.name_prefix}-public-rt"
  }
}

resource "aws_route_table_association" "public" {
  for_each = var.public_subnets

  subnet_id      = aws_subnet.public[each.key].id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-web"
  description = "Midterm practice web tier, managed by Terraform"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_ports

    content {
      description = "Inbound TCP ${ingress.value}"
      from_port   = ingress.value
      to_port     = ingress.value
      protocol    = "tcp"
      cidr_blocks = [var.ingress_cidr]
    }
  }

  egress {
    description = "Allow all outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "${local.name_prefix}-web"
  }
}

resource "aws_s3_bucket" "artifacts" {
  count = var.enable_artifact_bucket ? 1 : 0

  bucket = local.artifact_bucket_name

  tags = {
    Name = local.artifact_bucket_name
  }
}

output "vpc_id" {
  description = "ID of the practice VPC."
  value       = aws_vpc.main.id
}

output "subnet_ids" {
  description = "Subnet IDs, keyed by the same names used in var.public_subnets."
  value       = { for name, subnet in aws_subnet.public : name => subnet.id }
}

output "web_security_group_id" {
  description = "ID of the web security group."
  value       = aws_security_group.web.id
}

output "artifact_bucket_name" {
  description = "Artifact bucket name, or null when enable_artifact_bucket is false."
  value       = one(aws_s3_bucket.artifacts[*].bucket)
}

output "provider_target" {
  description = "Which API this configuration was planned against."
  value       = var.use_localstack ? var.localstack_endpoint : "real AWS in ${var.aws_region}"
}
