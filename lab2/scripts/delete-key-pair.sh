#!/usr/bin/env bash
set -euo pipefail

# Lab 2: remove the custom key pair from AWS (local private key is kept).
KEY_NAME="acs730-lab2-key"

aws ec2 delete-key-pair --key-name "$KEY_NAME"
echo "Key pair $KEY_NAME removed from AWS (local file ~/.ssh/${KEY_NAME} kept)."
