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
| E1 | timestamp shim idle (`HB_D3D12_TSSHIM=0`) | 38.50, 38.61 | no gain |
| E2 | CrossOver's NVIDIA identity variables | 38.71, 38.71 | no gain |
| E3 | `D3DM_EXE_OVERRIDE` with the game's exe name | 38.71, 38.50 | no gain; D3DMetal already detects the exe |
| E4 | `ROSETTA_ADVERTISE_AVX=1` (CrossOver wrapper default) | 38.81, 38.71 | no gain |
| E5 | CrossOver's own winemac (stock) | 38.81, 38.71 | no gain |
| E6 | Wine patch 0005's `sched_yield` calls removed | 38.50, 38.81 | no gain |
| X1 | CrossOver runtime on a clone of the Highball prefix | 39.24, 39.02 | prefix excluded; the gap is in the runtime |
| E7 | timestamp shim removed from the DLL path | 38.61, 38.81 | no gain |
| E8 | Highball's audio additions off | 38.81, 38.61 | no gain |
| E9 | engine's Wine loaders signed ad hoc | 39.13, 39.34 | at CrossOver's level |

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

## Limits

- Highball reaches CrossOver's rendered frame rate here; it does not beat it. Every other runtime
  difference tried left the GPU time per frame unchanged.
- Parity holds for the static view. In the 20 s walk the means are CrossOver 40.48, signed 40.01,
  unsigned 39.66 FPS: signed is about 1% behind CrossOver there and overlaps the unsigned runs. The
  walk is scripted input with more spread (camera and streaming), so it is weaker evidence either way.
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
