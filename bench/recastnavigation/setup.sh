#!/usr/bin/env bash
# setup.sh - generate the recast benchmark input (idempotent, deterministic):
#
#   * intermediates/recastnavigation/recast_city.obj  deterministic 512x512 "city"
#     scene (gen_mesh 512 city v2 = 512x512 terrain + 145 buildings + 70
#     floating slabs + 55 ramps; 525k tris, multi-level with overhangs and
#     slopes; built at cs=0.25/ch=0.15 resolution - just under the
#     65535-vert navmesh cap and the largest resolution the scene supports)
#
# gen_mesh is shared with meshoptimizer: source tools/gen_mesh.cpp,
# binary built into intermediates/tools/gen_mesh (idempotent - whichever of
# the two apps' setup runs first builds it).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR" "$TOOLS_INT"

build_tool gen_mesh clang++ "$TOOLS_INT" $CFLAGS_BOLT -std=c++17 $LDFLAGS_BOLT

if [ ! -f "$INT_DIR/recast_city.obj" ]; then
  echo "== generating recast_city.obj (gen_mesh 512 city) ..."
  "$TOOLS_INT/gen_mesh" 512 "$INT_DIR/recast_city.obj" city
fi

setup_done
