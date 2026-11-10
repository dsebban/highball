# Hellblade II: Highball against CrossOver, same configuration (local study)

Hill-climb of Highball's x86_64 engine (`x64-crossover26.3-r30`, D3DMetal 4.0b3 linked from a
local GPTK) against the working CrossOver 26.3 setup as the oracle. One Mac: M6, macOS 27.2,
3440x1440 at 120 Hz. Nothing of Apple's, CodeWeavers' or the game's is in this repository.

## Method

- **Same configuration on both sides.** One copy of the game, the same save (Continue checkpoint)
  and settings files, hash-checked in both bottles: 3440x1440 fullscreen, DLSS Ultra Performance
  (MetalFX 1149x481 to 3440x1440), the same Frame Generation state, `D3DM_MTL4=0`, Metal HUD on.
- **Oracle.** The CrossOver runtime on an APFS clone of the working bottle, picked by absolute
  `--bottle` path; Highball in an isolated `HIGHBALL_HOME`. Original runtime, bottle, launchers
  and saves are never written.
- **No ceiling.** Measurement runs use `D3DM_MAX_FPS=120` on both sides so the playable cap (60)
  cannot hide a difference; the playable profile is restored afterwards.
- **Frame Generation off for the hill-climb** (measurement only, both sides): with FG on the
  rendered rate was the same on both sides (29.39 against 29.27 FPS, GPU 24.2 ms on both), and
  every generated frame halves a rendered-rate difference. FG off is GPU-bound (GPU ms × FPS ≈ 1000),
  so it shows any change in GPU work per frame.
- **One run.** Launch, Continue, 20 s settle, 30 s static view (HUD read by OCR every 2 s: FPS,
  GPU ms), a 20 s scripted walk with an 18 s ScreenCaptureKit capture (changed pictures per second,
  interval percentiles), screenshots, thermal, swap, memory pressure and CPU time per process.
  Rendered and presented frames are counted separately; with FG off they are equal.
- **Clean slate.** Steam and other background load stopped, audio muted, one GPU workload at a time
  by agreement (a shared lock directory; once broken by another program, and that run was replaced).
- **One change at a time.** Each candidate is an engine or environment change on a clone, two
  runs first, then an interleaved A/B with a negative control on the unchanged binary if it moves
  outside Highball's own spread.
- **Correct picture.** Added after the fact, when one CrossOver run came out 8% faster: its static
  frame showed a different lighting state (MetalFX exposure 7.98 against about 4.3). A hillside luma
  check over every run in the study found only that one (0.1 against 0.9–2.1); it is not counted.

## Work log (compact)

| Step | Change | Static FPS (n) | Verdict |
|---|---|---|---|
| Baseline, FG on | none | cx 29.39 [29.33–29.57] vs hb 29.27 [28.97–29.45] (3/3) | no difference |
| Baseline, FG off | none | cx 39.02–39.34 (5) vs hb 38.50–38.81 (5) | hb 0.8–1.3% slower, GPU 25.8 vs 26.1 ms, game CPU equal |
| E1 | timestamp shim idle (`HB_D3D12_TSSHIM=0`) | 38.50, 38.61 | no gain on the unsigned engine (but see E11) |
| E2 | CrossOver's NVIDIA identity variables | 38.71, 38.71 | no gain |
| E3 | `D3DM_EXE_OVERRIDE` with the game's exe name | 38.71, 38.50 | no gain; D3DMetal already detects the exe |
| E4 | `ROSETTA_ADVERTISE_AVX=1` (CrossOver wrapper default) | 38.81, 38.71 | no gain |
| E5 | CrossOver's own winemac (stock) | 38.81, 38.71 | no gain |
| E6 | Wine patch 0005's `sched_yield` calls removed | 38.50, 38.81 | no gain |
| X1 | CrossOver runtime on a clone of the Highball prefix | 39.24, 39.02 | prefix excluded; the gap is in the runtime |
| E7 | timestamp shim removed from the DLL path | 38.61, 38.81 | no gain on the unsigned engine (but see E11) |
| E8 | Highball's audio additions off | 38.81, 38.61 | no gain |
| E9 | engine's Wine loaders signed ad hoc | 39.13, 39.34 | at CrossOver's level |
| E10 | Mac Driver `CaptureDisplaysForFullscreen=y` for the game | 38.97 | no gain; HUD still "Composited" |
| E11 | timestamp shim idle on the signed engine (found by Metal System Trace) | 39.33 (3, interleaved) | ahead of CrossOver in that batch, FG off; see below |

E9's lead came from the system log: for the unsigned process Apple's Neural Engine daemon logged
`bundleID rejected` and `refusing compile — outputPath is nil/empty (rejected by cache manager).
csIdentity=<engine>/lib/wine/x86_64-unix/wine_unsigned`, and MPSGraph in the game process
`ANE compilation failed` and `Full compile with ANE as preferred device failed. Falling back to
full compile on GPU`. CrossOver's loader carries a Developer ID signature. With an ad hoc
signature the daemon compiles the network and those lines are gone.

## Result

Confirmation with the change in Highball's code (`EngineStore.signIntelLoader`), interleaved
cx S U U S cx S U cx, 3 counted runs per side; S is the new binary on the engine it signed, U the
parent binary on a clone of the engine whose unsigned loaders are restored before each run.
Two runs were replaced and not counted: one control overlapped another program's GPU benchmark
during its load, and one CrossOver run rendered a different lighting state (hillside luma 0.1
against 0.9–2.1 in every other run).

| FG off, cap 120 (measurement) | Static FPS, run means | Mean (sd) | GPU ms | Walk FPS, run medians | Capture p50 / p99 |
|---|---|---|---|---|---|
| CrossOver | 39.22, 38.88, 39.17 | 39.09 (0.18) | 25.8 | 40.0–40.3 | 25.0 / 33.3 ms |
| Highball, loaders signed | 39.12, 39.00, 39.14 | 39.09 (0.07) | 25.8 | 39.6–40.6 | 25.0 / 33.3 ms |
| Highball, loaders unsigned | 38.51, 38.60, 38.68 | 38.60 (0.09) | 26.1 | 39.5–39.8 | 25.0 / 33.3 ms |

Every unsigned run logged MPSGraph's "Falling back to full compile on GPU" twice; no signed or
CrossOver run did. That the fallback network is what costs the 0.3 ms of GPU per frame is
inferred from this correlation and the GPU time, not traced inside D3DMetal.

| FG on (the playable configuration), cap 120 | Rendered FPS | Presented FPS | GPU ms |
|---|---|---|---|
| CrossOver (2 runs) | 29.21, 29.39 | 58.5, 58.8 | 24.4, 24.2 |
| Highball, loaders signed (2 runs) | 29.39, 29.33 | 59.0, 58.8 | 24.3, 24.3 |

With frame generation on the two were already level before the change, and remain level.
The playable profile (cap 60, FG on, MTL4=0, MetalFX) was restored and checked with a fresh launch.

## Second pass: profiler sample, timestamp shim idle for this game

After signing, the frame is GPU-bound on both sides (frame interval minus GPU time is −0.2 ms on
every run, game CPU time equal), so the next lever had to be GPU work. One 6 s Metal System Trace
per side during the static view (profiling-only runs, not counted, `xctrace` lowers FPS by 1.1–1.7
on both sides) showed GPU busy 99.7% against 99.8% and similar Fragment and Vertex time, but
Highball issued about 1092 Blit encoders a second against CrossOver's 547, about 14 more per frame,
and its Compute time was higher (summed interval time 6955% of the span against 5720%, with the
same 692 dispatches per frame in the HUD).

The extra commands come from Highball's timestamp shim (`spike/tsshim/d3d12.c`). D3DMetal 4.0b3
still has no D3D12 timestamp queries (it logs `Unsupported: ...EndQuery - Type = 2` and
`...ResolveQueryData - Type = 2`), so the shim serves them, and `hook_ResolveQueryData`, the only
hook that records commands, adds one `CopyBufferRegion` from its upload ring per resolve. D3DMetal's
HUD agrees: Copy Resource per frame 172 with the shim, 121 with it idle, 120 on CrossOver (FG off;
90, 63 and 63 with FG on). A trace with `HB_D3D12_TSSHIM=0` (the shim's existing kill switch)
brought Blit to 563 a second and Compute time to 5660%. That these copies are what costs the GPU
time (plausibly by splitting the game's compute encoders) is inferred, not isolated: the kill
switch idles every hook of the shim, not only the copy.

Confirmation, interleaved cx I S I cx S cx I S for each table, 3 counted runs per side, no runs
replaced; I is the signed engine with the shim idle, S the signed engine with the shim active
(the configuration committed in 961a715). Launch headers for I and S differ only in
`HB_D3D12_TSSHIM=0`; same binary, engine and signed loaders.

| FG off, cap 120 (measurement) | Static FPS, run means | Mean (sd) | GPU ms | Walk FPS mean (sd) |
|---|---|---|---|---|
| CrossOver | 39.05, 39.14, 39.21 | 39.13 (0.08) | 25.78 | 40.38 (0.30) |
| Highball, shim idle | 39.31, 39.32, 39.37 | 39.33 (0.03) | 25.65 | 40.31 (0.09) |
| Highball, shim active | 39.11, 39.15, 39.21 | 39.16 (0.05) | 25.76 | 40.23 (0.15) |

| FG on (playable graphics), cap 120 | Rendered FPS, static run means | Mean (sd) | Presented | GPU ms | Walk rendered |
|---|---|---|---|---|---|
| CrossOver | 29.36, 29.32, 29.13 | 29.27 (0.12) | 58.83 | 24.26 | 29.90 |
| Highball, shim idle | 29.55, 29.52, 29.55 | 29.54 (0.02) | 59.25 | 24.08 | 29.64 |
| Highball, shim active | 29.53, 29.23, 29.45 | 29.40 (0.16) | 59.30 | 24.09 | 29.73 |

- **FG off, static view:** with the shim idle Highball rendered 0.5% more frames than CrossOver
  and than itself with the shim active, GPU 0.13 ms less per frame; the run ranges are disjoint
  within this batch. Across the whole study the CrossOver mean is the same (39.13, 12 counted
  runs), but its two best earlier runs (39.31 and 39.32, unrounded 39.307 and 39.315) reach the idle range. The HUD reads FPS in
  steps of about 0.11, so the gain is about two steps.
- **FG on:** idle Highball rendered 29.54 against CrossOver's 29.27 (pooled over the study 29.33,
  8 runs; one earlier CrossOver run reached 29.55). The shim is not shown to cause this part: idle
  and active differ by 0.14 FPS with overlapping runs and equal GPU time (24.08 against 24.09 ms),
  and the shim-active runs were also ahead of CrossOver in this batch. Treat FG on as level to
  slightly ahead, not as a measured shim gain.
- **E1 and E7 disagree.** On the unsigned engine the same switch (and removing the shim) gave
  38.64 on average against 38.66 for the unsigned runs without it, no gain at all, where an additive
  0.2 FPS would have shown. Why the effect appears only after signing is not known; part of the
  I minus S gap could be this batch's noise. Three runs per arm is a small sample.
- **Walk:** no measurable difference in either direction; the walk's spread (scripted input,
  streaming) is larger than the effect. One idle FG-on run walked at 29.06.
- **Picture and pacing:** MetalFX 1149x481 to 3440x1440 on every run (so no dynamic resolution),
  HUD draw counts in the inspected screenshots 1015–1027 (FG off) and 508–512 (FG on) on all sides;
  hillside luma 0.9–2.0 on every run; walk capture p50 16.7 / p99 25.0 ms with FG on and
  25.0 / 33.3 ms with FG off on all three sides, 58.7–60.4 changed pictures a second with FG on,
  5th-percentile picture difference 0.28–0.37 (no cluster of repeated pictures).
- **HUD caveat:** the Metal HUD's "Frame Interpolator" rows were missing on 5 of the 6 Highball
  FG-on runs in this batch (shim idle and active alike) and on none of its CrossOver runs; earlier
  they were missing on two CrossOver runs (cx2, cxF2) and present on every Highball run. The Render
  FPS row was present, presented FPS was twice rendered on every FG-on run, and the capture showed
  about 60 distinct pictures a second, so interpolation ran and the counts do not depend on that row.
- **Timestamps:** neither mode gives the game real GPU timings. The shim stamps the CPU clock when
  the command list is recorded; idle, the queries are unanswered by D3DMetal, which is what CrossOver
  (same D3DMetal 4.0b3, no shim, Copy Resource 120) presumably gives the game too.

Applied as configuration, not code: the program's pin carries `HB_D3D12_TSSHIM=0`
(`highball pin set <bottle> "Hellblade II" env HB_D3D12_TSSHIM=0`). The shim stays the default,
because D3DMetal 4.0b3 still lacks timestamps and the game it was written for (#63) needs it.
The playable profile with this setting (cap 60, FG on, MTL4=0, MetalFX, shim idle) was checked
with a fresh launch: Frame Interpolator Enabled on every HUD sample, 59.3 presented and 29.5
rendered FPS, capture p50 16.7 / p99 25.0 ms.

## Limits

- With loader signing alone Highball reaches CrossOver's rendered frame rate. With the shim idle
  for this game as well it rendered 0.5% more than CrossOver in the static view with FG off
  (0.13 ms of GPU per frame), in one interleaved batch of 3 runs per side; with FG on it was level
  to slightly ahead, not attributable to the shim. The margin shows only where the scene is steady
  and is not visible at the playable 60 cap with frame generation. The other runtime differences
  tried (E2–E8, E10) left the GPU time per frame unchanged.
- Idling the shim also idles its other fixes (shader-model answer, multisampled depth resolve,
  append-aligned input layouts). Hellblade runs correctly without them, as it does on CrossOver,
  which has none; another game may not, so this is per program.
- The walk does not separate the sides. In the first confirmation its means were CrossOver 40.48,
  signed 40.01, unsigned 39.66 FPS (signed about 1% behind); in the second, interleaved again, they
  were CrossOver 40.38, signed 40.23, signed with the shim idle 40.31, all within one run's spread.
  The walk is scripted input with more spread (camera and streaming), so it is weaker evidence
  either way.
- The mechanism (refused ANE compile, GPU fallback network, 0.3 ms more GPU per frame) is a
  correlation across every run, not traced inside D3DMetal or MPSGraph; no knock-out was run.
- One game, one scene, one Mac. Other games whose D3DMetal path builds MPSGraph networks may be
  affected the same way; unmeasured.
- The loader is signed when an engine is read and its loader is a thin unsigned Mach-O; a loader
  with a broken signature is not re-signed. The signed copy replaces the file by rename, so a running game
  keeps its mapping. Each call signs its own copy and renames it over the loader, so two
  processes signing at once each install a whole signed file. A loader that fails to sign is tried
  again only in a later process.
- Exclusions: two of the eleven confirmation runs were replaced (reasons above); including
  the excluded CrossOver run would make CrossOver's mean 39.85 and Highball 1.9% slower in that set.
