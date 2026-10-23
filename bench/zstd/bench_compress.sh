#!/usr/bin/env bash
# bench_compress.sh - single-command benchmark:
#   zstd -q -T1 -12 -f -c $INT_DIR/zstd_corpus.bin > /dev/null   (~20 s/iter)
# Input: deterministic synthetic corpus (zstd tests/datagen -g700M -P50 -s1).
# Usage: bench_compress.sh [budget_seconds] [zstd_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
ZSTD="${2:-$REPO_ROOT/work/zstd/build-bolt/programs/zstd}"
CORPUS=$INT_DIR/zstd_corpus.bin

require "$CORPUS" "missing input $CORPUS; run $SCRIPT_DIR/setup.sh"
require "$ZSTD" "zstd binary not found: $ZSTD"
CSIZE=$(stat -c %s "$CORPUS")

run_bench "$APP compress" "$BUDGET" "$ZSTD" -q -T1 -12 -f -c "$CORPUS"
MBPS=$(rate "$((CSIZE * ITER / 1000000))" "$ELAPSED")
echo "$APP compress: iterations=$ITER wall=${ELAPSED}s compress=${MBPS} MB/s"
echo "$APP compress: binary=$ZSTD corpus=${CSIZE}B"
