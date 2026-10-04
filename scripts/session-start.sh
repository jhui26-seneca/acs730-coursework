#!/usr/bin/env bash
#
# session-start.sh -- run this FIRST, at the start of every AWS Academy lab
# session, from inside your course repository on the workstation. It walks the
# whole start-of-session ritual and tells you exactly what still needs doing.
#
# Usage:
#   cd ~/<your-repo> && ./scripts/session-start.sh
#
set -uo pipefail

PASS="✅"; WARN="⚠️ "; FAIL="❌"
step() { echo -e "\n--- $* ---"; }

step "1/5  AWS identity (instance profile)"
if ARN=$(aws sts get-caller-identity --query Arn --output text 2>/dev/null); then
  echo "$PASS $ARN"
  case "$ARN" in
    *assumed-role*) : ;;
    *) echo "$WARN Not an assumed-role ARN -- did someone run 'aws configure' on this box? That's never needed in this course." ;;
  esac
else
  echo "$FAIL No AWS credentials. Two usual causes:"
  echo "   - Your Vocareum lab session isn't started (Start Lab, wait for green)."
  echo "   - This instance is missing LabInstanceProfile (Console: Actions -> Security -> Modify IAM role)."
  exit 1
fi

step "2/5  Repository up to date"
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  git pull --ff-only && echo "$PASS repo pulled"
  REPO=$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
else
  echo "$WARN Not inside a git repository -- cd into your course repo and re-run."
  REPO=""
fi

step "3/5  GitHub Actions credentials (session-scoped)"
if [ -n "$REPO" ] && command -v gh >/dev/null 2>&1 && gh auth status >/dev/null 2>&1; then
  # Which environments exist? (Assignment 1 onward: secrets live per-environment)
  ENVS=$(gh api "repos/${REPO}/environments" --jq '.environments[].name' 2>/dev/null | tr '\n' ' ' || true)
  if [ -n "${ENVS// }" ]; then
    SUGGEST="./scripts/refresh-gha-creds.sh ${REPO} ${ENVS}"
  else
    SUGGEST="./scripts/refresh-gha-creds.sh ${REPO}"
  fi
  echo "Your pipelines' AWS secrets died with the last session. Refresh them now?"
  echo "   (You'll need the credentials block from Vocareum: AWS Details -> AWS CLI: Show)"
  read -r -p "Run:  ${SUGGEST}   now? [y/N] " yn
  if [[ "${yn:-N}" =~ ^[Yy]$ ]]; then
    # shellcheck disable=SC2086
    ./scripts/refresh-gha-creds.sh ${REPO} ${ENVS}
  else
    echo "$WARN Skipped. Any deploy workflow will fail with ExpiredToken until you run:"
    echo "     ${SUGGEST}"
  fi
else
  echo "$WARN gh not authenticated (or not in a repo) -- if you haven't done Lab 1 Part 2 on this box: gh auth login && gh auth setup-git"
fi

step "4/5  Self-hosted runner (Lab 8 onward -- skipped if not installed)"
if [ -d "$HOME/actions-runner" ]; then
  if sudo "$HOME/actions-runner/svc.sh" status 2>/dev/null | grep -q "active (running)"; then
    echo "$PASS runner service running (GitHub may take ~30s to show it Idle)"
  else
    echo "$WARN runner installed but not running -- starting it:"
    sudo "$HOME/actions-runner/svc.sh" start || echo "$FAIL could not start; check: sudo ~/actions-runner/svc.sh status"
  fi
else
  echo "   (no runner installed -- fine before Lab 8)"
fi

step "5/5  Kubernetes cluster (Lab 8 onward -- skipped if not created)"
if command -v kind >/dev/null 2>&1 && kind get clusters 2>/dev/null | grep -q "acs730"; then
  if kubectl get nodes >/dev/null 2>&1; then
    kubectl get nodes | sed "s/^/$PASS /"
  else
    echo "$WARN cluster exists but API not answering -- the kind container may need a nudge:"
    echo "     docker start acs730-control-plane   (then wait ~1 minute)"
  fi
else
  echo "   (no kind cluster -- fine before Lab 8)"
fi

echo
echo "Session checklist done. Reminders:"
echo "  - This instance's PUBLIC IP changed when it restarted; your laptop's next SSH needs the new one."
echo "  - Working on Lab 2/6-style instances? Their SGs allowlist THIS box's IP at apply time -- re-apply if stale."
