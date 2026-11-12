#!/usr/bin/env bash
# Lab 7 Week 10: give the self-hosted runner a kubeconfig that logs in as the
# acs730-lab7-deployer ServiceAccount, so pipeline jobs get only the deployer Role's rights
# instead of the cluster-admin context that kind create cluster wrote for ec2-user.
# Creates:   /home/acs730-lab7-runner/.kube/config (mode 600, owned by acs730-lab7-runner) with a
#            short-lived ServiceAccount token; replaces an older one. The token never touches the repo.
# Deletes:   nothing (a temporary folder it makes is removed on exit)
# Arguments: [duration], optional, e.g. 12h (default 24h). Run again to renew an expired token.
# Run on:    the workstation, as ec2-user (needs the admin context kind-acs730-lab7 and sudo).
set -euo pipefail

CLUSTER="acs730-lab7"
NS="acs730-lab7"
SA="acs730-lab7-deployer"
RUNNER_USER="acs730-lab7-runner"
DURATION="${1:-24h}"
ADMIN="kind-$CLUSTER"                       # the admin context and cluster entry kind wrote

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
CFG="$TMP/config"

# Same API server address and CA as the admin context; only the identity changes
SERVER=$(kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$ADMIN')].cluster.server}")
kubectl config view --raw -o jsonpath="{.clusters[?(@.name=='$ADMIN')].cluster.certificate-authority-data}" \
  | base64 -d > "$TMP/ca.crt"
TOKEN=$(kubectl --context "$ADMIN" -n "$NS" create token "$SA" --duration="$DURATION")

kubectl --kubeconfig "$CFG" config set-cluster "$CLUSTER" --server="$SERVER" \
  --certificate-authority="$TMP/ca.crt" --embed-certs=true > /dev/null
kubectl --kubeconfig "$CFG" config set-credentials "$SA" --token="$TOKEN" > /dev/null
kubectl --kubeconfig "$CFG" config set-context "$SA" --cluster="$CLUSTER" --user="$SA" --namespace="$NS" > /dev/null
kubectl --kubeconfig "$CFG" config use-context "$SA" > /dev/null

echo "Token valid for $DURATION. Testing the new kubeconfig:"
kubectl --kubeconfig "$CFG" auth whoami
kubectl --kubeconfig "$CFG" get deployments
echo "can-i get secrets: $(kubectl --kubeconfig "$CFG" auth can-i get secrets || true)"

sudo install -d -o "$RUNNER_USER" -g "$RUNNER_USER" -m 700 "/home/$RUNNER_USER/.kube"
sudo install -o "$RUNNER_USER" -g "$RUNNER_USER" -m 600 "$CFG" "/home/$RUNNER_USER/.kube/config"
echo "Installed /home/$RUNNER_USER/.kube/config"
