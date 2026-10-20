# Body scan root wiring record

Story: integration wiring of Body Scan with the Nutrition Coach at the app root.

## What changed
- `mobile/lib/core/wiring/body_scan_wiring.dart` (new): the only place that knows both body_scan and nutrition state.
  - `bodyScanRootOverrides()`: `scanPlanContextProvider` -> `nutritionScanPlanContextSourceProvider` (replaces the measurement-only placeholder), `bodyFatTrendSourceProvider` -> `scanBodyFatTrendSourceProvider`, `scanResultSourceProvider` -> `dataScanResultSourceProvider`. Only when `BODY_SCAN_CLOUD` is compiled in: `bodyScanRepositoryProvider` and `bodyScanSettingsStoreProvider` -> Firestore implementations keyed by the signed-in uid (in-memory while signed out).
  - `bodyScanRootWiringProvider` (watched once in `FitnessApp.build`): bridge `scanCompletedProvider` -> `scanDoneSignalProvider`; keeps `weeklyReviewTriggersProvider` alive (nobody else watched it); resumes the job runner when it appears (sign-in/account change) and when the router location enters `/progress` (no edit to `progress_page.dart`).
  - `resumeBodyScanRunner(ref)`: called on app foreground.
- `mobile/lib/main.dart`: drops the placeholder override/import, spreads `bodyScanRootOverrides()`, resumes the runner on `AppLifecycleState.resumed`, watches the wiring provider.
- `mobile/lib/features/body_scan/state/body_scan_flow_driver.dart` (new, body_scan only): executes the effects of `scanFlowControllerProvider` through the runner. Keeps `FlowContext` in step with flags, consent and the weight log; after the capture screen returns a scan id it sets `bodyScanActiveScanIdProvider`, replays capture events to `savingLocal`, answers `saveLocal`, starts the runner (resume after save), forwards cancel/retry, and follows the persisted scan record to `done` or `failed`.
- `mobile/lib/features/body_scan/body_scan_flow_page.dart`: watches the driver, uses the id popped by `/photos/scan`, and shows `CloudConsentSheet` before start only when `BODY_SCAN_CLOUD` is on and no current consent exists (a refusal keeps the scan on the device).

## Not bound
- `/nutrition` route placeholder: skipped on purpose (C19 owns it).
- Scans saved directly from `/photos/scan` (outside the flow page) are picked up by the next foreground or Progress open, not instantly.
- A cloud-path face-check detector is still the fail-closed default (`faceCheckPortProvider`).

## Verification state
Not run (operator rule). No tests, analyze or build executed.
