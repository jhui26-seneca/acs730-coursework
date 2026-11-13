data "aws_availability_zones" "available" {
  state = "available"
}

locals {
  name_prefix = "acs730-assign1-${var.environment}"

  azs = slice(data.aws_availability_zones.available.names, 0, 2)

  public_subnets = {
    a = { cidr = cidrsubnet(var.vpc_cidr, 8, 1), az = local.azs[0] }
    b = { cidr = cidrsubnet(var.vpc_cidr, 8, 2), az = local.azs[1] }
  }
}

resource "aws_vpc" "main" {
  cidr_block           = var.vpc_cidr
  enable_dns_support   = true
  enable_dns_hostnames = true

  tags = { Name = "${local.name_prefix}-vpc" }
}

# Accepted risk (tfsec aws-ec2-no-public-ip-subnet, HIGH) - jhui26-seneca, 2026-11-13, review by 2027-01-31.
# The web server has to be reachable from the internet on port 80, and the module has no NAT gateway
# (about $33 a month) or load balancer to put it behind, so these subnets give each instance a public
# address. In a real account: the instance in private subnets, a load balancer in the public ones.
#tfsec:ignore:aws-ec2-no-public-ip-subnet
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

# The security group itself holds no rules: each rule is its own resource below, so tfsec judges each
# one separately and a suppression covers exactly one rule, never the whole group.
resource "aws_security_group" "web" {
  name        = "${local.name_prefix}-sg"
  description = "ACS730 assign1 ${var.environment} web server - HTTP only, no SSH"
  vpc_id      = aws_vpc.main.id

  tags = { Name = "${local.name_prefix}-sg" }
}

# Accepted risk (tfsec aws-ec2-no-public-ingress-sgr, CRITICAL) - jhui26-seneca, 2026-11-13, review by 2027-01-31.
# This is a public web server: port 80 open to everyone is its purpose, not an accident. It is the only
# public inbound rule, there is no port 22, and the page holds no secret. In a real account the
# instance would sit behind a load balancer and accept port 80 from the load balancer's group only.
#tfsec:ignore:aws-ec2-no-public-ingress-sgr
resource "aws_security_group_rule" "http_public" {
  type              = "ingress"
  description       = "HTTP from anywhere (the web page)"
  from_port         = 80
  to_port           = 80
  protocol          = "tcp"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}

# Any extra inbound rules a caller passes in. Deliberately NOT suppressed: a caller that opens another
# port to 0.0.0.0/0 is caught by the required tfsec check and cannot merge.
resource "aws_security_group_rule" "extra_ingress" {
  for_each = { for i, r in var.ingress_rules : tostring(i) => r }

  type              = "ingress"
  description       = each.value.description
  from_port         = each.value.port
  to_port           = each.value.port
  protocol          = "tcp"
  cidr_blocks       = each.value.cidr_blocks
  security_group_id = aws_security_group.web.id
}

# Accepted risk (tfsec aws-ec2-no-public-egress-sgr, CRITICAL) - jhui26-seneca, 2026-11-13, review by 2027-01-31.
# The SSM agent, dnf and Ansible's S3 transfers all need outbound HTTPS to AWS and Amazon Linux addresses
# that have no fixed range to list. Outbound only: nothing on the internet can open a connection to the
# instance through this rule. In a real account: VPC endpoints for SSM and S3, and 443 only.
#tfsec:ignore:aws-ec2-no-public-egress-sgr
resource "aws_security_group_rule" "all_out" {
  type              = "egress"
  description       = "All outbound (dnf, SSM agent, Ansible over SSM)"
  from_port         = 0
  to_port           = 0
  protocol          = "-1"
  cidr_blocks       = ["0.0.0.0/0"]
  security_group_id = aws_security_group.web.id
}
