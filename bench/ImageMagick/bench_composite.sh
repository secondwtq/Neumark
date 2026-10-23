#!/usr/bin/env bash
# bench_composite.sh - single-command benchmark:
#   magick -bench 6 <input> <input> -compose Over -composite /dev/null   (~21 s/iter)
# Over-composite of the deterministic 4096x4096 plasma image onto itself
# (blend pipeline); -bench runs the pipeline 6x internally.
# Single-threaded (built --disable-openmp; verified Threads: 1).
# Usage: bench_composite.sh [budget_seconds] [magick_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
MAGICK="${2:-$BUILD_DIR/utilities/magick}"
INPUT="${IM_INPUT:-$INT_DIR/im_input.png}"
ITERS=6   # ~21 s
export MAGICK_CONFIGURE_PATH="${MAGICK_CONFIGURE_PATH:-$SRC_DIR/config}"

require "$MAGICK" "magick not found: $MAGICK"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP composite" "$BUDGET" \
  --warmup "$MAGICK" -bench 1 "$INPUT" "$INPUT" -compose Over -composite /dev/null -- \
  "$MAGICK" -bench "$ITERS" "$INPUT" "$INPUT" -compose Over -composite /dev/null
echo "$APP composite: iterations=$ITER wall=${ELAPSED}s (magick -bench $ITERS x Over-composite)"
echo "$APP composite: binary=$MAGICK input=$INPUT"
