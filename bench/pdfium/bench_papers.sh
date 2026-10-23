#!/usr/bin/env bash
# bench_papers.sh - render formula-dense documents:
#   pdfium_bench render papers.pdf 2 2.5   (~20.7 s/iter)
# 2610 pages of six documents packed with dense, complex formulas
# (measured 4-18 equations/page): Ginsparg's Applied Conformal Field Theory
# (the densest), Tong's General Relativity and QFT notes, Siegel's Fields,
# Qualls' CFT notes and Vakil's "The Rising Sea" - concatenated by gen_pdf
# cat; rendered at 2.5x (180 dpi), 2 passes; sampled pixel checksum for
# A/B verification.
# Usage: bench_papers.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_PAPERS:-$INT_DIR/papers.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP papers" "$BUDGET" "$BIN" render "$INPUT" 2 2.5
echo "$APP papers: iterations=$ITER wall=${ELAPSED}s (2610 formula-dense pages x2 @2.5x of $INPUT)"
echo "$APP papers: binary=$BIN"
