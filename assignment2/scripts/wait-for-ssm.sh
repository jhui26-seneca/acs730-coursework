#!/usr/bin/env bash
set -euo pipefail

# Assignment 2: wait until instances report SSM PingStatus Online (an instance that is running
# but not Online is invisible to Ansible over SSM). Used on the workstation and in CI.
# Usage: wait-for-ssm.sh [instance-id ...]   (no argument = every running Role=web, Assignment=assign2 instance)
REGION="us-east-1"

if [ $# -ge 1 ]; then
  IDS="$*"
else
  IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Role,Values=web" "Name=tag:Assignment,Values=assign2" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
fi
[ -n "$IDS" ] || { echo "No running assign2 web instance found." >&2; exit 1; }

for id in $IDS; do
  status="None"
  for attempt in $(seq 1 40); do
    status=$(aws ssm describe-instance-information --region "$REGION" \
      --filters "Key=InstanceIds,Values=$id" \
      --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null || echo "None")
    if [ "$status" = "Online" ]; then
      echo "$id: PingStatus Online"
      break
    fi
    echo "$id: not registered yet ($status) - attempt $attempt/40, waiting 15 s"
    sleep 15
  done
  [ "$status" = "Online" ] || { echo "$id never reached PingStatus Online" >&2; exit 1; }
done
