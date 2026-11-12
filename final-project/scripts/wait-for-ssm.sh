#!/usr/bin/env bash
# Final project: wait until the VM reports SSM PingStatus Online. An instance that is running but
# not Online is invisible to Ansible over SSM. Used on the workstation and in the pipeline.
# Creates:   nothing
# Deletes:   nothing
# Arguments: [instance-id ...] (none = every running instance tagged Role=web and Project=final)
# Run on:    the workstation or a GitHub-hosted runner, with AWS credentials
set -euo pipefail
REGION="us-east-1"

if [ $# -ge 1 ]; then
  IDS="$*"
else
  IDS=$(aws ec2 describe-instances --region "$REGION" \
    --filters "Name=tag:Role,Values=web" "Name=tag:Project,Values=final" "Name=instance-state-name,Values=running" \
    --query 'Reservations[].Instances[].InstanceId' --output text)
fi
[ -n "$IDS" ] || { echo "No running final-project web instance found." >&2; exit 1; }

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
