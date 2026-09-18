#!/usr/bin/env bash
set -euo pipefail
 
IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=acs730-week1" "Name=instance-state-name,Values=pending,running,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)
 
if [ -z "$IDS" ]; then
  echo "Nothing to delete."
else
  aws ec2 terminate-instances --instance-ids $IDS --query 'TerminatingInstances[].InstanceId' --output text
  echo "Terminating: $IDS"
fi
