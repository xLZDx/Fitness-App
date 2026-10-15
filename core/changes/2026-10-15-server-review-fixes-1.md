# Change record: server review fixes, part 1 (body scan purge, erase gating, estimate hardening)

## What changed
- `functions/src/body_scan/purge.ts`: every pass accepts only documents whose path matches `users/{uid}/body_scans/{scanId}` (P-1); new pass `purgeFailedScans` deletes objects of `failed` scans past `pendingExpiresAt` (DB-F1/P-3); the unmatched-object sweep no longer persists the NEXT page token after a mid-page deadline break (DB-F3); a `purge-abandoned` error log with a count is emitted when documents are skipped at 10 attempts (DB-F4).
- `functions/src/body_scan/flags.ts`, `shared.ts`: new `BODY_SCAN_ACCEPT_UPLOADS` switch (default on when the bucket is set) gates `createBodyScan`/`estimateBodyScan` only; `deleteBodyScan` and `manageBodyScanData` skip the AI kill switch and depend on the bucket name alone (P-2/DB-F2). `SCAN_DOC_PATH` shared constant; `tombstoneScrub` also removes `estimateAttempts` and `uploadReissues`.
- `functions/src/body_scan/estimate.ts`: consent re-checked before the provider call (P-4); per-scan `estimateAttempts` counter, max 3, never reset by a refund (P-8); a failed release of the charge marker no longer refunds the quota (SF-F7).
- `functions/src/body_scan/create.ts`: reissue extends `pendingExpiresAt` (DB-F8) and is capped at 5 per scan with `resource-exhausted: upload-url-limit` (P-5).
- `functions/src/body_scan/manage.ts`: `deleteAllPhotos` deletes objects before marking `deleted` (DB-F7); `exportLinks` cursor is `<takenAt ms>:<scanId>` (DB-F6).
- Tests: `manage.test.ts` updated and extended; `fakes.ts` supports a composite `startAfter`.

## Why
Review findings DB-F1/F2/F3/F4/F6/F7/F8, P-1/P-2/P-3/P-4/P-5/P-8, SF-F7. Erasure must keep working when intake is rolled back.

## Affected contracts and paths
`exportLinks` cursor format changed (old bare-ms cursors are rejected as `invalid-cursor`). Erase callables no longer read the AI kill switch. New server-only doc fields `estimateAttempts`, `uploadReissues`. New env var `BODY_SCAN_ACCEPT_UPLOADS`. Tests for guard/estimate/create/purge are updated in the follow-up commit.

## Verification state
Not run (no tests, lint, tsc, build or CI executed).
