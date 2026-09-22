# Planet foundation tests

Run from the project root with Godot 4.6:

```powershell
godot --headless --path . --script res://tests/planet/planet_foundation_test.gd
```

The process exits with code `0` and prints `PLANET_FOUNDATION_TEST_OK` when the face bases, conversions, edge continuity, `PatchId`, topology, patch neighbors and determinism contracts pass.

## Quadtree (Stage 2)

```powershell
godot --headless --path . --script res://tests/planet/planet_quadtree_test.gd
./tests/planet/run_validation.ps1
```

The full quadtree test prints `QUADTREE_TEST_OK` and exits with code 0.
It includes transition endpoints, cross-face stitching, hysteresis and budgets.
Controller tests cover both restrictive (1 split / 1 merge) and batched
(8 splits / 2 merges) budgets, with 3 mesh commits per update.
For the geometry subset only, append `-- --geometry-only`.
The PowerShell runner accepts `-Godot <executable>` and writes logs to a fresh
temporary directory. It never uses Git.

To capture the real renderer (requires a graphical session):

```powershell
godot --path . --windowed --resolution 1100x760 --script res://tests/planet/planet_visual_test.gd -- <absolute-output-directory>
```

Static screenshots cannot prove the absence of transient visual artifacts during
arbitrary manual flight. FreeFly/RTS/Orbital remain accessible with keys 1/2/3;
Tab cycles cameras and Escape releases FreeFly mouse capture.
The visual route is CPU-heavy and may require several minutes; use a process
timeout of at least 600 seconds on low-end hardware. It is not an FPS benchmark.

## Stutter profiling

```powershell
./tests/planet/run_profile.ps1 -Label debug-on -Graphics
./tests/planet/run_profile.ps1 -Label debug-off -Graphics -DebugOff
```

Run these **sequentially**, without other tests in parallel. Omit `-Graphics`
for CPU-only headless diagnostics, not for claims about perceived smoothness.
The route uses 1,200 updates, a fixed simulation delta of 0.05 s, the same
camera poses and a 1100×760 viewport. It covers distance, progressive approach,
surface proximity, lateral movement, retreat and a fixed settling interval.
Output JSON includes per-update timings/counters and summaries; files go to a
fresh temporary directory printed by the runner. No per-frame file I/O occurs.

`update_us` measures the coordinator's CPU work. `selection_total_us` includes
structural/balance work during selection; `selection_sse_us` subtracts those
instrumented subsets. Do not add overlapping timers. `frame_us` is wall-clock
time to the next process-frame signal, including rendering/engine/waiting; it is
not a GPU timer. For component p95, only updates containing that timer are used;
update/frame percentiles cover all samples. Visual removal times measure queuing
of deletion, with deferred engine cost reflected in frame time.

The 4 ms CPU budget is **soft**, additional to operation budgets: it yields at
64-vertex blocks, leaf checks, or a complete ArrayMesh commit. It cannot preempt
an engine call. A value of 0 disables the time deadline for deterministic
operation-budget tests. CPU timing changes intermediate states, so compare
latency, work counts and final convergence, not only elapsed time. A fixed-length
route can end before all merges have completed; the visual test additionally
waits for stable states. Profiling is opt-in through `view.profile.enabled`.
