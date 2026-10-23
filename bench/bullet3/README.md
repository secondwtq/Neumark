# Bullet3 benchmarks

Bullet's own `App_Benchmarks` scenes (`examples/Benchmarks/BenchmarkDemo.cpp`)
driven headlessly by the harness `bullet_bench.cpp` (console main +
BenchmarkDemo, no rendering); fixed timestep dt=1/60, single-threaded
`btDiscreteDynamicsWorld` (`BULLET2_MULTITHREADING=OFF`), deterministic
scene construction.

## Inputs

No input files - the scenes are constructed procedurally; `bench/bullet3/setup.sh`
is a no-op. `intermediates/bullet3/` holds only the built harness binary.

## Benchmarks

```bash
intermediates/bullet3/bullet_bench 1 3800     # ~19 s/iter; scene 1 "3000 boxes", 3800 frames
intermediates/bullet3/bullet_bench 5 96000    # ~19 s/iter; scene 5 "Prim vs Mesh", 96000 frames
intermediates/bullet3/bullet_bench 6 9500     # ~17 s/iter; scene 6 "Convex vs Mesh", 9500 frames
#   args: <scene> <frames>; fixed timestep dt=1/60, single-threaded
```

## Gotchas

* **`DummyGUIHelper` crashes in `CommonRigidBodyMTBase`.**
  `createDefaultParameters()` calls `m_guiHelper->getParameterInterface()`
  unconditionally, and `DummyGUIHelper` returns 0 - instant segfault in
  the "console mode" pattern. The harness uses a GUI-helper subclass that
  returns a stub `CommonParameterInterface` (6 no-op methods). Also,
  `BenchmarkDemo.h` does NOT declare the `BenchmarkDemo` class - only the
  `BenchmarkCreateFunc` factory; scenes are selected via
  `CommonExampleOptions::m_option` (1-8).
* **Scenes keep "settling".** Bodies come to rest and sleeping
  bodies are nearly free, so frame cost drops over time (scene 5 got ~2x
  faster between calibration and warm validation). Frame counts were tuned
  on warm runs; per-iteration times land in the 17-20 s band and are
  inherently a bit variable.
