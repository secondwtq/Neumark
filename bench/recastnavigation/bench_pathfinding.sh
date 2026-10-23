#!/usr/bin/env bash
# bench_pathfinding.sh - single-command benchmark:
#   recast_bench path <recast_city.bin> <queries>   (~20 s/iter)
# Builds the "city" navmesh once, then runs <queries> Detour
# pathfinding queries (findNearestPoly + findPath + findStraightPath)
# between a pool of walkable points.  Deterministic (seeded RNG).
# Single-threaded.
# Usage: bench_pathfinding.sh [budget_seconds] [recast_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/recast_bench}"
MESH="${RECAST_MESH:-$INT_DIR/recast_city.obj}"
QUERIES=2800000   # ~20 s at cs=0.25/ch=0.15

require "$BIN" "recast_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH"

run_bench "$APP pathfinding" "$BUDGET" \
  --warmup "$BIN" path "$MESH" 1000 -- \
  "$BIN" path "$MESH" "$QUERIES" 0.25 0.15
RATE=$(rate "$((QUERIES * ITER))" "$ELAPSED")
echo "$APP pathfinding: iterations=$ITER wall=${ELAPSED}s queries=$((QUERIES * ITER)) (${RATE} queries/s)"
echo "$APP pathfinding: binary=$BIN mesh=$MESH "
