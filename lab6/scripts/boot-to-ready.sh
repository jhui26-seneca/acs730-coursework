#!/usr/bin/env bash
set -euo pipefail

# Lab 6: time "launch request -> web page served" for both approaches, then terminate.
# Usage: boot-to-ready.sh ansible   (plain AL2023 + wait for SSM + run the role)
#        boot-to-ready.sh golden    (newest acs730-lab6-golden-* AMI, nothing else)
MODE="${1:?usage: boot-to-ready.sh ansible|golden}"
REGION="us-east-1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../evidence/boot-to-ready-${MODE}.txt"

case "$MODE" in
  ansible)
    AMI=$(aws ssm get-parameter --region "$REGION" \
      --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
      --query 'Parameter.Value' --output text)
    ROLE_TAG="web" ;;
  golden)
    AMI=$(aws ec2 describe-images --region "$REGION" --owners self \
      --filters "Name=name,Values=acs730-lab6-golden-*" \
      --query 'sort_by(Images,&CreationDate)[-1].ImageId' --output text)
    ROLE_TAG="golden" ;;
  *) echo "usage: boot-to-ready.sh ansible|golden" >&2; exit 1 ;;
esac

SG_ID=$(aws ec2 describe-security-groups --region "$REGION" \
  --filters Name=group-name,Values=acs730-lab6-sg --query 'SecurityGroups[0].GroupId' --output text)
SUBNET_ID=$(aws ec2 describe-subnets --region "$REGION" \
  --filters Name=availability-zone,Values=us-east-1a Name=default-for-az,Values=true \
  --query 'Subnets[0].SubnetId' --output text)

{
  echo "=== boot-to-ready ($MODE) - $(date -u) ==="
  echo "AMI: $AMI"
  START=$(date +%s)
  ID=$(aws ec2 run-instances --region "$REGION" --image-id "$AMI" --instance-type t3.micro \
    --subnet-id "$SUBNET_ID" --security-group-ids "$SG_ID" \
    --iam-instance-profile Name=LabInstanceProfile --metadata-options HttpTokens=required \
    --tag-specifications "ResourceType=instance,Tags=[{Key=Name,Value=acs730-lab6-b2r-$MODE},{Key=Role,Value=$ROLE_TAG},{Key=Lab,Value=lab6}]" \
    --query 'Instances[0].InstanceId' --output text)
  echo "+0s     launch requested: $ID"
  aws ec2 wait instance-running --region "$REGION" --instance-ids "$ID"
  IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)
  echo "+$(( $(date +%s) - START ))s   instance running ($IP)"

  if [ "$MODE" = "ansible" ]; then
    "$HERE/wait-for-ssm.sh" "$ID" | tail -1
    echo "+$(( $(date +%s) - START ))s   SSM online"
    (cd "$HERE/../ansible" && ansible-playbook site.yml --limit "$ID" | grep -A2 'PLAY RECAP')
    echo "+$(( $(date +%s) - START ))s   playbook finished"
  fi

  for i in $(seq 1 150); do
    if curl -s -m 3 "http://$IP/" | grep -q "ACS730 lab6"; then break; fi
    sleep 2
  done
  echo "+$(( $(date +%s) - START ))s   READY: page served"
  curl -s -m 3 "http://$IP/" | grep '<h1>'

  aws ec2 terminate-instances --region "$REGION" --instance-ids "$ID" >/dev/null
  aws ec2 wait instance-terminated --region "$REGION" --instance-ids "$ID"
  echo "Terminated $ID"
} 2>&1 | tee "$OUT"
