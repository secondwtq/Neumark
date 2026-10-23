#!/usr/bin/env bash
# setup.sh - fetch dwz's real-world DWARF benchmark input.
#
# The input is GCC's cc1 executable from Debian 13 (trixie), with the
# matching public -dbgsym package merged back into it. The package pins stay
# with this benchmark; common Debian extraction/merge logic is in tools/.
#
# Usage: setup.sh

set -euo pipefail

REPO_ROOT=$(cd "$(dirname "$0")/../.." && pwd)
source "$REPO_ROOT/bench/vars.sh"

DWARF_DIR="$REPO_ROOT/intermediates/dwarf"
STAGE_DIR="$DWARF_DIR/.gcc-14"
INPUT="$DWARF_INPUT"

MAIN_URL="https://deb.debian.org/debian/pool/main/g/gcc-14/cpp-14-x86-64-linux-gnu_14.2.0-19_amd64.deb"
MAIN_SHA256="ef274b5379f5f97fc71619d39ecc84d039d3e184570d207b909c90afaa5d79e0"
DEBUG_URL="https://deb.debian.org/debian-debug/pool/main/g/gcc-14/cpp-14-x86-64-linux-gnu-dbgsym_14.2.0-19_amd64.deb"
DEBUG_SHA256="745a0efc8c8208e71e4d1f535375f87fe513a37e62620fcf0d8cd7fcebdace87"

exec bash "$REPO_ROOT/tools/setup_debian_dwarf_input.sh" \
  "Debian GCC 14 cc1" \
  "$INPUT" \
  "$STAGE_DIR" \
  "usr/libexec/gcc/x86_64-linux-gnu/14/cc1" \
  755 \
  "$MAIN_URL" "$MAIN_SHA256" \
  "$DEBUG_URL" "$DEBUG_SHA256"
