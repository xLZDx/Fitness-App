# S02-03 change record: activity summary, stream, settings and tombstone blocks

Date: 2026-10-16. Story: S02-03 "Firestore rules" (design sections 3.2, 4, 6.1, 6.2; GPS-PRIV-058, 061, 070, 071, 072; test ids R01-R21, R23-R37, U06, R25).

## What changed

- `firestore.rules`: new section "Unified activity" before the top-level server-only blocks.
  - `activitySummaryOk(id, d)` with small helpers (`actNumOk`, `actIntOk`, `actStrOk`, `actCountsOk`, `actMeasuresOk`, `actLabelsOk`): id pattern `^act_[0-9a-f]{40}$`, a single `hasOnly` allowlist of 32 keys, `hasAll` of `schema, sport, startUtc, endUtc, rev`, type and range checks for every key (design 3.2 table, identical to `summary_fields.dart`), `endUtc >= startUtc`, `startUtc` clamp (2000-01-01 inclusive .. `request.time` + 1 day).
  - `users/{uid}/activities/{activityId}`: owner read; create requires `rev == 1`; update requires `startUtc` and `sport` unchanged and `rev` strictly greater than the stored value; create and update both require no tombstone and no `activity_account_state/{uid}` fence (two `exists()` lookups, so the repository batches at most 8 summaries); delete is `false`.
  - `activity_streams`, `activity_settings`, `activity_tombstones`: owner read, `write: false`.
  - No block for the top-level `activity_account_state` (default deny; the file has no top-level catch-all).

## Why

Design section 4: rules are the single shape gate for the offline-first summary write, the tombstone and fence give delete-wins and account-deletion protection, and the server-authored paths must not be client-forgeable.

## Affected contracts and paths

`firestore.rules`. Allowlist, bounds and the A-5 string patterns match `mobile/lib/features/activity/data/summary_fields.dart`. Deviations and notes: the `summary_fields.dart` string patterns for `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion` (`^[A-Za-z0-9._:-]{1,32}$`) and `sourceTermsSnapshot` (`^[A-Za-z0-9._:+/=-]{1,64}$`) are stricter than the design's "string <= 32 / <= 64"; the rules use the same patterns (they imply the length bounds, and the design says strings carry a regex and a length bound) so rules never accept more than the serializer emits. `primarySourceId` has only the design's length bound (<= 64) in both places. Not in this commit: `firestore.indexes.json` (later story), `debug_sessions` `create: false` (S02-09).

## Verification state

No tests, emulator runs or checks were run (operator rule v4). Test agents verify with R01-R21, R23-R37, U06, R25.
