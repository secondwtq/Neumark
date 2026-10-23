#!/usr/bin/env bash
# build.sh - fetch and build the recast benchmark harness, BOLT-ready.
#
#   * downloads the source into work/recastnavigation (git clone, pinned to a fixed commit,
#     skipped if the clone is already present)
#   * builds the Recast/Detour/DetourCrowd libraries (build-bolt) and the
#     headless harness recast_bench.cpp into intermediates/recastnavigation/recast_bench
#     (the binary is an intermediate result)
#
# The scripts call clang / clang++ / ld.lld from PATH.
# -fuse-ld=lld needs an lld on PATH; alternatively override LDFLAGS_BOLT
# (GNU ld also supports --emit-relocs). CFLAGS_BOLT / LDFLAGS_BOLT can
# be overridden via the environment.
#
# Usage: build.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

# --- fetch the source (idempotent) ------------------------------------------
# pinned source version (release tag); to update, change the pin and
# re-clone (rm -rf work/recastnavigation):
fetch_repo https://github.com/recastnavigation/recastnavigation.git v1.6.0

# --- build libraries ----------------------------------------------------------
echo "== building recastnavigation libraries ..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="$CFLAGS_BOLT" -DCMAKE_CXX_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DRECASTNAVIGATION_DEMO=OFF -DRECASTNAVIGATION_TESTS=OFF \
  -DRECASTNAVIGATION_EXAMPLES=OFF
cmake --build "$BUILD_DIR"

# --- build harness (intermediate result -> intermediates/recastnavigation/) ------------
# (Recast libs are built with -fno-rtti -fno-exceptions; match it)
echo "== building recast_bench harness ..."
mkdir -p "$INT_DIR"
# same flags as the libraries (built with -fno-rtti -fno-exceptions +
# CFLAGS_BOLT from vars.sh)
clang++ $CFLAGS_BOLT -fno-rtti -fno-exceptions -std=c++17 \
  -I "$SRC_DIR/Recast/Include" -I "$SRC_DIR/Detour/Include" -I "$SRC_DIR/DetourCrowd/Include" \
  "$SCRIPT_DIR/recast_bench.cpp" \
  "$BUILD_DIR/Recast/libRecast.a" "$BUILD_DIR/Detour/libDetour.a" \
  "$BUILD_DIR/DetourCrowd/libDetourCrowd.a" \
  $LDFLAGS_BOLT -o "$INT_DIR/recast_bench"

echo "recast ready: $INT_DIR/recast_bench"
