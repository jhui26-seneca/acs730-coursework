#!/usr/bin/env bash
set -uo pipefail

# Assignment 2 Task 8 teardown, in dependency order, ending with proof that nothing is left:
# 1. the timing instance (if one is left), 2. golden AMIs AND the snapshots behind them
# (deregistering alone leaves the snapshot billing), 3. terraform destroy (both web servers and
# both security groups), 4. the SSM bucket (created by the CLI, not Terraform).
REGION="us-east-1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../evidence/teardown.txt"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-assign2-ssm-${ACCOUNT_ID}"

{
  echo "=== Assignment 2 teardown - $(date -u) ==="

  echo "--- 1. Timing instance (terraform/timing)"
  terraform -chdir="$HERE/../terraform/timing" init -input=false >/dev/null
  if [ "$(terraform -chdir="$HERE/../terraform/timing" state list 2>/dev/null | wc -l)" -gt 0 ]; then
    terraform -chdir="$HERE/../terraform/timing" destroy -auto-approve -input=false -no-color -var mode=ansible | tail -1
  else
    echo "None."
  fi

  echo "--- 2. Golden AMIs and the snapshots behind them"
  for AMI in $(aws ec2 describe-images --region "$REGION" --owners self \
      --filters "Name=name,Values=acs730-assign2-golden-*" --query 'Images[].ImageId' --output text); do
    SNAPS=$(aws ec2 describe-images --region "$REGION" --image-ids "$AMI" \
      --query 'Images[0].BlockDeviceMappings[].Ebs.SnapshotId' --output text)
    aws ec2 deregister-image --region "$REGION" --image-id "$AMI" >/dev/null && echo "Deregistered AMI $AMI"
    for SNAP in $SNAPS; do
      aws ec2 delete-snapshot --region "$REGION" --snapshot-id "$SNAP" && echo "Deleted snapshot $SNAP"
    done
  done

  echo "--- 3. terraform destroy (both web servers and both security groups)"
  terraform -chdir="$HERE/../terraform" destroy -auto-approve -input=false -no-color | tail -1

  echo "--- 4. SSM transfer bucket (created by create-ssm-bucket.sh, not Terraform)"
  if aws s3api head-bucket --bucket "$BUCKET" >/dev/null 2>&1; then
    aws s3 rb "s3://$BUCKET" --force >/dev/null && echo "Deleted bucket $BUCKET and its contents"
  else
    echo "None."
  fi

  echo "--- 5. Proof nothing is left (each list must be [])"
  echo "Instances tagged Assignment=assign2, not terminated:"
  aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Assignment,Values=assign2" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
    --query 'Reservations[].Instances[].InstanceId' --output json
  echo "AMIs named acs730-assign2-*:"
  aws ec2 describe-images --region "$REGION" --owners self \
    --filters "Name=name,Values=acs730-assign2-*" --query 'Images[].ImageId' --output json
  echo "Snapshots tagged Assignment=assign2:"
  aws ec2 describe-snapshots --region "$REGION" --owner-ids self \
    --filters "Name=tag:Assignment,Values=assign2" --query 'Snapshots[].SnapshotId' --output json
  echo "Security groups acs730-assign2-* and leftover packer_*:"
  aws ec2 describe-security-groups --region "$REGION" \
    --filters "Name=group-name,Values=acs730-assign2-*,packer_*" --query 'SecurityGroups[].GroupId' --output json
  echo "Key pairs left by Packer (packer_*):"
  aws ec2 describe-key-pairs --region "$REGION" \
    --filters "Name=key-name,Values=packer_*" --query 'KeyPairs[].KeyName' --output json
  echo "S3 buckets acs730-assign2-*:"
  aws s3api list-buckets --query "Buckets[?starts_with(Name, 'acs730-assign2-')].Name" --output json
  echo "Terraform state entries (main, timing):"
  terraform -chdir="$HERE/../terraform" state list | wc -l
  terraform -chdir="$HERE/../terraform/timing" state list | wc -l
} 2>&1 | tee "$OUT"
