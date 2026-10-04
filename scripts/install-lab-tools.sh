#!/usr/bin/env bash
#
# install-lab-tools.sh -- install the tools a given lab needs, on the workstation.
# Idempotent: safe to re-run any time (including after an AWS Academy lab RESET,
# which wipes the workstation -- re-run Lab 1 Part 0 to relaunch it, then run
# this script for every lab you've reached).
#
# Usage:
#   ./scripts/install-lab-tools.sh lab3    # Terraform
#   ./scripts/install-lab-tools.sh lab4    # Docker
#   ./scripts/install-lab-tools.sh lab6    # Ansible + Packer + AWS collections
#   ./scripts/install-lab-tools.sh lab7    # tfsec + gitleaks
#   ./scripts/install-lab-tools.sh lab8    # kubectl + kind
#   ./scripts/install-lab-tools.sh all
#
# Versions are pinned to match the lab handouts on purpose -- do not "upgrade"
# one place without the other.

set -euo pipefail

TFSEC_VERSION="v1.28.14"
KUBECTL_VERSION="v1.31.0"
KIND_VERSION="v0.24.0"
GITLEAKS_VERSION="8.21.2"

say()  { echo -e "\n==> $*"; }
have() { command -v "$1" >/dev/null 2>&1; }

need_hashicorp_repo() {
  if [ ! -f /etc/yum.repos.d/hashicorp.repo ]; then
    say "Adding the HashiCorp dnf repository"
    sudo dnf install -y 'dnf-command(config-manager)' >/dev/null
    sudo dnf config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
  fi
}

install_lab3() {
  if have terraform; then say "Terraform already installed: $(terraform version | head -1)"; else
    need_hashicorp_repo
    say "Installing Terraform"
    sudo dnf install -y terraform
  fi
  terraform version | head -1
}

install_lab4() {
  if have docker; then say "Docker already installed"; else
    say "Installing Docker"
    sudo dnf install -y docker
  fi
  sudo systemctl enable --now docker
  if id -nG "$USER" | grep -qw docker; then
    say "User '$USER' already in the docker group"
  else
    sudo usermod -aG docker "$USER"
    say "Added '$USER' to the docker group."
    echo "    IMPORTANT: log out and SSH back in for this to take effect,"
    echo "    then verify with:  docker ps"
  fi
}

install_lab6() {
  say "Installing Ansible (pip) + AWS collections + Packer"
  pip3 install --user --quiet ansible boto3 botocore
  export PATH="$HOME/.local/bin:$PATH"
  ansible-galaxy collection install amazon.aws community.aws >/dev/null
  need_hashicorp_repo
  if have packer && /usr/bin/packer version >/dev/null 2>&1; then
    say "Packer already installed: $(/usr/bin/packer version | head -1)"
  else
    sudo dnf install -y packer
  fi
  if have session-manager-plugin; then
    say "session-manager-plugin already installed: $(session-manager-plugin --version)"
  else
    say "Installing session-manager-plugin (required by community.aws.aws_ssm and by Packer's session_manager interface)"
    sudo dnf install -y https://s3.amazonaws.com/session-manager-downloads/plugin/latest/linux_64bit/session-manager-plugin.rpm
  fi
  ansible --version | head -1
  /usr/bin/packer version | head -1
  session-manager-plugin --version
  echo "    Note: always call '/usr/bin/packer' if plain 'packer' prints cracklib usage text."
}

install_lab7() {
  if have tfsec && [ "$(tfsec --version 2>/dev/null)" = "${TFSEC_VERSION}" ]; then
    say "tfsec ${TFSEC_VERSION} already installed"
  else
    say "Installing tfsec ${TFSEC_VERSION}"
    sudo curl -sL -o /usr/local/bin/tfsec \
      "https://github.com/aquasecurity/tfsec/releases/download/${TFSEC_VERSION}/tfsec-linux-amd64"
    sudo chmod +x /usr/local/bin/tfsec
  fi
  if have gitleaks && [ "$(gitleaks version 2>/dev/null)" = "${GITLEAKS_VERSION}" ]; then
    say "gitleaks ${GITLEAKS_VERSION} already installed"
  else
    say "Installing gitleaks ${GITLEAKS_VERSION}"
    curl -sL -o /tmp/gitleaks.tar.gz \
      "https://github.com/gitleaks/gitleaks/releases/download/v${GITLEAKS_VERSION}/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz"
    sudo tar -xzf /tmp/gitleaks.tar.gz -C /usr/local/bin gitleaks
    sudo chmod +x /usr/local/bin/gitleaks
    rm -f /tmp/gitleaks.tar.gz
  fi
  tfsec --version
  gitleaks version
}

install_lab8() {
  if have kubectl; then say "kubectl already installed: $(kubectl version --client | head -1)"; else
    say "Installing kubectl ${KUBECTL_VERSION}"
    curl -sLo /tmp/kubectl "https://dl.k8s.io/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl"
    sudo install /tmp/kubectl /usr/local/bin/kubectl && rm -f /tmp/kubectl
  fi
  if have kind; then say "kind already installed: $(kind version)"; else
    say "Installing kind ${KIND_VERSION}"
    curl -sLo /tmp/kind "https://kind.sigs.k8s.io/dl/${KIND_VERSION}/kind-linux-amd64"
    sudo install /tmp/kind /usr/local/bin/kind && rm -f /tmp/kind
  fi
  echo "    Reminder: Lab 8 assumes the workstation was resized to t3.large first"
  echo "    (Console: Stop -> Change instance type -> Start; see Lab 8 Part A0)."
  free -h | awk 'NR<=2'
}

TARGET="${1:?Usage: $0 <lab3|lab4|lab6|lab7|lab8|all>}"
case "$TARGET" in
  lab3) install_lab3 ;;
  lab4) install_lab4 ;;
  lab6) install_lab6 ;;
  lab7) install_lab7 ;;
  lab8) install_lab8 ;;
  all)  install_lab3; install_lab4; install_lab6; install_lab7; install_lab8 ;;
  *) echo "Unknown target '$TARGET'. Use lab3|lab4|lab6|lab7|lab8|all." >&2; exit 1 ;;
esac

say "Done."
