#!/usr/bin/env bash
# Final project pre-step: create each environment's placeholder database password in SSM
# Parameter Store, once, out of band. The Assignment 1 module only READS it (a data source), and
# won't plan without it.
# Creates:   SecureString /acs730/assign1/final-<env>/db_password for each environment given (an existing
#            parameter is left unchanged)
# Deletes:   nothing (teardown.sh deletes them)
# Arguments: <staging|prod> [...]
# Run on:    the workstation (LabRole), before the first terraform plan of that environment
set -euo pipefail
[ $# -ge 1 ] || { echo "usage: create-ssm-parameter.sh <staging|prod> [...]" >&2; exit 1; }
REGION="us-east-1"

for ENV in "$@"; do
  case "$ENV" in
    staging|prod) ;;
    *) echo "unknown environment '$ENV' (staging or prod)" >&2; exit 1 ;;
  esac
  NAME="/acs730/assign1/final-${ENV}/db_password"   # the A1 module only accepts /acs730/assign1/...

  if aws ssm get-parameter --region "$REGION" --name "$NAME" >/dev/null 2>&1; then
    echo "$NAME already exists - left unchanged"
  else
    VERSION=$(aws ssm put-parameter --region "$REGION" \
      --name "$NAME" \
      --type SecureString \
      --value "placeholder-not-a-real-password-final-${ENV}" \
      --description "ACS730 final project ${ENV} placeholder database password - read by Terraform" \
      --tags "Key=Course,Value=ACS730" "Key=Project,Value=final" "Key=Environment,Value=${ENV}" \
      --query 'Version' --output text)
    echo "Created $NAME (SecureString, version $VERSION)"
  fi
done
