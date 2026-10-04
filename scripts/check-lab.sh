#!/usr/bin/env bash
#
# check-lab.sh -- run the SAME kinds of checks the grading pipeline runs, on one
# deliverable folder, BEFORE you push. Green here ≈ green in grading.
#
# Usage (from the repo root):
#   ./scripts/check-lab.sh lab1
#   ./scripts/check-lab.sh lab5
#   ./scripts/check-lab.sh assignment1
#
# Checks per folder (mirroring the instructor pipeline):
#   *.sh            -> bash -n syntax
#   *.tf dirs       -> terraform init -backend=false && terraform validate (+ tfsec if installed;
#                      tfsec HIGH/CRITICAL is a HARD FAIL for lab7, informational elsewhere)
#   Dockerfile      -> docker build (if docker available)
#   ansible/        -> ansible-playbook --syntax-check (playbooks), YAML parse (inventory)
#   k8s/*.yaml      -> YAML parse (grading additionally runs kubeconform)
#   *.json          -> JSON parse
# Plus a required-files list per lab, matching the handout's Deliverable section.
#
set -uo pipefail

DIR="${1:?Usage: $0 <lab1..lab8|assignment1|assignment2|final-project>}"
[ -d "$DIR" ] || { echo "❌ No such folder '$DIR' -- run from the repository root."; exit 1; }

FAILS=0
pass() { echo "✅ $*"; }
fail() { echo "❌ $*"; FAILS=$((FAILS+1)); }
warn() { echo "⚠️  $*"; }
skip() { echo "⏭️  $* (tool not installed -- grading WILL run this; install via ./scripts/install-lab-tools.sh)"; }

req() {  # req <path> [description]
  if compgen -G "$1" >/dev/null; then pass "required: $1"; else fail "MISSING required file: $1  ${2:-}"; fi
}

echo "=== Required files for $DIR (per the handout's Deliverable section) ==="
case "$DIR" in
  lab1)
    req "$DIR/scripts/create-instance.sh"; req "$DIR/scripts/create-security-group.sh"
    req "$DIR/scripts/delete-instance.sh"; req "$DIR/scripts/delete-security-group.sh"
    req "$DIR/README.md"; req "$DIR/evidence/*" "screenshot(s)"; req ".gitignore" ;;
  lab2)
    req "$DIR/scripts/deploy-web.sh"; req "$DIR/acs730-web.service"
    req "$DIR/README.md"; req "$DIR/evidence/*" ;;
  lab3)
    req "$DIR/main.tf"; req ".github/workflows/lab3-ci.yml"; req ".github/workflows/lab3-deploy.yml"
    req "$DIR/README.md"; req "$DIR/evidence/*"; req "scripts/refresh-gha-creds.sh" "never delete this" ;;
  lab4)
    req "$DIR/app.py"; req "$DIR/requirements.txt"; req "$DIR/requirements-dev.txt"
    req "$DIR/tests/test_app.py"; req "$DIR/pytest.ini"
    req "$DIR/Dockerfile"; req "$DIR/Dockerfile.naive"; req "$DIR/.dockerignore"
    req "$DIR/README.md"; req "$DIR/evidence/*"
    req ".github/workflows/lab4-ci.yml"; req ".github/workflows/docker-build.yml"
    req ".github/actions/python-deps/action.yml" ;;
  lab5)
    req "$DIR/versions.tf"; req "$DIR/providers.tf"; req "$DIR/variables.tf"
    req "$DIR/network.tf"; req "$DIR/compute.tf"; req "$DIR/outputs.tf"
    req "$DIR/localstack.tfvars"; req "$DIR/README.md"; req "$DIR/evidence/*"
    req ".github/workflows/lab5-ci.yml" ;;
  lab6)
    req "$DIR/terraform/main.tf"
    req "$DIR/ansible/ansible.cfg"; req "$DIR/ansible/site.yml"
    req "$DIR/ansible/inventory/lab6.aws_ec2.yml"; req "$DIR/ansible/group_vars/role_web.yml"
    req "$DIR/ansible/roles/webserver/tasks/main.yml"; req "$DIR/ansible/roles/webserver/defaults/main.yml"
    req "$DIR/ansible/roles/webserver/handlers/main.yml"; req "$DIR/ansible/roles/webserver/templates/index.html.j2"
    req "$DIR/packer/web.pkr.hcl"; req "$DIR/packer/files/index.html"; req "$DIR/scripts/boot-to-ready.sh"
    req "$DIR/README.md"; req "$DIR/evidence/*"
    req ".github/workflows/lab6-configure.yml" ;;
  lab7)
    req "$DIR/main.tf"; req "$DIR/policies/lab7-deploy-policy.json"
    req "$DIR/README.md"; req "$DIR/evidence/*"
    req ".github/workflows/lab7-policy.yml" ;;
  lab8)
    req "$DIR/kind-cluster.yaml"; req "$DIR/scripts/create-cluster.sh"
    req "$DIR/k8s/namespace.yaml"; req "$DIR/k8s/configmap.yaml"; req "$DIR/k8s/secret.yaml"
    req "$DIR/k8s/deployment.yaml"; req "$DIR/k8s/service.yaml"
    req "$DIR/README.md"; req "$DIR/evidence/*"
    req ".github/workflows/lab8-ci.yml"
    # Week 10 half. Warn rather than fail, so running this at the end of Week 9
    # on a correct submission does not go red.
    for w10 in "$DIR/k8s/rbac.yaml" ".github/workflows/lab8-deploy.yml"; do
      if compgen -G "$w10" >/dev/null; then pass "required (Week 10): $w10"
      else warn "not present yet: $w10 -- required for the Week 10 half of this lab"; fi
    done ;;
  assignment1)
    req "$DIR/REPORT.md"; req "$DIR/terraform/modules/*"; 
    req "$DIR/terraform/dev/*"; req "$DIR/terraform/staging/*"; req "$DIR/terraform/prod/*"
    req "$DIR/evidence/*" ;;
  assignment2)
    req "$DIR/REPORT.md"; req "$DIR/terraform/*"; req "$DIR/ansible/roles/*"
    req "$DIR/packer/*.pkr.hcl"; req "$DIR/evidence/*" ;;
  final-project)
    req "$DIR/REPORT.md"; req "$DIR/terraform/*"; req "$DIR/k8s/*"; req "$DIR/evidence/*" ;;
  *) warn "No required-files list for '$DIR'; running generic checks only." ;;
esac

echo; echo "=== Shell scripts: bash -n ==="
found=0
while IFS= read -r sf; do
  found=1
  if bash -n "$sf" 2>/tmp/checklab.err; then pass "bash -n $sf"; else fail "bash -n $sf: $(cat /tmp/checklab.err)"; fi
done < <(find "$DIR" -iname '*.sh' 2>/dev/null)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== Terraform: init -backend=false + validate ==="
found=0
while IFS= read -r tfd; do
  found=1
  if command -v terraform >/dev/null 2>&1; then
    if (cd "$tfd" && terraform init -backend=false -input=false >/dev/null 2>&1 && terraform validate >/dev/null 2>/tmp/checklab.err); then
      pass "terraform validate $tfd"
    else
      fail "terraform validate $tfd: $(tail -3 /tmp/checklab.err | tr '\n' ' ')"
    fi
    if command -v tfsec >/dev/null 2>&1; then
      if tfsec "$tfd" --minimum-severity HIGH >/dev/null 2>&1; then
        pass "tfsec (HIGH/CRITICAL clean) $tfd"
      else
        if [ "$DIR" = "lab7" ]; then fail "tfsec HIGH/CRITICAL findings in $tfd -- grading HARD-FAILS lab7 on this; run: tfsec $tfd"
        else warn "tfsec has findings in $tfd (informational for this folder; grader reviews them): tfsec $tfd"; fi
      fi
    else
      [ "$DIR" = "lab7" ] && skip "tfsec on $tfd" || true
    fi
  else
    skip "terraform validate on $tfd"
  fi
done < <(find "$DIR" -name '*.tf' -exec dirname {} \; 2>/dev/null | sort -u)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== Dockerfiles: docker build ==="
found=0
while IFS= read -r df; do
  found=1
  if command -v docker >/dev/null 2>&1 && docker ps >/dev/null 2>&1; then
    if docker build -q -f "$df" "$(dirname "$df")" >/dev/null 2>/tmp/checklab.err; then
      pass "docker build $df"
    else
      fail "docker build $df: $(tail -3 /tmp/checklab.err | tr '\n' ' ')"
    fi
  else
    skip "docker build $df"
  fi
done < <(find "$DIR" -iname 'Dockerfile' 2>/dev/null)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== Ansible: playbook syntax + inventory YAML ==="
found=0
while IFS= read -r pb; do
  found=1
  if command -v ansible-playbook >/dev/null 2>&1; then
    if ansible-playbook --syntax-check "$pb" >/dev/null 2>/tmp/checklab.err; then pass "syntax-check $pb"
    else fail "syntax-check $pb: $(tail -2 /tmp/checklab.err | tr '\n' ' ')"; fi
  else skip "ansible-playbook --syntax-check $pb"; fi
done < <(find "$DIR" -path '*ansible*' \( -iname '*.yml' -o -iname '*.yaml' \) \
            ! -path '*/inventory/*' ! -path '*/group_vars/*' ! -path '*/host_vars/*' \
            ! -path '*/roles/*' 2>/dev/null \
          | while IFS= read -r f; do grep -qE '^[[:space:]]*-?[[:space:]]*hosts:' "$f" && echo "$f"; done)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== YAML files (inventory, k8s, workflows touched by this lab): parse ==="
found=0
while IFS= read -r y; do
  found=1
  if python3 -c "import yaml,sys; list(yaml.safe_load_all(open(sys.argv[1])))" "$y" 2>/tmp/checklab.err; then
    pass "yaml $y"
  else fail "yaml $y: $(tail -1 /tmp/checklab.err)"; fi
done < <(find "$DIR" \( -path '*/inventory/*' -o -path '*k8s*' \) \( -iname '*.yml' -o -iname '*.yaml' \) 2>/dev/null)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== Python lint (flake8): the same gate lab4-ci.yml applies ==="
if [ "$DIR" = "lab4" ]; then
  if command -v flake8 >/dev/null 2>&1; then
    if flake8 "$DIR" --max-line-length 100 >/tmp/checklab.err 2>&1; then pass "flake8 $DIR"
    else fail "flake8 $DIR: $(head -3 /tmp/checklab.err | tr '\n' ' ')"; fi
  else skip "flake8 $DIR"; fi
else echo "(not applicable)"; fi

echo; echo "=== Packer: template validation ==="
found=0
while IFS= read -r pk; do
  found=1
  pkdir=$(dirname "$pk")
  if command -v packer >/dev/null 2>&1 || [ -x /usr/bin/packer ]; then
    PK=$(command -v /usr/bin/packer || command -v packer)
    if (cd "$pkdir" && "$PK" init . >/dev/null 2>&1 && "$PK" validate . >/tmp/checklab.err 2>&1); then
      pass "packer validate $pk"
    else fail "packer validate $pk: $(tail -2 /tmp/checklab.err | tr '\n' ' ')"; fi
  else skip "packer validate $pk"; fi
done < <(find "$DIR" -iname '*.pkr.hcl' 2>/dev/null)
[ $found -eq 0 ] && echo "(none)"

echo; echo "=== JSON files: parse ==="
found=0
while IFS= read -r j; do
  found=1
  if python3 -c "import json,sys; json.load(open(sys.argv[1]))" "$j" 2>/tmp/checklab.err; then pass "json $j"
  else fail "json $j: $(tail -1 /tmp/checklab.err)"; fi
done < <(find "$DIR" -iname '*.json' 2>/dev/null)
[ $found -eq 0 ] && echo "(none)"

echo
if [ "$FAILS" -eq 0 ]; then
  echo "🎉 $DIR: all checks passed. Push with confidence (and make sure it's MERGED to main, not just on a branch)."
else
  echo "❌ $DIR: $FAILS check(s) failed -- fix before the deadline. Grading runs these exact categories."
  exit 1
fi
