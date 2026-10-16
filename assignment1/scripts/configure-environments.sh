#!/usr/bin/env bash
set -euo pipefail

# Assignment 1 Task 3: create the two GitHub Environments.
#   staging - no reviewer, no wait: a merge to main deploys it automatically.
#   prod    - one required reviewer (me), self-review allowed because I am the
#             only person on the repository, and a deployment branch policy so
#             that only main can ever deploy to prod.
# Safe to run again: every call creates or updates, never duplicates.
# Usage: configure-environments.sh <owner>/<repo>
REPO="${1:?usage: configure-environments.sh <owner>/<repo>}"
ME_ID=$(gh api user --jq .id)
ME_LOGIN=$(gh api user --jq .login)

gh api -X PUT "repos/$REPO/environments/staging" --silent
echo "staging: created or updated - no reviewer, any branch"

gh api -X PUT "repos/$REPO/environments/prod" --input - --silent <<JSON
{
  "wait_timer": 0,
  "prevent_self_review": false,
  "reviewers": [ { "type": "User", "id": $ME_ID } ],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
echo "prod: created or updated - required reviewer $ME_LOGIN, selected branches only"

if gh api "repos/$REPO/environments/prod/deployment-branch-policies" \
     --jq '.branch_policies[].name' | grep -qx main; then
  echo "prod: branch policy 'main' already exists"
else
  gh api -X POST "repos/$REPO/environments/prod/deployment-branch-policies" \
    -f name=main -f type=branch --silent
  echo "prod: branch policy 'main' added"
fi
