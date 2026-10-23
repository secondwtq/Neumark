#!/usr/bin/env bash
# bench_build.sh - single-command benchmark:
#   recast_bench build <recast_city.bin> <builds>   (~20 s/iter)
# Full Recast navmesh pipeline (rasterize -> filters -> watershed regions ->
# contours -> poly mesh -> detail mesh -> Detour navmesh) on the
# deterministic 524k-triangle "city" scene, repeated <builds> times.
# Single-threaded.
# Usage: bench_build.sh [budget_seconds] [recast_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/recast_bench}"
MESH="${RECAST_MESH:-$INT_DIR/recast_city.obj}"
BUILDS=4     # 4 builds at cs=0.25/ch=0.15 ~ 18.5 s

require "$BIN" "recast_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH"

run_bench "$APP build" "$BUDGET" \
  --warmup "$BIN" build "$MESH" 1 -- \
  "$BIN" build "$MESH" "$BUILDS" 0.25 0.15
RATE=$(rate "$((BUILDS * ITER))" "$ELAPSED")
echo "$APP build: iterations=$ITER wall=${ELAPSED}s builds=$((BUILDS * ITER)) (${RATE} builds/s)"
echo "$APP build: binary=$BIN mesh=$MESH "
