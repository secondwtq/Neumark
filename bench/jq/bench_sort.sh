#!/usr/bin/env bash
# bench_sort.sh - single-command benchmark:
#   jq -c 'sort_by(.value) | .[-100:] | map(.name) | length' big.json > /dev/null   (~22 s/iter)
# Sort + slice over a deterministic 4M-object JSON document.
# Single-threaded.
# Usage: bench_sort.sh [budget_seconds] [jq_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
JQ="${2:-$REPO_ROOT/work/jq/build-bolt/jq}"
INPUT="${JQ_INPUT:-$INT_DIR/big.json}"
FILTER='sort_by(.value) | .[-100:] | map(.name) | length'

require "$JQ" "jq not found: $JQ"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP sort" "$BUDGET" "$JQ" -c "$FILTER" "$INPUT"
echo "$APP sort: iterations=$ITER wall=${ELAPSED}s (sort: $FILTER)"
echo "$APP sort: binary=$JQ input=$INPUT"
