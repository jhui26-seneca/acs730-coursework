#!/usr/bin/env bash
set -euo pipefail

# Lab 5: stop and remove the LocalStack container (all emulated resources vanish with it).
NAME="acs730-lab5-localstack"

if docker ps -a --format '{{.Names}}' | grep -qx "$NAME"; then
  docker rm -f "$NAME" >/dev/null
  echo "LocalStack container $NAME removed."
else
  echo "No $NAME container - nothing to remove."
fi
