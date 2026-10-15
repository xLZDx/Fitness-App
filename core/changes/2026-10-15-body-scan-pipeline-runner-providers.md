# Change record: C14 part 2 - job runner, upload port, repositories, providers

## What changed
New files under `mobile/lib/features/body_scan/state/`:
- `body_scan_job_runner.dart`: the offline queue executor. The queue is the set of v2 `ScanRecord`s with a non-terminal `analysis.status`; legacy v1 scans are never touched (D-6). One scan at a time, re-entrant `resume()`, backoff `min(2^attempt, 300)` s with max 5 attempts via the pure `BodyScanJob`, a retry timer (no `connectivity_plus` in pubspec), `retry`, `cancel` (aborts the PUT, asks the server to delete, or records `pendingRemoteDelete` when that fails) and `forget` (a locally deleted scan can never be resurrected). Every write is fenced by `accountChanged()` and a per-scan stop set.
  - LOCAL path (default): computes the provisional estimate on the device with zero callable and zero PUT calls, works offline, never reads a photo (D-52); verification is the pure `evaluatePlausibility` (manual override lowers confidence, previous-scan weight context).
  - CLOUD path: reachable only when `BodyScanFlags.cloudPhotos` is on AND the stored consent is current AND the server reports a provider; `provider-not-configured` / `feature-disabled` fall back to the local path. Create, blur on device, face check on the BLURRED bytes (`faceCheckAllowsUpload`, the default detector says "cannot verify" so nothing is uploaded, D-69), PUT, estimate, verify. An expired URL re-calls the idempotent create once per pose; `scan-cancelled` rotates `remoteId` to `<id>_r<n>` and re-queues.
- `photo_upload_port.dart`: `PhotoUploadPort` and `DioPhotoUploadPort` (PUT with the signed headers, 3 attempts, 1/2/4 s backoff, 403 or past-expiry reported as `upload-url-expired`, other 4xx not retried, abort support).
- `firestore_body_scan_repository.dart`: `FirestoreBodyScanRepository` (reads `body_scans`, writes only `weightKg` and `clientNote`, matching the rules) and `InMemoryBodyScanRepository`.
- `body_scan_settings.dart`: `BodyScanSettings`, store interface, Firestore store (consent written with a server timestamp only when it changes; merge writes keep the old consent valid under the rules) and in-memory store.
- `scan_trend_source.dart`: `readingsFrom` (local + server readings, deduplicated by scan id, server wins), `bodyFatTrendInputFor` (4-week label, change in points, provisional and estimator-change flags, D-54) and `ScanBodyFatTrendSource` for the weekly review (D-71).
- `body_scan_providers.dart`: safe defaults for every port (in-memory repositories, lazy callable client, `UnavailableFaceCheck`), `bodyScanSettingsProvider`, `bodyScanEntriesProvider`, `scanTrendProvider` (segmented per estimator), `scanBodyFatTrendSourceProvider`, `scanCompletedProvider`, `bodyScanRunnerProvider` and `DataScanResultSource` (binds the C15 `ScanResultSource` port).
- `body_scan_api.dart`: the callable client is now constructed lazily (no Firebase access until a call).

## Already present, not duplicated
The weight repository (Firestore + in-memory), `weightEntriesProvider`, `currentWeightProvider` and the weight actions already exist in `nutrition_plan` from the C18 commit; this commit reuses them (`nutritionClockProvider`, `currentWeightProvider`, `weightEntriesProvider`) instead of creating a second weight repository.

## Why
Sprint plan C14; design s9, s10, D-4, D-52, D-67, D-69, D-71, D-72, D-78.

## App root still has to bind (outside this commit)
- `bodyScanRepositoryProvider` -> `FirestoreBodyScanRepository(uid: ...)` and `bodyScanSettingsStoreProvider` -> `FirestoreBodyScanSettingsStore(uid: ...)` (only needed when the cloud path is built).
- `scanPlanContextProvider` -> `nutritionScanPlanContextSourceProvider` (replaces `kScanPlanContextPlaceholder`).
- `bodyFatTrendSourceProvider` -> `scanBodyFatTrendSourceProvider`.
- `scanResultSourceProvider` -> `dataScanResultSourceProvider`.
- A bridge listening to `scanCompletedProvider` that bumps nutrition `scanDoneSignalProvider` (body_scan does not import the review state, D-71).
- A trigger calling `ref.read(bodyScanRunnerProvider)?.resume()` on app foreground and when Progress opens (also after a scan is saved).

## Deviations (recorded)
- The flow state machine stays the pure spec used by the flow controller; the runner persists progress through `analysis.status` and `BodyScanJob` (same retry policy and caps) rather than driving `FlowState`.
- `connectivity_plus` is not available, so resume is foreground / Progress-open / timer.
- Local verification does not use the smoothed previous trend value (`previousSmoothedPct` stays null).

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: local path makes zero api/uploader calls, cloud branch unreachable with flag off or consent missing, fail-closed refusal (default face check uploads nothing), `scan-cancelled` rotation, account-change fence, cancel race, retry/backoff, trend segmentation per estimator.

## Review state
Pending the test phase and specialist reviewers.
