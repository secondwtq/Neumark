#!/usr/bin/env bash
# Full-cost Myers diff (XDF_NEED_MINIMAL - git diff --minimal) over a corpus of 58 of the longest real-world single
# source files, each diffed between two multi-year-apart versions (json.hpp,
# ufbx.c, X86ISelLowering, clang Sema*, sqlite3.c, v8, WebKit JSC/WebKit/
# WebCore, gecko, gcc, postgres, qemu, coreclr, swift, erlang, chromium,
# mame, linux phy, clickhouse, libreoffice, jdk, hermes, R, ffmpeg,
# cataclysm, skia, mariadb, rustc): ~1065k old + ~1265k new lines per pass.
# Real source diffs are fast (~2880 ms/pass), so 6 passes per
# iteration fill the budget (meshopt's codec_decode precedent: 500 passes).
# Single-threaded, deterministic; every pass is verified inside the
# harness (the emitted diff must reproduce both trees exactly).
# Usage: bench_minimal.sh [budget_seconds] [diff_bench_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
BIN="${2:-$INT_DIR/diff_bench}"
OLD="${XDIFF_TREE_OLD:-$INT_DIR/tree/old}"
NEW="${XDIFF_TREE_NEW:-$INT_DIR/tree/new}"
PASSES=6

require "$BIN" "diff_bench not found: $BIN (run $SCRIPT_DIR/build.sh)"
require "$OLD" "input not found: $OLD (run $SCRIPT_DIR/setup.sh)"
require "$NEW" "input not found: $NEW (run $SCRIPT_DIR/setup.sh)"

run_bench "$APP minimal" "$BUDGET" \
  --warmup "$BIN" minimal "$OLD" "$NEW" 1 -- \
  "$BIN" minimal "$OLD" "$NEW" "$PASSES"
echo "$APP minimal: iterations=$ITER wall=${ELAPSED}s passes=$((PASSES * ITER))"
echo "$APP minimal: binary=$BIN old=$OLD new=$NEW"
