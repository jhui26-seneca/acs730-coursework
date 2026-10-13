data "aws_ami" "web" {
  most_recent = true
  owners      = var.ami_owners

  filter {
    name   = "name"
    values = [var.ami_name_filter]
  }
}

resource "aws_instance" "web" {
  ami                    = data.aws_ami.web.id
  instance_type          = var.instance_type
  subnet_id              = aws_subnet.public["a"].id
  vpc_security_group_ids = [aws_security_group.web.id]

  user_data                   = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    echo "<h1>ACS730 lab5 - $(hostname)</h1>" > /var/www/html/index.html
    systemctl enable --now httpd
  EOF
  user_data_replace_on_change = true

  # The implicit graph only links the instance to its subnet, not to the route
  # to the internet. user_data needs that route at first boot (dnf install),
  # so wait for the route table associations explicitly.
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${local.name_prefix}-web" }
}
