packer {
  required_plugins {
    amazon = {
      source  = "github.com/hashicorp/amazon"
      version = "~> 1"
    }
    ansible = {
      source  = "github.com/hashicorp/ansible"
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
  communicator            = "ssh"
  ssh_username            = "ec2-user"
  ssh_interface           = "session_manager"
  iam_instance_profile    = "LabInstanceProfile"
  temporary_key_pair_type = "ed25519"

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

  # The SAME webserver role that configures the live servers. Ansible runs on the workstation
  # and connects through Packer's Session Manager tunnel (use_proxy = false: straight to the
  # tunnel's local port with Packer's temporary key), so no port 22 is opened.
  provisioner "ansible" {
    playbook_file    = "../ansible/site.yml"
    user             = "ec2-user"
    use_proxy        = false
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
    extra_arguments = [
      "--extra-vars", "ansible_python_interpreter=/usr/bin/python3",
      "--extra-vars", "webserver_build_tag=golden-ami"
    ]
  }

  # A static page decided once at bake time, beside the rendered index.html.
  # The role never manages baked.html, so idempotency is unaffected.
  provisioner "file" {
    source      = "files/index.html"
    destination = "/tmp/baked.html"
  }

  provisioner "shell" {
    inline = [
      "sudo install -m 0644 -o root -g root /tmp/baked.html /var/www/html/baked.html"
    ]
  }
}
