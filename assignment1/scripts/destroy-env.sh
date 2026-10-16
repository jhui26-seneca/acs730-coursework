#!/usr/bin/env bash
set -euo pipefail

# Assignment 1: terraform destroy one environment from the workstation.
# Run it BEFORE delete-ssm-parameters.sh: the destroy still reads the parameter.
# Usage: destroy-env.sh <dev|staging|prod>
ENV="${1:?usage: destroy-env.sh <dev|staging|prod>}"
case "$ENV" in
  dev|staging|prod) ;;
  *) echo "unknown environment '$ENV' (dev, staging or prod)" >&2; exit 1 ;;
esac
HERE="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$HERE/../terraform/$ENV"

echo "=== assign1 $ENV destroy - $(date -u) ==="
terraform -chdir="$TF_DIR" init -input=false -no-color >/dev/null
terraform -chdir="$TF_DIR" destroy -auto-approve -input=false -no-color
echo "--- state entries left for assign1/$ENV: $(terraform -chdir="$TF_DIR" state list | wc -l)"
