#!/usr/bin/env bash
set -uo pipefail

# Lab 6 teardown: leftover timing instances, golden AMIs AND their snapshots,
# terraform destroy, then the SSM bucket (created by the CLI, not Terraform);
# finishes with proof that nothing from lab6 is left.
REGION="us-east-1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../evidence/teardown.txt"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-lab6-ssm-${ACCOUNT_ID}"

{
  echo "=== Lab 6 teardown - $(date -u) ==="

  echo "--- 1. Leftover boot-to-ready instances"
  IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Name,Values=acs730-lab6-b2r-*" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
  if [ -n "$IDS" ]; then
    aws ec2 terminate-instances --region "$REGION" --instance-ids $IDS >/dev/null
    aws ec2 wait instance-terminated --region "$REGION" --instance-ids $IDS
    echo "Terminated: $IDS"
  else
    echo "None."
  fi

  echo "--- 2. Golden AMIs and the snapshots behind them"
  for AMI in $(aws ec2 describe-images --region "$REGION" --owners self \
      --filters "Name=name,Values=acs730-lab6-golden-*" --query 'Images[].ImageId' --output text); do
    SNAPS=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI" \
      --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
    aws ec2 deregister-image --region "$REGION" --image-id "$AMI" && echo "Deregistered AMI $AMI"
    for SNAP in $SNAPS; do
      aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$SNAP" && echo "Deleted snapshot $SNAP"
    done
  done

  echo "--- 3. terraform destroy (target instance and both security groups)"
  terraform -chdir="$HERE/../terraform" destroy -auto-approve -input=false -no-color | tail -1

  echo "--- 4. SSM transfer bucket (created by create-ssm-bucket.sh, not Terraform)"
  if aws s3api head-bucket --bucket "$BUCKET" 2>/dev/null; then
    aws s3 rb "s3://$BUCKET" --force >/dev/null && echo "Deleted bucket $BUCKET and its contents"
  else
    echo "None."
  fi

  echo "--- 5. Proof nothing is left (each list must be [])"
  echo "Instances tagged Lab=lab6, not terminated:"
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Lab,Values=lab6" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output json
  echo "AMIs named acs730-lab6-*:"
  aws ec2 describe-images --region "$REGION" --owners self \
    --filters "Name=name,Values=acs730-lab6-*" --query 'Images[].ImageId' --output json
  echo "Snapshots tagged Lab=lab6:"
  aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --filters "Name=tag:Lab,Values=lab6" --query 'Snapshots[].SnapshotId' --output json
  echo "Security groups acs730-lab6-*:"
  aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=acs730-lab6-*" --query 'SecurityGroups[].GroupId' --output json
  echo "S3 buckets acs730-lab6-*:"
  aws s3api list-buckets --query "Buckets[?starts_with(Name, 'acs730-lab6-')].Name" --output json
  echo "Terraform state entries:"
  terraform -chdir="$HERE/../terraform" state list | wc -l
} 2>&1 | tee "$OUT"
