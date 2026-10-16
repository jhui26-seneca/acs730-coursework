variable "environment" {
  description = "Environment this copy of the module builds: dev, staging, prod (or ci for the LocalStack check)."
  type        = string

  validation {
    condition     = contains(["ci", "dev", "staging", "prod"], var.environment)
    error_message = "environment must be one of ci, dev, staging, prod."
  }
}

variable "vpc_cidr" {
  description = "CIDR block for this environment's VPC - different per environment so they never overlap."
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block, e.g. 10.10.0.0/16."
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
  description = "Inbound rules for the web security group; one dynamic ingress block per entry. Port 22 is refused."
  type = list(object({
    description = string
    port        = number
    cidr_blocks = list(string)
  }))
  default = [
    { description = "HTTP from anywhere", port = 80, cidr_blocks = ["0.0.0.0/0"] },
  ]

  validation {
    condition     = alltrue([for r in var.ingress_rules : r.port != 22])
    error_message = "Port 22 is not allowed - use Session Manager (LabInstanceProfile) to reach the instance."
  }
}

variable "ami_name_filter" {
  description = "Name pattern for the web server AMI (real AWS: standard Amazon Linux 2023, which has the SSM agent)."
  type        = string
  default     = "al2023-ami-2023.*-x86_64"
}

variable "ami_owners" {
  description = "Owners searched by the AMI data source."
  type        = list(string)
  default     = ["amazon"]
}

variable "instance_profile_name" {
  description = "Instance profile attached to the web server, so its SSM agent can register (Session Manager, no SSH)."
  type        = string
  default     = "LabInstanceProfile"
}

variable "detailed_monitoring" {
  description = "true = EC2 publishes metrics every 60 s (needed for a 60 s alarm period); false = every 300 s."
  type        = bool
  default     = false
}

variable "cpu_alarm_threshold" {
  description = "Average CPU percentage above which the CloudWatch alarm goes into ALARM."
  type        = number

  validation {
    condition     = var.cpu_alarm_threshold > 0 && var.cpu_alarm_threshold <= 100
    error_message = "cpu_alarm_threshold must be a percentage between 1 and 100."
  }
}

variable "alarm_evaluation_periods" {
  description = "How many consecutive periods must breach before the alarm fires."
  type        = number
  default     = 3

  validation {
    condition     = var.alarm_evaluation_periods >= 1 && var.alarm_evaluation_periods <= 10
    error_message = "alarm_evaluation_periods must be between 1 and 10."
  }
}

variable "db_password_parameter_name" {
  description = "SSM Parameter Store name of this environment's database password. Created out of band; Terraform only reads it."
  type        = string

  validation {
    condition     = startswith(var.db_password_parameter_name, "/acs730/assign1/")
    error_message = "db_password_parameter_name must start with /acs730/assign1/."
  }
}
