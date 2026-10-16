# S02-01 change record: cloud summary, projection, three-way merge

Date: 2026-10-16. Story: S02-01 "Model v2" (design 3.1, 3.2).

## What changed

New pure Dart files in `mobile/lib/features/activity/data/`:

- `summary_projection.dart`: `derive` (raw), `recompute` (raw plus explicit values), `effective` (plus cloud overrides); `reconcile` (mandatory version reconciliation first, explicit-value source candidates, value-based override lifecycle); `applyExplicitEdit` (names its fields, drops those overrides, replaces explicit entries, appends the ring, saturating `userEditCount` capped at 64); `adoptServerValue` / `keepCloudValue`; `offeredChoices` and the atomic `resolveCandidate`.
- `summary_three_way_merge.dart`: `mergeSummaries` (per-field three-way merge, whole-document conflict, immutable `startUtc`/`sport` violation as a typed error, null base conflicts, `rev = max + 1`).
- `activity_cloud_summary.dart`: `ActivityCloudSummary.fromSession` (allowlisted scalars only, bounds respected, `hasRoute` flag, no HR, `rev` from value changes only, throws for a read-only session).

## Why

Design 3.2: the summary is the effective projection of the record; overrides and explicit values keep devices convergent; the cloud counter can never exceed the rules range.

## Affected contracts and paths

Only `mobile/lib/features/activity/data/`. The key allowlist is `summary_fields.dart` (previous commit) and must match `firestore.rules` (story S02-03).

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
