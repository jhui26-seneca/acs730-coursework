#!/usr/bin/env bash
set -euo pipefail

# Assignment 2 Task 6: time "launch -> first HTTP 200" for one approach, then destroy the instance.
# Usage: boot-to-ready.sh ansible   (stock AL2023, then wait for SSM and converge with the webserver role)
#        boot-to-ready.sh golden    (newest acs730-assign2-golden-* AMI, nothing else)
# Both runs use the same two clock positions, written into the evidence file.
# The private IP is looked up and used for curl but never printed (no IP in any committed file).
MODE="${1:?usage: boot-to-ready.sh ansible|golden}"
case "$MODE" in ansible|golden) ;; *) echo "usage: boot-to-ready.sh ansible|golden" >&2; exit 1 ;; esac
REGION="us-east-1"
HERE="$(cd "$(dirname "$0")" && pwd)"
TF="$HERE/../terraform/timing"
OUT="$HERE/../evidence/boot-to-ready-${MODE}.txt"

terraform -chdir="$TF" init -input=false >/dev/null
# Start from nothing: an instance left over from an earlier run would skip the launch.
terraform -chdir="$TF" destroy -auto-approve -input=false -var "mode=$MODE" >/dev/null

{
  echo "=== boot-to-ready ($MODE) - $(date -u) ==="
  echo "Clock start: the moment terraform apply is started for one fresh t3.micro (terraform/timing, mode=$MODE)"
  echo "Clock stop:  the first curl of the instance's home page that returns HTTP 200 with the ACS730 assign2 page"
  START=$(date +%s)
  terraform -chdir="$TF" apply -auto-approve -input=false -no-color -var "mode=$MODE" | grep -E '^Apply complete'
  ID=$(terraform -chdir="$TF" output -raw instance_id)
  echo "AMI: $(terraform -chdir="$TF" output -raw ami_id)"
  echo "+$(( $(date +%s) - START ))s  terraform apply finished, instance $ID launched"
  IP=$(aws ec2 describe-instances --region "$REGION" --instance-ids "$ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' --output text)

  if [ "$MODE" = "ansible" ]; then
    "$HERE/wait-for-ssm.sh" "$ID" | tail -1
    echo "+$(( $(date +%s) - START ))s  SSM online"
    (cd "$HERE/../ansible" && ansible-playbook site.yml --limit "$ID" 2>&1 | grep -A2 'PLAY RECAP')
    echo "+$(( $(date +%s) - START ))s  converge finished"
  fi

  CODE=000
  for i in $(seq 1 300); do
    CODE=$(curl -s -m 3 -o /tmp/b2r-page.html -w '%{http_code}' "http://$IP/" || true)
    if [ "$CODE" = "200" ] && grep -q "ACS730 assign2" /tmp/b2r-page.html; then break; fi
    sleep 1
  done
  SECS=$(( $(date +%s) - START ))
  [ "$CODE" = "200" ] || { echo "Page never answered 200 (last code $CODE)"; exit 1; }
  grep '<h1>' /tmp/b2r-page.html
  echo "RESULT: boot-to-ready ($MODE) = ${SECS} seconds from terraform apply start to first HTTP 200"
} 2>&1 | tee "$OUT"

terraform -chdir="$TF" destroy -auto-approve -input=false -no-color -var "mode=$MODE" | grep -E '^Destroy complete' | tee -a "$OUT"
