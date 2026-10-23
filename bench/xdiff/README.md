# xdiff benchmarks

[git's xdiff engine](https://github.com/git/git) - the diff algorithm
library behind `git diff`, `git log -p` and `git blame` - driven by the
headless harness `diff_bench.cpp`, built BOLT-ready.

git ships no standalone diff binary, so (like meshoptimizer) the harness
compiles the engine in and drives it directly. Only the `xdiff/` subtree
of git is built (~7 C files, pinned to `v2.55.0`); the engine expects
git's compat wrappers, which the harness provides as shims (see
`diff_bench.cpp`, "shims for git-compat-util symbols").

## Inputs (real-world)

The benchmark splits into two independent benchmark groups with separate
corpora (both fetched by `bench/xdiff/setup.sh`, idempotent, SHA-256-pinned):

* `intermediates/xdiff/tree/{old,new}/` - **source corpus**: two versions of
  **58 of the longest single source files in the real world**, downloaded from pinned commits/tags and SHA-256-verified by
`bench/xdiff/setup.sh` (idempotent) into
`intermediates/xdiff/{tree,logtree}/{old,new}/` (~2.7 GB total; logs are ~90%% of the lines):

| subdir | files | old -> new |
|---|---|---|
| `json/` | json.hpp | nlohmann/json v3.5.0 (2018) -> v3.12.0 (2025) |
| `ufbx/` | ufbx.c | v0.9.0 -> v0.15.1 |
| `llvm/` | X86ISelLowering.cpp | llvmorg-11.0.0 (2020) -> llvmorg-19.1.7 (2025) |
| `clang/` | SemaExpr.cpp, SemaDecl.cpp, ExprConstant.cpp | llvmorg-15.0.0 -> llvmorg-19.1.7 |
| `sqlite/` | sqlite.h.in, btree.c | 3.20.0 (2017) -> 3.53.0 (2026) |
| `sqlite/` | sqlite3.c (amalgamation, 204k -> 269k lines) | sqlite.org autoconf tarballs |
| `v8/` | code-stub-assembler.cc, api.cc, liftoff-compiler.cc | @2020-01 -> @2026 (main) |
| `webkit/` | DFGSpeculativeJIT64.cpp, DFGSpeculativeJIT.cpp, FTLLowerDFGToB3.cpp, WKContentViewInteraction.mm, WebPageProxy.cpp, Document.cpp, RenderLayer.cpp | WebKit-7613.2.6 (2023) -> WebKit-7624.4.5 (2025) |
| `gecko/` | Document.cpp, ActorsParent.cpp | 2021-12 -> 2026 (commits) |
| `gcc/` | cp/parser.cc, cp/pt.cc, dwarf2out.cc | gcc-12.2.0 (2022) -> gcc-14.2.0 (2024) |
| `postgres/` | tablecmds.c, pg_dump.c | REL_15_0 -> REL_18_0 |
| `qemu/` | mips translate.c, linux-user syscall.c, i386 cpu.c | v7.2.0 -> v9.2.0 |
| `dotnet/` | coreclr gentree.cpp, emitxarch.cpp | v7.0.0 -> v9.0.0 |
| `swift/` | CSSimplify.cpp, Decl.cpp | swift-5.7 -> swift-6.1 |
| `erlang/` | beam/erl_process.c | OTP-25.0 -> OTP-27.0 |
| `chromium/` | about_flags.cc | 115.0.5790.0 (2023) -> 138.0.7188.0 (2025) |
| `mame/` | bfm_sc4.cpp (51.5k lines), cps1.cpp | mame0221 (2021) -> mame0278 (2024) |
| `linux/` | brcmsmac phy_n.c | v6.1 -> v6.12 |
| `clickhouse/` | MergeTreeData.cpp, StorageReplicatedMergeTree.cpp | v21.8.14.5-lts -> v24.8.5.115-lts |
| `libreoffice/` | svdfppt.cxx, msdffimp.cxx | libreoffice-7.3.7.2 -> libreoffice-24.8.4.2 |
| `jdk/` | hotspot assembler_x86.cpp, library_call.cpp, Character.java | jdk-17+35 -> jdk-24+36 |
| `hermes/` | JSParserImpl.cpp, Interpreter.cpp | 2021-12 -> 2026 (commits) |
| `r/` | eval.c, grDevices devPS.c | 2021-12 -> 2026 (commits) |
| `ffmpeg/` | libavformat mov.c | n5.0 -> n7.0 |
| `cataclysm/` | activity_actor.cpp, game.cpp, map.cpp | 0.F (2021) -> 0.H (2023) |
| `skia/` | SkRasterPipeline_opts.h, SkSLSPIRVCodeGenerator.cpp | 2021-12 -> 2026 (commits) |
| `mariadb/` | sql/sql_select.cc | mariadb-10.8.2 -> mariadb-11.8.1 |
| `rust/` | rustc_resolve late.rs, rustc_borrowck conflict_errors.rs | 1.65.0 -> 1.87.0 |
* `intermediates/xdiff/logtree/{old,new}/` - **log corpus**: four real-world
  log pairs:

  | pair | lines (old/new) | source |
  |---|---|---|
  | `hdfs.log` | 2x 5.6M (38.7h HDFS run, first vs second half) | logpai/loghub (Zenodo) |
  | `bgl.log` | 2x 2.4M (Blue Gene/L 214.7 days, halves) | logpai/loghub (Zenodo) |
  | `nasa.log` | 1.9M / 1.6M (web access logs, July vs Aug 1995) | ita.ee.lbl.gov |
  | `hadoop.log` | 99k / 59k (two mapreduce container logs) | logpai/loghub (Zenodo) |

Every file is downloaded from the pinned commit/tag in its URL and
verified against a SHA-256 computed at pin time - the same
checksum-pinned pattern as the bloaty/dwz Debian inputs. The corpus is
~1.07M old + ~1.27M new lines for the source corpus and ~9.9M +
~9.6M for the log corpus (lines diffed per pass), multi-year
gaps per project, so every pair is a substantial real diff. The largest
files were found by ranking the recursive git trees of 17 major OSS
repos by blob size (see EXPERIMENT.md).

## Benchmarks

Four workloads (myers / minimal / patience / histogram), one binary, two
benchmark groups (all deterministic, single-threaded; every pass is
verified inside the harness - the emitted diff must reproduce both
trees exactly):

**Source group** (`bench_myers.sh` / `bench_minimal.sh` /
`bench_patience.sh` / `bench_histogram.sh`, corpus: `tree/`):

```bash
intermediates/xdiff/diff_bench myers      tree/old tree/new   30   # ~19.1 s/iter
intermediates/xdiff/diff_bench minimal    tree/old tree/new    6   # ~17.3 s/iter
intermediates/xdiff/diff_bench patience   tree/old tree/new   72   # ~19.1 s/iter
intermediates/xdiff/diff_bench histogram  tree/old tree/new   55   # ~19.2 s/iter
```

One pass = one full diff of all 58 source pairs (like `git diff
old_tree new_tree`). Real source diffs are fast (0.2-2.9 s/pass
depending on the algorithm), so the iteration budget is filled by pass
counts - the meshopt codec_decode precedent (500 passes/iteration).

**Log group** (`bench_log_myers.sh` / `bench_log_minimal.sh` /
`bench_log_patience.sh` / `bench_log_histogram.sh`, corpus: `logtree/`):

```bash
intermediates/xdiff/diff_bench myers      logtree/old logtree/new  1   # ~10.4 s/iter
intermediates/xdiff/diff_bench minimal    logtree/old logtree/new  1   # ~11.0 s/iter
intermediates/xdiff/diff_bench patience   logtree/old logtree/new  1   # ~10.6 s/iter
intermediates/xdiff/diff_bench histogram  logtree/old logtree/new  1   # ~10.4 s/iter
```

One pass = one full diff of the four log pairs; one pass already fills
the iteration. Logs are throughput-bound (long lines, heavy repetition,
~1.7M lines/s vs ~5M lines/s for source), so all four algorithms cost
about the same - `minimal` is NOT the pathological case it is on
synthetic heavily-edited inputs.

## Correctness (built into the harness)

Every pass is verified: the diff context is set to the whole file, so the
emitted unified diff is a *lossless* encoding of each input pair. The
harness reconstructs both files from the emitted stream (context + `-`
lines = old file, context + `+` lines = new file) and compares line
count + FNV-1a digest against the originals - all 62 pairs, every pass.
A broken binary fails loudly instead of silently emitting wrong output;
this is what validated the BOLT binary (`results/xdiff_myers.bolt`
passes all four workloads). The full-file emit costs a few percent of
pass time.

## BOLT pipeline (measured)

Profiled with `perf record -e cycles:u -j any,u` on the myers driver of
each group, converted with `perf2bolt`, optimized with the standard
flags (one `.bolt` per group):

* **source** (`results/xdiff_myers.bolt`, 156k samples): 22/71 functions
  profiled (31%), 21 layouts modified, taken conditional branches
  -30.4%. A/B: ~-3% (19.1 vs 19.9 s) - at 0.66 s/pass the source
  workload is search/IO-dominated and layout changes don't pay off
  (same as sqlite's -2.9% in this suite)
* **logs** (`results/xdiff_log_myers.bolt`, 125k samples): 13/71
  functions profiled (18.3%), 13 layouts modified, taken conditional
  branches -32.7%. A/B: **+3-4%** (10.4 vs 10.1 s, consistent over 2
  rounds) - the throughput-bound log workload responds to BOLT's layout
  changes, like bloaty's +2.7%

## Gotchas

* **The engine needs git's compat layer.** `xinclude.h` pulls in
  `git-compat-util.h`, so the xdiff `.c` files compile with
  `-I work/xdiff` and reference `xmalloc`/`xcalloc`/`xrealloc`/`BUG_fl`
  (via `xdl_*` macros) and `sane_ctype[256]` (git's ctype table, which
  replaces libc `isalpha`/`isspace`). The harness provides all five as
  shims - `nm -u` on the objects lists exactly these.
* **`.sframe` blocks BOLT (suite-wide).** This clang/lld toolchain emits
  a `.sframe` section with unclaimable relocations; strip it before
  profiling: `llvm-objcopy --remove-section=.sframe
  --remove-section=.rela.sframe intermediates/xdiff/diff_bench`.
* **GNU tar: `--strip-components` + member name matches the stripped
  name** (extracts nothing, rc=0). setup.sh extracts sqlite3.c
  unstripped into a staging dir and moves it.
* **Logs are harder than source for xdiff** (~1.7M lines/s vs ~5M
  lines/s for code: longer lines, heavy repetition) and throughput-bound
  - all four algorithms cost about the same, and `minimal` is not
  pathological on them. The log pairs (HDFS/BGL halves, NASA months,
  Hadoop jobs) are the workload's dominant share; the sources are
  ~10%% of the lines. setup.sh pins the Zenodo/LBL archives and verifies
  the split halves by SHA-256.
* **Version pins must move carefully.** Some "new" files are pinned to
  main-branch commit SHAs (v8, gecko - no release tags); updating them
  means resolving new SHAs and recomputing the SHA-256 pins. The
  raw.githubusercontent.com URLs are stable for the pinned refs.
* **The git clone is large** (~400 MB with history) - `fetch_repo` pins
  it to `v2.55.0`; to update, change the pin and re-clone
  (`rm -rf work/xdiff`).
