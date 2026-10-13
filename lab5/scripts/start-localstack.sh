#!/usr/bin/env bash
set -euo pipefail

# Lab 5: run LocalStack (AWS emulator) on the workstation, port 4566.
NAME="acs730-lab5-localstack"
IMAGE="localstack/localstack:3.8"

if docker ps --format '{{.Names}}' | grep -qx "$NAME"; then
  echo "LocalStack container $NAME already running."
else
  docker rm -f "$NAME" >/dev/null 2>&1 || true
  docker run -d --name "$NAME" -p 4566:4566 "$IMAGE" >/dev/null
  echo "Started $NAME from $IMAGE - waiting for it to be ready..."
fi

for i in $(seq 1 60); do
  if curl -sf http://localhost:4566/_localstack/health >/dev/null; then
    echo "LocalStack is ready on http://localhost:4566"
    exit 0
  fi
  sleep 2
done
echo "LocalStack did not become ready in 120 s - check: docker logs $NAME" >&2
exit 1
