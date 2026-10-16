#!/usr/bin/env bash
set -euo pipefail

# Lab 6: S3 bucket that Ansible's SSM connection uses to copy modules to the instance.
# Created with the AWS CLI (not Terraform): the Academy account denies
# s3:GetBucketObjectLockConfiguration, which the Terraform AWS provider reads after creating a bucket.
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-lab6-ssm-${ACCOUNT_ID}"

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
