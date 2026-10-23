#!/usr/bin/env bash
# bench_decompress.sh - single-command benchmark:
#   zstd -q -d -T1 -c $INT_DIR/zstd_stream.zst > /dev/null   (~8-12 s/iter)
# Input: deterministic stream (zstd -3 of tests/datagen -g14G -P30 -s2).
# Usage: bench_decompress.sh [budget_seconds] [zstd_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
ZSTD="${2:-$REPO_ROOT/work/zstd/build-bolt/programs/zstd}"
STREAM=$INT_DIR/zstd_stream.zst

require "$STREAM" "missing input $STREAM; run $SCRIPT_DIR/setup.sh"
require "$ZSTD" "zstd binary not found: $ZSTD"
ZSIZE=$(stat -c %s "$STREAM")

run_bench "$APP decompress" "$BUDGET" "$ZSTD" -q -d -T1 -c "$STREAM"
MBPS=$(rate "$((ZSIZE * ITER / 1000000))" "$ELAPSED")
echo "$APP decompress: iterations=$ITER wall=${ELAPSED}s decompress=${MBPS} MB/s"
echo "$APP decompress: binary=$ZSTD stream=${ZSIZE}B"
