# S02-04b change record: commitActivityStream callable

Date: 2026-10-16. Story: S02-04b (design 5.1, 5.1a, 5.2 items 2 and 3, 5.3, 5.4; test ids F09-F11, F46-F50, F54, F60-F62, F84-F86).

## What changed

- `functions/src/activity_streams/commit_stream.ts` (new): callable `commitActivityStream` on the `RARE` profile, reusing `upload_common.ts`, the S02-04a validator (`validateUploadedStream`), `paths.ts`, the bucket seam and the fence helpers.
  - Pipeline: auth -> `noteAppCheck` -> anonymous refused -> strict `{activityId, uploadId}` parse (unknown fields ignored) -> bucket configured -> daily quota `activityStreamCommit` -> commit.
  - Transaction 1 (`precheckCommit`): fence documents + Auth existence, tombstone (`deleted`), summary, consent; a row already `stored` by the same `uploadId` returns success without any write; `uploadId` must be the row's `pendingUploadId` (or a never-stored row's own `uploadId`), else bare `superseded`; a derived expiry already due clears the pending marker (or removes a never-stored row) in the same transaction, the quarantine object is deleted and bare `expired` is returned.
  - Single read: object metadata first (missing = `upload_missing`, size over 5 MiB = `too_large` without download), then the bytes pinned to the metadata generation (a 404 on the pinned read = `generation_changed`). The same in-memory bytes are hashed, decompressed, validated and re-serialised by `validateUploadedStream`.
  - Intent: a transaction writes `intendedStoredSha256` BEFORE promotion; then the canonical bytes are saved at `streams/<uid>/<activityId>/<uploadId>.json.gz`.
  - Transaction 2 (`selectPromotedObject`): re-checks fence, tombstone, summary, consent and `uploadId`, then writes `objectPath`, `state = stored`, `bytes`, `kinds`, `schema`, `contentSha256`, `storedSha256`, `activityDateUtc`, `expiresAt` hint (null = never), `settingsGeneration`, `receivedAt` in ONE write and clears the pending fields and the intent. A competing commit of the SAME `uploadId` that finds the row already stored returns success and keeps the object.
  - After transaction 2 only: the quarantine object and the previous `objectPath` are deleted (failures are logged by code and left to the reconciler).
  - Compensation: any bare refusal after the read deletes this commit's own quarantine object and, if already promoted, its own promoted object; a validation or generation failure also clears the pending marker (stored row keeps `stored` and its old object) or removes the never-stored row. An infrastructure failure between promotion and transaction 2 deliberately leaves the promoted object for the reconciler repair (intent hash).
  - Errors are bare codes (validator codes pass through as `invalid-argument`); logs carry slugs and counts only; the quota charge is refunded only for fence refusals.

## Why

Validated bytes must be exactly the promoted bytes, a stored row must never point at a missing object, and two overlapping commits must leave exactly one object and one stored row without ever touching each other's path.

## Deviations and notes

- A row in state `expired` that still carries `pendingUploadId` (purge ran during a re-upload) is handled like a stored row: the pending marker is cleared, state stays `expired`.
- Consent, summary and tombstone are re-checked in all three transactions (stricter than the minimum in the design).
- Reconciler repair and the purge itself are other stories (S02-05b, S02-06a/b).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4). Test agents verify F09-F11, F46-F50, F54, F60-F62, F84-F86.
