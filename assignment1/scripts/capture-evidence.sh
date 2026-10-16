#!/usr/bin/env bash
set -uo pipefail

# Assignment 1 evidence, using the exact file names from the course evidence list.
# Usage: capture-evidence.sh <owner>/<repo> <item> [run-id | environment]
#   environments              -> evidence/environments.json      (Task 3)
#   secrets-scope             -> evidence/secrets-scope.txt      (Task 4, right after the deletion)
#   staging-apply <run-id>    -> evidence/staging-apply.txt      (Task 5)
#   prod-apply <run-id>       -> evidence/prod-apply.txt         (Task 5, approval shown first)
#   backend-state-keys        -> evidence/backend-state-keys.txt (Tasks 1-2)
#   ssm-parameter [env]       -> evidence/ssm-parameter.txt      (Task 6, default prod)
#   cloudwatch-alarm [env]    -> evidence/cloudwatch-alarm.json  (Task 7, default prod; waits for real data)
REPO="${1:?usage: capture-evidence.sh <owner>/<repo> <item> [run-id|env]}"
ITEM="${2:?usage: capture-evidence.sh <owner>/<repo> <item> [run-id|env]}"
ARG3="${3:-}"
HERE="$(cd "$(dirname "$0")" && pwd)"
EVIDENCE_DIR="$HERE/../evidence"
TF_ROOT="$HERE/../terraform"
REGION="us-east-1"

# One job of an assign1-deploy run: header, timing, then its full log.
job_section() {   # job_section <run-id> <job-name>
  local run="$1" job="$2" job_id
  job_id=$(gh run view "$run" --repo "$REPO" --json jobs --jq ".jobs[] | select(.name==\"$job\") | .databaseId")
  gh run view "$run" --repo "$REPO" --json url,event,headBranch,headSha,displayTitle \
    --jq '"--- run: \(.url)\n--- event: \(.event)   branch: \(.headBranch)   commit: \(.headSha)\n--- title: \(.displayTitle)"'
  gh api "repos/$REPO/actions/runs/$run/jobs" \
    --jq ".jobs[] | select(.name==\"$job\") | \"--- job $job: created \(.created_at)   started \(.started_at)   completed \(.completed_at)   conclusion \(.conclusion)\""
  echo "--- job log:"
  gh run view "$run" --repo "$REPO" --job "$job_id" --log
}

case "$ITEM" in
  environments)
    # One valid JSON document, because check-lab.sh parses every .json file in evidence/.
    jq -n \
      --arg captured "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson environments "$(gh api "repos/$REPO/environments")" \
      --argjson prod_policies "$(gh api "repos/$REPO/environments/prod/deployment-branch-policies")" \
      '{captured_at_utc: $captured, environments: $environments, prod_deployment_branch_policies: $prod_policies}' \
      | tee "$EVIDENCE_DIR/environments.json"
    ;;

  secrets-scope)
    {
      echo "=== GitHub Actions secret scope - $(date -u) ==="
      echo "--- repository-level secrets:"
      gh secret list --repo "$REPO"
      if gh secret list --repo "$REPO" --json name --jq '.[].name' | grep -q '^AWS_'; then
        echo "RESULT: AWS secrets are STILL at repository level"
      else
        echo "RESULT: no AWS_* secret at repository level"
      fi
      echo "--- environment 'staging' secrets:"
      gh secret list --repo "$REPO" --env staging
      echo "--- environment 'prod' secrets:"
      gh secret list --repo "$REPO" --env prod
      echo "--- repository variables (the region is a variable, not a secret):"
      gh variable list --repo "$REPO"
    } 2>&1 | tee "$EVIDENCE_DIR/secrets-scope.txt"
    ;;

  staging-apply)
    RUN="${ARG3:?usage: capture-evidence.sh <owner>/<repo> staging-apply <run-id>}"
    {
      echo "=== staging job of assign1-deploy run $RUN - captured $(date -u) ==="
      echo "--- environment 'staging' has no required reviewer: the job started as soon as the merge triggered it"
      job_section "$RUN" staging
    } 2>&1 | tee "$EVIDENCE_DIR/staging-apply.txt"
    ;;

  prod-apply)
    RUN="${ARG3:?usage: capture-evidence.sh <owner>/<repo> prod-apply <run-id>}"
    {
      echo "=== prod job of assign1-deploy run $RUN - captured $(date -u) ==="
      echo "--- approval recorded for this run (GitHub approvals API):"
      gh api "repos/$REPO/actions/runs/$RUN/approvals" \
        --jq '.[] | "approved by \(.user.login)   state: \(.state)   environments: \([.environments[].name] | join(","))   comment: \(.comment)"'
      DEP=$(gh api "repos/$REPO/deployments?environment=prod&per_page=1" --jq '.[0].id')
      echo "--- prod deployment $DEP status history (oldest first):"
      gh api "repos/$REPO/deployments/$DEP/statuses" --jq 'reverse | .[] | "\(.created_at)   \(.state)"'
      job_section "$RUN" prod
    } 2>&1 | tee "$EVIDENCE_DIR/prod-apply.txt"
    ;;

  backend-state-keys)
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
    {
      echo "=== Terraform backend state keys - $(date -u) ==="
      echo "--- s3://acs730-tfstate-${ACCOUNT_ID}/assign1/  (one key per environment)"
      aws s3 ls "s3://acs730-tfstate-${ACCOUNT_ID}/assign1/" --recursive --human-readable
    } 2>&1 | tee "$EVIDENCE_DIR/backend-state-keys.txt"
    ;;

  ssm-parameter)
    ENV="${ARG3:-prod}"
    TF_DIR="$TF_ROOT/$ENV"
    {
      echo "=== SSM parameter vs Terraform data source ($ENV) - $(date -u) ==="
      echo "--- stored in AWS (aws ssm get-parameter --with-decryption):"
      aws ssm get-parameter --region "$REGION" --name "/acs730/assign1/${ENV}/db_password" --with-decryption \
        --query 'Parameter.{Name:Name,Type:Type,Version:Version,Value:Value,LastModifiedDate:LastModifiedDate}' --output json
      echo "--- read by Terraform's data source (terraform output, from the $ENV state):"
      terraform -chdir="$TF_DIR" init -input=false -no-color > /dev/null
      echo "db_password_parameter_name    = $(terraform -chdir="$TF_DIR" output -raw db_password_parameter_name)"
      echo "db_password_parameter_version = $(terraform -chdir="$TF_DIR" output -raw db_password_parameter_version)"
      echo "db_password                   = $(terraform -chdir="$TF_DIR" output -raw db_password)"
    } 2>&1 | tee "$EVIDENCE_DIR/ssm-parameter.txt"
    ;;

  cloudwatch-alarm)
    ENV="${ARG3:-prod}"
    ALARM="acs730-assign1-${ENV}-cpu-alarm"
    # Wait for real datapoints: INSUFFICIENT_DATA is not an accepted state.
    for i in $(seq 1 60); do
      STATE=$(aws cloudwatch describe-alarms --region "$REGION" --alarm-names "$ALARM" \
        --query 'MetricAlarms[0].StateValue' --output text)
      echo "$(date -u +%H:%M:%S) $ALARM: $STATE"
      [ "$STATE" != "INSUFFICIENT_DATA" ] && break
      sleep 30
    done
    # Pure JSON (no date line), because check-lab.sh parses every .json file in evidence/.
    aws cloudwatch describe-alarms --region "$REGION" --alarm-names "$ALARM" --output json \
      > "$EVIDENCE_DIR/cloudwatch-alarm.json"
    jq -r '.MetricAlarms[0] | "saved: \(.AlarmName)  \(.Namespace)/\(.MetricName)  \(.Statistic) > \(.Threshold)  period \(.Period)s  x\(.EvaluationPeriods)  state \(.StateValue) since \(.StateUpdatedTimestamp)"' \
      "$EVIDENCE_DIR/cloudwatch-alarm.json"
    ;;

  *)
    echo "unknown evidence item '$ITEM'" >&2
    exit 1
    ;;
esac
