#!/usr/bin/env bash
# bench_codec_encode.sh - single-command benchmark:
#   meshopt_bench codec_encode <mesh.bin> <iters>   (~20 s/iter)
# meshopt_encodeIndexBuffer + encodeVertexBuffer (the glTF mesh codec) on a
# deterministic 8.4M-triangle heightfield mesh.  Single-threaded.
# Usage: bench_codec_encode.sh [budget_seconds] [meshopt_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/meshopt_bench}"
MESH="${MESHOPT_MESH:-$INT_DIR/mesh.bin}"
ITERS=65   # 65 passes of the shared 15.8M-tri mesh ~ 19 s

require "$BIN" "meshopt_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP codec_encode" "$BUDGET" \
  --warmup "$BIN" codec_encode "$MESH" 1 -- \
  "$BIN" codec_encode "$MESH" "$ITERS"
echo "$APP codec_encode: iterations=$ITER wall=${ELAPSED}s encode_passes=$((ITERS * ITER))"
echo "$APP codec_encode: binary=$BIN mesh=$MESH"
