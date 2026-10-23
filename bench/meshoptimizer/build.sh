#!/usr/bin/env bash
# build.sh - fetch and build the meshoptimizer benchmark harness, BOLT-ready.
#
#   * downloads the source into work/meshoptimizer (git clone, pinned to a fixed commit,
#     skipped if the clone is already present)
#   * compiles the library together with the harness meshopt_bench.cpp
#     into intermediates/meshoptimizer/meshopt_bench (the binary is an
#     intermediate result; meshoptimizer ships no CLI anymore)
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
# re-clone (rm -rf work/meshoptimizer):
fetch_repo https://github.com/zeux/meshoptimizer.git v0.24

# --- build harness + library (intermediate result -> intermediates/meshoptimizer/) -
echo "== building meshopt_bench harness ..."
mkdir -p "$INT_DIR"
clang++ $CFLAGS_BOLT -std=c++17 \
  -I "$SRC_DIR/src" "$SCRIPT_DIR/meshopt_bench.cpp" "$SRC_DIR"/src/*.cpp \
  $LDFLAGS_BOLT -o "$INT_DIR/meshopt_bench"

echo "meshopt ready: $INT_DIR/meshopt_bench"
