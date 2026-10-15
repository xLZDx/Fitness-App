# C25 part 1: server export paging for body-scan and nutrition collections

## What changed
- `functions/src/account_export.ts`: `exportAccountData` now also exports `body_scans`,
  `weight_entries`, `food_entries`, `saved_foods`, `nutrition_plan_reviews` (paged, explicit
  newest-first order) and `body_scan_settings/main`, `nutrition_plan/main` (single documents).
- Ordering: `takenAt desc` (scans), `loggedAt desc` (food), document id desc for the date/week keyed
  collections and for `saved_foods` (its `createdAt` is optional, so an `orderBy` on it would drop rows).
- Paging: 500 rows per section per call. The response adds `paging: {section: {returned, hasMore,
  nextCursor}}`. The caller repeats the call with `cursors: {section: nextCursor}` (cursor = last
  document id). Continuation calls read only the named sections and are charged to a separate
  counter `accountExportPage` (400/day) instead of the 3/day `accountExport` quota.
- Design deviation, deliberate: the design text names the paging map `truncated`; the existing
  `truncated` key is a string array consumed by the old sections and their tests, so the new
  paging state lives under `paging` and `truncated` is unchanged.
- Byte guard: paged sections are trimmed to what the 8 MiB budget leaves (min one row each) and keep a
  valid cursor, so trimming never drops rows silently.
- No signed URLs: scan rows drop any key matching url/link/objectPath/storagePath and carry
  `photoLinksAvailable: true` when `photosState == stored`. A note states links come from
  `manageBodyScanData.exportLinks` and that device originals/meal thumbnails are not in the file.
- Stale cursor -> `failed-precondition`; malformed cursor -> `invalid-argument`; HttpsErrors are no longer
  remapped to `internal`.
- Tests: `functions/src/__tests__/account_export.test.ts` mock gains `orderBy/startAfter`;
  new `functions/src/__tests__/account_export_paging.test.ts`.

## Why
D-61, review finding D5 (unordered export keeps a random/oldest subset), F14.

## Contracts / paths affected
`exportAccountData` response (additive), client export loop (next commit), data inventory rows.

## Verification state
Not run (sprint rule: tests run by the test agents after coding). Static read only.
