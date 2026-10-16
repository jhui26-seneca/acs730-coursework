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
  iam_instance_profile   = var.instance_profile_name
  monitoring             = var.detailed_monitoring

  metadata_options {
    http_endpoint = "enabled"
    http_tokens   = "required" # IMDSv2 only
  }

  # The database password comes from the SSM data source (secrets.tf), so this
  # whole value is sensitive: Terraform never prints it in a plan or a CI log.
  # The password goes into a root-only file for the application; the web page
  # only says which parameter version was loaded.
  user_data                   = <<-EOF
    #!/bin/bash
    dnf install -y httpd
    install -d -m 0700 /etc/acs730
    cat > /etc/acs730/app.env <<'ENVFILE'
    DB_PASSWORD=${data.aws_ssm_parameter.db_password.value}
    ENVFILE
    chmod 0600 /etc/acs730/app.env
    cat > /var/www/html/index.html <<HTML
    <h1>ACS730 assign1 - ${var.environment}</h1>
    <p>Host: $(hostname)</p>
    <p>Database password: loaded from ${var.db_password_parameter_name} (version ${data.aws_ssm_parameter.db_password.version}) into /etc/acs730/app.env - never shown here.</p>
    HTML
    systemctl enable --now httpd
  EOF
  user_data_replace_on_change = true

  # The implicit graph only links the instance to its subnet, not to the route
  # to the internet. user_data needs that route at first boot (dnf install),
  # so wait for the route table associations explicitly.
  depends_on = [aws_route_table_association.public]

  tags = { Name = "${local.name_prefix}-web" }
}
