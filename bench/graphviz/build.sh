#!/usr/bin/env bash
# build.sh - fetch and build the graphviz benchmark binary, BOLT-ready.
#
#   * downloads the source into work/graphviz (git clone, pinned to a fixed commit,
#     skipped if the clone is already present)
#   * builds work/graphviz/build-bolt/dot with the BOLT flags; everything
#     external is disabled (--without-libgd is required: the system libgd
#     drags in a broken libSvtAv1Enc.so.3 dependency)
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
# re-clone (rm -rf work/graphviz):
fetch_repo https://gitlab.com/graphviz/graphviz.git 12.1.1

# --- build (autotools) --------------------------------------------------------
echo "== building graphviz ..."
(cd "$SRC_DIR" && ./autogen.sh)
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC=clang CFLAGS="$CFLAGS_BOLT" LDFLAGS="$LDFLAGS_BOLT" \
  "$SRC_DIR/configure" --without-x --without-libgd --without-pango --without-cairo \
  --without-gdk-pixbuf --without-gts --without-qt --without-gtk \
  --without-glitz --without-freetype --without-fontconfig \
  --disable-java --disable-php --disable-python --disable-ruby --disable-tcl \
  --disable-perl --disable-lua --disable-sharp --disable-go --disable-r \
  --disable-rust --disable-ltdl --disable-shared --enable-static
make -j
# dot is built as cmd/dot/dot_static; the tool selects its layout engine
# from argv[0], so the benchmark binary must be named dot:
cp "$BUILD_DIR/cmd/dot/dot_static" "$BUILD_DIR/dot"

echo "graphviz ready: $BUILD_DIR/dot"
