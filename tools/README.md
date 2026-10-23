# Shared input tools (tools)

`gen_mesh.cpp` is the only input generator shared by two applications, so it
lives here instead of in an application folder:

| source | used by | invocation (binary: `intermediates/tools/gen_mesh`) |
|---|---|---|
| `gen_mesh.cpp` | recast | `gen_mesh 512 <out>.obj city` (deterministic "city" scene, 525k tris) |
| | meshoptimizer | `gen_mesh 2816 <out>.bin` (heightfield, 15.8M tris, binary format) |

The binary is an intermediate result at `intermediates/tools/gen_mesh`,
built idempotently by `bench/recastnavigation/setup.sh` and `bench/meshoptimizer/setup.sh`
(whichever runs first). It is deterministic (integer-hash value noise) and
platform-independent - inputs are reproducible on any machine.

`gen_mesh` writes standard Wavefront OBJ when the output ends in `.obj`,
else a compact binary format (uint32 nverts, uint32 ntris,
float verts[nverts][3], uint32 indices[ntris][3]).

Build: `./build.sh` (also done idempotently by
`bench/recastnavigation/setup.sh` / `bench/meshoptimizer/setup.sh`).

## Generic Debian DWARF helper

`setup_debian_dwarf_input.sh` contains the shared mechanics for the
benchmark-local DWARF inputs: checking dependencies, downloading and
verifying packages, extracting them, matching the debug file by Build ID,
and merging it with the ELF via `eu-unstrip`. The URL and SHA-256 pins stay in
each benchmark's `bench/<app>/setup.sh`; those scripts pass the pins and
artifact-specific paths to this helper.
