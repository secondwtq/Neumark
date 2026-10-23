#!/usr/bin/env bash
# bench.sh - single-command benchmark:
#   bloaty -d compileunits <input> > /dev/null
# Input: Debian's public LLVM 19 shared library with its matching DWARF data.
# Point BLOATY_INPUT at another debug binary to reproduce elsewhere.
# Usage: bench.sh [budget_seconds] [bloaty_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BLOATY="${2:-$REPO_ROOT/work/bloaty/build-bolt/bloaty}"
INPUT="${BLOATY_INPUT:-$BLOATY_INPUT_DEFAULT}"

require "$INPUT" "missing input $INPUT (run bench/bloaty/setup.sh or set BLOATY_INPUT)"
require "$BLOATY" "bloaty binary not found: $BLOATY"

run_bench "$APP" "$BUDGET" "$BLOATY" -d compileunits "$INPUT"
echo "$APP: iterations=$ITER wall=${ELAPSED}s"
echo "$APP: binary=$BLOATY input=$INPUT"
