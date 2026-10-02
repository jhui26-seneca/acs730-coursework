#!/usr/bin/env bash
set -uo pipefail

# Lab 2 evidence, using the V2 handout's file names. Run on the WORKSTATION.
# Usage: ./lab2/scripts/capture-evidence.sh before   (or: after)
LABEL="${1:?usage: capture-evidence.sh before|after}"
NAME_TAG="acs730-lab2-web"
SG_NAME="acs730-lab2-sg"
ADMIN_USER="acs730-lab2-admin"
KEY_FILE="$HOME/.ssh/acs730-lab2-key"
EVIDENCE_DIR="$(dirname "$0")/../evidence"

WEB_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME_TAG}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

# 1. Security group rules (same query as the handout's Checkpoint 2)
aws ec2 describe-security-groups --group-names "$SG_NAME" \
  --query 'SecurityGroups[0].IpPermissions' --output json \
  | tee "$EVIDENCE_DIR/security-group-rules.json"

# 2. Service state on the instance, checked as my admin user
ssh -i "$KEY_FILE" "${ADMIN_USER}@${WEB_IP}" '
  echo "--- captured $(date -u) on $(hostname) as $(whoami)"
  echo "--- last boot time: $(uptime -s)"
  echo "--- is-enabled: $(systemctl is-enabled acs730-web)"
  echo "--- is-active:  $(systemctl is-active acs730-web)"
  systemctl status acs730-web --no-pager
  echo "--- process owner:"; ps -o user:20,cmd -C python3
  echo "--- app files:"; ls -l /opt/acs730-lab2-web' \
  | tee "$EVIDENCE_DIR/service-${LABEL}-reboot.txt"

# 3. The page over the internet, from the workstation
curl -i -sS "http://${WEB_IP}/" | tee "$EVIDENCE_DIR/http-${LABEL}-reboot.txt"
