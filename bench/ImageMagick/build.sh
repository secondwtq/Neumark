#!/usr/bin/env bash
# build.sh - fetch and build the ImageMagick benchmark binary, BOLT-ready.
#
#   * downloads the source into work/ImageMagick (git clone, pinned to a fixed commit,
#     skipped if the clone is already present)
#   * builds work/ImageMagick/build-bolt/utilities/magick with the BOLT
#     flags; OpenMP is disabled so the binary is single-threaded
#
# The scripts call clang / clang++ / ld.lld from PATH.
# -fuse-ld=lld needs an lld on PATH; alternatively override LDFLAGS_BOLT
# (GNU ld also supports --emit-relocs). CFLAGS_BOLT / LDFLAGS_BOLT can
# be overridden via the environment. At runtime the benchmark scripts set
# MAGICK_CONFIGURE_PATH to work/ImageMagick/config.
#
# Usage: build.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

# --- fetch the source (idempotent) ------------------------------------------
# pinned source version (release tag); to update, change the pin and
# re-clone (rm -rf work/ImageMagick):
fetch_repo https://github.com/ImageMagick/ImageMagick.git 7.1.1-40

# --- build (autotools; system PNG/JPEG/TIFF/WebP delegates) -------------------
echo "== building ImageMagick ..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
CC=clang CFLAGS="$CFLAGS_BOLT" LDFLAGS="$LDFLAGS_BOLT" \
  "$SRC_DIR/configure" --prefix="$PWD/install" --disable-openmp --disable-shared \
  --enable-static --disable-docs --without-modules --without-magick-plus-plus \
  --without-perl --without-x --disable-hdri --with-quantum-depth=16
make -j

echo "imagemagick ready: $BUILD_DIR/utilities/magick"
echo "note: runtime config path is work/ImageMagick/config (MAGICK_CONFIGURE_PATH)"
