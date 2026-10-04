#!/usr/bin/env bash
#
# cleanup-check.sh -- your $50 budget guard. Lists everything in the account
# that is (or will keep) costing money, so nothing is forgotten after a lab.
# READ-ONLY: this script deletes nothing; it tells you what to delete and how.
#
# Run at the end of every lab session:
#   ./scripts/cleanup-check.sh
#
set -uo pipefail
R="us-east-1"
FOUND=0

section() { echo -e "\n=== $* ==="; }

section "EC2 instances (workstation is expected; anything else should usually be gone)"
aws ec2 describe-instances --region "$R" \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].[InstanceId,InstanceType,State.Name,Tags[?Key==`Name`]|[0].Value]' \
  --output table
COUNT=$(aws ec2 describe-instances --region "$R" \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'length(Reservations[].Instances[][])' --output text)
EXTRA=$(aws ec2 describe-instances --region "$R" \
  --filters "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[?!(Tags[?Key==`Name`&&Value==`acs730-workstation`]))][].InstanceId' \
  --output text 2>/dev/null || true)
if [ -n "${EXTRA// }" ]; then
  FOUND=1
  echo "⚠️  Non-workstation instances present: $EXTRA"
  echo "    Terminate with: aws ec2 terminate-instances --instance-ids <id ...>"
fi

section "AMIs you own (their snapshots bill continuously)"
aws ec2 describe-images --region "$R" --owners self \
  --query 'Images[].[ImageId,Name,CreationDate]' --output table
AMIS=$(aws ec2 describe-images --region "$R" --owners self --query 'Images[].ImageId' --output text)
if [ -n "${AMIS// }" ]; then
  FOUND=1
  echo "⚠️  Owned AMIs present. For each one you no longer need:"
  echo "    SNAP=\$(aws ec2 describe-images --image-ids <ami-id> --query 'Images[0].BlockDeviceMappings[0].Ebs.SnapshotId' --output text)"
  echo "    aws ec2 deregister-image --image-id <ami-id> && aws ec2 delete-snapshot --snapshot-id \$SNAP"
fi

section "EBS snapshots you own"
aws ec2 describe-snapshots --region "$R" --owner-ids self \
  --query 'Snapshots[].[SnapshotId,VolumeSize,StartTime,Description]' --output table
SNAPS=$(aws ec2 describe-snapshots --region "$R" --owner-ids self --query 'Snapshots[].SnapshotId' --output text)
[ -n "${SNAPS// }" ] && { FOUND=1; echo "⚠️  Snapshots present (some belong to AMIs above -- deregister the AMI first)."; }

section "Unattached EBS volumes (billing while 'available')"
aws ec2 describe-volumes --region "$R" --filters "Name=status,Values=available" \
  --query 'Volumes[].[VolumeId,Size,CreateTime]' --output table
VOLS=$(aws ec2 describe-volumes --region "$R" --filters "Name=status,Values=available" --query 'Volumes[].VolumeId' --output text)
[ -n "${VOLS// }" ] && { FOUND=1; echo "⚠️  Delete with: aws ec2 delete-volume --volume-id <id>"; }

section "Security groups (default and your workstation's are expected)"
aws ec2 describe-security-groups --region "$R" \
  --query 'SecurityGroups[].[GroupId,GroupName]' --output table

section "Key pairs (vockey is Academy's; others should exist only mid-lab)"
aws ec2 describe-key-pairs --region "$R" --query 'KeyPairs[].[KeyName]' --output table

section "S3 buckets (your tfstate bucket is expected and stays all term)"
aws s3 ls

section "Terraform states that still track resources (destroy before deadline)"
if command -v terraform >/dev/null 2>&1 && git rev-parse --show-toplevel >/dev/null 2>&1; then
  ROOT=$(git rev-parse --show-toplevel)
  while IFS= read -r tfd; do
    case "$tfd" in *".terraform"*) continue ;; esac
    if [ -d "$tfd/.terraform" ]; then
      N=$(cd "$tfd" && terraform state list 2>/dev/null | wc -l)
      if [ "$N" -gt 0 ]; then
        FOUND=1
        echo "⚠️  $tfd still tracks $N resource(s) -> cd $tfd && terraform destroy"
      else
        echo "✅ $tfd: state empty"
      fi
    fi
  done < <(find "$ROOT" -name '*.tf' -exec dirname {} \; | sort -u)
else
  echo "(terraform not installed or not in a repo -- skipping state inspection)"
fi

echo
if [ "$FOUND" -eq 0 ]; then
  echo "🎉 Nothing unexpected found. Your workstation stops automatically when the session ends."
else
  echo "⚠️  Items flagged above are eating the \$50. Clean them up before you leave."
fi
