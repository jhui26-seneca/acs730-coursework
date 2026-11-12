#!/usr/bin/env bash
# Lab 7: create the kind cluster acs730-lab7 from lab7/kind-cluster.yaml.
# Creates:   kind cluster acs730-lab7 (Docker container acs730-lab7-control-plane) and the
#            kubectl context kind-acs730-lab7 in ~/.kube/config (an admin context)
# Deletes:   nothing
# Arguments: none
# Run on:    the workstation, from any folder. Safe to run again: an existing cluster is kept.
set -euo pipefail

CLUSTER="acs730-lab7"
LAB_DIR="$(cd "$(dirname "$0")/.." && pwd)"   # lab7/, wherever the script is called from

if kind get clusters 2>/dev/null | grep -qx "$CLUSTER"; then
  echo "Cluster $CLUSTER already exists"
else
  kind create cluster --config "$LAB_DIR/kind-cluster.yaml" --wait 120s
fi

kubectl config use-context "kind-$CLUSTER"
kubectl version
kubectl get nodes -o wide
