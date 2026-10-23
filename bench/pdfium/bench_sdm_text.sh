#!/usr/bin/env bash
# bench_sdm_text.sh - text extraction from the full SDM:
#   pdfium_bench text sdm.pdf 5   (~20.0 s/iter)
# FPDFText_GetText for every one of the 5363 pages (real technical text,
# embedded fonts, tables); char checksum for A/B verification.
# Usage: bench_sdm_text.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_SDM:-$INT_DIR/sdm.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP text" "$BUDGET" "$BIN" text "$INPUT" 5
echo "$APP text: iterations=$ITER wall=${ELAPSED}s (5363 SDM pages x5 of $INPUT)"
echo "$APP text: binary=$BIN"
