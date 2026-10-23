#!/usr/bin/env bash
# bench_filter.sh - single-command benchmark:
#   jq -c '.[] | select(.value > 500000) | .name' big.json > /dev/null   (~5 s/iter)
# Filter/select pipeline over a deterministic 4M-object JSON document.
# Single-threaded.
# Usage: bench_filter.sh [budget_seconds] [jq_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
JQ="${2:-$REPO_ROOT/work/jq/build-bolt/jq}"
INPUT="${JQ_INPUT:-$INT_DIR/big.json}"
FILTER='.[] | select(.value > 500000) | .name'

require "$JQ" "jq not found: $JQ"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP filter" "$BUDGET" "$JQ" -c "$FILTER" "$INPUT"
echo "$APP filter: iterations=$ITER wall=${ELAPSED}s (filter: $FILTER)"
echo "$APP filter: binary=$JQ input=$INPUT"
