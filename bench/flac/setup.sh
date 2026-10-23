#!/usr/bin/env bash
# setup.sh - generate the flac benchmark inputs (idempotent, deterministic):
#
#   * intermediates/flac/music.wav   ~2.2 GB music-like WAV (gen_wav 12500,
#                                    RF64 container) -> flac -8 ~20 s
#   * intermediates/flac/music.flac  flac -8 encoding -> decode ~8 s
#
# The gen_wav binary is an intermediate result built into intermediates/flac/
# from gen_wav.c (next to this script).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

FLAC_BIN=$BUILD_DIR/src/flac/flac

build_tool gen_wav clang "$INT_DIR" -O3 -ffast-math -fno-math-errno -fveclib=libmvec -lm

if [ ! -f "$INT_DIR/music.wav" ]; then
  echo "== generating music.wav (~2.2 GB, gen_wav 12500) ..."
  "$INT_DIR/gen_wav" 12500 "$INT_DIR/music.wav"
fi
if [ ! -f "$INT_DIR/music.flac" ]; then
  echo "== encoding music.flac (flac -8) ..."
  "$FLAC_BIN" -f -s -8 -o "$INT_DIR/music.flac" "$INT_DIR/music.wav"
fi

setup_done
