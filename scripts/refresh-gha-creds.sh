#!/usr/bin/env bash
#
# refresh-gha-creds.sh
#
# Pushes your current AWS Academy session credentials to GitHub Actions
# secrets, so GitHub-hosted runners can deploy to your Academy account.
# Run this ONCE at the start of every lab session (the credentials on the
# Vocareum page are session-scoped: they expire when your lab session ends,
# which also caps the blast radius if they ever leak).
#
# In a real AWS account you would use OIDC federation instead and store no
# credentials at all -- AWS Academy denies the IAM writes OIDC needs, so
# this script is the Academy-compatible substitute.
#
# Prerequisites (one-time):
#   - GitHub CLI installed and authenticated:  gh auth login
#
# Usage:
#   1. Vocareum lab page -> AWS Details -> "AWS CLI: Show"
#   2. Copy the whole block (the 3 lines under [default])
#   3. Run:  ./refresh-gha-creds.sh <github-owner>/<repo> [environment ...]
#      and paste the block, then press Ctrl-D.
#
#   With no environments listed, secrets are set at REPOSITORY level
#   (Weeks 3-7). Once Assignment 1 Task 4 moves your credentials into
#   GitHub Environments, list the environments instead, e.g.:
#      ./refresh-gha-creds.sh you/your-repo staging prod
#
#   Add --from-file anywhere to read ~/.aws/credentials instead of pasting:
#      ./refresh-gha-creds.sh you/your-repo staging prod --from-file

set -euo pipefail

REPO="${1:?Usage: $0 <github-owner>/<repo> [environment ...] [--from-file]}"
shift

FROM_FILE=false
ENVS=()
for arg in "$@"; do
  if [[ "$arg" == "--from-file" ]]; then FROM_FILE=true; else ENVS+=("$arg"); fi
done

if $FROM_FILE; then
  INPUT=$(cat ~/.aws/credentials)
else
  echo "Paste the AWS CLI credentials block from the Vocareum page, then press Ctrl-D:"
  INPUT=$(cat)
fi

# Portable: matches both "key=value" and "key = value". Avoids `grep -oP`,
# which is GNU-only -- a student running this from a macOS laptop gets
# "grep: invalid option -- P" and three empty values.
get() { sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" <<<"$INPUT" | head -1 | tr -d ' \r'; }

KEY_ID=$(get aws_access_key_id)
SECRET=$(get aws_secret_access_key)
TOKEN=$(get aws_session_token)

[[ -n "$KEY_ID" && -n "$SECRET" && -n "$TOKEN" ]] || {
  echo "ERROR: could not parse all three values. Paste the exact block from 'AWS CLI: Show'." >&2
  exit 1
}

# Sanity check: are these credentials actually alive?
if ! AWS_ACCESS_KEY_ID="$KEY_ID" AWS_SECRET_ACCESS_KEY="$SECRET" AWS_SESSION_TOKEN="$TOKEN" \
     aws sts get-caller-identity --output text >/dev/null 2>&1; then
  echo "WARNING: credentials failed sts:GetCallerIdentity -- is your lab session started?" >&2
fi

set_all() {  # set_all [--env <name>]
  gh secret set AWS_ACCESS_KEY_ID     --repo "$REPO" "$@" --body "$KEY_ID"
  gh secret set AWS_SECRET_ACCESS_KEY --repo "$REPO" "$@" --body "$SECRET"
  gh secret set AWS_SESSION_TOKEN     --repo "$REPO" "$@" --body "$TOKEN"
}

if [ ${#ENVS[@]} -eq 0 ]; then
  set_all
  echo "Repository-level secrets refreshed for $REPO."
else
  for e in "${ENVS[@]}"; do
    # Create the environment if it does not exist yet. `gh secret set --env`
    # errors out on a missing environment, and under `set -e` that aborts the
    # whole script with a message that gives no hint what went wrong. This
    # call is idempotent, so it is safe to run every session.
    gh api -X PUT "repos/$REPO/environments/$e" --silent 2>/dev/null \
      || echo "NOTE: could not pre-create environment '$e'; continuing." >&2
    set_all --env "$e"
    echo "Environment '$e' secrets refreshed for $REPO."
  done
fi
gh variable set AWS_REGION --repo "$REPO" --body "${AWS_REGION:-us-east-1}"

echo "Done -- valid until this lab session ends."
echo "If a workflow later fails with 'ExpiredToken', your session ended: start a new one and re-run this script."
