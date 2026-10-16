#!/usr/bin/env bash
set -euo pipefail

# Assignment 1 Task 6 pre-step: create each environment's placeholder database
# password in SSM Parameter Store, ONCE, out of band. Terraform only READS it
# (data source in modules/web-env/secrets.tf); nothing in Terraform creates it.
# An existing parameter is left unchanged.
# Usage: create-ssm-parameters.sh <env> [env ...]     e.g.  dev   or   staging prod
[ $# -ge 1 ] || { echo "usage: create-ssm-parameters.sh <dev|staging|prod> [...]" >&2; exit 1; }
REGION="us-east-1"

for ENV in "$@"; do
  case "$ENV" in
    dev|staging|prod) ;;
    *) echo "unknown environment '$ENV' (dev, staging or prod)" >&2; exit 1 ;;
  esac
  NAME="/acs730/assign1/${ENV}/db_password"

  if aws ssm get-parameter --region "$REGION" --name "$NAME" >/dev/null 2>&1; then
    echo "$NAME already exists - left unchanged"
  else
    VERSION=$(aws ssm put-parameter --region "$REGION" \
      --name "$NAME" \
      --type SecureString \
      --value "placeholder-not-a-real-password-${ENV}" \
      --description "ACS730 assign1 ${ENV} placeholder database password - read by Terraform" \
      --tags "Key=Course,Value=ACS730" "Key=Assignment,Value=assign1" "Key=Environment,Value=${ENV}" \
      --query 'Version' --output text)
    echo "Created $NAME (SecureString, version $VERSION)"
  fi
done
