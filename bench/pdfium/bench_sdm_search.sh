#!/usr/bin/env bash
# bench_sdm_search.sh - find-in-page search in the full SDM:
#   pdfium_bench search sdm.pdf 5 "CPUID" "page fault" \
#       "last branch record" "the current privilege level" \
#       "If a memory operand effective address is outside the"
#       (~20 s/iter)
# FPDFText_FindStart/FindNext on every page, five real-world queries of
# successively increasing length, one more word each (one per pass:
# 1/2/3/4/9 words, 5/10/18/27/52 chars, 114-1729 hit pages), the last one
# half a sentence; the checksum folds all five queries' hit counts + bytes.
# Usage: bench_sdm_search.sh [budget_seconds] [binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$REPO_ROOT/intermediates/pdfium/pdfium_bench}"

require "$BIN" "pdfium_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
INPUT="${PDFIUM_SDM:-$INT_DIR/sdm.pdf}"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP search" "$BUDGET" "$BIN" search "$INPUT" 5 \
  "CPUID" "page fault" "last branch record" "the current privilege level" \
  "If a memory operand effective address is outside the"
echo "$APP search: iterations=$ITER wall=${ELAPSED}s (5363 SDM pages, 5 queries of increasing length: CPUID 1w / page fault 2w / last branch record 3w / the current privilege level 4w / 'If a memory operand effective address is outside the' 9w)"
echo "$APP search: binary=$BIN"
