#!/usr/bin/env bash
# bench_encode.sh - single-command benchmark:
#   flac -f -s -8 -o /dev/null $INT_DIR/music.wav   (~20 s/iter)
# Input: deterministic ~2.2 GB music-like WAV (gen_wav 12500, RF64).
# Usage: bench_encode.sh [budget_seconds] [flac_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
FLAC="${2:-$REPO_ROOT/work/flac/build-bolt/src/flac/flac}"
WAV=$INT_DIR/music.wav

require "$WAV" "missing input $WAV; run $SCRIPT_DIR/setup.sh"
require "$FLAC" "flac binary not found: $FLAC"
WSIZE=$(stat -c %s "$WAV")

run_bench "$APP encode" "$BUDGET" "$FLAC" -f -s -8 -o /dev/null "$WAV"
MBPS=$(rate "$((WSIZE * ITER / 1000000))" "$ELAPSED")
echo "$APP encode: iterations=$ITER wall=${ELAPSED}s encode=${MBPS} MB/s"
echo "$APP encode: binary=$FLAC wav=${WSIZE}B"
