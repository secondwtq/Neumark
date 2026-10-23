#!/usr/bin/env bash
# setup.sh - generate the ffmpeg benchmark inputs (idempotent, deterministic):
#
#   * intermediates/ffmpeg/video.y4m  deterministic 1080p YUV420p plasma
#     video (gen_video 1920 1080 950)
#   * intermediates/ffmpeg/video.avi  mpeg4 encode of video.y4m
#     (setup-time, 1 thread)
#
# The gen_video binary is an intermediate result built into
# intermediates/ffmpeg/ from gen_video.cpp (next to this script).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

build_tool gen_video clang++ "$INT_DIR" $CFLAGS_BOLT -std=c++17 $LDFLAGS_BOLT

if [ ! -f "$INT_DIR/video.y4m" ]; then
  echo "== generating video.y4m (gen_video 1920x1080 950) ..."
  "$INT_DIR/gen_video" 1920 1080 950 "$INT_DIR/video.y4m"
fi
if [ ! -f "$INT_DIR/video.avi" ]; then
  echo "== encoding video.avi (ffmpeg mpeg4, 1 thread) ..."
  FFMPEG_BIN=$BUILD_DIR/ffmpeg
  "$FFMPEG_BIN" -y -i "$INT_DIR/video.y4m" -c:v mpeg4 -threads 1 -q:v 5 "$INT_DIR/video.avi" 2>/dev/null
fi

setup_done
