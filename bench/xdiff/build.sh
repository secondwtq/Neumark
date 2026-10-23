#!/usr/bin/env bash
# build.sh - fetch and build the git-xdiff benchmark harness, BOLT-ready.
#
#   * downloads git's source into work/xdiff (git clone, pinned to a fixed
#     release tag, skipped if the clone is already present)
#   * compiles git's xdiff/ engine - the diff engine behind `git diff`,
#     `git log -p` and `git blame` - together with the harness
#     diff_bench.cpp into intermediates/xdiff/diff_bench (an intermediate
#     result)
#
# Only the xdiff/ subtree of git is built (~7 C files); nothing else from
# git is needed.  The engine expects git's compat wrappers (xmalloc,
# BUG_fl, ...), which the harness provides (see diff_bench.cpp).
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
# re-clone (rm -rf work/xdiff):
fetch_repo https://github.com/git/git.git v2.55.0

# --- build the xdiff engine + harness ----------------------------------------
# (xdiff sources are C, the harness is C++; keep the engine compiled as C)
echo "== building diff_bench harness ..."
mkdir -p "$INT_DIR"
for f in "$SRC_DIR"/xdiff/*.c; do
  clang $CFLAGS_BOLT -I "$SRC_DIR" -I "$SRC_DIR/xdiff" \
    -c "$f" -o "$INT_DIR/$(basename "${f%.c}").o"
done
clang++ $CFLAGS_BOLT -I "$SRC_DIR/xdiff" \
  "$SCRIPT_DIR/diff_bench.cpp" "$INT_DIR"/*.o \
  $LDFLAGS_BOLT -o "$INT_DIR/diff_bench"

echo "xdiff ready: $INT_DIR/diff_bench"
