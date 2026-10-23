#!/usr/bin/env bash
# bench.sh - single-command benchmark:
#   sqlite3 :memory: < sqlite_workload.sql   (~18.5 s/iter)
# Deterministic read/write workload: builds a 2-table schema in memory
# (4M items + 2M sales via WITH RECURSIVE), then runs a battery of queries
# (aggregates, joins, grouping, LIKE, ordering, updates, deletes).
# Single-threaded.
# Usage: bench.sh [budget_seconds] [sqlite3_binary]

set -u

source "$(cd "$(dirname "$0")/.." && pwd)/vars.sh"

BUDGET="${1:-20}"
SQLITE3="${2:-$REPO_ROOT/work/sqlite/build-bolt/sqlite3}"
SQL="${SQLITE_WORKLOAD:-$SCRIPT_DIR/sqlite_workload.sql}"

require "$SQLITE3" "sqlite3 not found: $SQLITE3"
require "$SQL" "workload not found: $SQL"

run_bench "$APP" "$BUDGET" "$SQLITE3" :memory: ".read '$SQL'"
echo "$APP: iterations=$ITER wall=${ELAPSED}s"
echo "$APP: binary=$SQLITE3 workload=$SQL"
