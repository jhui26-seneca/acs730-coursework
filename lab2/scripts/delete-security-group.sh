#!/usr/bin/env bash
set -euo pipefail

# Lab 2: remove the security group (run AFTER delete-instance.sh).
SG_NAME="acs730-lab2-sg"

if aws ec2 describe-security-groups --group-names "$SG_NAME" >/dev/null 2>&1; then
  aws ec2 delete-security-group --group-name "$SG_NAME"
  echo "Security group $SG_NAME deleted."
else
  echo "Security group $SG_NAME not found - nothing to delete."
fi
