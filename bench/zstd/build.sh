#!/usr/bin/env bash
# build.sh - fetch and build the zstd benchmark binary, BOLT-ready.
#
#   * downloads the source into work/zstd (git clone, pinned to a fixed commit, skipped if
#     the clone is already present)
#   * builds work/zstd/build-bolt/programs/zstd with the BOLT flags
#     (relocations, non-PIE, per-function sections, DWARF, frame pointers)
#   * builds tests/datagen (deterministic synthetic input generator)
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
# re-clone (rm -rf work/zstd):
fetch_repo https://github.com/facebook/zstd.git v1.5.7

# --- build -------------------------------------------------------------------
echo "== building zstd ..."
cmake -S "$SRC_DIR/build/cmake" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_C_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_CONTRIB=OFF \
  -DZSTD_LEGACY_SUPPORT=ON -DZSTD_MULTITHREAD_SUPPORT=OFF
cmake --build "$BUILD_DIR" --target zstd
echo "== building datagen (input generator) ..."
make -C "$SRC_DIR/tests" datagen

echo "zstd ready: $BUILD_DIR/programs/zstd"
echo "datagen ready: $SRC_DIR/tests/datagen"
