# S02-01 change record: model v2 building blocks

Date: 2026-10-16. Branch: phase2/s02-unified-activity. Story: S02-01 "Model v2" (design sections 3.2, 3.3).

## What changed

- New `mobile/lib/features/activity/data/activity_versions.dart`: schema constant (`kActivitySchema = 2`), A-5 calculation-version constants, `CalcVersions` triple, caps (`userEditCount` 64, edit ring 64).
- New `summary_fields.dart`: single allowlist of cloud-summary keys, numeric and integer bounds, required keys, bookkeeping and immutable key sets, string patterns.
- New `summary_overrides.dart`: `ExplicitValue`, `SummaryOverride` (with `atComputed`, `atVersions`, `atRev`, optional recalc candidate), `EditHistoryEntry` ring helpers and tolerant readers that drop bad entries without throwing.
- `ActivitySummary`, `Lap`, `SourceRecord` now keep unknown JSON keys in an `extras` map (tolerant reader, design 3.3).

## Why

Foundation for the schema = 2 session, migration chain, cloud summary projection and stream payload that follow in later commits of this story.

## Affected contracts and paths

Only `mobile/lib/features/activity/data/`. JSON of the three changed classes gains the preserved unknown keys; known keys are unchanged. No Firestore rules, functions or journal files are touched.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4). Not verified by execution.
