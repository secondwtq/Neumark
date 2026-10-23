#!/usr/bin/env bash
# bench_resize.sh - single-command benchmark:
#   magick -bench 12 <input> -resize 50% /dev/null   (~20 s/iter)
# Lanczos resample of a deterministic 4096x4096 plasma image; -bench runs
# the whole pipeline (read + resize + PNG encode) 12x internally.
# Single-threaded (built --disable-openmp; verified Threads: 1).
# Usage: bench_resize.sh [budget_seconds] [magick_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
MAGICK="${2:-$BUILD_DIR/utilities/magick}"
INPUT="${IM_INPUT:-$INT_DIR/im_input.png}"
ITERS=14   # ~20 s
export MAGICK_CONFIGURE_PATH="${MAGICK_CONFIGURE_PATH:-$SRC_DIR/config}"

require "$MAGICK" "magick not found: $MAGICK"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP resize" "$BUDGET" \
  --warmup "$MAGICK" -bench 1 "$INPUT" -resize 50% /dev/null -- \
  "$MAGICK" -bench "$ITERS" "$INPUT" -resize 50% /dev/null
echo "$APP resize: iterations=$ITER wall=${ELAPSED}s (magick -bench $ITERS x resize 50%)"
echo "$APP resize: binary=$MAGICK input=$INPUT"
