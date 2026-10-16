#!/usr/bin/env bash
set -euo pipefail

# Assignment 1: create (or update) the dev environment from the workstation.
# The pipeline deploys only staging and prod; dev is built by this script:
# SSM parameter -> terraform init -> plan -> refuse any destroy -> apply -> wait for the page.
# Output is also saved to evidence/dev-apply.txt.
# Usage: create-dev.sh     (no arguments)
HERE="$(cd "$(dirname "$0")" && pwd)"
TF_DIR="$HERE/../terraform/dev"
OUT="$HERE/../evidence/dev-apply.txt"

"$HERE/create-ssm-parameters.sh" dev

{
  echo "=== assign1 dev - create-dev.sh - $(date -u) ==="
  echo "--- state key: $(grep -o 'assign1/dev/terraform.tfstate' "$TF_DIR/versions.tf")"
  terraform -chdir="$TF_DIR" init -input=false -no-color
  terraform -chdir="$TF_DIR" plan -input=false -no-color -out=tfplan

  # Same rule as reading a plan before approving it: never apply a destroy unread.
  PLAN_TEXT=$(terraform -chdir="$TF_DIR" show -no-color tfplan)
  if grep -qE '[1-9][0-9]* to destroy' <<<"$PLAN_TEXT"; then
    echo "STOP: this plan destroys something. Nothing was applied."
    echo "Read it with: terraform -chdir=$TF_DIR show tfplan"
    exit 1
  fi

  terraform -chdir="$TF_DIR" apply -input=false -no-color tfplan
  terraform -chdir="$TF_DIR" output

  URL=$(terraform -chdir="$TF_DIR" output -raw web_url)
  echo "--- waiting for $URL (user_data installs httpd at first boot)"
  for i in $(seq 1 40); do
    PAGE=$(curl -s -m 5 "$URL" || true)
    if grep -q "ACS730 assign1" <<<"$PAGE"; then
      break
    fi
    sleep 10
  done
  curl -sS -m 5 "$URL"
} 2>&1 | tee "$OUT"
