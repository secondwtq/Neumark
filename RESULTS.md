# Results

Measured benchmark and BOLT-optimization data: flamegraphs, profile
statistics and A/B numbers. The full command log and raw data are in
[`EXPERIMENT.md`](EXPERIMENT.md).

## Benchmarks (flamegraphs)

One SVG per benchmark, produced with `perf record -F 999 -g` on the
benchmark run + `stackcollapse-perf.pl` + `flamegraph.pl` from the
FlameGraph repo; the profiled binary accounts for >99% of samples in
every one. Inputs and commands for each benchmark: `bench/<app>/README.md`.

### zstd (2 benchmarks)

Inputs and commands: [bench/zstd/README.md](bench/zstd/README.md)
<img src="results/flame/zstd_compress.svg" width="700" alt="zstd_compress flamegraph">
<img src="results/flame/zstd_decompress.svg" width="700" alt="zstd_decompress flamegraph">

### flac (2 benchmarks)

Inputs and commands: [bench/flac/README.md](bench/flac/README.md)
<img src="results/flame/flac_encode.svg" width="700" alt="flac_encode flamegraph">
<img src="results/flame/flac_decode.svg" width="700" alt="flac_decode flamegraph">

### bloaty (1 benchmark)

Inputs and commands: [bench/bloaty/README.md](bench/bloaty/README.md)
<img src="results/flame/bloaty.svg" width="700" alt="bloaty flamegraph">

### RecastNavigation (3 benchmarks)

Inputs and commands: [bench/recastnavigation/README.md](bench/recastnavigation/README.md)
<img src="results/flame/recast_build.svg" width="700" alt="recast_build flamegraph">
<img src="results/flame/recast_pathfinding.svg" width="700" alt="recast_pathfinding flamegraph">
<img src="results/flame/recast_crowd.svg" width="700" alt="recast_crowd flamegraph">

### Bullet3 (3 benchmarks)

Inputs and commands: [bench/bullet3/README.md](bench/bullet3/README.md)
<img src="results/flame/bullet_boxes.svg" width="700" alt="bullet_boxes flamegraph">
<img src="results/flame/bullet_prim_mesh.svg" width="700" alt="bullet_prim_mesh flamegraph">
<img src="results/flame/bullet_convex_mesh.svg" width="700" alt="bullet_convex_mesh flamegraph">

### meshoptimizer (4 benchmarks)

Inputs and commands: [bench/meshoptimizer/README.md](bench/meshoptimizer/README.md)
<img src="results/flame/meshopt_simplify.svg" width="700" alt="meshopt_simplify flamegraph">
<img src="results/flame/meshopt_optimize.svg" width="700" alt="meshopt_optimize flamegraph">
<img src="results/flame/meshopt_codec_encode.svg" width="700" alt="meshopt_codec_encode flamegraph">
<img src="results/flame/meshopt_codec_decode.svg" width="700" alt="meshopt_codec_decode flamegraph">

### dwz (1 benchmark)

Inputs and commands: [bench/dwz/README.md](bench/dwz/README.md)
<img src="results/flame/dwz.svg" width="700" alt="dwz flamegraph">

### ImageMagick (4 benchmarks)

Inputs and commands: [bench/ImageMagick/README.md](bench/ImageMagick/README.md)
<img src="results/flame/imagemagick_resize.svg" width="700" alt="imagemagick_resize flamegraph">
<img src="results/flame/imagemagick_blur.svg" width="700" alt="imagemagick_blur flamegraph">
<img src="results/flame/imagemagick_sharpen.svg" width="700" alt="imagemagick_sharpen flamegraph">
<img src="results/flame/imagemagick_composite.svg" width="700" alt="imagemagick_composite flamegraph">

### SQLite (1 benchmark)

Inputs and commands: [bench/sqlite/README.md](bench/sqlite/README.md)
<img src="results/flame/sqlite.svg" width="700" alt="sqlite flamegraph">

### ffmpeg (2 benchmarks)

Inputs and commands: [bench/ffmpeg/README.md](bench/ffmpeg/README.md)
<img src="results/flame/ffmpeg_encode.svg" width="700" alt="ffmpeg_encode flamegraph">
<img src="results/flame/ffmpeg_decode.svg" width="700" alt="ffmpeg_decode flamegraph">

### jq (2 benchmarks)

Inputs and commands: [bench/jq/README.md](bench/jq/README.md)
<img src="results/flame/jq_filter.svg" width="700" alt="jq_filter flamegraph">
<img src="results/flame/jq_sort.svg" width="700" alt="jq_sort flamegraph">

### Graphviz (1 benchmark)

Inputs and commands: [bench/graphviz/README.md](bench/graphviz/README.md)
<img src="results/flame/graphviz_dot.svg" width="700" alt="graphviz_dot flamegraph">

### PDFium (7 benchmarks)

Inputs and commands: [bench/pdfium/README.md](bench/pdfium/README.md)
<img src="results/flame/pdfium_sdm_render.svg" width="700" alt="pdfium_sdm_render flamegraph">
<img src="results/flame/pdfium_sdm_thumb.svg" width="700" alt="pdfium_sdm_thumb flamegraph">
<img src="results/flame/pdfium_sdm_text.svg" width="700" alt="pdfium_sdm_text flamegraph">
<img src="results/flame/pdfium_sdm_search.svg" width="700" alt="pdfium_sdm_search flamegraph">
<img src="results/flame/pdfium_sdm_merge.svg" width="700" alt="pdfium_sdm_merge flamegraph">
<img src="results/flame/pdfium_vector.svg" width="700" alt="pdfium_vector flamegraph">
<img src="results/flame/pdfium_papers.svg" width="700" alt="pdfium_papers flamegraph">

## BOLT results - recent projects (single-command benchmarks)

All nine newer projects were profiled (perf LBR on their primary
benchmark), optimized with the flags below, verified byte-identical, and
A/B tested. The `.bolt` binaries are in `results/`; graphviz's must be
named `dot` (the tool selects its layout engine from argv[0]):

| project | binary | profiled functions | reordered | A/B (per-iteration time) |
|---|---|---|---|---|
| recast | intermediates/recastnavigation/recast_bench | 34/311 (10.9%) | 27 | 18.3 / 18.3 / 20.2 s - ~0% |
| bullet | intermediates/bullet3/bullet_bench | 122/1592 (7.7%) | 72 | 19.5 / 19.0 / 17.0 s - ~0% |
| meshopt | intermediates/meshoptimizer/meshopt_bench | 4/141 (2.8%) | 4 | 21.2 / 18.5 / 18.6 / 18.7 s - ~0% |
| dwz | work/dwz/dwz | 72/196 (36.7%) | 55 | 22.4 -> 22.5 s - +0.4% |
| imagemagick | utilities/magick | 41/2974 (1.4%) | 34 | 20.4 / 15.8 / 18.3 / 21.0 s - ~0% |
| sqlite | build-bolt/sqlite3 | 98/2401 (4.1%) | 87 | 17.1 -> 16.6 s - **-2.9% (avg of 4)** |
| ffmpeg | build-bolt/ffmpeg | 204/3437 (5.9%) | 124 | encode 20.2 -> 20.5 s - **+1.5%**; decode +0.7% |
| jq | build-bolt/jq | 58/647 (9.0%) | 41 | 5.1 / 21.5 s - ~0% |
| graphviz | build-bolt/dot | 113/2078 (5.4%) | 82 | 17.3 -> 17.2 s - -0.6% |

Notes: most workloads are near noise-level; the consistent outliers are
sqlite (~3% faster - 87 functions, 88.8% of profiled, reordered) and
ffmpeg encode (~1.5% slower across 3 consistent runs). All optimized
binaries produce byte-identical output vs the originals (verified with
`cmp`/`compare -metric AE`; ImageMagick PNG output differs only in the
embedded timestamp chunk).

## Results (measured on the previous composite benchmark shape)

> A/B numbers below correspond to the earlier composite benchmarks (zstd
> c+d, flac -5/-8, bloaty multi-input sweeps); the current single-command
> benchmarks are ready for a fresh profile -> optimize -> measure cycle
> (`results/*.bolt` binaries are from those earlier runs). Step wall times
> are in EXPERIMENT.md.

| project | baseline | BOLT | speedup |
|---------|----------|------|---------|
| zstd  (MB/s combined c+d) | 444.1 / 446.0 | 446.0 / 449.7 | +0.4% / +0.8% |
| flac  (MB/s codec)        | 100.0 / 100.0 | 100.8 / 100.8 | +0.8% / +0.8% |
| bloaty (s per 3 iterations) | 60.0 / 59.0 | 58.4 / 58.2 | +2.7% / +1.4% |

Notes: the codec workloads are tight, already well-predicted inner loops, so
BOLT's block reordering has little to grab (fewer than 10% of functions are
touched by the profile). bloaty's scattered control flow benefits most from
hfsort+ext-tsp.

