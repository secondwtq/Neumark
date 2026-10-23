# SQLite benchmark

[SQLite](https://sqlite.org/) CLI (`sqlite3`), built BOLT-ready.

## Inputs

No input files - the workload is the static SQL script
`sqlite_workload.sql` (next to these scripts): a deterministic read/write
workload that builds a two-table schema in `:memory:` (4M items + 2M sales
via WITH RECURSIVE), then runs a battery of queries (aggregates, joins,
grouping, LIKE, ordering, updates, deletes). `bench/sqlite/setup.sh` is a no-op (no generated
inputs); `intermediates/sqlite/` stays empty.

## Benchmarks

```bash
work/sqlite/build-bolt/sqlite3 :memory: < bench/sqlite/sqlite_workload.sql
#   ~17-18 s/iter; builds the 2-table schema in memory, then runs the query battery
```