#!/usr/bin/env bash
# build.sh - fetch and build the flac benchmark binary, BOLT-ready.
#
#   * downloads the source into work/flac (git clone, pinned to a fixed commit, skipped if
#     the clone is already present)
#   * builds work/flac/build-bolt/src/flac/flac with the BOLT flags
#     (relocations, non-PIE, per-function sections, DWARF, frame pointers)
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
# re-clone (rm -rf work/flac):
fetch_repo https://github.com/xiph/flac.git 1.5.0

# --- build -------------------------------------------------------------------
echo "== building flac ..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_C_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DBUILD_PROGRAMS=ON -DBUILD_CXXLIBS=OFF -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DWITH_OGG=OFF \
  -DWITH_FORTIFY_SOURCE=OFF -DWITH_STACK_PROTECTOR=OFF \
  -DENABLE_MULTITHREADING=ON -DINSTALL_MANPAGES=OFF
cmake --build "$BUILD_DIR" --target flac

echo "flac ready: $BUILD_DIR/src/flac/flac"
