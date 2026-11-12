#!/usr/bin/env bash
# Final project: create the GitHub Environment "final" used by the deploy workflow's AWS jobs.
# Creates:   GitHub Environment final, with no reviewer and no wait timer (a merge to main must
#            deploy with no human step), and a deployment branch policy that allows only main
# Deletes:   nothing
# Arguments: <owner>/<repo>
# Run on:    the workstation (needs gh logged in). Safe to run again: every call creates or updates.
set -euo pipefail

REPO="${1:?usage: configure-environment.sh <owner>/<repo>}"
ENV="final"

gh api -X PUT "repos/$REPO/environments/$ENV" --input - --silent <<'JSON'
{
  "wait_timer": 0,
  "reviewers": [],
  "deployment_branch_policy": { "protected_branches": false, "custom_branch_policies": true }
}
JSON
echo "$ENV: created or updated - no reviewer, selected branches only"

if gh api "repos/$REPO/environments/$ENV/deployment-branch-policies" \
     --jq '.branch_policies[].name' | grep -qx main; then
  echo "$ENV: branch policy 'main' already exists"
else
  gh api -X POST "repos/$REPO/environments/$ENV/deployment-branch-policies" \
    -f name=main -f type=branch --silent
  echo "$ENV: branch policy 'main' added"
fi

echo "--- proof"
gh api "repos/$REPO/environments/$ENV" --jq '{name, protection_rules: [.protection_rules[].type]}'
gh api "repos/$REPO/environments/$ENV/deployment-branch-policies" --jq '[.branch_policies[].name]'
