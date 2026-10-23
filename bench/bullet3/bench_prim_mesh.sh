#!/usr/bin/env bash
# bench_prim_mesh.sh - single-command benchmark:
#   bullet_bench 5 <frames>   (~20 s/iter)
# Bullet3 "Prim vs Mesh" scene (App_Benchmarks test 5): primitive shapes
# (boxes/spheres) resting on and falling onto a triangle mesh - stresses
# btBvhTriangleMeshShape collision.  Single-threaded, dt=1/60.
# Usage: bench_prim_mesh.sh [budget_seconds] [bullet_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/bullet_bench}"
FRAMES=96000   # ~20 s

require "$BIN" "bullet_bench not found: $BIN"

run_bench "$APP prim_mesh" "$BUDGET" \
  --warmup "$BIN" 5 60 -- \
  "$BIN" 5 "$FRAMES"
FPS=$(rate "$((FRAMES * ITER))" "$ELAPSED")
echo "$APP prim_mesh: iterations=$ITER wall=${ELAPSED}s frames=$((FRAMES * ITER)) (${FPS} fps)"
echo "$APP prim_mesh: binary=$BIN scene=5 (Prim vs Mesh)"
