#!/usr/bin/env bash
set -uo pipefail

# Assignment 1 Task 9: destroy dev, staging and prod from the workstation into ONE
# evidence file, then delete the SSM parameters (only after the destroys, which
# still read them), then prove that nothing from Assignment 1 is left.
# Usage: teardown.sh     (no arguments)
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../evidence/destroy-complete.txt"
REGION="us-east-1"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

{
  echo "=== Assignment 1 teardown - $(date -u) ==="
  for ENV in dev staging prod; do
    "$HERE/destroy-env.sh" "$ENV"
  done

  echo "=== SSM parameters (created out of band, so no destroy removes them)"
  "$HERE/delete-ssm-parameters.sh" dev staging prod

  echo "=== Proof that nothing is left (every list must be [])"
  echo "--- instances tagged Assignment=assign1, not terminated:"
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Assignment,Values=assign1" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output json
  echo "--- VPCs tagged Assignment=assign1:"
  aws ec2 describe-vpcs --region "$REGION" --filters "Name=tag:Assignment,Values=assign1" \
    --query 'Vpcs[].VpcId' --output json
  echo "--- CloudWatch alarms named acs730-assign1-*:"
  aws cloudwatch describe-alarms --region "$REGION" --alarm-name-prefix acs730-assign1- \
    --query 'MetricAlarms[].AlarmName' --output json
  echo "--- SSM parameters under /acs730/assign1/:"
  aws ssm get-parameters-by-path --region "$REGION" --path /acs730/assign1/ --recursive \
    --query 'Parameters[].Name' --output json
  echo "--- state keys kept in the backend bucket (now empty states - the record stays):"
  aws s3 ls "s3://acs730-tfstate-${ACCOUNT_ID}/assign1/" --recursive --human-readable
} 2>&1 | tee "$OUT"
