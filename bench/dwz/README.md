# dwz benchmark

[dwz](https://sourceware.org/dwz/) DWARF compressor, built BOLT-ready.

## Inputs

One real-world DWARF-rich binary: Debian's GCC 14 x86-64 `cc1` executable,
with its matching public debug-symbol package merged back into the ELF. The
input is downloaded and prepared by `bench/dwz/setup.sh` (or the bloaty setup
script), into the shared path `intermediates/dwarf/gcc-14-cc1` (106 MiB).
The two Debian package URLs and SHA-256 pins are in `bench/dwz/setup.sh`; it
delegates the common extraction and merge to
`tools/setup_debian_dwarf_input.sh`.

```bash
bash bench/dwz/setup.sh
```

To reproduce the benchmark with another debug binary, override `DWZ_INPUT`:

```bash
export DWZ_INPUT=.../cc1-with-debug-info
```

The `-o` flag keeps the input intact, so the same file is reused every
iteration; the compressed output is written to
`intermediates/dwz/dwz_out.so` (an intermediate result, overwritten each
iteration).

## Benchmarks

```bash
work/dwz/dwz -q -o intermediates/dwz/dwz_out.so intermediates/dwarf/gcc-14-cc1
#   ~15.4 s/iter; -q quiet; -o keeps the input intact (repeatable benchmark)
```

## Gotchas

* **Input format matters.** The pinned Debian GCC artifact uses a DWARF
  layout accepted by this dwz build. Also: dwz rewrites its input in place by
  default;
  `-o OUTFILE` keeps the input intact, which is what makes a repeatable
  benchmark possible. Single-file mode is single-threaded (verified
  Threads: 1); `-j` is only for multiple files.
* **The setup needs elfutils.** `eu-unstrip` merges the matching Debian
  `cc1.debug` file with the stripped executable; `curl`, `ar`, `tar`,
  `readelf` and `sha256sum` are also required by the downloader.
