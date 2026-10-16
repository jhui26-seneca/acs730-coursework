#!/usr/bin/env bash
set -uo pipefail

# Assignment 1 evidence, using the exact file names from the course evidence list.
# Usage: capture-evidence.sh <owner>/<repo> <item>
#   item: environments  -> evidence/environments.json
REPO="${1:?usage: capture-evidence.sh <owner>/<repo> <item>}"
ITEM="${2:?usage: capture-evidence.sh <owner>/<repo> <item>   (item: environments)}"
EVIDENCE_DIR="$(cd "$(dirname "$0")/.." && pwd)/evidence"

case "$ITEM" in
  environments)
    # Task 3: staging with no reviewer; prod with a required reviewer and a
    # branch policy naming main. One valid JSON document, because check-lab.sh
    # parses every .json file in evidence/.
    jq -n \
      --arg captured "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson environments "$(gh api "repos/$REPO/environments")" \
      --argjson prod_policies "$(gh api "repos/$REPO/environments/prod/deployment-branch-policies")" \
      '{captured_at_utc: $captured, environments: $environments, prod_deployment_branch_policies: $prod_policies}' \
      | tee "$EVIDENCE_DIR/environments.json"
    ;;
  *)
    echo "unknown evidence item '$ITEM'" >&2
    exit 1
    ;;
esac
