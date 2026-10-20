# S02 remediation B2: corrupt cloud summary result and tombstone push error code

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `activity_summary_backend.dart`: new `SummaryCorrupt` exception next to `SummaryBackendUnavailable`.
- `firestore_activity_summary_backend.dart` (SF4): `_read` wraps only the network call in the unavailable catch; the parse runs afterwards and a parse failure throws `SummaryCorrupt`.
- `activity_sync_repository.dart`: a corrupt cloud summary during `_readAndMerge` marks `sync_conflict` (visible, local data kept, no offline retry) and the conflict view returns `cloudKnown: false`; `syncAll` treats a corrupt tombstone listing as unknown. SF9: the last tombstone push error code is kept (`lastTombstonePushError`) and printed through `debugPrint`, the diagnostics path this layer already uses; `lastCorruptRead` records the time of a corrupt read.
- `activity_sync_resolution.dart`: `resolveConflict` returns `conflict` and the candidate resolution treats the server as unknown when the cloud summary is corrupt.
- `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md` heading B2 extended.

## Why
Silent-failure review items SF4 (a corrupt document was reported as backend unavailable) and SF9 (tombstone push errors looked like being offline).

## Affected contracts and paths
`ActivitySummaryBackend.readSummary` may now throw `SummaryCorrupt`; the two test backends (`fake_summary_backend.dart`, `two_device_world.dart`) implement the interface unchanged.

## Verification state
No tests, analyzer or builds were run (batch rule); the new generic `_read<R, T>` signature is unchecked by a compiler.
