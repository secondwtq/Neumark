# bloaty benchmark

[google/bloaty](https://github.com/google/bloaty) CLI, built BOLT-ready.

## Inputs

One real-world DWARF-rich binary: Debian's LLVM 19 x86-64 runtime shared
library, with its matching public debug-symbol package merged back into the
ELF. The input is downloaded and prepared by `bench/bloaty/setup.sh`, into
`intermediates/bloaty/libLLVM-19.so` (210 MiB). The two Debian package URLs
and SHA-256 pins are in `bench/bloaty/setup.sh`; it delegates the common
extraction and merge to `tools/setup_debian_dwarf_input.sh`.

```bash
bash bench/bloaty/setup.sh
```

To reproduce the benchmark with another debug binary, override
`BLOATY_INPUT`:

```bash
export BLOATY_INPUT=.../libLLVM-with-debug-info
```

## Benchmarks

```bash
work/bloaty/build-bolt/bloaty -d compileunits intermediates/bloaty/libLLVM-19.so > /dev/null
#   ~5.5 s/iter; -d compileunits: size profile by DWARF compile unit
```

## Gotchas

* **BOLT strips DWARF by default; bloaty needs it.** The
  `-d compileunits` workload requires debug info; an optimized binary
  without `-update-debug-sections` prints `bloaty: missing debug info`.
  The BOLT pass for bloaty adds `-update-debug-sections` (the binary grows
  from 18.7 MB to 58.1 MB).
* **Deceptively fast on stripped binaries.** `bloaty -d symbols` on a
  stripped binary takes milliseconds - it silently falls back to
  section-level data. The benchmark therefore needs a DWARF-rich input
  (the `-g` builds), which is why setup restores LLVM's public debug data.
* **The setup needs elfutils.** `eu-unstrip` merges the matching Debian
  `libLLVM.debug` file with the stripped shared library; `curl`, `ar`, `tar`,
  `readelf` and `sha256sum` are also required by the downloader.
* **CMake 4.2 vs vendored zlib.** bloaty's vendored zlib declares
  `cmake_minimum_required(VERSION 2.4...)`; CMake 4.2 removed pre-3.5
  compat and aborts. `build.sh` passes `-DCMAKE_POLICY_VERSION_MINIMUM=3.5`
  for this reason.
