#!/usr/bin/env bash
# Lab 8: run the same AWS calls as two identities and record ALLOWED or DENIED for each.
#   LabRole - the workstation's instance profile (what the CLI and Terraform use locally)
#   voclabs - the Vocareum "AWS CLI" session credentials (what the GitHub secrets held for CI)
# Creates:   lab8/evidence/labrole-vs-voclabs.txt
# Deletes:   nothing. Every call is read-only, a --dry-run, or deliberately invalid: the IAM create
#            calls get an empty document, so an allowed identity gets MalformedPolicyDocument and
#            nothing is created.
# Arguments: <voclabs-credentials-file> - a file OUTSIDE the repository holding the [default] block
#            from Vocareum AWS Details -> AWS CLI: Show. Delete it afterwards with shred -u.
# Run on:    the workstation.
set -uo pipefail

CREDS="${1:?usage: compare-identities.sh <voclabs-credentials-file>}"
[ -f "$CREDS" ] || { echo "No such file: $CREDS" >&2; exit 1; }
REGION="us-east-1"
HERE="$(cd "$(dirname "$0")" && pwd)"
OUT="$HERE/../evidence/labrole-vs-voclabs.txt"
MASK='s#(assumed-role/voclabs/)[^" ]+#\1<session>#g'   # the voclabs session name can carry your name

as_labrole() { env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN -u AWS_PROFILE \
                 AWS_SHARED_CREDENTIALS_FILE=/dev/null aws --region "$REGION" "$@"; }
as_voclabs() { env -u AWS_ACCESS_KEY_ID -u AWS_SECRET_ACCESS_KEY -u AWS_SESSION_TOKEN \
                 AWS_SHARED_CREDENTIALS_FILE="$CREDS" AWS_PROFILE=default aws --region "$REGION" "$@"; }

# Run one call and turn its result into a short verdict
verdict() {
  local out rc
  out=$("$@" 2>&1); rc=$?
  if [ $rc -eq 0 ]; then echo "ALLOWED"
  elif grep -q 'DryRunOperation' <<<"$out"; then echo "ALLOWED (dry run)"
  elif grep -qE 'MalformedPolicyDocument|ValidationError' <<<"$out"; then echo "ALLOWED (reached validation)"
  elif grep -q 'service control policy' <<<"$out"; then echo "DENIED (SCP explicit deny)"
  elif grep -q 'explicit deny' <<<"$out"; then echo "DENIED (explicit deny)"
  elif grep -q 'no identity-based policy allows' <<<"$out"; then echo "DENIED (no policy allows it)"
  elif grep -qE 'AccessDenied|UnauthorizedOperation|not authorized' <<<"$out"; then echo "DENIED"
  else echo "OTHER: $(tail -1 <<<"$out" | cut -c1-60)"; fi
}

LAB_ARN=$(as_labrole sts get-caller-identity --query Arn --output text 2>&1)
VOC_ARN=$(as_voclabs sts get-caller-identity --query Arn --output text 2>&1)
if ! grep -q 'assumed-role/voclabs/' <<<"$VOC_ARN"; then
  echo "The credentials file did not give a voclabs identity (got: $VOC_ARN). Nothing was compared." >&2
  exit 1
fi
AMI=$(as_labrole ssm get-parameter --name /aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64 \
      --query Parameter.Value --output text)

{
  echo "=== LabRole vs voclabs - $(date -u) ==="
  echo "LabRole: $LAB_ARN"
  echo "voclabs: $VOC_ARN" | sed -E "$MASK"
  echo
  printf '%-46s %-30s %s\n' "Call" "LabRole (workstation)" "voclabs (Vocareum CLI / CI)"
  printf '%-46s %-30s %s\n' "----" "---------------------" "---------------------------"
  while IFS='|' read -r label cmd; do
    # shellcheck disable=SC2086  # cmd is word-split on purpose
    printf '%-46s %-30s %s\n' "$label" "$(verdict as_labrole $cmd)" "$(verdict as_voclabs $cmd)"
  done <<EOF
ec2 describe-vpcs|ec2 describe-vpcs --query Vpcs[].VpcId
ec2 run-instances t3.micro (--dry-run)|ec2 run-instances --dry-run --image-id $AMI --instance-type t3.micro
ssm describe-parameters|ssm describe-parameters --max-results 1
s3api list-buckets|s3api list-buckets --query Buckets[].Name
cloudtrail lookup-events|cloudtrail lookup-events --max-results 1
iam get-role LabRole|iam get-role --role-name LabRole
iam list-attached-role-policies LabRole|iam list-attached-role-policies --role-name LabRole
iam list-attached-role-policies voclabs|iam list-attached-role-policies --role-name voclabs
iam create-policy (empty document)|iam create-policy --policy-name acs730-lab8-probe --policy-document {}
iam create-role (empty trust policy)|iam create-role --role-name acs730-lab8-probe --assume-role-policy-document {}
access-analyzer validate-policy|accessanalyzer validate-policy --policy-type IDENTITY_POLICY --policy-document {}
EOF
  echo
  echo "--- managed policies attached to each role (read as LabRole)"
  for role in LabRole voclabs; do
    echo "$role: $(as_labrole iam list-attached-role-policies --role-name "$role" --query 'AttachedPolicies[].PolicyName' --output text 2>&1 | tr '\t' ' ')"
  done
} 2>&1 | tee "$OUT"
