#!/usr/bin/env bash
# bench_sharpen.sh - single-command benchmark:
#   magick -bench 2 <input> -sharpen 0x2 /dev/null   (~18 s/iter)
# Unsharp-mask sharpen (radius 2) of a deterministic 4096x4096 plasma
# image; -bench runs the pipeline 2x internally.
# Single-threaded (built --disable-openmp; verified Threads: 1).
# Usage: bench_sharpen.sh [budget_seconds] [magick_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
MAGICK="${2:-$BUILD_DIR/utilities/magick}"
INPUT="${IM_INPUT:-$INT_DIR/im_input.png}"
ITERS=2   # ~18 s
export MAGICK_CONFIGURE_PATH="${MAGICK_CONFIGURE_PATH:-$SRC_DIR/config}"

require "$MAGICK" "magick not found: $MAGICK"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP sharpen" "$BUDGET" \
  --warmup "$MAGICK" -bench 1 "$INPUT" -sharpen 0x2 /dev/null -- \
  "$MAGICK" -bench "$ITERS" "$INPUT" -sharpen 0x2 /dev/null
echo "$APP sharpen: iterations=$ITER wall=${ELAPSED}s (magick -bench $ITERS x sharpen 0x2)"
echo "$APP sharpen: binary=$MAGICK input=$INPUT"
