#!/usr/bin/env bash
# Final project: the S3 bucket Ansible's SSM connection uses to copy its modules to the VM.
# Created with the AWS CLI, not Terraform: the Academy account denies
# s3:GetBucketObjectLockConfiguration, which the Terraform AWS provider reads after creating a bucket
# (found in Lab 6). Kept apart from the versioned state bucket, which would keep every copied module.
# Creates:   bucket acs730-final-ssm-<account-id> in us-east-1 with all public access blocked
#            (an existing bucket is kept)
# Deletes:   nothing (teardown.sh deletes it)
# Arguments: none
# Run on:    the workstation (LabRole), before the first Ansible run
set -euo pipefail
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-final-ssm-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "Bucket $BUCKET already exists."
else
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  echo "Created bucket $BUCKET in $REGION"
fi

aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "SSM transfer bucket ready: $BUCKET (public access blocked)"
