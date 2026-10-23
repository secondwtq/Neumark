#!/usr/bin/env bash
# build.sh - build the shared mesh generator gen_mesh, BOLT-ready.
#
# gen_mesh is the only input generator shared by two applications (recast's
# "city" scene, meshoptimizer's heightfield); the binary is an intermediate
# result at intermediates/tools/gen_mesh. It is also built idempotently by
# bench/recastnavigation/setup.sh and bench/meshoptimizer/setup.sh.
#
# Toolchain/flags: see the top-level README.md (any recent LLVM/Clang
# works; CFLAGS_BOLT / LDFLAGS_BOLT are env-overridable).
#
# Usage: build.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/bench/vars.sh"

mkdir -p "$INT_DIR"
clang++ $CFLAGS_BOLT -std=c++17 \
  "$SCRIPT_DIR/gen_mesh.cpp" $LDFLAGS_BOLT -o "$INT_DIR/gen_mesh"

echo "gen_mesh ready: $INT_DIR/gen_mesh"
