#!/usr/bin/env bash
set -euo pipefail

# Lab 2 security group: SSH from the workstation only, HTTP from anywhere.
SG_NAME="acs730-lab2-sg"

if aws ec2 describe-security-groups --group-names "$SG_NAME" >/dev/null 2>&1; then
  echo "Security group $SG_NAME already exists."
  exit 0
fi

# MY_IP = the WORKSTATION's public IP, because that is where we SSH from.
MY_IP=$(curl -s https://checkip.amazonaws.com)

GROUP_ID=$(aws ec2 create-security-group \
  --group-name "$SG_NAME" \
  --description "ACS730 lab 2 web server security group" \
  --query 'GroupId' --output text)

# SSH: one address only (least privilege)
aws ec2 authorize-security-group-ingress \
  --group-id "$GROUP_ID" \
  --protocol tcp --port 22 --cidr "${MY_IP}/32"

# HTTP: public web server, so open to all
aws ec2 authorize-security-group-ingress \
  --group-id "$GROUP_ID" \
  --protocol tcp --port 80 --cidr 0.0.0.0/0

echo "Security group $SG_NAME created: $GROUP_ID (SSH from ${MY_IP}/32 only, HTTP from anywhere)"
