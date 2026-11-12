#!/usr/bin/env bash
# Final project: remove everything the final project created, in dependency order, with proof.
# Creates:   evidence/teardown.txt (the VM's public IP masked)
# Deletes:   namespace acs730-final (Deployment, Service, ConfigMap, deployer ServiceAccount and RBAC);
#            the runner's service and GitHub registration (lab7/scripts/teardown-runner.sh); the staging
#            stack (terraform destroy: VM, VPC, subnets, gateway, routes, security group, CPU alarm);
#            SSM parameter /acs730/assign1/final-staging/db_password; bucket acs730-final-ssm-<account>;
#            the frontend images on the workstation. Puts Lab 7's Service back and scales it to 2.
# Keeps:     the kind cluster, the term-long state bucket (the empty final-project state stays as a
#            record), and GitHub Environment final
# Arguments: none
# Run on:    the workstation, as ec2-user, from the repository root (admin context, gh logged in)
set -uo pipefail
export AWS_DEFAULT_REGION=us-east-1
EV="final-project/evidence/teardown.txt"
TF="final-project/terraform/staging"
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
BUCKET="acs730-final-ssm-${ACCOUNT_ID}"
PARAM="/acs730/assign1/final-staging/db_password"
VM_URL=$(terraform -chdir="$TF" output -raw web_url 2>/dev/null || true)
VM_IP="${VM_URL#http://}"
mask() { if [ -n "$VM_IP" ]; then sed "s/${VM_IP//./\\.}/<vm-public-ip>/g"; else cat; fi; }
K="kubectl --context kind-acs730-lab7"

{ date -u
  echo "=== 1. Kubernetes: the final project's namespace, then Lab 7's Service back on NodePort 30080"
  $K delete namespace acs730-final --wait=true --timeout=120s
  $K apply -f lab7/k8s/service.yaml
  $K -n acs730-lab7 scale deployment acs730-lab7-web --replicas=2
  echo; echo "=== 2. The self-hosted runner: stop the service, deregister it from GitHub"
  ./lab7/scripts/teardown-runner.sh
  echo; echo "=== 3. Terraform: destroy the staging stack (the Assignment 1 module)"
  terraform -chdir="$TF" destroy -auto-approve -input=false -no-color
  echo; echo "=== 4. The SSM parameter (after the destroy, which still reads it) and the transfer bucket"
  aws ssm delete-parameter --name "$PARAM" && echo "deleted $PARAM"
  aws s3 rb "s3://$BUCKET" --force && echo "deleted bucket $BUCKET"
  echo; echo "=== 5. The frontend images on the workstation"
  docker images --format '{{.Repository}}:{{.Tag}}' | grep '^acs730-final-web:' | xargs -r docker rmi
  echo; echo "=== 6. Proof that nothing is left"
  echo "instances tagged Project=final (not terminated): [$(aws ec2 describe-instances --filters Name=tag:Project,Values=final Name=instance-state-name,Values=pending,running,stopping,stopped --query 'Reservations[].Instances[].InstanceId' --output text)]"
  echo "VPCs tagged Project=final: [$(aws ec2 describe-vpcs --filters Name=tag:Project,Values=final --query 'Vpcs[].VpcId' --output text)]"
  echo "CloudWatch alarms named acs730-assign1-staging*: [$(aws cloudwatch describe-alarms --alarm-name-prefix acs730-assign1-staging --query 'MetricAlarms[].AlarmName' --output text)]"
  echo "SSM parameters under /acs730/assign1/final-: [$(aws ssm describe-parameters --parameter-filters Key=Name,Option=BeginsWith,Values=/acs730/assign1/final- --query 'Parameters[].Name' --output text)]"
  echo "bucket $BUCKET: $(aws s3api head-bucket --bucket "$BUCKET" > /dev/null 2>&1 && echo STILL THERE || echo gone)"
  echo "resources in the staging state: $(terraform -chdir="$TF" state list 2>/dev/null | wc -l)"
  echo "namespace acs730-final: $($K get namespace acs730-final 2>&1 | tail -1)"
  echo "runners registered in GitHub: $(gh api "repos/$REPO/actions/runners" --jq .total_count)"
  echo "Lab 7 back on NodePort 30080: $(sleep 10; curl -s http://localhost:30080/)"
} 2>&1 | mask | tee "$EV"
