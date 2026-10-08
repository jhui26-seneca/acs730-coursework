#!/usr/bin/env bash
set -euo pipefail

# Lab 4: per-job and per-step timings of one lab4-ci run, plus the cache lines from its log.
# Usage: ./lab4/scripts/ci-timings.sh <run-id> <label>     label: baseline | miss | hit
RUN="${1:?usage: ci-timings.sh <run-id> <label>}"
LABEL="${2:?usage: ci-timings.sh <run-id> <label>}"
OUT="$(dirname "$0")/../evidence/ci-timings-${LABEL}.txt"
DUR='((.completedAt|fromdateiso8601) - (.startedAt|fromdateiso8601))'

{
  echo "=== lab4-ci run $RUN ($LABEL) - captured $(date -u)"
  gh run view "$RUN" --json displayTitle,conclusion,createdAt,updatedAt \
    --jq '"\(.displayTitle) | \(.conclusion) | wall clock: \((.updatedAt|fromdateiso8601) - (.createdAt|fromdateiso8601)) s"'
  echo "--- jobs:"
  gh run view "$RUN" --json jobs \
    --jq ".jobs[] | select(.completedAt != null) | \"\(.name): \($DUR) s\""
  echo "--- install and build steps:"
  gh run view "$RUN" --json jobs \
    --jq ".jobs[] | .name as \$j | .steps[] | select(.completedAt != null)
          | select(.name | test(\"install|python-deps|build\"; \"i\"))
          | \"\(\$j) / \(.name): \($DUR) s\""
  echo "--- cache lines from the log:"
  gh run view "$RUN" --log | grep -iE "cache restored|cache not found|cache saved|importing cache|exporting cache|#[0-9]+ CACHED" \
    | head -20 || true
} | tee "$OUT"
