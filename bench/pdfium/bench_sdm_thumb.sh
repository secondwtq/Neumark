#!/usr/bin/env bash
# bench_sdm_thumb.sh - thumbnail strip of the full SDM:
#   pdfium_bench thumb sdm.pdf 3   (~14 s/iter)
# render all 5363 pages at 0.25x (viewer thumbnail strip); pixel checksum.
# Usage: bench_sdm_thumb.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_SDM:-$INT_DIR/sdm.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP thumb" "$BUDGET" "$BIN" thumb "$INPUT" 3
echo "$APP thumb: iterations=$ITER wall=${ELAPSED}s (5363 SDM pages x3 @0.25x of $INPUT)"
echo "$APP thumb: binary=$BIN"
