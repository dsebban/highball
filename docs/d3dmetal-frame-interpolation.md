# D3DMetal 4 frame interpolation (local prototype)

Per-program profiles that let a game's DLSS Frame Generation run on D3DMetal 4's MetalFX
frame interpolator. Prototype on one Mac (M6, macOS 27.2, 3440x1440 at 120 Hz), with
D3DMetal 4.0 beta 3 linked from a Game Porting Toolkit already installed on that Mac.
Nothing of Apple's is redistributed by this repository.

## How it works

- `highball engine install <manifest> --local-d3dmetal <dir> --accept-d3dmetal-license` links
  the engine's `renderers/d3dmetal/{wine,external}` to a local GPTK folder instead of
  downloading D3DMetal. The version must match the manifest's component; Apple's licence must be
  accepted; the framework binary's sha256 is recorded. A reinstall links it again.
- `highball pin set <bottle> <pin> interpolation cap=N mtl4=0|1 cwd=PATH` stores a
  `FrameInterpolationProfile` on the pin. `highball pin check` prints what a launch would get.
- At launch (`WineRunner.start(pin:)`) the profile applies only when the stack can use it:
  renderer d3dmetal, D3DMetal >= 4, the bottle's DLSS (MetalFX) on, the working folder exists,
  and `nvngx_dlssg.dll` lies beneath the executable's folder or the working folder (D3DMetal's
  own search). Otherwise the program starts exactly as without a profile, and the log header
  says why.
- A ready profile sets `D3DM_MAX_FPS` (presented frames, generated ones included),
  `D3DM_MTL4`, the working folder, and `CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`.

## Why each part is needed (measured, Hellblade II)

1. **Working folder.** D3DMetal reports `FrameGeneration.Available` to Streamline only when it
   finds `nvngx_dlssg.dll` under the executable's folder or the process working folder. Hellblade
   II ships it under `Engine/Plugins/...`, so the profile starts it in the game's root
   (`cwd=../../..`).
2. **`CX_ACTIVE_GRAPHICS_BACKEND=d3dmetal`.** Streamline then queries
   `D3DKMTQueryAdapterInfo` type 70 (WDDM 2.7 caps, hardware GPU scheduling). The engine's
   `win32u` answers it (supported, enabled) only when this variable is `d3dmetal`. CrossOver
   sets it per process from the backend it chose; Highball's engine never did. Unanswered,
   Streamline logs "Disabling DLSS-G since it is not supported on current hardware" and the
   game hides Frame Generation.
3. **Presented cap.** `D3DM_MAX_FPS=60` with 2x interpolation means about 30 rendered and
   30 generated frames per second.

## Methodology

- **Isolation.** An isolated `HIGHBALL_HOME` and bottle; game saves and settings copied in
  and hashed; the original CrossOver bottle, launchers and saves are never written. One GPU
  workload at a time (a shared lock directory).
- **Single-variable controls.** Each causal claim is an A/B in which only one variable
  differs, run positive → negative → positive so order and warmth favour neither. The
  negative build is the same source with only the variable removed.
- **What is counted.** Rendered frames (D3DMetal HUD "Render FPS") are kept apart from
  presented frames (HUD "FPS", and changed pictures per second on a ScreenCaptureKit capture).
  A capture is not panel evidence. Logs give the Wine and Streamline side (`+d3dkmt` trace,
  Streamline console log), with an unrelated fixme (type 48) as a check that the channel was on.
- **Correct output.** Interpolation is only claimed when the HUD reports the interpolator
  active, the capture shows about 2x changed pictures over the render rate, and inspected
  frames show gameplay without visible defects.

## Result (2026-11-09)

| Run | Variable | type-70 unanswered | Streamline DLSS-G | HUD rendered / presented | Changed pictures/s |
|---|---|---|---|---|---|
| P1 | set | 0 | (not logged) | 29.6 / 59.5, interpolator on | 58.6 |
| N | absent | 1 | disabled | 39.8, no interpolator | 40.1 |
| P2 | set | 0 | loaded, menu offers it | 30.0 / 60.0, interpolator on | 58.6 |
| P3 (fresh launch, plain pin) | set | n/a | (not logged) | 30.0 / 60.0, interpolator on | 58.5 |

## Limits

- Only programs with a profile get the variable; other D3DMetal games with DLSS still have
  Frame Generation refused, and games Steam starts get no profile.
- The marker search bounds (12 levels, 50,000 entries) are measured, not documented by Apple.
- Interpolation adds latency; it was not re-measured here.
