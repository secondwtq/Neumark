#!/usr/bin/env bash
# bench_sdm_merge.sh - import + re-save the full SDM:
#   pdfium_bench merge sdm.pdf 1 8   (~15.5 s/iter)
# import all 5363 pages 8x into a fresh doc, FPDF_SaveAsCopy to memory,
# re-parse and pixel-check a sample. Raw output bytes are not deterministic
# (absl hash seeding), so the A/B checksum covers page count + re-rendered
# sample pixels.
# Usage: bench_sdm_merge.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_SDM:-$INT_DIR/sdm.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP merge" "$BUDGET" "$BIN" merge "$INPUT" 1 8
echo "$APP merge: iterations=$ITER wall=${ELAPSED}s (5363 SDM pages x8 copies of $INPUT)"
echo "$APP merge: binary=$BIN"
