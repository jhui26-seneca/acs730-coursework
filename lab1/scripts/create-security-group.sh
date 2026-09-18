#!/usr/bin/env bash
set -euo pipefail
 
# Least privilege from day one: SSH only from *your* current IP, not the world.
MY_IP=$(curl -s https://checkip.amazonaws.com)
 
GROUP_ID=$(aws ec2 create-security-group \
  --group-name acs730-week1-sg \
  --description "ACS730 week 1 test security group" \
  --query 'GroupId' --output text)
 
aws ec2 authorize-security-group-ingress \
  --group-id "$GROUP_ID" \
  --protocol tcp --port 22 --cidr "${MY_IP}/32"
 
echo "Security group created: $GROUP_ID (SSH allowed from ${MY_IP}/32 only)"
