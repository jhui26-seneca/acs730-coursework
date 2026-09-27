#!/usr/bin/env bash
set -euo pipefail

# Lab 2 custom key pair (not vockey). Private key stays OUTSIDE the repo.
KEY_NAME="acs730-lab2-key"
KEY_FILE="$HOME/.ssh/${KEY_NAME}"

mkdir -p "$HOME/.ssh"
chmod 700 "$HOME/.ssh"

if [ -f "$KEY_FILE" ]; then
  echo "Local key already exists: $KEY_FILE"
else
  ssh-keygen -t ed25519 -f "$KEY_FILE" -C "$KEY_NAME" -N ""
fi

if aws ec2 describe-key-pairs --key-names "$KEY_NAME" >/dev/null 2>&1; then
  echo "Key pair $KEY_NAME already imported into AWS."
else
  aws ec2 import-key-pair \
    --key-name "$KEY_NAME" \
    --public-key-material "fileb://${KEY_FILE}.pub" \
    --query 'KeyPairId' --output text
  echo "Imported public key as $KEY_NAME"
fi
