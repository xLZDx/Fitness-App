# Change record: C14 part 1 - callable client, blur service, scrubbed errors

## What changed
New files under `mobile/lib/features/body_scan/state/`:
- `body_scan_api.dart`: `BodyScanApi` (createBodyScan, estimateBodyScan, deleteBodyScan) and `CallableBodyScanApi` (region `europe-west1` through `functionsForRegion`). Request and response shapes follow `functions/src/body_scan/{create,estimate,delete}.ts`: `{scanId, takenAtMs, subject{sexAtBirth, heightCm, weightKg}, capture{manualOverride{front,side,back}}}`; `uploads.<pose>{url, headers, expiresAtMs}`; `estimate{bodyFatPct, rangeLowPct, rangeHighPct, confidence, checkCodes, modelId, modelVersion}`. Every `FirebaseFunctionsException` becomes a `BodyScanApiException` carrying a CLOSED slug, a `retriable` flag and the helpers `isScanCancelled` (rotate `remoteId`) and `isMissingUpload` (upload again).
- `scrubbed_error.dart`: `scrubbedError(Object)` reduces any error to a closed slug (D-67); raw messages of unknown types never reach `lastError` or `recordError`.
- `blur_service.dart`: `BlurService` port and `IsolateBlurService`. Geometry is the existing pure `computeFaceRegion`; pixels are handled in an isolate with the `image` package: bake EXIF orientation, long edge 1280, pixelate the head box (block `max(8, side/10)`), two Gaussian blur passes, re-encode JPEG from raw pixels at quality 85/70/55 until `<= 3 MB`. FAIL CLOSED: no landmarks, unsizable head box, undecodable bytes or an oversize result return `BlurRefused`, never an unblurred image (D-4).

## Why
Sprint plan C14, design s7, s9, D-4, D-67, D-69. The runner and providers follow in the next commit.

## Deviations (recorded)
- The design names two box-blur passes; `image`'s `gaussianBlur` is used twice (no extra dependency, equally irreversible on top of pixelation).
- No new package is added (`dio`, `image`, `cloud_functions` are already in pubspec); `connectivity_plus` is NOT in pubspec, so the runner (next commit) resumes on foreground, on Progress open and on a retry timer, which the design allows as the fallback.

## Affected contracts and paths
New files only; no existing file is edited.

## Verification state
Not run, per DEVELOPMENT RULES v4. Focused tests: slug mapping, fail-closed blur refusals, blurred head box differs from the source while the rest is intact, output `<= 3 MB` and metadata free.

## Review state
Pending the test phase and specialist reviewers.
