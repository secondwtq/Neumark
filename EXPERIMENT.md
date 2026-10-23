# BOLT Experiment Log: flac, zstd, bloaty

Full command log, collected data, and gotchas for the BOLT optimization
testbed. Companion to `README.md` (which summarizes the setup); this file
documents *exactly* what was run and what happened.

> Note: this log documents the runs as they happened, under the old layout
> (drivers in `bench/`, inputs in `/tmp/benchdata`). The benchmark has since
> been reorganized: one folder per application (`bench/<app>/` with scripts,
> sources and a README) and a standalone `intermediates/<app>/` tree for all
> generated inputs and intermediate binaries; see `README.md` for the
> current layout.

Environment: Arch Linux, x86-64, 32 cores, 125 GB RAM, `/tmp` = tmpfs (61 GB).
System clang 22.1.3; the BOLT toolchain used is a pre-existing LLVM build
(`llvm-bolt` / `perf2bolt` v24.0.0git, with its own `clang-24` / `ld.lld`).
`perf_event_paranoid=0`, so LBR profiling needs no privileges.

---

## 1. Fetch

```bash
git clone --depth 1 https://github.com/xiph/flac.git     work/flac    # e94ff9f 2026-07-19
git clone --depth 1 https://github.com/facebook/zstd.git work/zstd    # 10da6ba 2026-08-27
git clone --depth 1 https://github.com/google/bloaty.git work/bloaty  # 25b99c6 2026-08-28
cd work/bloaty && git submodule update --init --recursive --depth 1
# bloaty vendors abseil, capstone, demumble, googletest, protobuf, re2, zlib, zstd
```

## 2. Build (BOLT-ready)

BOLT's core requirement: the binary must carry relocations and (for the
classic path) be non-PIE. Shared flags:

```bash
export PATH=$LLVM_ROOT/bin:$PATH   # clang-24, ld.lld, llvm-bolt, perf2bolt
CFLAGS_BOLT="-O3 -g -fno-pie -ffunction-sections -fno-omit-frame-pointer"
LDFLAGS_BOLT="-no-pie -Wl,-q -fuse-ld=lld"              # -Wl,-q == --emit-relocs
```

### zstd
```bash
cd work/zstd
cmake -S build/cmake -B build-bolt -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_C_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DZSTD_BUILD_TESTS=OFF -DZSTD_BUILD_CONTRIB=OFF \
  -DZSTD_LEGACY_SUPPORT=ON -DZSTD_MULTITHREAD_SUPPORT=OFF
ninja -C build-bolt zstd          # -> programs/zstd (4,966,816 B)
```

### flac
```bash
cd work/flac
cmake -S . -B build-bolt -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_C_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DBUILD_PROGRAMS=ON -DBUILD_CXXLIBS=OFF -DBUILD_EXAMPLES=OFF \
  -DBUILD_TESTING=OFF -DBUILD_DOCS=OFF -DWITH_OGG=OFF \
  -DWITH_FORTIFY_SOURCE=OFF -DWITH_STACK_PROTECTOR=OFF \
  -DENABLE_MULTITHREADING=ON -DINSTALL_MANPAGES=OFF
ninja -C build-bolt flac          # -> src/flac/flac (2,055,912 B)
# no nasm/yasm on host -> pure C intrinsics build (still SIMD)
```

### bloaty
```bash
cd work/bloaty
cmake -S . -B build-bolt -G Ninja -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_C_COMPILER=clang -DCMAKE_CXX_COMPILER=clang++ \
  -DCMAKE_C_FLAGS="$CFLAGS_BOLT" -DCMAKE_CXX_FLAGS="$CFLAGS_BOLT" \
  -DCMAKE_EXE_LINKER_FLAGS="$LDFLAGS_BOLT" \
  -DCMAKE_POLICY_VERSION_MINIMUM=3.5 -DBUILD_TESTING=OFF \
  -DBLOATY_PREFER_SYSTEM_ABSL=OFF -DBLOATY_PREFER_SYSTEM_CAPSTONE=OFF \
  -DBLOATY_PREFER_SYSTEM_PROTOBUF=OFF -DBLOATY_PREFER_SYSTEM_RE2=OFF \
  -DBLOATY_PREFER_SYSTEM_ZLIB=OFF -DBLOATY_PREFER_SYSTEM_ZSTD=OFF
ninja -C build-bolt bloaty        # -> bloaty (79,667,608 B, 699/699 targets)
```

### BOLT-readiness check
```bash
file <binary>                      # "ELF 64-bit LSB executable ... not PIE"
readelf -S <binary> | grep -c rela.text     # 1  -> .rela.text present
llvm-bolt <binary> -o /dev/null    # must complete without errors
```

## 3. Benchmark inputs (`bench/setup.sh`, idempotent, checksum-pinned)

Nothing depends on `/usr` or on rebuilding the projects. Generated inputs
come from fixed seeds, and the real-world DWARF inputs are assembled from
immutable, SHA-256-pinned Debian packages:

```bash
# zstd compress input: 734 MB synthetic corpus, 50% compressible, seed 1
# (zstd's own deterministic generator, tests/datagen - see the zstd README, Gotchas);
# level -12 is ~10x slower than -3, so the corpus is 10x smaller:
work/zstd/tests/datagen -g700M -P50 -s1 > /tmp/benchdata/zstd_corpus.bin
# -> 734,003,200 B

# zstd decompress input: ~10 GB stream.  A 13 GB low-compressibility
# corpus (datagen -g13G -P10 -s2) is compressed once with system zstd -T0 -3
# and then deleted; only the stream is kept.  Level does NOT help shrink
# this one: on incompressible data every level gives the same ~71% ratio
# and zstd decodes at ~1.1 GB/s regardless, so the stream size is bounded
# by the 8-12 s decode target, not by the level:
/usr/bin/zstd -q -T0 -3 -f <13G P10 corpus> -o /tmp/benchdata/zstd_stream.zst
# -> 9,987,273,477 B

# flac inputs: ~2.2 GB music-like WAV (bench/gen_wav, deterministic synth)
# + its flac -8 encoding; -8 is ~2.3x slower than -5, so the WAV is 2.3x
# smaller.  > 4 GB not needed anymore, but gen_wav still emits RF64 when
# asked to (see the flac README, Gotchas):
./gen_wav 12500 /tmp/benchdata/music.wav     # -> 2,205,000,044 B
flac -f -s -8 -o /tmp/benchdata/music.flac /tmp/benchdata/music.wav  # 1,124,761,368 B

# bloaty input: Debian LLVM 19 runtime plus its matching dbgsym package
bash bench/bloaty/setup.sh
# -> intermediates/bloaty/libLLVM-19.so (210 MiB; override with BLOATY_INPUT)
# dwz input: Debian GCC 14 x86-64 cc1 plus its matching dbgsym package
bash bench/dwz/setup.sh
# -> intermediates/dwarf/gcc-14-cc1 (106 MiB; override with DWZ_INPUT)
```
All inputs live on tmpfs so the benchmarks are CPU-bound, not I/O-bound.

## 4. Benchmarks (5 single-command benchmarks, one input each)

Each driver: `bench/<name>_bench.sh [budget_seconds] [binary]`, does a warmup
run, then loops whole iterations until the budget is reached. The workload is
**one command per iteration**; everything is **single-threaded** (zstd `-T1`;
flac and bloaty are single-threaded by design).

**One-line iteration commands** (the exact work each script repeats):

```bash
# zstd_compress_bench.sh   (measured: 22.3 s/iter; level -12)
zstd -q -T1 -12 -f -c /tmp/benchdata/zstd_corpus.bin > /dev/null

# zstd_decompress_bench.sh (measured: 8.5 s/iter)
zstd -q -d -T1 -c /tmp/benchdata/zstd_stream.zst > /dev/null

# flac_encode_bench.sh     (measured: 19.9 s/iter; level -8)
flac -f -s -8 -o /dev/null /tmp/benchdata/music.wav

# flac_decode_bench.sh     (measured: 7.9 s/iter)
flac -d -f -s -c /tmp/benchdata/music.flac > /dev/null

# bloaty_bench.sh          (measured: ~5.5 s/iter on the downloaded input)
bloaty -d compileunits intermediates/bloaty/libLLVM-19.so > /dev/null
```

The drivers (one per benchmark, all in `bench/`): `zstd_compress_bench.sh`,
`zstd_decompress_bench.sh`, `flac_encode_bench.sh`, `flac_decode_bench.sh`,
`bloaty_bench.sh`. Default budget is 20 s (2-3 iterations for the faster
benchmarks); pass the binary to test as the second argument (e.g.
`results/zstd.bolt` for the optimized one).

## 5. Profile (perf + LBR)

```bash
cd results
perf record -e cycles:u -j any,u -o zstd.perf.data \
    -- ../bench/zstd_bench.sh 40 ../work/zstd/build-bolt/programs/zstd
perf record -e cycles:u -j any,u -o flac.perf.data \
    -- ../bench/flac_bench.sh 40 ../work/flac/build-bolt/src/flac/flac
perf record -e cycles:u -j any,u -o bloaty.perf.data \
    -- ../bench/bloaty_bench.sh 40 ../work/bloaty/build-bolt/bloaty
```
Record one at a time (see the perf mlock gotcha below). Samples (final ~20 s/iteration shape):
zstd 296,275 SAMPLE events (127.9 MB perf.data), flac 196,796 (84.9 MB),
bloaty 622,755 (178.4 MB; only 61.5% of events - the rest are fork/exec
events from the 7,000+ short-lived bloaty processes per run).

## 6. Optimize with BOLT

```bash
perf2bolt -p zstd.perf.data -o zstd.fdata -nl ../work/zstd/build-bolt/programs/zstd
llvm-bolt ../work/zstd/build-bolt/programs/zstd -o zstd.bolt -b zstd.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=hfsort \
    -split-functions -split-all-cold -split-eh -icf=1 \
    -jump-tables=aggressive -dyno-stats
```
Same for flac (`flac.fdata`/`flac.bolt`) and bloaty (`bloaty.fdata`/`bloaty.bolt`),
where the `llvm-bolt` step additionally used `-update-debug-sections` (see
the bloaty README Gotchas).

## 7. Correctness validation (byte-exact)

```bash
# zstd: compress+decompress through the BOLT binary must reproduce the corpus
./zstd.bolt -q -T1 -3 -f -c /tmp/benchdata/corpus.tar -o /tmp/rt.zst
./zstd.bolt -q -d -f -c /tmp/rt.zst -o /tmp/rt.tar && cmp /tmp/benchdata/corpus.tar /tmp/rt.tar
./zstd.bolt -q -d -f -c /tmp/benchdata/corpus.tar.zst -o /tmp/rt2.tar && cmp ...   # -19 stream

# flac: encode with BOLT binary, decode with original, PCM must be identical
./flac.bolt -f -s -5 -o /tmp/rt.flac /tmp/benchdata/music.wav
flac -d -f -s -c /tmp/rt.flac -o /tmp/rt.wav && cmp /tmp/benchdata/music.wav /tmp/rt.wav

# bloaty: BOLT binary output must be identical to original
diff <(bloaty -d compileunits bloaty) <(./bloaty.bolt -d compileunits bloaty)
```
All three passed.

## 8. Reprofile / reoptimize / rerun (previous composite benchmark shape)

The wall times below were measured on the earlier composite workloads
(zstd compress+decompress together, flac -5/-8 together, bloaty multi-input
sweeps). The benchmarks have since been split into single-command form (see
section 4); the binaries under test are unchanged. Step wall times remain
representative:

| project | profile (perf record) | perf2bolt | llvm-bolt | correctness |
|---|---|---|---|---|
| zstd | 74.2 s | 0.5 s | 0.1 s | roundtrip cmp OK |
| flac | 49.2 s | 0.4 s | 0.1 s | roundtrip cmp OK |
| bloaty | 53.7 s | 2.3 s | 1.0 s | output diff OK |

(The profile step includes the benchmark itself plus perf's LBR recording
overhead - zstd's 296k samples take longer to write than flac's 197k. The
pipeline steps after profiling are sub-second to a couple of seconds.)

A/B measurement loop (2 alternating runs each):

```bash
for i in 1 2; do
  bench/zstd_bench.sh 40 work/zstd/build-bolt/programs/zstd | head -2   # baseline
  bench/zstd_bench.sh 40 results/zstd.bolt            | head -2   # optimized
 done
```
(identical pattern for flac and bloaty)

---

## Data collected

### Single-run timings (used to size the inputs)

| workload | time |
|---|---|
| zstd -12 compress of 734 MB datagen P50 | 22.3 s (~33 MB/s) |
| zstd -3 compress (reference) | ~360 MB/s |
| zstd decode of 10 GB stream (P10, -3) | 8.5 s (~1.17 GB/s) |
| flac -8 encode of 2.2 GB WAV | 19.9 s (~111 MB/s) |
| flac -8 decode | 7.9 s |
| bloaty -d compileunits on 210 MiB Debian LLVM 19 | ~5.5 s |
| datagen generation | ~1-2 s per GB |
| gen_wav generation of 2.2 GB | ~2-3 min (single-threaded synth) |

### Benchmark runs (baseline binaries, final single-command shape)

| benchmark | budget | iterations | per-iter | input | throughput |
|---|---|---|---|---|---|
| zstd_compress | 20 s | 1 | 22.3 s | 734 MB corpus | 32.9 MB/s |
| zstd_decompress | 20 s | 2-3 | 8.5 s | 10 GB stream | 1,174.9 MB/s |
| flac_encode | 20 s | 2 | 19.9 s | 2.2 GB WAV | 110.8 MB/s |
| flac_decode | 20 s | 2-3 | 7.9 s | 1.1 GB stream | 143.0 MB/s |
| bloaty | 20 s | 4 | ~5.5 s | 210 MiB Debian LLVM 19 | - |

Total persistent inputs: ~14.3 GB (compress corpus 0.7 + stream 10 + wav 2.2 +
flac 1.1 + bloaty LLVM 0.2 + dwz GCC 0.1). Generated inputs are deterministic
and machine-independent; the downloaded inputs are immutable and
checksum-pinned.
Nothing depends on `/usr` or on rebuilding the projects.

### BOLT pass statistics (final shape)

| project | functions | profiled (non-empty profile) | layout modified | hot text |
|---|---|---|---|---|
| zstd | 965 | 87 (9.0%) | 72 functions (82.8% of profiled) | 0x600000-0x60ad27 |
| flac | 594 | 72 (12.1%) | 61 (84.7%) | 0x800000-0x8075a5 |
| bloaty | 8,642 | 353 (4.1%) | 262 (74.2%); ICF folded 4 | 0x1000000-0x1014bc5 |

zstd `-dyno-stats` (post-optimization): total branches -4.2%, taken branches
-53.1%, taken conditional branches -51.2%, non-taken conditional +18.7%
(counts from the profile, before/after layout).

### Benchmark runs - RecastNavigation and Bullet3 (single-command shape)

| benchmark | binary | per-iter | workload per iteration |
|---|---|---|---|
| recast_build | bench/recast_bench | 18.1 s | 4 navmesh builds of city v2 at cs=0.25/ch=0.15 (62.0k verts / 35.5k polys) |
| recast_pathfinding | bench/recast_bench | 19.4 s | 2.8M findNearestPoly+findPath+findStraightPath queries |
| recast_crowd | bench/recast_bench | 20.0 s | 400 agents x 15250 frames (dtCrowd) |
| bullet_boxes | bench/bullet_bench | 19.0 s | scene 1 "3000 boxes", 3800 frames |
| bullet_prim_mesh | bench/bullet_bench | 19.1-19.4 s | scene 5 "Prim vs Mesh", 96000 frames |
| bullet_convex_mesh | bench/bullet_bench | 17.2-17.4 s | scene 6 "Convex vs Mesh", 9500 frames |

### Benchmark runs - all 12 projects (single-command shape)

| benchmark | binary | per-iter | workload per iteration |
|---|---|---|---|
| meshopt_simplify | bench/meshopt_bench | 21.1 s | 5x meshopt_simplify (50%) |
| meshopt_optimize | bench/meshopt_bench | 18.4-18.5 s | 15x vcache+overdraw+fetch |
| meshopt_codec_encode | bench/meshopt_bench | 18.5-18.6 s | 65x index+vertex encode |
| meshopt_codec_decode | bench/meshopt_bench | 18.9-21.0 s | 500x index+vertex decode |
| dwz | work/dwz/dwz | 15.4 s | DWARF compression of 106 MiB Debian GCC cc1 |
| imagemagick_resize | utilities/magick | 20.5 s | magick -bench 14 resize 50% of 4096^2 plasma |
| imagemagick_blur | utilities/magick | 15.8 s | magick -bench 1 blur 0x8 |
| imagemagick_sharpen | utilities/magick | 18.3 s | magick -bench 2 sharpen 0x2 |
| imagemagick_composite | utilities/magick | 21.0 s | magick -bench 6 Over-composite |
| sqlite | build-bolt/sqlite3 | 17.1 s | workload.sql on :memory: (4M+2M rows, query battery) |
| ffmpeg_encode | build-bolt/ffmpeg | 20.5 s | mpeg4 encode of 950-frame 1080p Y4M |
| ffmpeg_decode | build-bolt/ffmpeg | 14.3 s | mpeg4 decode to null muxer |
| jq_filter | build-bolt/jq | 5.0 s | select/filter over 4M-object JSON |
| jq_sort | build-bolt/jq | 22.2 s | sort_by + slice over 4M-object JSON |
| graphviz_dot | build-bolt/dot | 17.6 s | dot layout of 33x200 layered digraph |

All four meshopt benchmarks share ONE input: `mesh.bin` (gen_mesh 2816,
deterministic heightfield, 7.93M verts / 15.85M tris, 285 MB) - kept in
the compact binary format because a 15.8M-triangle .obj would be ~550 MB
of ASCII and take seconds to parse every invocation; only the pass count
differs (decode is ~100x faster per pass than simplify, hence
500 vs 5 passes).  dwz input: checksum-pinned Debian GCC `cc1` with its
matching DWARF (overridable via `DWZ_INPUT`).  Both verified
single-threaded (Threads: 1) and BOLT-ready (relocations, non-PIE,
`.sframe` stripped).

All verified single-threaded (Threads: 1 in /proc/PID/status during runs).
Recast input: `recast_city.obj` (gen_mesh 512 city v2 - terrain + 145
buildings + 70 floating slabs + 55 ramps, deterministic).  The navmesh
resolution was raised to cs=0.25/ch=0.15 (1.2x/1.33x vs defaults) - the
scene then yields 62.0k verts / 35.5k polys, at the 65,534-vert effective
cap (dtCreateNavMeshData requires vertCount < 0xffff, one tighter than
rcBuildPolyMesh's <= 0xffff).  cs=0.2 triggers Recast's distance-field
0xffff sentinel (no regions, empty navmesh) at this scene size, so 0.25 is
the practical ceiling.  Bullet inputs: none (procedural scenes).
Both harnesses link only the projects' own libraries and pass the BOLT
readiness checks (relocations, non-PIE, `.sframe` stripped).

### Verification that the output is actually optimized

BOLT runs in **lite mode** by default when a profile is present: only the
profiled functions are disassembled and rewritten; all other functions stay
byte-identical in the preserved `.bolt.org.text` section. This is also why
`llvm-bolt` is so fast on zstd/flac (0.1 s) - the binaries are tiny (5 MB /
2 MB, ~600-1000 functions) and only ~9-12% of functions are touched.

Evidence that the outputs are genuinely rewritten (not no-ops):

* outputs differ from inputs (`cmp`, and size 4.96 -> 6.42 MB / 2.05 ->
  8.49 MB);
* new `.text` section == the hot region (`__hot_start`/`__hot_end` symbols
  present, e.g. zstd 0x600000-0x60ad27), plus `.text.cold` for split-out
  cold blocks;
* symbol addresses changed: 101/960 zstd and 103/593 flac text symbols
  relocated, e.g. zstd `ZSTD_decompressContinue` 0x2a7b00 -> 0x60151a,
  `ZSTD_compressBlock_internal` 0x241ca0 -> 0x606f80; flac
  `FLAC__stream_encoder_process` 0x258930 -> 0x803640;
* function splitting happened: 79 (zstd) / 63 (flac) `.cold.` symbols in
  the outputs (e.g. `..._intrin_avx2.cold.0`);
* benchmark deltas are consistent across repeated runs (flac 100.0 vs
  100.8 MB/s in both A/B pairs).

### A/B results (final ~20 s/iteration shape, 2 alternating runs each)

| project | metric | baseline | BOLT | speedup |
|---|---|---|---|---|
| zstd | combined c+d MB/s | 444.1 / 446.0 | 446.0 / 449.7 | +0.4% / +0.8% |
| flac | codec MB/s | 100.0 / 100.0 | 100.8 / 100.8 | +0.8% / +0.8% |
| bloaty | s per 3 iterations | 60.0 / 59.0 | 58.4 / 58.2 | +2.7% / +1.4% |

Binary sizes: zstd 4.97 MB -> 6.42 MB, flac 2.06 MB -> 8.49 MB,
bloaty 79.7 MB -> 58.1 MB (with `-update-debug-sections`; 18.7 MB without).

Interpretation: the codec loops are tight, already well-predicted inner loops;
BOLT's block/func reordering has little to grab (fewer than 10% of functions
are even touched by the profile). bloaty's scattered control flow benefits
most from hfsort+ext-tsp clustering. bloaty's wall numbers sit at the 60 s
edge because its sweep workload varies with page-cache state between runs.

The `results/*.perf.data`, `*.fdata` and `*.bolt` artifacts above are all
from the final benchmark shape (reprofiled/reoptimized in section 8).

---

### BOLT pass on the 9 newer projects (actual optimize + A/B)

All nine were profiled (perf LBR on their primary benchmark), converted
with perf2bolt, optimized with the standard flags, verified byte-identical,
and A/B tested (per-iteration wall time, one run each unless noted):

| project | profile | perf2bolt | llvm-bolt | functions profiled | A/B |
|---|---|---|---|---|---|
| recast (build) | ~25 s | ~2 s | ~1 s | 34/311 | ~0% |
| bullet (boxes) | ~25 s | ~1 s | ~1 s | 122/1592 | ~0% |
| meshopt (simplify) | ~25 s | ~1 s | ~1 s | 4/141 | ~0% |
| dwz | ~25 s | ~1 s | ~1 s | 72/196 | +0.4% |
| imagemagick (resize) | ~25 s | ~2 s | ~2 s | 41/2974 | ~0% |
| sqlite | ~25 s | ~1 s | ~1 s | 98/2401 | **-2.9% (avg of 4 runs)** |
| ffmpeg (encode) | ~25 s | ~2 s | ~2 s | 204/3437 | **+1.5% (3 consistent runs)** |
| jq (sort) | ~25 s | ~1 s | ~1 s | 58/647 | ~0% |
| graphviz (dot) | ~25 s | ~1 s | ~1 s | 113/2078 | -0.6% |

Gotchas hit during the pass: ffmpeg and jq rebuilds regenerated `.sframe`
(4 unclaimed relocations) - strip again before perf2bolt; jq's default
libtool build produces a thin executable (16 functions, profile empty) -
rebuild with `--disable-shared`; graphviz picks its layout engine from
argv[0] - the `.bolt` binary must be named `dot`.

## Gotchas

> App-specific gotchas now live in the per-application READMEs
> (`bench/<app>/README.md`, "Gotchas" section); this section keeps the
> pipeline-wide ones.

**`.sframe` section blocks BOLT (the big one).**
This clang/lld toolchain emits a `.sframe` section in every binary (3
PC-relative relocations in `.rela.sframe`). BOLT cannot claim them:

```
BOLT-ERROR: 3 unclaimed PC-relative relocation(s) left in data. Re-run with -v=1 to see the list
BOLT-ERROR: unable to proceed with --strict
```
Fix (verified byte-identical behavior afterwards):
```bash
llvm-objcopy --remove-section=.sframe --remove-section=.rela.sframe <binary>
```
Related: compiling `gen_wav.c` with the *system* GNU ld prints
`ld: error in .../Scrt1.o(.sframe); no .sframe will be created` - a harmless
warning from GNU ld's own sframe handling.

**perf2bolt validates the binary name against perf.data.**
A stripped copy under a new name (`zstd.nosframe`) was rejected with
`Please rename the input binary.` Strip in place (keep path+name), or record
against the copy.

**perf record: mlock limit, run sequentially.**
`perf_event_mlock_kb=516` is a *per-user* limit. Running three `perf record`s
in parallel -> `Permission error mapping pages ... (current value: 4294967295,0)`.
Explicit `-m 64M`/`-m 2M` also exceed the 516 KB limit (`current value:
16384/512`). Default mmap size works - just run records one at a time.

**`bc` is not installed on this host.**
First benchmark scripts used `bc` for the budget check; the failed command
made the loop run forever (until killed). Rewrote the timing with pure-bash
integer nanoseconds (`date +%s%N`), `awk` for division, plus an iteration
safety cap.

**measure from the files, not from memory.**
Mid-experiment I "verified" a 25% compression ratio that was actually
computed from stale hardcoded numbers while the real file was 100.5% -
leading to a long wild-goose chase. All ratio checks were re-done with
`os.path.getsize()` on the actual files. The mtime confusion that followed
was a symptom of this, not of stale files.

**the budget loop finishes the in-flight iteration.**
The wall clock is checked after each iteration completes, so a run can
overshoot the budget by up to one iteration (flac at budget 45 ran 3 x 20.4 s
= 61.2 s). Default budget 40 makes all three runs land at 2-3 iterations,
40-53 s total.

---

### xdiff (git's diff engine) - build, real-world inputs, BOLT pass, A/B

New application added after the others: **xdiff** - git's diff algorithm
engine, driven by a headless harness (like meshopt). Full docs:
`bench/xdiff/README.md`. The benchmark diffs two versions of **58 of the longest single source files in the real world plus 4
real-world log pairs** (~11.0M old + ~10.9M new lines, ~22M lines
diffed per pass).

**Build** (git pinned to v2.55.0, only the `xdiff/` subtree compiled):

```bash
git clone https://github.com/git/git.git work/xdiff && git -C work/xdiff checkout v2.55.0
# xdiff/*.c compiled as C with $CFLAGS_BOLT + -I work/xdiff (git-compat-util.h),
# linked with the C++ harness diff_bench.cpp:
#   intermediates/xdiff/diff_bench  (266 KB)
```

Gotcha: the engine references git's compat symbols (`xmalloc`,
`xcalloc`, `xrealloc`, `BUG_fl`, `sane_ctype[256]` - the latter via
sane-ctype.h's `isalpha`/`isspace` remapping). The harness provides all
five as shims (`nm -u` on the objects lists exactly these). `regex_t`/
`size_t` come from `<regex.h>`/`<stddef.h>` before `xdiff.h`.

**Corpus construction** (how the 35 files were found): the recursive git
trees of 17 major OSS repos (mozilla/gecko-dev, llvm, chromium, swift,
dotnet/runtime, rust, qemu, postgres, php, godot, blender, gcc, erlang,
mongo, wine, WebKit) were ranked by blob size via the GitHub trees API;
the biggest hand-written C/C++ files (excluding tests, generated files,
vendored third_party and data tables) were selected: WebKit's JSC/WebKit
trio (DFGSpeculativeJIT64.cpp, DFGSpeculativeJIT.cpp, FTLLowerDFGToB3.cpp
- the latter ~200k lines), Firefox's Document.cpp, LLVM's Sema* files,
GCC's cp/parser.cc (~50k lines), sqlite3.c amalgamation (204k -> 269k
lines, from sqlite.org autoconf tarballs), coreclr's gentree.cpp,
Swift's CSSimplify.cpp, plus json.hpp, ufbx.c, postgres, qemu, erlang,
chromium and v8 files. Notable misses: php's zend_jit_ir.c (only exists
since PHP 8.3 - no old version), mongo (trees API 404), rust (no big
C/C++ files), godot/blender (biggest files are vendored or generated).

**Inputs** (checksum-pinned downloads at pinned tags/commits, SHA-256
computed at pin time; webkit/gecko/v8 "new" files pinned to commit SHAs
where no release tags exist):

```bash
# 70 files + 2 sqlite3.c tarballs, ~62 MB total, into intermediates/xdiff/tree/{old,new}/<project>/
```

**Input-shape history** (four shapes were measured):

| shape | per-pass work | per-pass time (myers) | verdict |
|---|---|---|---|
| synthetic 2M-line pair, 30% edits | 2M lines, huge D | 7.8 s (minimal 210 s) | not real code; minimal pathological |
| kernel tree v6.6 -> v6.12 | 52M lines of changed files | ~7.2 s | real but heavy: 290 MB download, 3.2 GB extracted |
| 8 giant files | 147k + 186k lines | 72 ms | real, light, but needs 240+ passes |
| **35 giant files** | 806k + 967k lines | 0.59 s (minimal 2.76, patience 0.21, histogram 0.28) | real, 62 MB, 7-95 passes |
| **58 giant files** | 1065k + 1265k lines | 0.66 s (minimal 2.88, patience 0.28, histogram 0.36) | real, ~90 MB, 6-72 passes |
| **58 files + 4 log pairs (mixed)** | 11.0M + 10.9M lines | 12.0 s (minimal 14.7, patience 11.6, histogram 11.4) | real, ~2.7 GB, 1 pass/iter |
| **split: 58 sources + 4 logs (final)** | 1.07M + 1.27M / 9.9M + 9.6M lines | 0.66 s / 10.4 s (source/log myers) | two benchmark groups, 8 drivers |

Key findings: **real source diffs are fast** - xdiff processes real
code at ~5M lines/s regardless of algorithm; **logs are ~3x harder**
(~1.7M lines/s: longer lines, heavy repetition) and fully
throughput-bound - all four algorithms cost about the same on the log
pairs, and `minimal` is NOT pathological (6.3 s on the 11M-line HDFS
pair, same as myers). One pass over the final corpus already fills the
iteration (11-15 s).

**Correctness design**: ctxlen is set to the whole file, so the emitted
unified diff is a lossless encoding of each input pair; the harness
reconstructs both files from the emitted stream (context + `-` = old,
context + `+` = new) and compares line count + FNV-1a digest with the
originals on **every pass, every pair**. Verified single-threaded
(Threads: 1) and BOLT-ready. Iteration: source 17.3-19.2 s (30/6/72/55 passes), log 10.3-11.0 s (1 pass)
(2 iterations per 20 s run).

**BOLT pass** (myers driver only, standard flags):

```bash
perf record -e cycles:u -j any,u -o results/xdiff_myers.perf.data -- bench/xdiff/bench_myers.sh 20   # 151,137 samples, 62 MB
perf2bolt -p results/xdiff_myers.perf.data -o results/xdiff_myers.fdata -nl intermediates/xdiff/diff_bench
llvm-bolt intermediates/xdiff/diff_bench -o results/xdiff_myers.bolt -b results/xdiff_myers.fdata \
    -reorder-blocks=ext-tsp -reorder-functions=hfsort -split-functions -split-all-cold \
    -split-eh -icf=1 -jump-tables=aggressive -dyno-stats
```

(.sframe stripped in place before profiling - the suite-wide clang/lld
gotcha.) 18/71 functions profiled (25.4%), 17 layouts modified, hot text
5.1 kB vs 20.0 kB cold, taken conditional branches -31.2% (dyno-stats).
Correctness: the .bolt binary passes the harness roundtrip on all four
workloads.

**A/B after the split** (2 alternating rounds each): source myers
19.1/19.2 vs 19.9/20.0 s (~-3%, layout changes don't pay off on the
search/IO-dominated source passes), log myers 10.4/10.5 vs 10.1/10.1 s
(**+3-4%**, the throughput-bound log workload gives BOLT's layout
changes - taken branches -32.7% - something to rearrange; best result
in the suite besides bloaty +2.7%). The mixed corpus hid this
contrast; separating the groups made it explicit. Each group has its
own perf.data/fdata/.bolt artifacts (results/xdiff_myers.* and
results/xdiff_log_myers.*).

**Log inputs** (fourth input class): real-world production log pairs -
logpai/loghub's HDFS_v1 (11.2M lines, 38.7h) and BGL (4.7M lines,
214.7 days) split into two time-window halves, NASA web access logs
July vs August 1995 (ita.ee.lbl.gov), and two Hadoop mapreduce
container logs (Zenodo). Downloads: Zenodo zips + LBL gz (pinned
SHA-256); the split halves are also pinned. setup.sh special-cases
them (unzip, head/tail split, gunzip). ~2.7 GB in intermediates.
Earlier failed attempt note: backgrounded curl jobs with `cd /tmp &&`
only apply the cd to the first job - two downloads silently landed in
the repo root (caught by git status).

**Corpus expansion** (second round): 23 more pairs added - MAME's
bfm_sc4.cpp (51.5k lines, one of the largest hand-written files
anywhere) + cps1.cpp, the kernel's brcmsmac phy_n.c, ClickHouse
MergeTreeData.cpp + StorageReplicatedMergeTree.cpp, LibreOffice
svdfppt.cxx + msdffimp.cxx, HotSpot assembler_x86.cpp +
library_call.cpp + Character.java, Hermes JSParserImpl.cpp +
Interpreter.cpp, R's eval.c + devPS.c, ffmpeg's mov.c, Cataclysm-DDA
activity_actor.cpp + game.cpp + map.cpp, Skia's SkRasterPipeline_opts.h
+ SkSLSPIRVCodeGenerator.cpp, MariaDB's sql_select.cc, rustc's late.rs +
conflict_errors.rs. Found by ranking the recursive git trees of 20 more
repos (mame, ClickHouse, duckdb, LibreOffice, MariaDB, linux, openjdk,
qtbase, opencv, skia, PCSX2, dolphin, Cataclysm-DDA, node, hermes,
haiku, glibc, r-source, ffmpeg, rust) by blob size; generated tables,
vendored code and tests excluded. Misses: duckdb (top files generated),
qtbase/opencv/node (vendored), glibc (iconv tables), dolphin/PCSX2
(3rdparty only). MAME's old refs use the pre-reorg src/mame/drivers/
paths (the src/mame/<vendor>/ layout arrived later).

