#!/usr/bin/env bash
set -uo pipefail

# Lab 3 evidence: the latest successful deploy run triggered by a push (merge) to main,
# plus proof from AWS that only ONE acs730-lab3-sg exists (updated, not duplicated).
OUT="$(dirname "$0")/../evidence/deploy-run.txt"

RUN_ID=$(gh run list --workflow lab3-deploy.yml --branch main --event push \
  --status success --limit 1 --json databaseId --jq '.[0].databaseId')

if [ -z "$RUN_ID" ]; then
  echo "No successful push-to-main run of lab3-deploy.yml found yet." >&2
  exit 1
fi

{
  echo "=== Lab 3 deploy evidence - captured $(date -u) ==="
  gh run view "$RUN_ID" --json url,displayTitle,event,headBranch,headSha,conclusion,createdAt \
    --jq '"Run URL:    \(.url)\nTitle:      \(.displayTitle)\nTrigger:    \(.event) to \(.headBranch)\nCommit:     \(.headSha)\nConclusion: \(.conclusion)\nStarted:    \(.createdAt)"'
  echo "--- plan and apply lines from the run log:"
  gh run view "$RUN_ID" --log \
    | grep -E "update in-place|Revision|Plan:|Apply complete" | cut -f3- | sed 's/^[0-9TZ:.-]* //'
  echo "--- acs730-lab3-sg in AWS (must be exactly one row):"
  aws ec2 describe-security-groups \
    --filters "Name=tag:Name,Values=acs730-lab3-sg" \
    --query 'SecurityGroups[].{ID:GroupId,Name:GroupName,Revision:Tags[?Key==`Revision`]|[0].Value}' \
    --output table
} | tee "$OUT"
