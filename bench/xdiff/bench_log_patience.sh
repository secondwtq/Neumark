#!/usr/bin/env bash
# bench_log_patience.sh - single-command benchmark:
#   diff_bench patience <logtree/old> <logtree/new> 1   (~11.3 s/iter)
# Patience diff (XDF_PATIENCE_DIFF - git diff --patience) over four real-world log pairs: HDFS_v1 38.7h halves, Blue
# Gene/L 214-day halves, NASA web access logs July vs Aug 1995, two
# Hadoop container logs (~9.9M old + ~9.6M new lines per pass).  Logs
# are throughput-bound (long lines, heavy repetition), so one pass
# fills the iteration and all four algorithms cost about the same.
# Single-threaded, deterministic; every pass is verified inside the
# harness (the emitted diff must reproduce both trees exactly).
# Usage: bench_log_patience.sh [budget_seconds] [diff_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/diff_bench}"
OLD="${XDIFF_LOG_TREE_OLD:-$INT_DIR/logtree/old}"
NEW="${XDIFF_LOG_TREE_NEW:-$INT_DIR/logtree/new}"
PASSES=1

require "$BIN" "diff_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
require "$OLD" "input not found: $OLD (run $SCRIPT_DIR/setup.sh)"
require "$NEW" "input not found: $NEW (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP log-patience" "$BUDGET" \
  --warmup "$BIN" patience "$OLD" "$NEW" 1 -- \
  "$BIN" patience "$OLD" "$NEW" "$PASSES"
echo "$APP log-patience: iterations=$ITER wall=${ELAPSED}s passes=$((PASSES * ITER))"
echo "$APP log-patience: binary=$BIN old=$OLD new=$NEW"
