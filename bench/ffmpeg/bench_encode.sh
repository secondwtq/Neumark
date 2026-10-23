#!/usr/bin/env bash
# bench_encode.sh - single-command benchmark:
#   ffmpeg -y -i video.y4m -c:v mpeg4 -threads 1 -q:v 5 -f avi /dev/null   (~20.5 s/iter)
# MPEG4 encode of a deterministic 1080p Y4M video (950 frames, ~3 min of
# content).  Single-threaded (-threads 1 after -c:v; verified user==wall).
# Usage: bench_encode.sh [budget_seconds] [ffmpeg_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
FFMPEG="${2:-$REPO_ROOT/work/ffmpeg/build-bolt/ffmpeg}"
INPUT="${FFMPEG_INPUT:-$INT_DIR/video.y4m}"

require "$FFMPEG" "ffmpeg not found: $FFMPEG"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP encode" "$BUDGET" "$FFMPEG" -y -i "$INPUT" -c:v mpeg4 -threads 1 -q:v 5 -f avi /dev/null
echo "$APP encode: iterations=$ITER wall=${ELAPSED}s (mpeg4 encode of $INPUT)"
echo "$APP encode: binary=$FFMPEG"
