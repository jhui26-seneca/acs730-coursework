packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
  }
}

locals {
  timestamp = regex_replace(timestamp(), "[- TZ:]", "")
}

source "amazon-ebs" "web" {
  ami_name      = "acs730-lab6-golden-${local.timestamp}"
  instance_type = "t3.micro"
  region        = "us-east-1"

  source_ami_filter {
    filters = {
      name = "al2023-ami-2023.*-x86_64"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  # Connect through Session Manager, not SSH over the internet.
  communicator         = "ssh"
  ssh_username         = "ec2-user"
  ssh_interface        = "session_manager"
  iam_instance_profile = "LabInstanceProfile"

  # Use our no-ingress group, so Packer never creates a temporary group with port 22.
  security_group_filter {
    filters = {
      "group-name" = "acs730-lab6-packer-sg"
    }
  }
  subnet_filter {
    filters = {
      "availability-zone" = "us-east-1a"
      "default-for-az"    = "true"
    }
  }
  associate_public_ip_address = true

  run_tags      = { Name = "acs730-lab6-packer-build", Lab = "lab6" }
  tags          = { Name = "acs730-lab6-golden", Lab = "lab6", Course = "ACS730", ManagedBy = "packer" }
  snapshot_tags = { Name = "acs730-lab6-golden", Lab = "lab6" }
}

build {
  sources = ["source.amazon-ebs.web"]

  provisioner "file" {
    source      = "files/index.html"
    destination = "/tmp/index.html"
  }

  provisioner "shell" {
    inline = [
      "sudo dnf install -y httpd",
      "sudo install -m 0644 -o root -g root /tmp/index.html /var/www/html/index.html",
      "sudo systemctl enable httpd"
    ]
  }
}

