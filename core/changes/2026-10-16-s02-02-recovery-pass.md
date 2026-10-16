# S02-02 change record: recovery pass

Date: 2026-10-16. Story: S02-02 "Local journal" (design 10 recovery rule, crash cases A-D; test ids I03, I04, I22, I35, I36, I40, I41, I46-I49, I54, I55).

## What changed

- New `mobile/lib/features/activity/repository/journal_recovery.dart`: `JournalRecoveryPass`. Per activity it selects the highest generation with a valid COMMIT (marker parses, `seq` equals the directory, `record.json` SHA-256 matches, record `seq` and id match). Generations without a valid COMMIT are deleted at once, including the first generation of a new activity (the activity is then absent). Only a streams-checksum mismatch or a missing `streams.bin` of a committed generation yields `streamLost`, with no new generation and no rollback. `CURRENT` is rebuilt when missing, corrupt or pointing elsewhere. Older committed generations are deleted once the selected one fully verifies, otherwise kept until a bounded age and passed through `quarantine/` (record only, bounded count). Temp files are removed. The index tolerates torn or garbage lines and is rewritten from the records when it disagrees (tombstones and sync state come from `record.json`). The highest sequence number seen is returned so counters stay monotonic across restarts.

## Why

Design 10: `CURRENT` and `index.jsonl` are rebuildable caches, the highest committed generation is the truth, and an uncommitted generation is never activated.

## Affected contracts and paths

`mobile/lib/features/activity/repository/journal_recovery.dart`. Deviation: `streamLost` from a damaged `streams.bin` is a derived state at start (no new generation, per test plan I55); only key loss is persisted (done in the repository).

## Verification state

No tests, analyzers, builds or formatters were run (operator rule v4).
