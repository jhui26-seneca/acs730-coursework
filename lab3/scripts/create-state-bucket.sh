#!/usr/bin/env bash
set -euo pipefail

# Lab 3: S3 bucket for Terraform remote state, shared by the workstation and CI.
# Kept for the whole term (later labs use their own key in the same bucket),
# so there is deliberately no delete script for it.
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-tfstate-${ACCOUNT_ID}"

if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
  echo "State bucket $BUCKET already exists."
else
  # us-east-1 is the one region where create-bucket takes no LocationConstraint
  aws s3api create-bucket --bucket "$BUCKET" --region "$REGION" >/dev/null
  echo "Created state bucket $BUCKET in $REGION"
fi

# Versioning keeps old copies of the state file; public access is always blocked
aws s3api put-bucket-versioning --bucket "$BUCKET" \
  --versioning-configuration Status=Enabled
aws s3api put-public-access-block --bucket "$BUCKET" \
  --public-access-block-configuration \
  BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true

echo "State bucket ready: $BUCKET (versioning on, public access blocked)"
