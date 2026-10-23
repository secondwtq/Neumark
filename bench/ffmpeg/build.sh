#!/usr/bin/env bash
# build.sh - fetch and build the ffmpeg benchmark binary, BOLT-ready.
#
#   * downloads the source into work/ffmpeg (git clone, pinned to a fixed commit, skipped
#     if the clone is already present)
#   * builds work/ffmpeg/build-bolt/ffmpeg with the BOLT flags - minimal
#     configure: only the mpeg4 codec, avi/y4m containers, the null muxer
#     and the file protocol
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
# re-clone (rm -rf work/ffmpeg):
fetch_repo https://github.com/FFmpeg/ffmpeg.git n7.1.3

# --- build -------------------------------------------------------------------
echo "== building ffmpeg ..."
mkdir -p "$BUILD_DIR"
cd "$BUILD_DIR"
"$SRC_DIR/configure" --cc=clang --extra-cflags="$CFLAGS_BOLT" --extra-ldflags="$LDFLAGS_BOLT" \
  --disable-everything --disable-doc --disable-debug --disable-x86asm \
  --disable-stripping \
  --enable-encoder=mpeg4 --enable-encoder=wrapped_avframe \
  --enable-decoder=mpeg4 --enable-decoder=rawvideo \
  --enable-muxer=avi --enable-muxer=null \
  --enable-demuxer=avi --enable-demuxer=yuv4mpegpipe \
  --enable-protocol=file --enable-parser=mpeg4video
# ffmpeg's configure appends -fomit-frame-pointer to CFLAGS after our flags
# (removing frame pointers breaks the flamegraph profiling) - strip it from
# the generated config before building:
sed -i 's/ -fomit-frame-pointer//g' ffbuild/config.mak && touch ffbuild/config.mak
make -j ffmpeg

echo "ffmpeg ready: $BUILD_DIR/ffmpeg"
