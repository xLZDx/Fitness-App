# C12: body-scan Cloud Functions and storage deletion step

Date: 2026-10-15. Branch: feature/body-scan-nutrition-coach. Scope: sprint plan C12 (design s7.1-7.4, 7.6, 7.8, s8, D-52, D-53, D-54, D-58, D-59, D-60, D-62, D-67, D-69 seam on the client side only).

## What changed

New files under `functions/src/body_scan/` (flags.ts already exists from C02):

- `types.ts`: closed vocabularies (`POSES`, `CHECK_CODES` mirroring design s12.7, `CONFIDENCES`, `SEXES_AT_BIRTH`) and the `BodyCompositionEstimator` interface from design s8.
- `estimator.ts`: provider registry. `licensed-api` is RESERVED (answers `failed-precondition: provider-not-configured`); `test-fake` resolves only under the emulator or jest through the `__setTestEstimatorForTests` seam. `EstimatorTerminalError` marks a non-retryable vendor rejection.
- `validate_estimate.ts`: `validateEstimate(output, modelId, modelVersion)`; any violation is `internal: provider-output-invalid`, never a clamp. Rebuilds the stored block field by field (extra provider keys cannot reach Firestore) and de-duplicates check codes.
- `shared.ts`: the single guard preamble `authorizeBodyScanCall` (auth -> App Check note -> non-anonymous -> `enforceAiGatewayEnabled` -> `assertFeatureEnabled(bodyScanCloudEnabled())`, all BEFORE any quota), object path scheme, timing constants, `errorSlug`, `logBodyScan` (closed operation/outcome, no uid/path/URL/metric), `tombstoneScrub`.
- `access.ts`: server-side age (`lowestAgeAt` formula, refuse unknown or under 18 with `age-required`, client age ignored, D-58) and tier gate (port of the client `effectiveTier`; free account -> `permission-denied: tier-required`).
- `create.ts` (`createBodyScan`): strict validation, `accountDeletionRetries` refusal, idempotent create (`done` replay, `pending` re-issue, `failed` reset, `cancelled` -> `scan-cancelled`), consent gate, quota `bodyScanCreate` charged only when a document is created or reset (refunded if the transaction shows another call created it first), three V4 PUT URLs with `contentType` and `x-goog-content-length-range`.
- `estimate.ts` (`estimateBodyScan`): done replay with no provider call, no quota and no writes; 60 s lease transaction; read-time metadata and JPEG sniff checks; 25 s provider timeout; `validateEstimate`; final transaction that re-reads `pending`/`awaiting_upload` so a racing delete wins; retention 0 deletes objects inline and then sets `photosState = deleted` (`photosExpireAt = now` meanwhile so a failure is purged at once).
- `delete.ts` (`deleteBodyScan`): tombstone written BEFORE the objects are deleted; `photosOnly` keeps the document.
- `manage.ts` (`manageBodyScanData`): `applyRetention`, `deleteAllPhotos`, `deleteAllScans`, `exportLinks` (1 hour READ URLs, at most 60 links per call, cursor).
- `purge.ts` (`purgeExpiredBodyScanPhotos`, `30 3 * * *`, 300 s, stops starting work after 240 s): four passes, `startAfter` paging, `purgeAttempts` with a `purge-stuck` event at 10, page token persisted in `body_scan_purge_state/main`. `runBodyScanPurge` is exported for the tests.

Edited `functions/src/index.ts` (minimal): imports, `sweepAccountData` gains a last step `sweepBodyScanObjects(uid)` (shared `bodyScanBucketName()`; unset = logged no-op; 404 on every error = nothing to delete; anything else throws an error carrying only the first error code so `deleteAccount` reports a failed sweep and the reconciler retries); five exports at the end. `reconcileAccountDeletions` needs no edit: it already calls `sweepAccountData`.

## Deviations from the plan (recorded, safe behaviour chosen)

1. NO server provisional provider. The task text mentioned one; plan SD-12 and design D-52 say the provisional estimator is Dart-only on the device and the server registry is `licensed-api` (reserved) + `test-fake`. Following the plan keeps body metrics off the server.
2. `estimateCharged` (server-only boolean on the scan document) is an additive field not in design s5.1. It makes "charged once, at first processing" true across a `missing-upload` retry; it is removed on success, on a provider failure (together with the refund) and on tombstoning.
3. `deleteBodyScan` for an id the server never saw writes a minimal tombstone (so an offline-queued delete that outran its create still blocks a later create of that id). Tombstones are SCRUBBED (`subject`, `estimate`, `weightKg`, `capture`, `clientNote`, `takenAt` removed) so no body metric survives a delete; this also removes them from the `takenAt` history query.
4. `manageBodyScanData` pages scans by document id (no composite index) and filters in code; `exportLinks` pages by `takenAt` (single-field index) with 20 scans (up to 60 links) per call.
5. NOT in this commit: the `release_guard.ts` flag-gated bucket check and `__tests__/discover_callables.ts` update (plan SD-11 lists them under C12). The discover list is a test file owned by the test agents; the guard check needs its own reading of `release_guard.ts` and is left for a follow-up in the same PR. Also not done: `runbooks/body_scan_bucket.md`.
6. Calls outside a configured bucket: `purgeExpiredBodyScanPhotos` returns immediately when `BODY_SCAN_BUCKET` is unset.

## Contracts and paths affected

- Callables (region europe-west1, profile `BODY_SCAN`, identity `fn-bodyscan`): `createBodyScan`, `estimateBodyScan`, `deleteBodyScan`, `manageBodyScanData`; scheduled `purgeExpiredBodyScanPhotos`.
- Closed error slugs (HttpsError `message`): `sign-in-required`, `feature-disabled`, `invalid-request`, `invalid-scan-id`, `invalid-taken-at`, `invalid-subject`, `invalid-capture`, `invalid-photos-only`, `invalid-action`, `invalid-cursor`, `invalid-retention`, `provider-not-configured`, `account-deleting`, `age-required`, `tier-required`, `consent-required`, `scan-cancelled`, `scan-failed`, `scan-not-ready`, `scan-not-found`, `estimate-in-progress`, `missing-upload:<poses>`, `provider-output-invalid`, `provider-unavailable`, `upload-url-failed`, `scan-create-conflict`, `scan-create-failed`, `scan-estimate-failed`, `scan-delete-failed`, `scan-manage-failed`.
- Firestore: `users/{uid}/body_scans/{scanId}`, `accountDeletionRetries/{uid}` (read), `users/{uid}/profile/main` (read), `users/{uid}/subscription/main` (read), `users/{uid}/body_scan_settings/main` (read), `body_scan_purge_state/main` (rw), collection-group queries on `body_scans` (indexes from C01).
- Storage: private bucket from `BODY_SCAN_BUCKET`, objects `users/{uid}/scans/{scanId}/{front|side|back}.jpg`.
- Operator prerequisites (not code): `fn-bodyscan` and `fn-account-delete` need `objectAdmin` on the bucket; `fn-bodyscan` also needs `secretAccessor` on the `ai-gateway-kill-switch` secret because every body-scan callable runs `enforceAiGatewayEnabled` (without it the callables fail closed with `unavailable`).
- Known behaviour: because `sweepAccountData` also runs in `deleteAccount` step 2, a configured-but-IAM-denied bucket makes the user's own delete-account call fail (retriable) until IAM is fixed; this is the documented go-live blocker (SD-6).

## Verification state

Nothing was run (operator policy: no tests, type checks, builds or lint). Written to type-check by reading only; `noUnusedLocals` and strict mode were considered but are UNVERIFIED. Test ids for the test agents are listed in the hand-off message of this commit.
