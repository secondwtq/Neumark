#!/usr/bin/env bash
# bench.sh - single-command benchmark:
#   dwz -q -o <out> <DWARF binary>
# DWARF compression (deduplication + compression) of GCC's public Debian
# cc1 executable with its matching DWARF data.
# The -o flag keeps the input intact, so the same file is reused every
# iteration.  Single-threaded (default; -j is not used).
# Usage: bench.sh [budget_seconds] [dwz_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
DWZ="${2:-$REPO_ROOT/work/dwz/dwz}"
INPUT="${DWZ_INPUT:-$DWARF_INPUT}"
OUT=$INT_DIR/dwz_out.so

require "$DWZ" "dwz not found: $DWZ"
require "$INPUT" "input not found: $INPUT (run bench/dwz/setup.sh or set DWZ_INPUT)"

run_bench "$APP" "$BUDGET" "$DWZ" -q -o "$OUT" "$INPUT"
echo "$APP: iterations=$ITER wall=${ELAPSED}s"
echo "$APP: binary=$DWZ input=$INPUT"
