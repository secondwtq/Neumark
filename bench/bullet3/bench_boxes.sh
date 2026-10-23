#!/usr/bin/env bash
# bench_boxes.sh - single-command benchmark:
#   bullet_bench 1 <frames>   (~20 s/iter)
# Bullet3 "3000 boxes" scene (App_Benchmarks test 1): a grid of falling
# boxes stressing box-box collision detection and the sequential-impulse
# constraint solver.  Single-threaded btDiscreteDynamicsWorld, dt=1/60.
# Usage: bench_boxes.sh [budget_seconds] [bullet_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/bullet_bench}"
FRAMES=3800   # ~20 s

require "$BIN" "bullet_bench not found: $BIN"

run_bench "$APP boxes" "$BUDGET" \
  --warmup "$BIN" 1 60 -- \
  "$BIN" 1 "$FRAMES"
FPS=$(rate "$((FRAMES * ITER))" "$ELAPSED")
echo "$APP boxes: iterations=$ITER wall=${ELAPSED}s frames=$((FRAMES * ITER)) (${FPS} fps)"
echo "$APP boxes: binary=$BIN scene=1 (3000 boxes)"
