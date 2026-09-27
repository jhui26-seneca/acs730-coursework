#!/usr/bin/env bash
set -uo pipefail

# Lab 2 evidence. Usage: ./lab2/scripts/capture-evidence.sh before   (or: after)
LABEL="${1:?usage: capture-evidence.sh before|after}"
NAME_TAG="acs730-lab2-web"
KEY_FILE="$HOME/.ssh/acs730-lab2-key"
OUT="$(dirname "$0")/../evidence/service-${LABEL}-reboot.txt"

WEB_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME_TAG}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

{
  echo "=== ${LABEL} reboot - captured $(date -u) - target ${NAME_TAG} ${WEB_IP} ==="
  ssh -i "$KEY_FILE" ec2-user@"$WEB_IP" '
    echo "--- last boot time: $(uptime -s)"
    echo "--- acs730-web enabled? $(systemctl is-enabled acs730-web)"
    echo "--- httpd enabled on its own? $(systemctl is-enabled httpd)"
    systemctl status acs730-web httpd --no-pager
    ls -l /var/www/html/index.html
    echo "--- curl localhost:"; curl -s localhost'
  echo "--- curl from workstation over the internet:"
  curl -s "http://${WEB_IP}"
} | tee "$OUT"
