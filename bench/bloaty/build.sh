#!/usr/bin/env bash
# build.sh - fetch and build the bloaty benchmark binary, BOLT-ready.
#
#   * downloads the source + submodules into work/bloaty (git clone
#     --depth 1, skipped if the clone is already present)
#   * builds work/bloaty/build-bolt/bloaty with the BOLT flags
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

# --- fetch the source + vendored deps (idempotent) ---------------------------
# bloaty vendors abseil, capstone, demumble, googletest, protobuf, re2,
# zlib, zstd
# pinned source version (release tag); to update, change the pin and
# re-clone (rm -rf work/bloaty):
fetch_repo https://github.com/google/bloaty.git v1.1 submodules

# --- patch + build -----------------------------------------------------------
# bloaty's CMakeLists overwrites CMAKE_CXX_FLAGS / CMAKE_CXX_FLAGS_RELEASE,
# discarding externally passed flags (its build would otherwise lose -O3,
# -g and -fno-omit-frame-pointer). Patch the two set() lines to keep them
# (no-op if already patched):
sed -i 's/set(CMAKE_CXX_FLAGS "-W -Wall -Wno-sign-compare")/set(CMAKE_CXX_FLAGS "-W -Wall -Wno-sign-compare -fno-omit-frame-pointer -g")/; s/set(CMAKE_CXX_FLAGS_RELEASE "-O2")/set(CMAKE_CXX_FLAGS_RELEASE "-O2 -fno-omit-frame-pointer -g")/' "$SRC_DIR/CMakeLists.txt"

echo "== building bloaty ..."
cmake -S "$SRC_DIR" -B "$BUILD_DIR" -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="$CFLAGS_BOLT" -DCMAKE_CXX_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
  -DBUILD_TESTING=OFF \
  -DBLOATY_PREFER_SYSTEM_ABSL=OFF -DBLOATY_PREFER_SYSTEM_CAPSTONE=OFF \
  -DBLOATY_PREFER_SYSTEM_PROTOBUF=OFF -DBLOATY_PREFER_SYSTEM_RE2=OFF \
  -DBLOATY_PREFER_SYSTEM_ZLIB=OFF -DBLOATY_PREFER_SYSTEM_ZSTD=OFF
cmake --build "$BUILD_DIR" --target bloaty

echo "bloaty ready: $BUILD_DIR/bloaty"
