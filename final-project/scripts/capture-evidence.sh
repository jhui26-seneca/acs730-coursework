#!/usr/bin/env bash
# Final project: capture the four deployment evidence files from ONE merge-triggered run of
# final-deploy, in one sitting, so they all describe the same deployment.
# Creates:   evidence/pipeline-merge-deploy.txt, evidence/credential-model.txt,
#            evidence/kubectl-get-all.txt, evidence/app-response.txt (the VM's public IP is replaced
#            by <vm-public-ip> in all four: evidence never carries an IP address)
# Deletes:   nothing (overwrites those four files)
# Arguments: <run-id> <pr-number>   the final-deploy run, and the pull request whose merge started it
# Run on:    the workstation, as ec2-user, from the repository root, straight after the run is green
set -euo pipefail

RUN="${1:?usage: capture-evidence.sh <run-id> <pr-number>}"
PR="${2:?usage: capture-evidence.sh <run-id> <pr-number>}"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
EV="final-project/evidence"
K="kubectl --context kind-acs730-lab7 -n acs730-final"
D="deployment/acs730-final-web"
VM_URL=$(terraform -chdir=final-project/terraform/staging output -raw web_url)
VM_IP="${VM_URL#http://}"
mask() { sed "s/${VM_IP//./\\.}/<vm-public-ip>/g"; }
git fetch -q origin
SHA=$(gh run view "$RUN" --json headSha --jq .headSha)
STEPS='Run aws-actions/configure-aws-credentials@v4|Show the AWS identity this job runs as|Prove this job has no AWS credentials|Show the cluster identity this job runs as'

# 1. The merge, the run it started, then the whole run log
{ date -u
  echo "=== The pull request that was merged"
  gh pr view "$PR" --json number,title,state,mergedAt,mergeCommit,headRefName,baseRefName \
    --jq '"PR #\(.number): \(.title)\nstate \(.state), \(.headRefName) merged into \(.baseRefName) at \(.mergedAt)\nmerge commit \(.mergeCommit.oid)"'
  echo; echo "=== The run that merge started (event push on main, at the merge commit)"
  gh run view "$RUN" --json event,headBranch,headSha,displayTitle,status,conclusion,createdAt,updatedAt,url \
    --jq '"event: \(.event)  branch: \(.headBranch)\nhead sha: \(.headSha)\ntitle: \(.displayTitle)\nresult: \(.status) / \(.conclusion), \(.createdAt) to \(.updatedAt)\n\(.url)"'
  echo; echo "\$ gh run view $RUN"; gh run view "$RUN"
  echo; echo "\$ gh run view $RUN --log   (every job, every step)"; gh run view "$RUN" --log
} 2>&1 | mask > "$EV/pipeline-merge-deploy.txt"

# 2. The credential model, inside that same run
GL_RC=0; gitleaks git --redact --no-banner --log-opts=--all . > /tmp/final-gitleaks.txt 2>&1 || GL_RC=$?
{ date -u
  echo "=== 1. Where the AWS credentials live: only in GitHub Environment 'final' (names, never values)"
  echo '$ gh secret list --env final'; gh secret list --env final
  echo '$ gh secret list   (repository level: no AWS_* secret expected)'; gh secret list
  echo; echo "=== 2. Which jobs can read them: no reviewer (no human step in the run), main only"
  gh api "repos/$REPO/environments/final" --jq '{name, protection_rules: [.protection_rules[].type]}'
  gh api "repos/$REPO/environments/final/deployment-branch-policies" --jq '{allowed_branches: [.branch_policies[].name]}'
  echo; echo "=== 3. Inside run $RUN: the identity each job used"
  gh run view "$RUN" --log | grep -E $'\t'"(${STEPS})" || true
  echo; echo "=== 4. How long they live"
  echo "AWS: Academy session credentials (voclabs role), pushed by scripts/refresh-gha-creds.sh at the"
  echo "start of this lab session (the UPDATED times in 1). They stop working when the session ends."
  echo -n "Kubernetes: the runner's ServiceAccount token was issued and expires: "
  sudo -u acs730-lab7-runner kubectl config view --raw -o jsonpath='{.users[0].user.token}' \
    | python3 -c 'import sys, json, base64, datetime as d
p = sys.stdin.read().split(".")[1]; p += "=" * (-len(p) % 4); c = json.loads(base64.urlsafe_b64decode(p))
f = lambda t: d.datetime.utcfromtimestamp(t).strftime("%Y-%m-%d %H:%M UTC")
print(f(c["iat"]), "to", f(c["exp"]))'
  echo; echo "=== 5. Nothing long-lived in the repository: gitleaks over every commit on every branch"
  tail -3 /tmp/final-gitleaks.txt; echo "gitleaks exit code: $GL_RC"
  echo; echo "=== 6. In a real account"
  echo "No stored keys at all: OIDC, with the trust policy designed in assignment1/REPORT.md
