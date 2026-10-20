# S02-04b change record: createActivityStreamUpload callable

Date: 2026-10-16. Story: S02-04b (design 5.2 item 1, 5.3, 5.4; test ids F07, F08, F44, F45, F60-F62, F86, F87).

## What changed

- `functions/src/activity_streams/upload_common.ts` (new): shared pieces of both upload callables: bare refusal codes and their HttpsError mapping, the injectable `UploadDeps` seam (Firestore, Auth existence, clock, bucket, upload id generator, validator options), the common in-transaction read `readUploadContext` (fence documents + Auth existence, tombstone `deleted`, summary `no_summary`, consent `consent_withdrawn` / `consent_required`, settings, existing row) and the derived-expiry arithmetic (`startUtc` clamped to [2000-01-01, now] plus current retention; null = never).
- `functions/src/activity_streams/create_upload.ts` (new): callable `createActivityStreamUpload` on the `RARE` profile.
  - Pipeline: auth -> `noteAppCheck` -> anonymous refused -> strict input parse (`activityId`, `bytes` 1..5 MiB integer, `contentSha256` 64 hex; unknown client fields ignored) -> bucket configured (else the shared feature-disabled answer) -> daily quota `activityStreamUpload` -> ONE transaction -> supersede cleanup -> V4 signed PUT.
  - Transaction: derived expiry already due gives bare `already_expired` (no row, no URL, no attempt counted); a `stored` row with the same `contentSha256` gives `already_stored` with no URL; attempts are capped at 5 per activity per UTC day through `attemptsDay` (`too_many_attempts`); a `stored` row keeps `state = stored` and gains `pendingUploadId`, `pendingContentSha256`, `pendingSince`; any other row is written `pending`.
  - The URL is signed after the transaction commits (no double signing on retry): V4, method PUT, content type `application/gzip`, TTL 10 minutes, header `x-goog-content-length-range` = `<bytes>,<bytes>`, path `quarantine/<uid>/<activityId>/<uploadId>`.
  - A superseded pending upload's quarantine object is deleted after the transaction (best effort; the reconciler and the lifecycle rule are the backstop).
- `functions/src/activity_streams/bucket.ts`: `StreamFile` gains `getSignedUrl` (structural, no `@google-cloud/storage` types).
- `functions/src/abuse_guard.ts`: `QUOTAS.activityStreamUpload = 30`, `QUOTAS.activityStreamCommit = 60`; both names added to `REDACTED_QUOTA_ACTIONS`.

## Why

The upload intent must be decided inside one fenced transaction so an account deletion, a tombstone or a consent withdrawal can never be followed by a fresh signed URL; keeping `state = stored` during a re-upload keeps the old object visible to the expiry purge.

## Deviations and notes

- `pendingContentSha256` is an added row field: the commit callable receives only `(activityId, uploadId)`, so the hash of a re-upload over a stored row (which differs from the stored row's `contentSha256`) must be kept on the row.
- The length-range header uses the declared byte count as both bounds (stricter than the 1..5 MiB window); the commit still hashes and bounds the real bytes.
- Quota is refunded only when the fence refused the call.
- Consent never granted gives `consent_required`; withdrawn gives `consent_withdrawn`.
- The pinned `REDACTED_QUOTA_ACTIONS` test is updated by test agents (F83).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify F07, F08, F44, F45, F60-F62, F86, F87.
