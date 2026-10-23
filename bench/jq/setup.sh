#!/usr/bin/env bash
# setup.sh - generate the jq benchmark input (idempotent, deterministic):
#
#   * intermediates/jq/big.json  deterministic 4M-object JSON document
#     (gen_json 4000000, fixed seed)
#
# The gen_json binary is an intermediate result built into
# intermediates/jq/ from gen_json.cpp (next to this script).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

build_tool gen_json clang++ "$INT_DIR" $CFLAGS_BOLT -std=c++17 $LDFLAGS_BOLT

if [ ! -f "$INT_DIR/big.json" ]; then
  echo "== generating big.json (gen_json 4000000) ..."
  "$INT_DIR/gen_json" 4000000 "$INT_DIR/big.json"
fi

setup_done
