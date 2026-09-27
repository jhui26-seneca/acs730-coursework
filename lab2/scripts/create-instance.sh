#!/usr/bin/env bash
set -euo pipefail

# Lab 2 test web server.
NAME_TAG="acs730-lab2-web"
KEY_NAME="acs730-lab2-key"
SG_NAME="acs730-lab2-sg"

EXISTING=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME_TAG}" "Name=instance-state-name,Values=pending,running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
if [ -n "$EXISTING" ]; then
  echo "Instance $NAME_TAG already exists: $EXISTING"
  exit 0
fi

AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)

SG_ID=$(aws ec2 describe-security-groups --group-names "$SG_NAME" \
  --query 'SecurityGroups[0].GroupId' --output text)

# No --iam-instance-profile: a web server needs no AWS API access (least privilege).
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --count 1 \
  --key-name "$KEY_NAME" \
  --security-group-ids "$SG_ID" \
  --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=${NAME_TAG}}]" \
  --query 'Instances[0].InstanceId' --output text)

echo "Instance $NAME_TAG launched: $INSTANCE_ID - waiting for it to be running..."
aws ec2 wait instance-running --instance-ids "$INSTANCE_ID"

PUBLIC_IP=$(aws ec2 describe-instances --instance-ids "$INSTANCE_ID" \
  --query 'Reservations[0].Instances[0].PublicIpAddress' --output text)

echo "Running. Public IP: $PUBLIC_IP"
echo "Connect with: ssh -i ~/.ssh/${KEY_NAME} ec2-user@${PUBLIC_IP}"
