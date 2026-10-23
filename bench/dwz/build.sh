#!/usr/bin/env bash
# build.sh - fetch and build the dwz benchmark binary, BOLT-ready.
#
#   * downloads the source into work/dwz (git clone, pinned to a fixed commit, skipped if
#     the clone is already present)
#   * builds work/dwz/dwz with the BOLT flags
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
# re-clone (rm -rf work/dwz):
fetch_repo https://sourceware.org/git/dwz.git dwz-0.17

# --- build -------------------------------------------------------------------
echo "== building dwz ..."
make -C "$SRC_DIR" CC=clang CFLAGS="$CFLAGS_BOLT" LDFLAGS="$LDFLAGS_BOLT"

echo "dwz ready: $SRC_DIR/dwz"
