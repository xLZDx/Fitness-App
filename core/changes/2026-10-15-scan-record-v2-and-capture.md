# Change record: C13 ScanRecord v2 and capture-screen changes

## What changed
- `progress_photos/scan/scan_models.dart`: `ScanRecord` v2 adds `analysis` (`ScanAnalysis`: job `status`, `attempt`, `remoteId`, `remoteStatus`, `lastError` slug, locally computed provisional `estimate`, `updatedAt`), `weightKg`, `manualOverride` (per pose) and `pendingRemoteDelete`. `tryFromJson` still reads v1: a record without `analysis` is a LEGACY local-only scan (`isLegacy`) and is never auto-uploaded (D-6). `remoteId` defaults to the local id. `ScanStore` format and atomic temp-file + rename are unchanged; the new fields live inside the same encrypted envelope.
- `ui/scan_ports.dart`: `ScanCamera.luminance` is a NON-abstract getter (default `null`); `MlKitScanCamera` overrides it from the new `CameraSession.lastBrightness`. `ScanSpeaker.say` now returns `Future<bool>` (false = speech failed, still swallowed but observable). `ScanHaptics` gains `pattern(ScanHapticPattern)` with six named patterns (ready, lost, distance, lighting, position, pose). `scanManualTimerSecondsProvider` (3 / 5 / 10 s, default 5).
- `core/camera/camera_session.dart`: stores the mean brightness it already computes per frame (`lastBrightness`); no new sampling.
- `ui/scan_capture_screen.dart`: real luminance into `ReadinessEvaluator` (over-exposure is now detectable); manual shutter starts a visible, announced, cancellable timer (D-80) and records `manualOverride[pose]` only when it FIRES while not ready; the auto machine is not fed while the manual timer runs; one announcement channel per countdown tick (screen reader: live region only; otherwise speech only; haptic ticks stay); the hint is a polite live region throttled to one change per 2 s; speech failure falls back to the live region; named haptic patterns on ready, lost and per failing check class; the panel is height-bounded (half the screen) and internally scrollable with the shutter and timer Cancel outside the scroll area at >= 48 dp; theme text styles instead of the 160 px / 12 px / 11 px literals; spinner replaced by static text under reduced motion; camera and save errors are live regions; pose-specific retake labels; the saved record carries `analysis: queued`, `weightKg`, `manualOverride`; the screen pops with the new scan id (`ScanCaptureScreen({weightKg})`).
- NEW `body_scan/widgets/skeleton_overlay.dart` (joints and bones from the latest `PoseFrame`; solid + filled when ready, dashed + hollow when not, so never colour alone; decorative for assistive tech) and `body_scan/widgets/setup_status_panel.dart` (four rows Distance / Lighting / Position / Pose, icon + text + state; a failing row shows the specific prompt of the current hint when it belongs to that row). Existing `scan.check.<name>.<status>` keys are kept.
- ARB EN + RU: `scanManualTimerStarted` (plural, RU one/few/many/other), `scanManualTimerCancel`, `scanAllChecksOk`, `scanRetakePose`.

## Why
Sprint plan C13; design s10, s11, D-6, D-52, D-80, D-81, D-85.

## VERIFY outcomes
- Camera luminance source: `CameraSession._updateLowLight` already computes `averageFrameBrightness` on every analysed frame; only the last value was missing, so one field was added. `ReadinessConfig.minLuminance 0.25 / maxLuminance 0.92` are now live for the real camera.
- Landmark projection: the overlay maps `x / aspectRatio * width, y * height` (the preview fills the screen); `scan_landmark_mapper.dart` is for stored landmarks and was not needed. Any letterboxing mismatch only shifts the overlay, never a decision.

## Deviations (recorded)
- The "all four checks OK" cue and the countdown go through live-region semantics rather than `SemanticsService.announce`; this is the one channel the design asks for and avoids a second announcement API.
- The manual-timer length is a provider default (5 s); the settings UI that changes it is a later UI commit.
- `mobile/test/features/progress_photos/scan/ui/scan_fakes.dart` is NOT edited here (test agents own tests): `FakeScanCamera` needs `luminance` (any `double?`), `FakeSpeaker.say` must return `Future<bool>`, `FakeHaptics` must implement `pattern`. Existing widget tests that tapped the manual shutter and expected an instant capture must pump the timer.
- The weight prompt UI that supplies `weightKg` is C15; the parameter is optional and null until then.

## Affected contracts and paths
`ScanSpeaker`, `ScanHaptics` and `ScanCamera` implementers; `ScanRecord` JSON (`v: 2`, tolerant of v1); screen pop result is now `String?`.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests belong to the test phase (coverage map: scan record v2 round-trip and v1 tolerance, manual-timer cancel / fire / override, single announcement channel, throttled hint live region, panel at text scale 2.0, status rows).

## Review state
Pending the test phase and specialist reviewers.
