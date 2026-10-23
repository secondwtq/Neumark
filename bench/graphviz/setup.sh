#!/usr/bin/env bash
# setup.sh - generate the graphviz benchmark input (idempotent, deterministic):
#
#   * intermediates/graphviz/big.dot  deterministic 33x200-node layered
#     digraph (~6.6k nodes, chain + skip edges; gen_dot 33 200)
#
# The gen_dot binary is an intermediate result built into
# intermediates/graphviz/ from gen_dot.cpp (next to this script).
# Applications are set up independently - run this script to prepare
# this application's inputs.
# Usage: setup.sh

set -e

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"
mkdir -p "$INT_DIR"

build_tool gen_dot clang++ "$INT_DIR" $CFLAGS_BOLT -std=c++17 $LDFLAGS_BOLT

if [ ! -f "$INT_DIR/big.dot" ]; then
  echo "== generating big.dot (gen_dot 33 200) ..."
  "$INT_DIR/gen_dot" 33 200 "$INT_DIR/big.dot" 1
fi

setup_done
