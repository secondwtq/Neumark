# Neumark

General-purpose CPU single-core benchmark suite.

Every benchmark should:
* Be based on open source software used in the real world.
* Be launched in a single command and contained in a single process.
* Runs in an appropriate duration (~20s on my system) on modern hardware.
* Uses only one logical processor.

One-command run of everything: `./run.sh` (stages: `build`, `setup`, `run`; each idempotent).

> Full command log, raw data and gotchas: see [`EXPERIMENT.md`](EXPERIMENT.md).
> Flamegraphs, profile statistics and A/B results: see [`RESULTS.md`](RESULTS.md).

## Layout

```
run.sh                      build + setup + run everything
                            (./run.sh [all|build|setup|run] [budget_seconds])
work/<project>/              source clones + <project>/build-bolt/ build dirs
bench/vars.sh               shared path/flag variables + helpers (sourced by all scripts)
tools/gen_mesh.cpp          shared mesh generator (recast + meshoptimizer)
tools/setup_debian_dwarf_input.sh  common Debian ELF + DWARF assembler
bench/<app>/                one folder per application (run individually):
  README.md                   input, build and run instructions
  build.sh                    fetch (git clone) + build, BOLT-ready
  setup.sh                    prepares this app's inputs (idempotent)
  bench_*.sh                  benchmark driver scripts
  *.cpp / *.c / *.sql         app sources (harnesses, input generators,
                              workloads)
intermediates/<app>/        standalone tree for ALL intermediate files
                            (generated inputs, harness + generator
                            binaries) - gitignored, rm -rf to clean
results/                    perf.data, .fdata, .bolt binaries, A/B outputs
```

## Toolchain

* Building: the `build.sh` scripts call `clang` / `clang++` / `ld.lld`
  from `PATH`. `-fuse-ld=lld` requires an lld on `PATH`; without one,
  override `LDFLAGS_BOLT` (GNU ld supports `--emit-relocs` too).
* BOLT pipeline: needs `llvm-bolt` / `perf2bolt` on `PATH`.
* `perf` with LBR: `perf record -e cycles:u -j any,u` (kernel
  `perf_event_paranoid=0`)
* Downloaded DWARF inputs: `curl`, `sha256sum`, `ar`, `tar`, `readelf` and
  `eu-unstrip` on `PATH`.

## Builds (BOLT requirements)

BOLT's core requirement is a **relocatable** binary. All projects use the
same flags - these are the defaults in `bench/vars.sh` (`CFLAGS_BOLT` /
`LDFLAGS_BOLT`, env-overridable), applied automatically by every
`build.sh`.

Every application folder ships a `build.sh` that performs the whole
fetch + build in one step: clone the source into `work/<project>` (skipped
if the clone is already present) **pinned to a fixed release** (the pin is
the second argument of `fetch_repo` in each script - a release tag, e.g.
`v1.5.7`; pdfium has no release tags, so it is pinned to a branch,
`chromium/7533`; to update, change the pin and re-clone), then build
the BOLT-ready binary with those flags (explained in the table below). Run them individually
(`bench/<app>/build.sh`); each
script prints the resulting binary path, and app-specific build quirks are
documented in its header (e.g. bloaty's CMakeLists patch, ffmpeg's
`-fomit-frame-pointer` fix, jq's libtool wrapper, graphviz's `dot`
naming, **pdfium's DEPS + GN build** - no depot_tools: the minimal DEPS
checkouts are fetched at the pinned revisions and `gn` comes from CIPD).
The scripts call `clang` / `clang++` / `ld.lld` from `PATH` (any
recent LLVM/Clang works - see [Toolchain](#toolchain)); pdfium's GN build
additionally derives `clang_base_path` from the same toolchain.

| Requirement | Flag |
|---|---|
| relocations in the binary | `-Wl,-q` (`--emit-relocs`) in the link flags |
| non-PIE executable (classic BOLT path) | `-fno-pie` + `-no-pie` |
| per-function sections (better splitting) | `-ffunction-sections` |
| DWARF for analysis | `-g` |
| debug-friendly frames | `-fno-omit-frame-pointer` |

**Gotcha (all binaries, incl. harnesses):** this clang/lld toolchain emits a
`.sframe` section whose 3 PC-relative relocations BOLT cannot claim
(`BOLT-ERROR: 3 unclaimed PC-relative relocation(s) ... unable to proceed
with --strict`). Strip it before profiling:
`llvm-objcopy --remove-section=.sframe --remove-section=.rela.sframe <binary>`.
Verified byte-identical behavior after stripping.

## Inputs (prepared per application, idempotent)

Each application prepares its inputs via `bench/<app>/setup.sh` -
run them individually, or prepare everything with:

```bash
for s in bench/*/setup.sh; do bash "$s"; done
```

The inputs, their sources and sizes are listed in each application's README
(`bench/<app>/README.md`). Applications without setup-time input data
(bullet and sqlite) have no-op setup scripts. Generated inputs use fixed
seeds.
Everything is kept in the standalone `intermediates/` tree.

## Benchmarks

Each driver takes `[budget_seconds] [binary]`, warms up, then loops whole
iterations until the budget is reached (default 20 s).

Applications and their benchmarks (details in each `bench/<app>/README.md`):

* **zstd** - compress, decompress
* **flac** - encode, decode
* **bloaty** - DWARF size profile
* **RecastNavigation** - build, pathfinding, crowd
* **Bullet3** - boxes, prim mesh, convex mesh
* **meshoptimizer** - simplify, optimize, codec encode, codec decode
* **dwz** - DWARF compression
* **ImageMagick** - resize, blur, sharpen, composite
* **SQLite** - in-memory read/write workload
* **ffmpeg** - encode, decode
* **jq** - filter, sort
* **Graphviz** - hierarchical layout
* **PDFium** - SDM render/thumb/text/search/merge, vector, papers
* **xdiff** - git's diff engine: myers, minimal, patience, histogram

Correctness is enforced inside the drivers (flac/zstd fail on bad
binaries) and by byte-exact roundtrip checks of the optimized binaries.

**Flamegraphs**: one SVG per benchmark, collected in
[`RESULTS.md`](RESULTS.md) (`results/flame/*.svg`, produced with
`perf record -F 999 -g` on the benchmark run + `stackcollapse-perf.pl` +
`flamegraph.pl` from the FlameGraph repo; the profiled binary accounts for
>99% of samples in every one). FP unwinding is used, so the build must use
`-fno-omit-frame-pointer`.

## BOLT pass (per binary)

```
perf record -e cycles:u -j any,u -o <p>.perf.data -- bench/<app>/bench_<p>.sh 20 <binary>
perf2bolt -p <p>.perf.data -o <p>.fdata -nl <binary>
llvm-bolt <binary> -o <p>.bolt -b <p>.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=hfsort \
    -split-functions -split-all-cold -split-eh -icf=1 \
    -jump-tables=aggressive -dyno-stats
```
(bloaty additionally uses `-update-debug-sections`, since its benchmark
parses DWARF and BOLT strips it by default.) Run perf records one at a time
(per-user mlock limit). Correctness after optimization: byte-exact
roundtrips (zstd/flac `cmp`), identical bloaty/dwz output (`diff`), and the
harnesses' built-in checks (recast builds must succeed, meshopt codec
roundtrip is verified at startup).
