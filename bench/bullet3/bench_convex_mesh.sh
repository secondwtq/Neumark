#!/usr/bin/env bash
# bench_convex_mesh.sh - single-command benchmark:
#   bullet_bench 6 <frames>   (~20 s/iter)
# Bullet3 "Convex vs Mesh" scene (App_Benchmarks test 6): convex hull
# shapes (btConvexHullShape) falling onto a triangle mesh - stresses
# convex-vs-triangle-mesh collision.  Single-threaded, dt=1/60.
# Usage: bench_convex_mesh.sh [budget_seconds] [bullet_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/bullet_bench}"
FRAMES=9500   # ~20 s

require "$BIN" "bullet_bench not found: $BIN"

run_bench "$APP convex_mesh" "$BUDGET" \
  --warmup "$BIN" 6 60 -- \
  "$BIN" 6 "$FRAMES"
FPS=$(rate "$((FRAMES * ITER))" "$ELAPSED")
echo "$APP convex_mesh: iterations=$ITER wall=${ELAPSED}s frames=$((FRAMES * ITER)) (${FPS} fps)"
echo "$APP convex_mesh: binary=$BIN scene=6 (Convex vs Mesh)"
