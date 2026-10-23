# PDFium benchmarks

[PDFium](https://pdfium.googlesource.com/pdfium/) is Google's PDF library
(the engine behind Chrome's PDF viewer), built BOLT-ready. It ships no CLI,
so the benchmark harness (`pdfium_bench`) and the input generator
(`gen_pdf`) are custom C++ harnesses linked against `libpdfium.a` — the
same pattern as meshoptimizer. Three benchmarks, all on real-world inputs:
**sdm** (five workloads over the Intel Software Developer's Manual),
**vector** and **papers** (formula-dense documents).

## Build

`build.sh` (idempotent):

1. clones pdfium (GitHub mirror, pinned to branch `chromium/7533` — a
   Chromium branch position, ~2024; there are no release tags) into
   `work/pdfium`
2. clones the **minimal DEPS set** at the revisions pinned in the checkout's
   `DEPS` (plain `git fetch <sha>`, no depot_tools): `build`, `buildtools`,
   `partition_allocator`, `abseil-cpp`, `fast_float`, `freetype2`,
   `libjpeg_turbo`, `libpng`, `zlib`, `icu`, `nasm`, `test_fonts`. Skia /
   V8 / gtest / corpus are **not** needed (verified by grepping the build
   graph; `pdf_enable_v8=false`, `pdf_enable_xfa=false` — XFA requires V8).
3. downloads the `gn` binary from CIPD (version from DEPS) into
   `intermediates/tools/`
4. builds `libpdfium.a` with GN/ninja + the BOLT flags
   (`pdf_is_complete_lib=true` → one self-contained archive), then links
   `pdfium_bench` + `gen_pdf` against it.

Build gotchas (all handled by `build.sh`):

* `clang_version` is derived from the toolchain's `lib/clang/*` (this build
  revision defaults to "22", which is wrong for clang-24; the deploy tree
  has 24).
* The deploy LLVM ships no compiler-rt builtins; the system
  `libclang_rt.builtins-x86_64.a` is copied into the deploy tree (only the
  `nasm` host tool needs it).
* `use_sysroot=false` (system glibc) also turns off clang modules
  (`using_tested_sysroot`), which avoids the `third_party/libc++` sources
  entirely even though BUILDCONFIG.gn references
  `//buildtools/third_party/libc++` from every target (the buildtools repo
  is still required for `deps_revisions.gni`).
* `clang_use_chrome_plugins=false` (deploy has no Chromium clang plugins).
* Chromium's build adds `-Wa,--crel`; the binary carries `.crel.text`
  instead of `.rela.text`. llvm-bolt 24 handles the resulting CREL
  relocations (verified end-to-end; only warning: "Failed to analyze 174
  relocations", benign — output verified byte-exact at the pixel level).
* The usual `.sframe` strip applies to the harness binaries before
  profiling.

The toolchain is taken from PATH like every other app (clang++ / ld.lld /
llvm-objcopy; `LLVM_BIN` overrides), and the GN `clang_base_path` /
`clang_version` are derived from it; the BOLT flags flow into the GN build
from the shared `CFLAGS_BOLT` / `LDFLAGS_BOLT`. Total checkout 514 MB,
`libpdfium.a` 34 MB, build ~10 min on 32 cores.

## Inputs

Fetched/converted by `setup.sh` (idempotent) into `intermediates/pdfium/`:
real-world documents, downloaded once and sha256-pinned (or converted from
pinned sources by gs/rsvg-convert/gen_pdf). Derived PDFs are
content-deterministic (self-checked by rendering pixel-identically):

| input | contents | size |
|---|---|---|
| `sdm.pdf` | **Intel SDM v092** (all volumes, 5363 pages, embedded fonts + figures, sha256-pinned download) | 26.6 MB |
| `vector_book.pdf` | **Real-vector gallery, 13 artworks**: tiger + golfer (classic Adobe Illustrator demo) + Escher + Vasarely + Koch snowflakes + Dore engraving (~4800 crosshatch lines) + the OSM Istanbul map (22k building fills + 5.4k road strokes) + **6 MPVG files** (car, contour, drops, hawaii, paris-30k = 30k paths, reschart; SVG via rsvg-convert, all pure vector) - 52 pages = 4 cycles | 36 MB |
| `papers.pdf` | **Formula-dense documents**: 2610 pages with 4-18 equations/page (measured) - Ginsparg's Applied Conformal Field Theory (17.7 eq/pg), Tong's General Relativity + QFT notes, Siegel's Fields (1080 pages), Qualls' CFT notes, Vakil's "The Rising Sea" - all sha256-pinned, concatenated by gen_pdf cat | 22 MB |

## Benchmarks

Each driver takes `[budget_seconds] [binary]` and runs the shared
`run_bench` loop (warmup pass + timed iterations). All workloads are
single-command, single-threaded, and in-memory (docs loaded with
`FPDF_LoadMemDocument`). Measured on this machine (32-core, clang-24); all
hit ~14-21 s per iteration, 1-2 iterations per 20 s budget:

| workload | driver | command | iter |
|---|---|---|---|
| sdm_render | `bench_sdm_render.sh` | `render sdm.pdf 1 2.0` (5363 pages @144 dpi) | ~15.2 s |
| sdm_thumb | `bench_sdm_thumb.sh` | `thumb sdm.pdf 3` (@0.25x) | ~12.5 s |
| sdm_text | `bench_sdm_text.sh` | `text sdm.pdf 5` (extract all pages) | ~20.0 s |
| sdm_search | `bench_sdm_search.sh` | `search sdm.pdf 5 "CPUID" "page fault" "last branch record" "the current privilege level" "If a memory operand effective address is outside the"` | ~20.2 s |
| sdm_merge | `bench_sdm_merge.sh` | `merge sdm.pdf 1 8` (import 8x + save) | ~15.6 s |
| vector | `bench_vector.sh` | `render vector_book.pdf 1 4.0` (13 artworks, 52 pages) | ~16.3 s |
| papers | `bench_papers.sh` | `render papers.pdf 2 2.5` (2610 formula-dense pages) | ~20.7 s |

### SDM - Intel Software Developer's Manual (5363 pages)

```bash
intermediates/pdfium/pdfium_bench render  intermediates/pdfium/sdm.pdf 1 2.0
#   ~15.2 s/iter; render all 5363 SDM pages at 144 dpi

intermediates/pdfium/pdfium_bench thumb   intermediates/pdfium/sdm.pdf 3
#   ~12.5 s/iter; render all 5363 SDM pages at 0.25x

intermediates/pdfium/pdfium_bench text    intermediates/pdfium/sdm.pdf 5
#   ~20.0 s/iter; extract text from all 5363 pages

intermediates/pdfium/pdfium_bench search  intermediates/pdfium/sdm.pdf 5 \
#     "CPUID" "page fault" "last branch record" \
#     "the current privilege level" \
#     "If a memory operand effective address is outside the"
#   ~20.2 s/iter; find-in-page, one pass per query: five real-world searches
#   of increasing length, one more word each (1/2/3/4/9 words, 5-52 chars,
#   114-1729 hit pages; the last is half a sentence)

intermediates/pdfium/pdfium_bench merge   intermediates/pdfium/sdm.pdf 1 8
#   ~15.4 s/iter; import the SDM 8x + save + re-parse + sample render
```

### Vector gallery (13 real vector artworks)

```bash
intermediates/pdfium/pdfium_bench render  intermediates/pdfium/vector_book.pdf 1 4.0
#   ~18.2 s/iter; the real-vector gallery: tiger + 5 demo classics + the OSM
#   Istanbul map + 6 MPVG files (car, contour, drops, hawaii, paris-30k,
#   reschart) - 52 pages, 13 artworks cycled, rendered at 4x = 288 dpi
```

### Papers (formula-dense documents)

```bash
intermediates/pdfium/pdfium_bench render  intermediates/pdfium/papers.pdf 2 2.5
#   ~20.7 s/iter; 2610 pages of dense equations (Ginsparg CFT, Tong GR + QFT,
#   Siegel Fields, Qualls CFT, Vakil) rendered at 2.5x, 2 passes
```

### What the five SDM workloads do

All run on `sdm.pdf` (Intel SDM v092, 5363 pages, 26.6 MB), one process per
iteration, document loaded once into memory via `FPDF_LoadMemDocument`; each
prints a checksum for the one-time A/B comparison against the BOLT binary:

| workload | per iteration | iter time |
|---|---|---|
| sdm_render | render all 5363 pages at 2x (144 dpi, `ANNOT\|LCD_TEXT`), 1 pass | ~15.2 s |
| sdm_thumb | render all 5363 pages at 0.25x (thumbnail strip), 3 passes | ~12.5 s |
| sdm_text | extract text of all 5363 pages (`FPDFText_GetText` + char count), 5 passes | ~20.0 s |
| sdm_search | search all 5363 pages, 5 passes, one query per pass, successively longer: `CPUID` (1w) -> `page fault` (2w) -> `last branch record` (3w) -> `the current privilege level` (4w) -> `If a memory operand effective address is outside the` (9w, half a sentence) | ~20-21 s |
| sdm_merge | import all 5363 pages 8x into a fresh doc (42 904-page doc), `FPDF_SaveAsCopy` to memory, re-parse the written bytes, pixel-check a sample | ~15.6 s |

What each exercises inside PDFium:

* **sdm_render** - the full viewer pipeline: content-stream parsing,
  embedded-font loading, FreeType glyph rasterization, AGG scanline
  rasterization, DIB compositing. Checksum = **pixel-exact** bitmap.
* **sdm_thumb** - the same pipeline at 0.25x (viewer thumbnail strip);
  different rasterizer behavior (small glyph sizes, cache patterns).
  Checksum = pixel-exact.
* **sdm_text** - the text side: same parser + font front-end, but instead of
  rasterizing it builds the per-character text model (char-code to Unicode
  mapping, positions) and extracts the full page text. Checksum = char-exact.
* **sdm_search** - text-model construction + find-in-page substring search
  (`FPDFText_FindStart`/`FindNext`); the increasing query lengths (5 to 52
  chars) walk the matcher from short to long patterns, the last query a
  genuine half-sentence from the manual. Checksum = folds all five queries'
  hit counts + query bytes.
* **sdm_merge** - the writer path: deep-copying the object graph of all 5363
  pages 8x (`FPDF_ImportPages`), then serializing (object numbering, xref,
  streams) to memory, then re-parsing the result and rendering a sample of
  it as the correctness gate (raw saved bytes are not deterministic across
  processes, so bytes themselves are never compared).

BOLT profile on the SDM render workload: 492/10281 functions profiled, 25
ICF-folded, 281 block-reordered, 67 KB hot / 234 KB cold split; all five
SDM drivers reproduce their golden checksums with the optimized binary.

## Correctness (A/B)

Like the other applications, correctness is verified **once after BOLT
optimization**, by comparing the optimized binary's output against the
baseline's (the testbed's EXPERIMENT.md does the same with `cmp`/`diff` for
zstd/flac/bloaty). Checksums must be identical between the two binaries
(run the identical command on both; render/text/merge checksums are
pass-independent - one pass suffices - while search folds all passes, so
use the full 5-query command for it):

```bash
# sdm render/thumb, vector, papers: pixel-exact bitmaps
for b in intermediates/pdfium/pdfium_bench intermediates/pdfium/pdfium_bench.bolt; do
  $b render  intermediates/pdfium/sdm.pdf 1 2.0 | grep -o checksum=.*
  $b thumb   intermediates/pdfium/sdm.pdf 1 | grep -o checksum=.*
  $b render  intermediates/pdfium/vector_book.pdf 1 4.0 | grep -o checksum=.*
  $b render  intermediates/pdfium/papers.pdf 2 2.5 | grep -o checksum=.*
  # text: char-exact
  $b text    intermediates/pdfium/sdm.pdf 1 | grep -o checksum=.*
  # search: hit-count-exact, full 5-query command (checksum folds all passes)
  $b search  intermediates/pdfium/sdm.pdf 5 "CPUID" "page fault" \
             "last branch record" "the current privilege level" \
             "If a memory operand effective address is outside the" | grep -o checksum=.*
  # merge: re-parsed page count + sample render (raw bytes are not
  # deterministic - absl hash seeding - so bytes are not compared)
  $b merge   intermediates/pdfium/sdm.pdf 1 8 | grep -o checksum=.*
done   # all 14 lines must match pairwise (7 workloads x 2 binaries)
```

## Notes (discovered while building this app)

* **Timing calibration**: cold-start per-pass costs are ~2x the in-loop
  steady-state costs (font/glyph caches warm up), so the drivers were
  tuned on steady-state numbers (e.g. the map page renders 0.13 s cold but
  the in-loop iteration is what the README quotes).
* **The A/B checksum must not dominate the benchmark**: hashing the full
  rendered bitmap of every page was 53-69% of the render iterations'
  samples (fnv1a flat leaf in the flamegraphs); buffers > 64 KB are now
  sampled every 16th byte - still deterministic and catches any pixel
  change, but the hash is ~1-15% instead of a majority.
* **`FPDF_SaveAsCopy` is NOT byte-deterministic between processes** (absl
  hash seeding varies object emission order) — so generated inputs and the
  merge workload are verified at the *content* level: regenerated PDFs are
  pixel-compared, and the merge checksum covers re-parsed page count +
  sample render, not raw bytes.
* **Real-world vector inputs need verification**: the OSM map initially
  rendered only a corner (projection offset bug + Overpass returning full
  geometry of ways crossing the bbox — fixed by clipping + centering on
  data bounds, confirmed with a content-bbox check); the MPVG and demo
  artworks were verified pure vector (0 image XObjects) after conversion.

## Remaining work (if integrating into run.sh)

* The `.sframe` strip is applied by build.sh to the harnesses; the BOLT
  section of the README's pipeline applies unchanged per workload (each
  workload needs its own perf record for its own speedup, as with the other
  apps).
* Flamegraphs: frame pointers are on; the harness accounts for ~100% of
  samples (the library is statically linked in).
* `run.sh` picks up `bench/pdfium/` automatically (it globs `bench/*/`).
