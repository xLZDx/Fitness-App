# S02-12 change record: sync orchestration and resolution operations

Date: 2026-10-16. Story: S02-12 (design 3.2, 6.2; test ids I26, I31-I33, I38, I39, I42-I45, I50-I53, I56, I57, E04).

## What changed

- New `repository/activity_sync_repository.dart` (`ActivitySyncRepository`): optimistic upload at `baseRev + 1` without a read; on `SummaryWriteDenied` it reads `activity_tombstones/{id}` and calls `decideOnSummaryWriteDenied` (tombstone: `journal.delete`; otherwise read server, three-way merge against `baseSummary`, ONE retry, a second rejection leaves `sync_conflict`). A fresh device (no base) reads before writing (update with `max + 1`, create with rev 1 only when the document is absent). Adopted server-only numeric fields become overrides via `SummaryProjection.adoptServerValue`, persisted BEFORE the write; a field the device cannot recompute stays a resolvable conflict. `syncAll` sweeps server tombstones first, skips synced entries and retries `sync_conflict` entries once per process only when asked. `syncBatch` refuses more than 8 ids before touching anything. `saveSession` is the passive input-change path (carries explicit values, overrides and edit state over). `watch()` is the state stream of conflicts and candidates (summary fields only).
- New `repository/activity_sync_resolution.dart` (part of the above): `resolveConflict` (keep this device / keep cloud), `resolveCandidate` (the three or two atomic choices) and `applyExplicitEdit`. Each stores its local change in one generation before any network write; a repeated call returns `alreadyResolved`.

## Deviations

- Summary keys that are derived metadata of the device's own record (counts, versions, provenance, `hasRoute`, `utcOffsetMinutes`, `endUtc`, `schema`, terms snapshot) never conflict across devices: the local value is written. Only the 15 numeric overridable fields can conflict.
- `hasRoute` of an entry whose streams are not loaded (stream lost) is taken from the last stored base.

## Verification state

No tests, builds or checks were run (operator rule v4).
