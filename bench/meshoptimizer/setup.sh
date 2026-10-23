#!/usr/bin/env bash
# setup.sh - generate the meshoptimizer benchmark input (idempotent,
# deterministic):
#
#   * intermediates/meshoptimizer/mesh.bin  deterministic 15.8M-triangle
#     heightfield mesh (gen_mesh 2816; integer-hash value noise,
#     bit-identical on any platform); binary format (uint32 nverts,
#     uint32 ntris, float verts[nverts][3], uint32 indices[ntris][3])
#
# gen_mesh is shared with recast: source tools/gen_mesh.cpp, binary
# built into intermediates/tools/gen_mesh (idempotent - whichever of the
# two apps' setup runs first builds it).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR" "$TOOLS_INT"

build_tool gen_mesh clang++ "$TOOLS_INT" $CFLAGS_BOLT -std=c++17 $LDFLAGS_BOLT

if [ ! -f "$INT_DIR/mesh.bin" ]; then
  echo "== generating mesh.bin (gen_mesh 2816, 15.8M tris) ..."
  "$TOOLS_INT/gen_mesh" 2816 "$INT_DIR/mesh.bin"
fi

setup_done
