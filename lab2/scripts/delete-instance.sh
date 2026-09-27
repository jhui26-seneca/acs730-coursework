#!/usr/bin/env bash
set -euo pipefail

# Lab 2: terminate the test web server and WAIT, so the SG can then be deleted.
NAME_TAG="acs730-lab2-web"

IDS=$(aws ec2 describe-instances \
  --filters "Name=tag:Name,Values=${NAME_TAG}" "Name=instance-state-name,Values=pending,running,stopping,stopped" \
  --query 'Reservations[].Instances[].InstanceId' --output text)

if [ -z "$IDS" ]; then
  echo "No $NAME_TAG instance found - nothing to delete."
else
  aws ec2 terminate-instances --instance-ids $IDS --query 'TerminatingInstances[].InstanceId' --output text
  echo "Terminating $NAME_TAG: $IDS - waiting for instance-terminated..."
  aws ec2 wait instance-terminated --instance-ids $IDS
  echo "Terminated: $IDS"
fi
