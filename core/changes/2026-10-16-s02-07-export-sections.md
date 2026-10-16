# S02-07 change record: account export sections for unified activity

Date: 2026-10-16. Story: S02-07 (design 7, 7.1; test ids F29, F30, F31, F70).

## What changed

- `functions/src/account_export.ts`:
  - `activities` (ordered newest first by `startUtc`) and `activityStreams` (stream index rows, document id descending) join `PAGED_COLLECTIONS`, so they reuse the existing `pagedRead` / `fitPaged` / `parseCursors` continuation path instead of a second mechanism.
  - The FIRST response reads up to `MAX_ROWS` (2000) of each (`CAPPED_FIRST_PAGE`, new optional `pageRows` argument of `pagedRead`); reaching the cap adds the section name to `truncated` and `paging.<section>` carries `hasMore` and `nextCursor`. Continuation pages use `PAGE_ROWS` (500). A byte-budget trim by `fitPaged` of either section is also named in `truncated`.
  - Stream index rows pass through an allow-list (`id`, `state`, `bytes`, `kinds`, `expiresAt`): object path, hashes and upload bookkeeping never leave. Samples are never in a row, so no GPS can appear in the export body.
  - `users/{uid}/activity_settings/main` is exported as `activitySettings` through the existing `one()` helper.
  - `STREAM_EXPORT_NOTE` (GPS-PRIV-053) is always in `notes`: streams are delivered by short-lived download links, and heart-rate streams are on the device only. Tombstones are not exported.

## Contracts and paths affected

- Response keys added: `activities`, `activityStreams`, `activitySettings`; `paging` gains the two section keys. `exportFormatVersion` stays 1 (additive keys only).
- Quotas unchanged (`accountExport`, `accountExportPage`).

## Verification state

No tests, builds or checks were run (operator rule v4). Existing export tests that count Firestore reads per collection may need the two new reads added by the test agents.
