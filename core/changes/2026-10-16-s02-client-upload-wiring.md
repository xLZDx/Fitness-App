# S02 client upload wiring behind ACTIVITY_CLOUD_STREAMS

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/core/wiring/activity_wiring.dart`: new providers for the account-scoped consent store, the cloud settings client, the stream uploader and the consent-withdrawal presenter. The uploader and presenter providers return null unless `ACTIVITY_CLOUD_STREAMS` is on and a journal is open, so the default build (flag OFF) is unchanged.
- The start-of-session pass in `activityCloudSyncWiringProvider` now runs the summary sync as before, then (flag ON only) signs the consent store in for the uid, loads the cached consent and runs `ActivityStreamUploader.runPending()` once. Errors are logged by type only and never block the UI.

## Why
The uploader and withdrawal flow must be reachable from the app; plan I15 requires that flag OFF has no upload path.

## Affected contracts and paths
`mobile/lib/core/wiring/activity_wiring.dart`. Uses `shared_preferences` (already a dependency).

## Verification state
No tests, analysis or builds were run (operator rule). A settings screen that calls `activityConsentWithdrawalProvider` is not part of this change.
