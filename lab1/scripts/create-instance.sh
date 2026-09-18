#!/usr/bin/env bash
set -euo pipefail
 
AMI_ID=$(aws ssm get-parameters --names /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
  --query 'Parameters[0].Value' --output text)
 
INSTANCE_ID=$(aws ec2 run-instances \
  --image-id "$AMI_ID" \
  --instance-type t3.micro \
  --count 1 \
  --iam-instance-profile Name=LabInstanceProfile \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=acs730-week1}]' \
  --query 'Instances[0].InstanceId' --output text)
 
echo "Instance launched: $INSTANCE_ID"
