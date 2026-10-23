#!/usr/bin/env bash
# setup_debian_dwarf_input.sh - assemble a Debian ELF + public DWARF input.
#
# Usage:
#   setup_debian_dwarf_input.sh LABEL INPUT STAGE MAIN_RELATIVE_PATH MODE \
#       MAIN_URL MAIN_SHA256 DEBUG_URL DEBUG_SHA256
#
# The caller owns the benchmark-specific package pins and tells this helper
# where the main ELF is found after extraction. Debian's dbgsym convention
# provides the matching .debug file by Build ID.

set -euo pipefail

if [ "$#" -ne 9 ]; then
  echo "usage: $0 LABEL INPUT STAGE MAIN_RELATIVE_PATH MODE MAIN_URL MAIN_SHA256 DEBUG_URL DEBUG_SHA256" >&2
  exit 2
fi

LABEL=$1
INPUT=$2
STAGE_DIR=$3
MAIN_RELATIVE_PATH=$4
OUTPUT_MODE=$5
MAIN_URL=$6
MAIN_SHA256=$7
DEBUG_URL=$8
DEBUG_SHA256=$9

require_command() {
  command -v "$1" >/dev/null || {
    echo "ERROR: required command not found: $1" >&2
    exit 1
  }
}

download_pinned() { # download_pinned <url> <sha256> <output>
  local url=$1 want=$2 output=$3
  if [ ! -f "$output" ]; then
    echo "== downloading $(basename "$output") ..."
    curl -fL --retry 3 --output "$output.part" "$url"
    mv "$output.part" "$output"
  fi
  echo "$want  $output" | sha256sum -c - >/dev/null \
    || { echo "ERROR: checksum mismatch for $output (delete it to re-download)" >&2; exit 1; }
}

if [ -f "$INPUT" ]; then
  echo "$LABEL input already ready: $INPUT"
  exit 0
fi

for tool in ar curl eu-unstrip readelf sha256sum tar; do
  require_command "$tool"
done

MAIN_DIR="$STAGE_DIR/main"
DEBUG_DIR="$STAGE_DIR/debug"
MAIN_DEB="$STAGE_DIR/main.deb"
DEBUG_DEB="$STAGE_DIR/debug.deb"
MAIN_ELF="$MAIN_DIR/$MAIN_RELATIVE_PATH"
mkdir -p "$MAIN_DIR" "$DEBUG_DIR" "$(dirname "$INPUT")"

download_pinned "$MAIN_URL" "$MAIN_SHA256" "$MAIN_DEB"
download_pinned "$DEBUG_URL" "$DEBUG_SHA256" "$DEBUG_DEB"

if [ ! -f "$MAIN_ELF" ]; then
  echo "== extracting $LABEL main package ..."
  ar p "$MAIN_DEB" data.tar.xz | tar xJf - -C "$MAIN_DIR"
fi
[ -f "$MAIN_ELF" ] || {
  echo "ERROR: Debian package did not contain $MAIN_ELF" >&2
  exit 1
}

BUILD_ID=$(readelf -n "$MAIN_ELF" | awk '/Build ID:/ { print $NF; exit }')
[ -n "$BUILD_ID" ] || { echo "ERROR: could not read $LABEL Build ID" >&2; exit 1; }
DEBUG_ELF="$DEBUG_DIR/usr/lib/debug/.build-id/${BUILD_ID:0:2}/${BUILD_ID:2}.debug"

if [ ! -f "$DEBUG_ELF" ]; then
  echo "== extracting matching $LABEL DWARF ..."
  ar p "$DEBUG_DEB" data.tar.xz | tar xJf - -C "$DEBUG_DIR"
fi
[ -f "$DEBUG_ELF" ] || {
  echo "ERROR: debug package has no $LABEL DWARF for build ID $BUILD_ID" >&2
  exit 1
}

echo "== merging $LABEL and its public DWARF ..."
INPUT_DIR=$(dirname "$INPUT")
INPUT_NAME=$(basename "$INPUT")
TMP_INPUT=$(mktemp "$INPUT_DIR/.$INPUT_NAME.XXXXXX")
trap 'rm -f "$TMP_INPUT"' EXIT
eu-unstrip -o "$TMP_INPUT" "$MAIN_ELF" "$DEBUG_ELF"
chmod "$OUTPUT_MODE" "$TMP_INPUT"
mv "$TMP_INPUT" "$INPUT"
trap - EXIT

echo "$LABEL input ready: $INPUT"
