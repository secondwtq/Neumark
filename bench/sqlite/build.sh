#!/usr/bin/env bash
# build.sh - fetch and build the sqlite benchmark binary, BOLT-ready.
#
#   * downloads the source into work/sqlite (git clone, pinned to a fixed commit, skipped
#     if the clone is already present)
#   * builds work/sqlite/build-bolt/sqlite3 with the BOLT flags
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
# re-clone (rm -rf work/sqlite):
fetch_repo https://github.com/sqlite/sqlite.git version-3.47.0

# --- build (autotools) --------------------------------------------------------
echo "== building sqlite3 ..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC=clang CFLAGS="$CFLAGS_BOLT" LDFLAGS="$LDFLAGS_BOLT" \
  "$SRC_DIR/configure" --disable-shared --enable-static
make -j sqlite3

echo "sqlite ready: $BUILD_DIR/sqlite3"
