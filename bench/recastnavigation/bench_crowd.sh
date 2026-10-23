#!/usr/bin/env bash
# bench_crowd.sh - single-command benchmark:
#   recast_bench crowd <recast_city.bin> <agents> <frames>   (~20 s/iter)
# Builds the "city" navmesh once, then simulates 400 crowd
# agents (DetourCrowd: path following + obstacle avoidance + separation)
# for 12000 frames at dt=1/60.  Deterministic.  Single-threaded.
# Usage: bench_crowd.sh [budget_seconds] [recast_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/recast_bench}"
MESH="${RECAST_MESH:-$INT_DIR/recast_city.obj}"
AGENTS=400
FRAMES=15250

require "$BIN" "recast_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH"

run_bench "$APP crowd" "$BUDGET" \
  --warmup "$BIN" crowd "$MESH" 20 60 -- \
  "$BIN" crowd "$MESH" "$AGENTS" "$FRAMES" 0.25 0.15
AF=$((AGENTS * FRAMES * ITER))
RATE=$(rate "$AF" "$ELAPSED" %.0f)
echo "$APP crowd: iterations=$ITER wall=${ELAPSED}s agent-frames=${AF} (${RATE} agent-frames/s)"
echo "$APP crowd: binary=$BIN mesh=$MESH, ${AGENTS} agents, ${FRAMES} frames"
