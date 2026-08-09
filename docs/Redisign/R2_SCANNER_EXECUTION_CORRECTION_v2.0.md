# R2 Scanner Execution Correction — v2.0

Use this correction immediately if an agent is already working from v1.9.

## What changed

The newer code/environment evidence changes R2 execution in five important ways:

1. Gallery retry/double-tap is host-testable with `ImagePickerPlatform.instance`; no production code change is required just to reach `_classify`.
2. Four platform scenarios are honestly reproducible on the current emulator: permission denied, permanently denied, no camera, and offline.
3. Real darkness and camera frame stalls are physical-device validation items, not emulator claims.
4. Figma visual parity is not automatically blocked by the absence of `design/` in Fitness-App. First use the read-only `xLZDx/ReviewExistingExamples` Make reference repo to render/capture deterministic reference states. Request manual PNG only for states that cannot be rendered there.
5. Brightness/confidence/frame thresholds must not be invented. Add debug-only instrumentation, collect live-device evidence, then calibrate in a separate gate.

## Required sequence

R2g → R2f → R2v → R2h → R2i → R2j → R2k(optional)

### R2g
Test-only fake `ImagePickerPlatform`; restore the two removed tests; prove the real retry path and assert recognizer/cloud boundary call count == 1 under rapid duplicate interaction.

### R2f
Emulator evidence for 4 real OS scenarios. No claims for real darkness/frame stall.

### R2v
Run/read `ReviewExistingExamples` if possible and capture reference screenshots; compare against deterministic Flutter screenshots. Manual PNG export only for missing/unrenderable reference states.

### R2h
Debug-only structured instrumentation for brightness/confidence margin/frame cadence/smoothing; no sensitive data and no release debug UI.

### R2i
Physical-device evidence collection.

### R2j
Evidence-based threshold/hysteresis calibration plus boundary tests.

### R2k
Goldens only after visual parity approval; deterministic camera fixture only.

Do not push the existing five R2 commits until separate push-GO.
