#!/usr/bin/env bash
# bench_vector.sh - render the real-vector gallery:
#   pdfium_bench render vector_book.pdf 1 4.0   (~18.2 s/iter)
# 52 pages cycling 13 real vector artworks: the Ghostscript tiger, five
# classic demo images (golfer, Escher, Vasarely, Koch snowflakes, Dore
# engraving), the OpenStreetMap historic peninsula of Istanbul, and six
# files from the MPVG dataset (car, contour, drops, hawaii, paris-30k with
# 30k paths, reschart - SVG, converted with rsvg-convert). Rendered at 4x
# (288 dpi), pixel checksum for A/B verification.
# Usage: bench_vector.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_VECTOR:-$INT_DIR/vector_book.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP vector" "$BUDGET" "$BIN" render "$INPUT" 1 4.0
echo "$APP vector: iterations=$ITER wall=${ELAPSED}s (52 vector-gallery pages @4x: 13 artworks incl. MPVG car/contour/drops/hawaii/paris-30k/reschart, of $INPUT)"
echo "$APP vector: binary=$BIN"
