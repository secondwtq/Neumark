#!/usr/bin/env bash
# bench_blur.sh - single-command benchmark:
#   magick -bench 1 <input> -blur 0x8 /dev/null   (~16 s/iter)
# Gaussian blur (radius 8) of a deterministic 4096x4096 plasma image - the
# heaviest single op; one -bench iteration is already ~16 s.
# Single-threaded (built --disable-openmp; verified Threads: 1).
# Usage: bench_blur.sh [budget_seconds] [magick_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
MAGICK="${2:-$BUILD_DIR/utilities/magick}"
INPUT="${IM_INPUT:-$INT_DIR/im_input.png}"
ITERS=1   # one blur pass ~ 16 s
export MAGICK_CONFIGURE_PATH="${MAGICK_CONFIGURE_PATH:-$SRC_DIR/config}"

require "$MAGICK" "magick not found: $MAGICK"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP blur" "$BUDGET" \
  --warmup "$MAGICK" -bench 1 "$INPUT" -blur 0x4 /dev/null -- \
  "$MAGICK" -bench "$ITERS" "$INPUT" -blur 0x8 /dev/null
echo "$APP blur: iterations=$ITER wall=${ELAPSED}s (magick -bench $ITERS x blur 0x8)"
echo "$APP blur: binary=$MAGICK input=$INPUT"
