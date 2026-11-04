#!/usr/bin/env bash
# Midterm mock: environment check. Read-only except starting LocalStack and pulling base images.
# Location: ~/acs730-coursework/midterm-practice/scripts/check-env.sh
REPO="jhui26-seneca/acs730-coursework"
sec() { echo; echo "=== $1 ==="; }

sec "1. Workstation"
TOKEN=$(curl -s -X PUT http://169.254.169.254/latest/api/token -H "X-aws-ec2-metadata-token-ttl-seconds: 60")
echo "instance type: $(curl -s -H "X-aws-ec2-metadata-token: $TOKEN" http://169.254.169.254/latest/meta-data/instance-type)"
free -h | head -2
df -h / | tail -1
aws sts get-caller-identity --query Arn --output text

sec "2. Tools"
docker --version
docker ps >/dev/null 2>&1 && echo "docker without sudo: OK" || echo "docker without sudo: FAIL"
terraform version | head -1
gh --version | head -1
gh auth status 2>&1 | grep -E "Logged in|scopes"
git --version
python3 --version
~/.local/bin/actionlint --version 2>/dev/null | head -1 || echo "actionlint: NOT INSTALLED"
python3 -m yamllint --version 2>/dev/null || echo "yamllint: NOT INSTALLED"

sec "3. LocalStack"
if ! docker ps --format '{{.Names}}' | grep -q localstack; then
  docker run -d --name midterm-localstack -p 4566:4566 localstack/localstack:3.8 >/dev/null \
    && echo "started midterm-localstack"
fi
for i in $(seq 1 60); do
  curl -sf http://localhost:4566/_localstack/health >/dev/null && { echo "LocalStack ready on :4566"; break; }
  sleep 2
done
curl -sf http://localhost:4566/_localstack/health >/dev/null || echo "LocalStack: NOT READY"
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Status}}'

sec "4. Repository"
cd ~/acs730-coursework || exit 1
git checkout -q main && git pull -q
git status --short | head -10
git log --oneline -3
echo "--- midterm-practice/:"
ls -la midterm-practice/

sec "5. Branch protection on main"
gh api "repos/$REPO/branches/main/protection" \
  --jq '{required_checks: .required_status_checks.contexts, pr_required: (.required_pull_request_reviews != null), admins_enforced: .enforce_admins.enabled}' 2>&1
echo "--- rulesets:"
gh api "repos/$REPO/rulesets" --jq '.[] | {name, enforcement, target}' 2>&1

sec "6. Workflows (trigger and paths filter)"
for f in .github/workflows/*.yml; do
  p=$(grep -q "paths:" "$f" && echo "paths-filtered" || echo "NO paths filter")
  t=$(grep -qE "^\s*push:" "$f" && echo "push" || echo "-")
  echo "  $f : $p, on push: $t"
done

sec "7. Actions token default"
gh api "repos/$REPO/actions/permissions/workflow" 2>&1

sec "8. Secrets, variables, environments"
gh secret list
gh variable list
gh api "repos/$REPO/environments" --jq '.environments[].name' 2>&1

sec "9. Base images (pre-pull)"
docker pull -q python:3.12-slim
docker pull -q python:3.11-slim
docker run --rm hello-world | grep -m1 "Hello from Docker"

echo; echo "=== CHECK COMPLETE ==="~
