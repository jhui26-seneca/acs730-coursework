#!/usr/bin/env bash
set -uo pipefail

# Lab 3 evidence. Run on the WORKSTATION straight after the merge to main, before anything else is pushed.
# Writes: evidence/apply-run.json, evidence/apply-run-log.txt, evidence/ssm-parameter-after-apply.txt
EVIDENCE_DIR="$(dirname "$0")/../evidence"
PARAM_NAME="acs730-lab3-param"

RUN_ID=$(gh run list --workflow lab3-deploy.yml --branch main --event push --limit 1 \
  --json databaseId --jq '.[0].databaseId')
if [ -z "$RUN_ID" ]; then
  echo "No push-to-main run of lab3-deploy.yml found yet." >&2
  exit 1
fi

# 1. The merged apply run: conclusion, event, branch, commit, URL
gh run view "$RUN_ID" \
  --json databaseId,workflowName,displayTitle,event,headBranch,headSha,status,conclusion,url,createdAt \
  | tee "$EVIDENCE_DIR/apply-run.json"

# 2. The plan and apply lines from that run's log (proves "1 changed", not "1 added")
{ echo "=== run $RUN_ID - captured $(date -u)"
  gh run view "$RUN_ID" --log | grep -E "will be|Plan:|Apply complete"
} 2>&1 | tee "$EVIDENCE_DIR/apply-run-log.txt"

# 3. The parameter, read back from AWS
{ date -u; aws ssm get-parameter --name "$PARAM_NAME" --output json; } 2>&1 \
  | tee "$EVIDENCE_DIR/ssm-parameter-after-apply.txt"
