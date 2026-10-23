#!/usr/bin/env bash
# setup.sh - generate the imagemagick benchmark input (idempotent,
# byte-deterministic):
#
#   * intermediates/ImageMagick/im_input.png  4096x4096 plasma image
#     (magick's own plasma:fractal generator, fixed seed 42; date/time
#     PNG chunks excluded so the file is byte-identical on every
#     regeneration)
#
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

if [ ! -f "$INT_DIR/im_input.png" ]; then
  echo "== generating im_input.png (4096x4096 plasma, seed 42) ..."
  IM_MAGICK="$BUILD_DIR/utilities/magick"
  MAGICK_CONFIGURE_PATH="$SRC_DIR/config" \
    "$IM_MAGICK" -seed 42 -size 4096x4096 plasma:fractal \
    -define png:exclude-chunks=date,time "$INT_DIR/im_input.png"
fi

setup_done
