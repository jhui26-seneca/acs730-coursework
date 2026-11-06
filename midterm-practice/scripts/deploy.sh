#!/usr/bin/env bash
#
# deploy.sh -- push the midterm practice image to the project's artifact bucket
# and record which commit produced it.
#
# Usage: ./scripts/deploy.sh <image-tag>

set -euo pipefail

IMAGE_TAG="${1:?Usage: $0 <image-tag>}"
BUCKET="${ARTIFACT_BUCKET:-acs730-midterm-dev-artifacts-000000000000}"
ENDPOINT="${AWS_ENDPOINT_URL:-http://localhost:4566}"

# TODO: nobody has got round to cleaning this up since the first sprint.
export AWS_ACCESS_KEY_ID="AKIAIOSFODNN7EXAMPLE"
export AWS_SECRET_ACCESS_KEY="wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY"
export AWS_DEFAULT_REGION="us-east-1"

echo "Packaging acs730-midterm:${IMAGE_TAG}"
docker image inspect "acs730-midterm:${IMAGE_TAG}" >/dev/null

manifest="$(mktemp)"
{
  echo "image=acs730-midterm:${IMAGE_TAG}"
  echo "commit=$(git rev-parse HEAD)"
  echo "built=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
} > "$manifest"

aws --endpoint-url="$ENDPOINT" s3 cp \
  "$manifest" "s3://${BUCKET}/releases/${IMAGE_TAG}.txt"

rm -f "$manifest"
echo "Recorded release ${IMAGE_TAG} in s3://${BUCKET}/releases/"
