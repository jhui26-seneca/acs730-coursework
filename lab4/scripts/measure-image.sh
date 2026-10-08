#!/usr/bin/env bash
set -euo pipefail

# Lab 4: build an image, record its size, rebuild after a one-line code change,
# and show who it runs as, what is inside /app and what each layer added.
# Usage (from anywhere): ./lab4/scripts/measure-image.sh <Dockerfile> <tag>
DOCKERFILE="${1:?usage: measure-image.sh <Dockerfile> <tag>}"
TAG="${2:?usage: measure-image.sh <Dockerfile> <tag>}"
IMAGE="acs730-lab4:${TAG}"
cd "$(dirname "$0")/.."                      # lab4/ is the build context

# Always put app.py back, even if a build fails
trap 'sed -i "s/release /version /" app.py' EXIT

build() {   # $1 = label for this build
  local start end
  start=$(date +%s.%N)
  docker build --progress=plain -f "$DOCKERFILE" -t "$IMAGE" . > "/tmp/build-${TAG}.log" 2>&1
  end=$(date +%s.%N)
  echo "--- $1: $(echo "$end - $start" | bc) s"
  grep -E "transferring context|CACHED|RUN pip install" "/tmp/build-${TAG}.log" | head -8 || true
}

{
  echo "=== $IMAGE from $DOCKERFILE - $(date -u)"
  build "first build"
  echo "--- image size: $(docker images "$IMAGE" --format '{{.Size}}')"
  sed -i 's/version /release /' app.py
  build "rebuild after a one-line code change"
  sed -i 's/release /version /' app.py
  echo "--- runs as: $(docker run --rm "$IMAGE" whoami)"
  echo "--- files in /app:"
  docker run --rm "$IMAGE" ls -a /app
  echo "--- layers (newest first):"
  docker history "$IMAGE" --format 'table {{.Size}}\t{{.CreatedBy}}' | head -12
} | tee "evidence/build-${TAG}.txt"
