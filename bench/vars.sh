#!/usr/bin/env bash
# vars.sh - shared path/flag variables for the benchmark scripts.
#
# Source it from any script under bench/<app>/:
#
#   source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
#
# Defines (all paths absolute):
#   SCRIPT_DIR   directory of the sourcing script (bench/<app>)
#   APP          application name (basename of SCRIPT_DIR)
#   BENCH_DIR    bench/
#   REPO_ROOT    repository root
#   WORK_DIR     work/ (source clones + build dirs)
#   SRC_DIR      work/<app> - the project dir under work/
#   BUILD_DIR    <SRC_DIR>/build-bolt
#   INT_DIR      intermediates/<app> (this app's generated inputs and
#                intermediate binaries)
#   BLOATY_INPUT_DEFAULT downloaded LLVM shared library with public DWARF
#   DWARF_INPUT  downloaded GCC cc1 with public DWARF for dwz
#   TOOLS_INT    intermediates/tools (shared generators, e.g. gen_mesh)
#   CFLAGS_BOLT  default BOLT compile flags (env-overridable)
#   LDFLAGS_BOLT default BOLT link flags (env-overridable)
#
# Common functions:
#   fetch_repo <url> [commit] [submodules]
#                                  clone the app's source into SRC_DIR if
#                                  not present, pinned to <commit> (hash
#                                  or tag) when given; initializes
#                                  submodules when the third argument is
#                                  non-empty, e.g. bloaty
#   require <path> <message>       print message to stderr and exit 1 if
#                                  path does not exist
#   run_bench <name> <budget> <cmd...>
#                                  run <cmd> repeatedly (stdout/stderr
#                                  silenced) until the budget or 10
#                                  iterations is reached; print
#                                  per-iteration timings; leave ITER and
#                                  ELAPSED (seconds) set for the caller's
#                                  summary line
#   rate <n> <seconds> [fmt]       one-decimal quotient (default %.1f) for
#                                  summary lines
#   build_tool <name> <compiler> <out_dir> <flags...>
#                                  build a generator binary into
#                                  <out_dir>/<name> if missing; the source
#                                  is looked up in tools/ (shared
#                                  generators) then in the app folder
#   setup_done                     print the app's "inputs ready" banner
#                                  + intermediates listing (setup.sh tail)

# directory of the script that sourced us
_CALLER="${BASH_SOURCE[1]:-$0}"
SCRIPT_DIR=$(cd "$(dirname "$_CALLER")" && pwd)
unset _CALLER

APP=$(basename "$SCRIPT_DIR")

BENCH_DIR=$(dirname "$SCRIPT_DIR")
REPO_ROOT=$(dirname "$BENCH_DIR")

WORK_DIR=$REPO_ROOT/work
INT_DIR=$REPO_ROOT/intermediates/$APP
BLOATY_INPUT_DEFAULT=$REPO_ROOT/intermediates/bloaty/libLLVM-19.so
DWARF_INPUT=$REPO_ROOT/intermediates/dwarf/gcc-14-cc1
TOOLS_INT=$REPO_ROOT/intermediates/tools

SRC_DIR=$WORK_DIR/$APP
BUILD_DIR=$SRC_DIR/build-bolt

CFLAGS_BOLT="${CFLAGS_BOLT:--O3 -g -fno-pie -ffunction-sections -fno-omit-frame-pointer}"
LDFLAGS_BOLT="${LDFLAGS_BOLT:--no-pie -Wl,-q -fuse-ld=lld}"

# --- common functions --------------------------------------------------------

# fetch_repo <url> [commit] [submodules] - check + clone the app's source.
# When a pin is given (full commit hash or tag name), the clone is checked
# out at exactly that commit; otherwise a shallow clone of the default
# branch. Submodules (bloaty) are checked out at the SHAs recorded in the
# pinned tree.
fetch_repo() {
  local url=$1 commit=${2:-} submodules=${3:-}
  if [ ! -d "$SRC_DIR/.git" ]; then
    echo "== fetching $APP ($url${commit:+, pinned to $commit}) ..."
    mkdir -p "$WORK_DIR"
    if [ -n "$commit" ]; then
      git clone -q "$url" "$SRC_DIR"
      git -C "$SRC_DIR" checkout -q "$commit"
    else
      git clone -q --depth 1 "$url" "$SRC_DIR"
    fi
    if [ -n "$submodules" ]; then
      git -C "$SRC_DIR" submodule update --init --recursive --depth 1
    fi
  fi
}

# require <path> <message> - exit with the message if the path is missing
require() {
  [ -e "$1" ] || { echo "$2" >&2; exit 1; }
}

# run_bench <name> <budget_seconds> [--warmup <warmup-cmd...> --] <cmd...>
#   Benchmark loop shared by all drivers: runs one warmup pass (the iteration
#   command by default, or the command between --warmup and -- for the
#   benchmarks whose warmup is a lighter variant), then runs <cmd> repeatedly
#   until the budget or 10 iterations is reached, timing each iteration. A
#   failing warmup aborts (broken binary). Leaves ITER (iterations) and
#   ELAPSED (seconds, 1 decimal) set for the caller's rate/summary line.
#   Output is silenced.
run_bench() {
  local name=$1 budget=$2; shift 2
  local warmup=()
  if [ "${1:-}" = "--warmup" ]; then
    shift
    while [ $# -gt 0 ] && [ "$1" != "--" ]; do
      warmup+=("$1"); shift
    done
    [ $# -gt 0 ] && shift   # consume the trailing --
  fi

  # warmup pass - fail fast on a broken binary
  if [ ${#warmup[@]} -gt 0 ]; then
    "${warmup[@]}" > /dev/null 2>&1 || exit 1
  else
    "$@" > /dev/null 2>&1 || exit 1
  fi

  BUDGET_NS=$((budget * 1000000000))
  START=$(date +%s%N)
  ITER=0
  while true; do
    T0=$(date +%s%N)
    "$@" > /dev/null 2>&1
    T1=$(date +%s%N)
    ITER=$((ITER + 1))
    ITS=$(awk -v ns="$((T1 - T0))" 'BEGIN { printf "%.1f", ns / 1e9 }')
    echo "$name: iteration $ITER took ${ITS}s"
    [ $(( $(date +%s%N) - START )) -ge $BUDGET_NS ] && break
    [ $ITER -ge 10 ] && break
  done
  ELAPSED_NS=$(( $(date +%s%N) - START ))
  ELAPSED=$(awk -v ns="$ELAPSED_NS" 'BEGIN { printf "%.1f", ns / 1e9 }')
}

# rate <numerator> <seconds> [format] - quotient for summary lines
rate() {
  awk -v n="$1" -v s="$2" -v fmt="${3:-%.1f}" 'BEGIN { printf fmt, n / s }'
}

# build_tool <name> <compiler> <out_dir> <flags...> - build a generator
# binary into <out_dir>/<name> if missing
build_tool() {
  local name=$1 compiler=$2 outdir=$3; shift 3
  local src
  for d in "$REPO_ROOT/tools" "$SCRIPT_DIR"; do
    [ -f "$d/$name.c" ]   && src="$d/$name.c"   && break
    [ -f "$d/$name.cpp" ] && src="$d/$name.cpp" && break
  done
  if [ ! -x "$outdir/$name" ]; then
    echo "== building $name ..."
    mkdir -p "$outdir"
    $compiler "$src" "$@" -o "$outdir/$name"
  fi
}

# setup_done - "inputs ready" banner + listing (setup.sh tail)
setup_done() {
  echo "== $APP inputs ready:"
  ls -la "$INT_DIR"
}
