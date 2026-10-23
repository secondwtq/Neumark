#!/usr/bin/env bash
# bench_codec_decode.sh - single-command benchmark:
#   meshopt_bench codec_decode <mesh.bin> <iters>   (~20 s/iter)
# meshopt_decodeIndexBuffer + decodeVertexBuffer on a pre-encoded
# deterministic 8.4M-triangle heightfield mesh (roundtrip verified at
# startup).  Single-threaded.
# Usage: bench_codec_decode.sh [budget_seconds] [meshopt_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/meshopt_bench}"
MESH="${MESHOPT_MESH:-$INT_DIR/mesh.bin}"
ITERS=500  # 500 passes of the shared 15.8M-tri mesh ~ 20 s (decode is fast)

require "$BIN" "meshopt_bench not found: $BIN"
require "$MESH" "mesh not found: $MESH (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP codec_decode" "$BUDGET" \
  --warmup "$BIN" codec_decode "$MESH" 1 -- \
  "$BIN" codec_decode "$MESH" "$ITERS"
echo "$APP codec_decode: iterations=$ITER wall=${ELAPSED}s decode_passes=$((ITERS * ITER))"
echo "$APP codec_decode: binary=$BIN mesh=$MESH"
