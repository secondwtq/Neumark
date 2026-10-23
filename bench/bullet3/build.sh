#!/usr/bin/env bash
# build.sh - fetch and build the bullet benchmark harness, BOLT-ready.
#
#   * downloads the source into work/bullet3 (git clone, pinned to a fixed commit, skipped
#     if the clone is already present)
#   * builds the Bullet libraries (build-bolt) and the headless harness
#     bullet_bench.cpp (App_Benchmarks scenes, no rendering) into
#     intermediates/bullet3/bullet_bench (the binary is an intermediate
#     result)
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
# re-clone (rm -rf work/bullet3):
fetch_repo https://github.com/bulletphysics/bullet3.git 3.24

# --- build libraries ----------------------------------------------------------
echo "== building bullet3 libraries ..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="$CFLAGS_BOLT" -DCMAKE_CXX_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DBUILD_EXAMPLES=OFF -DBUILD_UNIT_TESTS=OFF -DBUILD_CPU_DEMOS=OFF \
  -DBUILD_OPENGL3_DEMOS=OFF -DBUILD_BULLET2_DEMOS=OFF -DBUILD_SHARED_LIBS=OFF \
  -DBULLET2_MULTITHREADING=OFF -DINSTALL_LIBS=OFF
cmake --build "$BUILD_DIR"

# --- build harness (intermediate result -> intermediates/bullet3/) ------------
echo "== building bullet_bench harness ..."
mkdir -p "$INT_DIR"
clang++ $CFLAGS_BOLT -std=c++17 \
  -I "$SRC_DIR/src" -I "$SRC_DIR/examples" \
  "$SCRIPT_DIR/bullet_bench.cpp" \
  "$SRC_DIR/examples/Benchmarks/BenchmarkDemo.cpp" \
  "$SRC_DIR/examples/MultiThreadedDemo/CommonRigidBodyMTBase.cpp" \
  "$BUILD_DIR/src/LinearMath/libLinearMath.a" \
  "$BUILD_DIR/src/BulletCollision/libBulletCollision.a" \
  "$BUILD_DIR/src/BulletDynamics/libBulletDynamics.a" \
  $LDFLAGS_BOLT -o "$INT_DIR/bullet_bench"

echo "bullet ready: $INT_DIR/bullet_bench"
