# Assignment 2 Task 5: golden AMI built by the SAME webserver role that configures the live servers.
# Packer reaches the build instance through Session Manager (no SSH over the internet) and uses
# acs730-assign2-packer-sg, which has no inbound rules, so no port 22 is ever opened.
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
  ami_name      = "acs730-assign2-golden-${local.timestamp}"
  instance_type = "t3.micro"
  region        = "us-east-1"

  # Same base image as the Terraform servers: the standard AL2023, which has the SSM agent.
  source_ami_filter {
    filters = {
      name = "al2023-ami-2023.*-kernel-6.1-x86_64"
    }
    owners      = ["amazon"]
    most_recent = true
  }

  communicator            = "ssh"
  ssh_username            = "ec2-user"
  ssh_interface           = "session_manager"
  iam_instance_profile    = "LabInstanceProfile"
  temporary_key_pair_type = "ed25519"

  security_group_filter {
    filters = {
      "group-name" = "acs730-assign2-packer-sg"
    }
  }
  subnet_filter {
    filters = {
      "availability-zone" = "us-east-1a"
      "default-for-az"    = "true"
    }
  }
  associate_public_ip_address = true

  run_tags = {
    Name       = "acs730-assign2-packer-build"
    Assignment = "assign2"
  }
  tags = {
    Name          = "acs730-assign2-golden"
    Assignment    = "assign2"
    Course        = "ACS730"
    ManagedBy     = "packer"
    ConfiguredBy  = "ansible-role-webserver"
    SourceAMIName = "{{ .SourceAMIName }}"
  }
  snapshot_tags = {
    Name       = "acs730-assign2-golden"
    Assignment = "assign2"
  }
}

build {
  sources = ["source.amazon-ebs.web"]

  # Ansible runs on the workstation and connects through Packer's Session Manager tunnel
  # (use_proxy = false: straight to the tunnel's local port, with Packer's temporary key).
  provisioner "ansible" {
    playbook_file    = "../ansible/bake.yml"
    user             = "ec2-user"
    use_proxy        = false
    ansible_env_vars = ["ANSIBLE_HOST_KEY_CHECKING=False"]
    extra_arguments  = ["-e", "ansible_python_interpreter=/usr/bin/python3"]
  }
}
