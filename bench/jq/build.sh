#!/usr/bin/env bash
# build.sh - fetch and build the jq benchmark binary, BOLT-ready.
#
#   * downloads the source into work/jq (git clone, pinned to a fixed commit, skipped if
#     the clone is already present)
#   * builds work/jq/build-bolt with the BOLT flags
#     (relocations, non-PIE, per-function sections, DWARF, frame pointers)
#
# Note: the real binary is build-bolt/.libs/jq - the top-level jq is a
# libtool wrapper, so use .libs/jq for BOLT profiling.
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
# re-clone (rm -rf work/jq):
fetch_repo https://github.com/jqlang/jq.git jq-1.8.1

# --- build (autotools) --------------------------------------------------------
echo "== building jq ..."
(cd "$SRC_DIR" && autoreconf -i)
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC=clang CFLAGS="$CFLAGS_BOLT" LDFLAGS="$LDFLAGS_BOLT" \
  "$SRC_DIR/configure" --disable-maintainer-mode --disable-docs
make -j

echo "jq ready: $BUILD_DIR/.libs/jq  (top-level $BUILD_DIR/jq is a libtool wrapper)"
