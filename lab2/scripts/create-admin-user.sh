#!/usr/bin/env bash
set -euo pipefail

# Lab 2: create my own sudo-enabled admin user on the test instance.
# Runs on the WORKSTATION. This is the ONLY step that logs in as ec2-user.
NAME_TAG="acs730-lab2-web"
KEY_FILE="$HOME/.ssh/acs730-lab2-key"
ADMIN_USER="acs730-lab2-admin"

WEB_IP=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME_TAG}" "Name=instance-state-name,Values=running" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)
if [ -z "$WEB_IP" ] || [ "$WEB_IP" = "None" ]; then
  echo "No running $NAME_TAG instance found."
  exit 1
fi

ssh -i "$KEY_FILE" -o StrictHostKeyChecking=accept-new "ec2-user@${WEB_IP}" \
  "sudo bash -s -- ${ADMIN_USER}" <<'REMOTE'
set -euo pipefail
ADMIN="$1"
if id -u "$ADMIN" >/dev/null 2>&1; then
  echo "User $ADMIN already exists."
else
  useradd -m "$ADMIN"
  echo "Created user $ADMIN"
fi
usermod -aG wheel "$ADMIN"
# Same SSH key as ec2-user, so I can log in as myself
mkdir -p "/home/$ADMIN/.ssh"
cp /home/ec2-user/.ssh/authorized_keys "/home/$ADMIN/.ssh/authorized_keys"
chown -R "$ADMIN:$ADMIN" "/home/$ADMIN/.ssh"
chmod 700 "/home/$ADMIN/.ssh"
chmod 600 "/home/$ADMIN/.ssh/authorized_keys"
# Passwordless sudo for this one named admin (the rule AL2023 gives ec2-user)
echo "$ADMIN ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$ADMIN"
chmod 440 "/etc/sudoers.d/90-$ADMIN"
visudo -cf "/etc/sudoers.d/90-$ADMIN"
echo "Admin user $ADMIN ready (wheel, SSH key, sudo)."
REMOTE

echo "Log in with: ssh -i $KEY_FILE ${ADMIN_USER}@${WEB_IP}"
