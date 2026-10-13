data "aws_availability_zones" "available" {
  state = "available"
}

data "aws_caller_identity" "current" {}

locals {
  name_prefix = "acs730-lab5"

  common_tags = {
    Course    = "ACS730"
    Lab       = "lab5"
    ManagedBy = "terraform"
  }

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets = {
    a = { cidr = cidrsubnet(var.vpc_cidr, 8, 1), az = local.azs[0] }
    b = { cidr = cidrsubnet(var.vpc_cidr, 8, 2), az = local.azs[1] }
  }
}

resource "aws_vpc" "main" {
cidr_block = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

resource "aws_subnet" "public" {
  for_each = local.public_subnets

  vpc_id                  = aws_vpc.main.id
  cidr_block              = each.value.cidr
  availability_zone       = each.value.az
  map_public_ip_on_launch = true

  tags = { Name = "${local.name_prefix}-subnet-${each.key}" }
}

resource "aws_internet_gateway" "main" {
  vpc_id = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-igw" }
}

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.main.id
  }

  tags = { Name = "${local.name_prefix}-rt" }
}

resource "aws_route_table_association" "public" {
  for_each = aws_subnet.public

  subnet_id      = each.value.id
  route_table_id = aws_route_table.public.id
}

resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-sg"
  description = "ACS730 lab5 web server"
  vpc_id      = aws_vpc.main.id

  dynamic "ingress" {
    for_each = var.ingress_rules
    content {
      description = ingress.value.description
      from_port   = ingress.value.port
      to_port     = ingress.value.port
      protocol    = "tcp"
      cidr_blocks = ingress.value.cidr_blocks
    }
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = { Name = "${local.name_prefix}-sg" }
}

resource "aws_s3_bucket" "artifacts" {
  count = var.create_bucket ? 1 : 0

  bucket        = "${local.name_prefix}-bucket-${data.aws_caller_identity.current.account_id}"
  force_destroy = true

  tags = { Name = "${local.name_prefix}-bucket" }
}
