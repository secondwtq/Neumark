#!/usr/bin/env bash
# setup.sh - generate the zstd benchmark inputs (idempotent, deterministic):
#
#   * intermediates/zstd/zstd_corpus.bin   700 MB synthetic corpus
#     (tests/datagen -g700M -P50 -s1) -> zstd -12 ~20 s
#   * intermediates/zstd/zstd_stream.zst   ~9 GB stream (zstd -3 of datagen
#     -g13G -P10 -s2) -> decode ~8 s; size bounded by zstd's decode
#     throughput (~1.1 GB/s), not by level
#
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

DATAGEN=$SRC_DIR/tests/datagen
ZSTD_BIN=$BUILD_DIR/programs/zstd
SYSTEM_ZSTD=$(command -v zstd || true)

# datagen tool (deterministic synthetic data generator, from zstd's tests)
if [ ! -x "$DATAGEN" ]; then
  echo "== building datagen ..."
  make -C "$REPO_ROOT/work/zstd/tests" datagen
fi

# --- compress input: 700 MB, 50% compressible, seed 1 -----------------------
# (level -12 is ~10x slower than -3, so the corpus can be 10x smaller)
if [ ! -f "$INT_DIR/zstd_corpus.bin" ]; then
  echo "== generating zstd_corpus.bin (datagen -g700M -P50 -s1) ..."
  "$DATAGEN" -g700M -P50 -s1 > "$INT_DIR/zstd_corpus.bin"
fi

# --- decompress input: stream of 13 GB, 10% compressible, seed 2 ------------
# (raw corpus is temporary - only the stream is kept; low compressibility
# gives a large stream so the decode benchmark runs ~8 s)
if [ ! -f "$INT_DIR/zstd_stream.zst" ]; then
  echo "== generating temporary datagen corpus + zstd -3 stream ..."
  "$DATAGEN" -g13G -P10 -s2 > "$INT_DIR/zstd_corpus.tmp"
  if [ -n "$SYSTEM_ZSTD" ]; then
    "$SYSTEM_ZSTD" -q -T0 -3 -f "$INT_DIR/zstd_corpus.tmp" -o "$INT_DIR/zstd_stream.zst"
  else
    "$ZSTD_BIN" -q -T1 -3 -f "$INT_DIR/zstd_corpus.tmp" -o "$INT_DIR/zstd_stream.zst"
  fi
  rm -f "$INT_DIR/zstd_corpus.tmp"
fi

setup_done
