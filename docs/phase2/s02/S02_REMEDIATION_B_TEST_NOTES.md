# S02 remediation B: test notes

## B1

- SF1: fake file system whose `readBytes` of the COMMIT of the highest generation throws a non-notfound `FileSystemException` (file still exists): after `start()` every generation directory of that activity still exists, the id is not in `report.absent`, `report.diagnostics` contains `unreadable:<id>`, and the next `start()` with the fault removed recovers the highest generation.
- SF1: same for an I/O error reading `record.json` of a committed generation (generation kept, `unreadable:<id>`).
- SF1: a genuinely missing COMMIT (file absent) or an invalid marker still deletes that uncommitted generation and keeps the older committed one.
- SF2: key store `loadKey` throws once; `read(id)` returns streamsLoaded false; then `updateSyncState(id, synced)`; with the key restored the next `read(id)` has streamLost false and streamsLoaded true (the metadata edit did not persist streamLost). Real key loss (`loadKey` returns null) still persists streamLost in a new generation.
- SF2: `streams.bin` read throws a non-notfound I/O error (file exists): `read` returns streamsLoaded false, nothing persisted as streamLost, the next read after the fault is removed loads the streams; a missing `streams.bin` or checksum mismatch is still stream-lost and persisted by the next metadata edit.
- SF2: recovery with an I/O error on `streams.bin` of the selected generation: entry recovered with streamLost false, `report.streamLost` does not contain the id, `report.diagnostics` contains `streamsUnreadable:<id>`, older committed generations are kept; `streamLostCount` stays 0.

## B2

- Wipe decorator: `ActivityAwareLocalDataWipe(inner: DeviceLocalDataWipe(...), journal, ownerStore)` with a seeded journal (sessions, sources, quarantine, key): after `wipe(uid)` `noDataLeft` is true and the key storage is empty; the inner prefs/photo wipe also ran. Un-skip both group 3 tests in `s02_account_wipe_e2e_test.dart` by building `wipeImpl()` through `activityAwareLocalDataWipe(...)` (remove the NOT WIRED skip).
- Relaunch path: `finishInterruptedWipe` with the same decorator object and a pending uid empties the journal and removes the marker; a journal-wipe failure leaves the pending marker and `LocalWipeIncomplete.remaining` contains `activity_journal`.
- No journal (null): `activityAwareLocalDataWipe(inner, null)` returns `inner` itself; the decorator with an inner failure still wipes the journal and rethrows the inner `LocalWipeIncomplete` plus `activity_journal` only when the journal wipe failed.
- Owner skip: pending wipe of uid X while the owner marker names uid Y leaves Y's journal untouched; marker equals X or absent wipes it; the marker is cleared after a wipe.
- Cross-account: `claimActivityJournal` with marker A and uid B calls `journal.wipe()` before `store.write(B)` and returns true; marker A and uid A, or no marker, never wipes and returns true (no marker is recorded as the uid); a wipe that throws returns false and the marker stays A; a marker write that throws returns false.
- Wiring: `activityCloudSyncWiringProvider` with owner marker A and signed-in B starts no `syncAll` and no stream upload when the wipe fails, and starts both after a successful wipe; same-uid sign-in keeps entries.

- SF4 backend: `FirestoreActivitySummaryBackend.readSummary` with a fake Firestore whose fetch succeeds but whose parse throws (corrupt document) throws `SummaryCorrupt`, never `SummaryBackendUnavailable`; a fetch that throws (timeout, `FirebaseException`) still throws `SummaryBackendUnavailable(code)`.
- SF4 sync: a backend whose `readSummary` throws `SummaryCorrupt` makes `syncEntry` (non-denial read and after a denial) end `SyncOutcome.conflict` with the entry `syncConflict` and local data intact, not `failed`/offline and no retry loop; `resolveConflict` returns `SyncOutcome.conflict` and keeps `syncConflict`; the conflict view shows `cloudKnown == false` without throwing; `lastCorruptRead` is set.
- SF9: a tombstone pusher that throws an object with `code` `permission-denied` sets `lastTombstonePushError == 'permission-denied'`; a plain `StateError` sets `StateError`; the local tombstone stays and the next pass retries; `syncAll` still completes.
