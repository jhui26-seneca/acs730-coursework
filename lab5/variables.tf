variable "aws_region" {
  description = "AWS region to deploy into."
  type        = string
  default     = "us-east-1"

  validation {
    condition     = can(regex("^[a-z]{2}-[a-z]+-[0-9]$", var.aws_region))
    error_message = "aws_region must look like us-east-1."
  }
}

variable "use_localstack" {
  description = "true = send every AWS API call to LocalStack; false = the real AWS account."
  type        = bool
  default     = false
}

variable "localstack_endpoint" {
  description = "LocalStack edge URL, used only when use_localstack is true."
  type        = string
  default     = "http://localhost:4566"
}

variable "vpc_cidr" {
  description = "CIDR block for the lab5 VPC."
  type        = string
  default     = "10.50.0.0/16"

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.50.0.0/16."
  }
}

variable "instance_type" {
  description = "EC2 instance type for the web server, kept small for the Academy budget."
  type        = string
  default     = "t3.micro"

  validation {
    condition     = contains(["t3.micro", "t3.small"], var.instance_type)
    error_message = "instance_type must be t3.micro or t3.small."
  }
}

variable "ingress_rules" {
  description = "Inbound rules for the web security group; one dynamic ingress block per entry."
  type = list(object({
    description = string
    port        = number
    cidr_blocks = list(string)
  }))
  default = [
    { description = "HTTP from anywhere", port = 80, cidr_blocks = ["0.0.0.0/0"] },
    { description = "HTTPS from anywhere", port = 443, cidr_blocks = ["0.0.0.0/0"] },
  ]
}

variable "create_bucket" {
  description = "Create the optional artifacts bucket (count-gated: 1 or 0)."
  type        = bool
  default     = false
}

variable "ami_name_filter" {
  description = "Name pattern for the web server AMI (real AWS: Amazon Linux 2023)."
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "ami_owners" {
  description = "Owners searched by the AMI data source."
  type        = list(string)
  default     = ["amazon"]
}
