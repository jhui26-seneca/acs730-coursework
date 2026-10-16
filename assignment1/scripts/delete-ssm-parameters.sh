#!/usr/bin/env bash
set -euo pipefail

# Assignment 1: delete the placeholder database passwords. terraform destroy does
# NOT delete them (Terraform never created them), so teardown runs this AFTER
# destroy-env.sh - the destroy still needs to read the parameter.
# Usage: delete-ssm-parameters.sh <env> [env ...]
[ $# -ge 1 ] || { echo "usage: delete-ssm-parameters.sh <dev|staging|prod> [...]" >&2; exit 1; }
REGION="us-east-1"

for ENV in "$@"; do
  case "$ENV" in
    dev|staging|prod) ;;
    *) echo "unknown environment '$ENV' (dev, staging or prod)" >&2; exit 1 ;;
  esac
  NAME="/acs730/assign1/${ENV}/db_password"

  if aws ssm get-parameter --region "$REGION" --name "$NAME" >/dev/null 2>&1; then
    aws ssm delete-parameter --region "$REGION" --name "$NAME"
    echo "Deleted $NAME"
  else
    echo "$NAME not found - nothing to delete"
  fi
done
