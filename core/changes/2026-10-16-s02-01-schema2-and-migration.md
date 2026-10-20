# S02-01 change record: schema 2 session and migration chain

Date: 2026-10-16. Story: S02-01 "Model v2" (design 3.3).

## What changed

- `ActivitySession` (`mobile/lib/features/activity/data/activity_session.dart`): default `schema = 2`; new fields `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`, `sourceTermsSnapshot` (A-5), `explicitValues`, `summaryOverrides`, saturating `userEditCount` (cap 64), `editHistory` ring (newest 64), non-serialised `readDiagnostics`; `copyWith`; `isReadOnly` and `toWritableJson()` (null for a record with schema above 2). The tolerant reader keeps unknown keys in `extras`, keeps the original text of an unknown sport in `extras['unknownSport']`, and records a diagnostic when a stream is dropped.
- New `activity_migration.dart`: `ActivityMigration.migrate` (total, never throws; schema 1 -> 2 defaults the A-5 strings and the counter; schema above 2 returned untouched) and `read`.
- `activity_merger.dart`: the merged session carries the primary session's A-5 and record-state fields.

## Why

Design 3.3: schema 2 persisted form, tolerant migration chain, newer-schema records read-only.

## Affected contracts and paths

Only `mobile/lib/features/activity/data/`. Existing `userEdits` map keeps its type because the merger depends on it; the design's ring is the new `editHistory` field (deviation recorded in the story hand-off). No rules, functions or journal files touched.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4). Existing tests that assert `schema == 1` defaults will need updating by the test agents.
