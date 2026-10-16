# S02-07 change record: getActivityStreamDownloadUrls callable and quota

Date: 2026-10-16. Story: S02-07 (design 5.4, 7, 7.1; test ids F32, F33, F69, F41, F60-F62).

## What changed

- New `functions/src/activity_streams/download_urls.ts`, callable `getActivityStreamDownloadUrls`, exported from `functions/src/index.ts`. Pipeline: auth, App Check note, anonymous refused, strict validation (`activityIds` array of `act_` ids, de-duplicated, at most 20 distinct, raw array bounded at 100), feature check (bucket unset answers `feature-disabled`), own daily quota, one read-only fenced transaction (`checkAccountFence` documents plus Auth existence, then per id the tombstone and the stream index row), V4 GET URLs signed after the transaction with a 15 minute TTL (`DOWNLOAD_URL_TTL_MS`).
- Per-id result (design 7.1): `stored` -> `{status: "ok", url, expiresAtMs}`; `expired` -> code `expired`; `pending` -> `not_ready`; `deleted`, tombstoned, missing or another user's id -> identical `not_found` (ids resolve only under `users/{auth.uid}`, so there is no existence oracle). A URL is never produced for a non-`stored` row. The row's `objectPath` must lie directly under `streams/{uid}/{activityId}/`, otherwise the row answers `not_found`.
- Fence refusals (`account_deleting`, `account_deleted`) refund the quota charge; quota refusal `quota_exceeded`; any other failure (including a transient Auth lookup error and a signing failure) is the bare code `download_failed` and nothing partial is returned.
- Logs carry closed outcome slugs and counts only; no uid, id, path or URL is logged or echoed.
- `functions/src/abuse_guard.ts`: `QUOTAS.activityDownloadUrls = 60` and `"activityDownloadUrls"` in `REDACTED_QUOTA_ACTIONS`. The pinned set test (`abuse_guard.test.ts`) is not edited here; test agents update it.
- `functions/src/activity_streams/bucket.ts`: `StreamFile.getSignedUrl` accepts `action: "read" | "write"` and an optional `contentType` (backwards compatible with the upload callable).

## Not done here

No flag gating beyond the bucket setting (same as the other stream callables); the derived-expiry hint is not consulted (purge owns expiry, a stale hint must not hide a stored stream).

## Verification state

No tests, builds or checks were run (operator rule v4).
