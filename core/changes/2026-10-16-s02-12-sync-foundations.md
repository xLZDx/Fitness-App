# S02-12 change record: sync foundations

Date: 2026-10-16. Story: S02-12 Sync-conflict UI (design 3.2, 6.2; test ids I26, I31-I33, I38, I39, I42-I45).

## What changed

- `ActivityJournal.updateRecord` (interface) and `FileActivityJournal.updateRecord`: replace the session map and the sync bookkeeping in ONE new generation while reusing the current `streams.bin` bytes. Works for `streamLost` entries, never needs the streams, is a no-op when nothing changed, honours `expectedGeneration`. `_commitStateOnly` gained an optional `sessionMap`.
- New `repository/activity_summary_backend.dart`: the cloud seam (`readSummary`, `tombstoneExists`, `listTombstoneIds`, `writeSummary`) with typed errors `SummaryWriteDenied`, `SummaryBackendUnavailable`, `SummaryBatchTooLarge` and `kMaxSummaryBatch = 8`.
- New `repository/summary_codec.dart`: JSON-safe `baseSummary` encoding (timestamps as ISO strings), decoding, `summariesEqual`, `summaryRev`.
- New `repository/sync_models.dart`: `SyncOutcome`, `ConflictChoice`, `SyncConflict`, `FieldConflict`, `SyncCandidate`, `ActivitySyncState`.

## Why

The journal had no way to change a record's overrides and sync state atomically without the streams; the sync layer needs one generation per resolution (design 3.2 atomic resolution).

## Verification state

No tests, builds or checks were run (operator rule v4). Test agents own I26, I31-I33, I38, I39, I42-I45.
