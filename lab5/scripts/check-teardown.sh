#!/usr/bin/env bash
set -euo pipefail

# Lab 5: after terraform destroy, prove the lab5 VPC is gone from LocalStack.
OUT="$(dirname "$0")/../evidence/describe-vpcs-after-destroy.json"

AWS_ACCESS_KEY_ID=test AWS_SECRET_ACCESS_KEY=test \
aws --endpoint-url http://localhost:4566 --region us-east-1 \
  ec2 describe-vpcs --filters "Name=tag:Name,Values=acs730-lab5-vpc" \
  --output json | tee "$OUT"
