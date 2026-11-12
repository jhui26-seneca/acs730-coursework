#!/usr/bin/env bash
# Final project: one-time set-up of the Kubernetes side, by a person with the admin context.
# Frees NodePort 30080 (the only port lab7/kind-cluster.yaml maps to the workstation) by removing
# Lab 7's Service and scaling Lab 7's Deployment to 0; the rest of namespace acs730-lab7 is kept.
# Creates:   namespace acs730-final; ServiceAccount, Role and RoleBinding from k8s/rbac.yaml; image
#            acs730-final-web:bootstrap loaded into kind; ConfigMap acs730-final-config (generated
#            from the staging Terraform output); Deployment acs730-final-web; Service acs730-final-svc
# Deletes:   Service acs730-lab7-svc (Lab 7's Deployment is scaled to 0, not deleted)
# Arguments: none
# Run on:    the workstation, as ec2-user, from the repository root (admin context kind-acs730-lab7)
set -euo pipefail

CLUSTER="acs730-lab7"
NS="acs730-final"
K8S="final-project/k8s"
kubectl config use-context "kind-$CLUSTER" > /dev/null
BACKEND_URL=$(terraform -chdir=final-project/terraform/staging output -raw web_url)

if kubectl -n acs730-lab7 get service acs730-lab7-svc > /dev/null 2>&1; then
  kubectl -n acs730-lab7 delete service acs730-lab7-svc
  kubectl -n acs730-lab7 scale deployment acs730-lab7-web --replicas=0
fi

kubectl apply -f "$K8S/namespace.yaml"
kubectl apply -f "$K8S/rbac.yaml"

docker build -q -t acs730-final-web:bootstrap final-project/app
kind load docker-image acs730-final-web:bootstrap --name "$CLUSTER"

# Generated, never committed: the VM's address changes every time Terraform rebuilds it
kubectl -n "$NS" create configmap acs730-final-config \
  --from-literal=APP_VERSION=bootstrap --from-literal=BACKEND_URL="$BACKEND_URL" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$K8S/deployment.yaml" -f "$K8S/service.yaml"
kubectl -n "$NS" rollout status deployment/acs730-final-web --timeout=120s
kubectl -n "$NS" get deploy,pods,svc,endpoints
echo "--- through the NodePort:"
curl -s http://localhost:30080/
