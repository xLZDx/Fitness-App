# S02-02 change record: journal value types

Date: 2026-10-16. Story: S02-02 "Local journal" (design 3.4, 10).

## What changed

- New `mobile/lib/features/activity/repository/journal_models.dart`: `JournalRecord` (the `record.json` envelope: `seq`, `streamHash`, raw session map without streams, `JournalState`), `JournalState` (tombstone, sync state, `baseRev`, `baseSummary`, `streamLost`, plaintext stream hash), `CommitMarker` (`seq` plus separate `record` and `streams` SHA-256), `JournalEntry`, `JournalRecoveryReport`, `SignOutAssessment` and `JournalMutex`.

## Why

Tombstones and `synced` markers must live in `record.json` so an index rebuild loses neither (design 10). The session map is kept raw so a newer-schema record keeps its unknown keys on state-only mutations.

## Affected contracts and paths

`mobile/lib/features/activity/repository/journal_models.dart`. Deviation: `record.json` is an envelope (`session` plus `state`) rather than the bare `toJson` map with extra keys, because extra top-level keys would be read back into `extras`.

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
