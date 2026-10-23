#!/usr/bin/env bash
# setup.sh - fetch bloaty's real-world DWARF benchmark input.
#
# The input is Debian's LLVM 19 runtime shared library, with the matching
# public -dbgsym package merged back into it. The package pins stay with this
# benchmark; common Debian extraction/merge logic is in tools/.
#
# Usage: setup.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/bench/vars.sh"

STAGE_DIR="$INT_DIR/.llvm-19"
INPUT="$BLOATY_INPUT_DEFAULT"

MAIN_URL="https://deb.debian.org/debian/pool/main/l/llvm-toolchain-19/libllvm19_19.1.7-3+b1_amd64.deb"
MAIN_SHA256="db0d614d61345ca710fb73e75105f1ec6e38898fa7b3aa99fa7eb7d8b0a11d57"
DEBUG_URL="https://deb.debian.org/debian-debug/pool/main/l/llvm-toolchain-19/libllvm19-dbgsym_19.1.7-3+b1_amd64.deb"
DEBUG_SHA256="c38d1c83faa38d6f7678ae40b11d7216b0fc97e95d4c27a2d9b870a152759262"

exec bash "$REPO_ROOT/tools/setup_debian_dwarf_input.sh" \
  "Debian LLVM 19 libLLVM" \
  "$INPUT" \
  "$STAGE_DIR" \
  "usr/lib/x86_64-linux-gnu/libLLVM.so.19.1" \
  644 \
  "$MAIN_URL" "$MAIN_SHA256" \
  "$DEBUG_URL" "$DEBUG_SHA256"
