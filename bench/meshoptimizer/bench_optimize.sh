#!/usr/bin/env bash
# bench_optimize.sh - single-command benchmark:
#   meshopt_bench optimize <mesh.bin> <iters>   (~20 s/iter)
# Vertex-cache + overdraw + vertex-fetch optimization pipeline on a
# deterministic 8.4M-triangle heightfield mesh.  Single-threaded.
# Usage: bench_optimize.sh [budget_seconds] [meshopt_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/meshopt_bench}"
MESH="${MESHOPT_MESH:-$INT_DIR/mesh.bin}"
ITERS=15   # 15 passes of the shared 15.8M-tri mesh ~ 19 s

require "$BIN" "meshopt_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP optimize" "$BUDGET" \
  --warmup "$BIN" optimize "$MESH" 1 -- \
  "$BIN" optimize "$MESH" "$ITERS"
echo "$APP optimize: iterations=$ITER wall=${ELAPSED}s optimize_passes=$((ITERS * ITER))"
echo "$APP optimize: binary=$BIN mesh=$MESH"
