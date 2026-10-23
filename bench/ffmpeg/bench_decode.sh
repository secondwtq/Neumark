#!/usr/bin/env bash
# bench_decode.sh - single-command benchmark:
#   ffmpeg -threads 1 -i video.avi -f null -   (~14.5 s/iter)
# MPEG4 decode of the pre-encoded video (950 frames, 1080p); output
# discarded via the null muxer.  Single-threaded (-threads 1 before -i;
# verified user==wall).
# Usage: bench_decode.sh [budget_seconds] [ffmpeg_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
FFMPEG="${2:-$REPO_ROOT/work/ffmpeg/build-bolt/ffmpeg}"
INPUT="${FFMPEG_AVI:-$INT_DIR/video.avi}"

require "$FFMPEG" "ffmpeg not found: $FFMPEG"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP decode" "$BUDGET" "$FFMPEG" -threads 1 -i "$INPUT" -f null -
echo "$APP decode: iterations=$ITER wall=${ELAPSED}s (mpeg4 decode of $INPUT)"
echo "$APP decode: binary=$FFMPEG"
