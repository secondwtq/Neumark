#!/usr/bin/env bash
# bench_sdm_render.sh - render the full Intel SDM (real-world):
#   pdfium_bench render sdm.pdf 1 2.0   (~15.2 s/iter)
# render all 5363 pages of the Intel Software Developer's Manual at 2x
# (144 dpi), ANNOT|LCD_TEXT - a real born-digital manual with embedded fonts
# and figures; sampled pixel checksum for A/B verification.
# Usage: bench_sdm_render.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_SDM:-$INT_DIR/sdm.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP render" "$BUDGET" "$BIN" render "$INPUT" 1 2.0
echo "$APP render: iterations=$ITER wall=${ELAPSED}s (5363 SDM pages @2x of $INPUT)"
echo "$APP render: binary=$BIN"
