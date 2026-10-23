#!/usr/bin/env bash
# bench_dot.sh - single-command benchmark:
#   dot -Tsvg big.dot -o /dev/null   (~20 s/iter)
# Hierarchical layout (dot engine) of a deterministic 33x200-node layered
# digraph (~7k nodes, chain + skip edges).  Single-threaded.
# Usage: bench_dot.sh [budget_seconds] [dot_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
DOT="${2:-$REPO_ROOT/work/graphviz/build-bolt/dot}"
INPUT="${DOT_INPUT:-$INT_DIR/big.dot}"

require "$DOT" "dot not found: $DOT"
require "$INPUT" "input not found: $INPUT (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP dot" "$BUDGET" "$DOT" -Tsvg "$INPUT" -o /dev/null
echo "$APP dot: iterations=$ITER wall=${ELAPSED}s (dot layout of $INPUT)"
echo "$APP dot: binary=$DOT"
