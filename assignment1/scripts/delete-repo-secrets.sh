#!/usr/bin/env bash
set -euo pipefail

# Assignment 1 Task 4: delete the REPOSITORY-level copies of the three AWS secrets.
# Refuses to run unless both environments already hold all three, so the
# pipeline is never left with no credentials at all. Safe to run again.
# Usage: delete-repo-secrets.sh <owner>/<repo>
REPO="${1:?usage: delete-repo-secrets.sh <owner>/<repo>}"
SECRETS="AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN"

for ENV in staging prod; do
  HAVE=$(gh secret list --repo "$REPO" --env "$ENV" --json name --jq '[.[].name | select(startswith("AWS_"))] | length')
  if [ "$HAVE" -ne 3 ]; then
    echo "environment $ENV holds $HAVE of 3 AWS secrets - run: ./scripts/refresh-gha-creds.sh $REPO staging prod" >&2
    exit 1
  fi
  echo "environment $ENV holds all 3 AWS secrets"
done

for S in $SECRETS; do
  if gh secret list --repo "$REPO" --json name --jq '.[].name' | grep -qx "$S"; then
    gh secret delete "$S" --repo "$REPO"
    echo "deleted repository-level $S"
  else
    echo "repository-level $S not present"
  fi
done
