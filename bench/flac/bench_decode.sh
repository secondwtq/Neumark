#!/usr/bin/env bash
# bench_decode.sh - single-command benchmark:
#   flac -d -f -s -c $INT_DIR/music.flac > /dev/null   (~8 s/iter)
# Input: flac -8 encoding of the deterministic music.wav.
# Usage: bench_decode.sh [budget_seconds] [flac_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
FLAC="${2:-$REPO_ROOT/work/flac/build-bolt/src/flac/flac}"
FLAC5=$INT_DIR/music.flac

require "$FLAC5" "missing input $FLAC5; run $SCRIPT_DIR/setup.sh"
require "$FLAC" "flac binary not found: $FLAC"
FSIZE=$(stat -c %s "$FLAC5")

run_bench "$APP decode" "$BUDGET" "$FLAC" -d -f -s -c "$FLAC5"
MBPS=$(rate "$((FSIZE * ITER / 1000000))" "$ELAPSED")
echo "$APP decode: iterations=$ITER wall=${ELAPSED}s decode=${MBPS} MB/s"
echo "$APP decode: binary=$FLAC stream=${FSIZE}B"
