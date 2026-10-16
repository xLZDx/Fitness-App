# S02 client cloud settings, consent cache and consent-withdrawal flow

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- New `mobile/lib/features/activity/repository/activity_cloud_settings_client.dart`:
  - `ActivityCloudSettingsClient`: calls `setActivityCloudSettings` (injectable call seam, Firebase default), caches the consent state (`unknown`/`granted`/`withdrawn`, in-memory or per-uid `SharedPreferences` store) and implements `CloudStreamsConsentView`, the only thing the uploader reads. Unknown is treated as not granted. Withdrawal flips the local cache before the network call, so uploads stop even if the call fails.
  - `ActivityConsentWithdrawal` (presenter, design 9.1, plan I28): `withdraw()` cancels queued uploads first, records the withdrawal and returns the offer "delete my cloud streams now"; `deleteCloudStreamsNow()` calls `setActivityCloudSettings` with `deleteExisting` once per instance. Not calling it leaves cloud streams in place. Nothing local or any summary is deleted by either path.

## Why
Plan rows I17 (no upload without consent) and I28 (client withdrawal) need this code.

## Affected contracts and paths
New file only; the consent version constant `kCloudStreamsConsentVersion = 1` mirrors `CLOUD_STREAMS_CONSENT_VERSION` in `functions/src/activity_streams/settings.ts`.

## Verification state
No tests, analysis or builds were run (operator rule). Not done here: the client does not continue the resumable bulk delete with `deleteAllActivityStreams` (the scheduled reconciler continues the job per design 9.1); no UI strings.
