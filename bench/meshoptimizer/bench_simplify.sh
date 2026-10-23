#!/usr/bin/env bash
# bench_simplify.sh - single-command benchmark:
#   meshopt_bench simplify <mesh.bin> <iters>   (~20 s/iter)
# meshopt_simplify to 50% triangle count on a deterministic 8.4M-triangle
# heightfield mesh.  Single-threaded, deterministic.
# Usage: bench_simplify.sh [budget_seconds] [meshopt_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/meshopt_bench}"
MESH="${MESHOPT_MESH:-$INT_DIR/mesh.bin}"
ITERS=5    # 5 passes of the shared 15.8M-tri mesh ~ 21 s

require "$BIN" "meshopt_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP simplify" "$BUDGET" \
  --warmup "$BIN" simplify "$MESH" 1 -- \
  "$BIN" simplify "$MESH" "$ITERS"
echo "$APP simplify: iterations=$ITER wall=${ELAPSED}s simplify_passes=$((ITERS * ITER))"
echo "$APP simplify: binary=$BIN mesh=$MESH"
