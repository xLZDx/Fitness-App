# S02 test epic 2: findings (plan versus design versus code)

Scope: ids I01-I10, I18-I25, I29, I35, I36, I40, I41, I45-I49, I54, I55 (story S02-02, local journal).

## Contradictions and how they were resolved (design followed)

1. Plan I48 says generation 1 is removed "only after the next verified read (not at recovery)". The design (section 10, step 7) allows "the next start or the next read", and the recovery pass deletes older committed generations as soon as the selected one verified. The tests assert the generation set after a read, and that the uncommitted generation is gone after recovery.
2. Plan I36 says an older COMMITTED orphan is kept before the bounded age in general. The code (and design 10 "removed after the bounded age") keeps an older committed generation before the age only when the selected generation is stream-lost; otherwise it is removed at recovery because the selected one was verified. I36 asserts the age rule in the stream-lost case and the delete-failure orphan rule separately.
3. Plan I20 lists "old-generation delete" as a step of the put. Design 10 deletes the old generation after the next verified read, so the fault points are the 32 operations of the put plus the operations of the following read (the delete is there).
4. Plan I05 describes a stream commit callable with `already_stored`. That callable belongs to S02-04 and does not exist in this build. I05 is proved with the summary write of `ActivitySyncRepository` and a fake backend that enforces the `rev` rule: failing write never produces `synced`; a lost answer or a kill between upload and marker followed by a second sync converges with exactly one applied server write. The stream-callable half stays for the sync epic.
5. Plan I29 describes a repository that routes a save by sport class. No such repository exists in S02 (only the pinned table `modelForSport`, which no write path consults). I29 therefore proves: no S02 source mentions the old collections, a save of every activity sport writes one journal entry and one server row, a sync pass over seeded old records writes nothing. Not enforced anywhere: a `strength` session handed to `saveSession` is accepted into `activities`. This is an open design question (a watch-recorded strength session is device data), not changed.
6. Plan I10 "journal survives a start with no valid session": `ActivityWipeCoordinator.onAuthFailureAtLaunch`, `onAccountDeleted` and `onSignOut` have no caller in the app (`grep` over `lib/`). The coordinator is tested; the wiring of the launch and sign-out flows is not in S02 code. Recorded as a gap, not changed.
7. Plan I21 "one call from the compute isolate seam": no isolate seam exists in the journal; callers submit through the mutex only. Covered by the async-caller cases.

## Production defects found and fixed (smallest change)

| File | Defect | Found by |
|---|---|---|
| `journal_errors.dart` | `JournalInvalidIdException` was `const` with a non-constant initializer: the whole journal did not compile | first run |
| `file_activity_journal.dart` `_commitStateOnly` | metadata edits (sync state, overrides) of an entry whose `streams.bin` is missing threw `JournalIoException`; the stream-lost flag was not carried into the rewritten generation | I55 |
| `file_activity_journal.dart` `read` | a COMMITTED generation whose `record.streamHash` differs from the marker stream checksum was read as a valid stream (recovery flagged it, `read` did not) | I35 |
| `activity_sync_repository.dart` `_readAndMerge` | after a lost acknowledgement with no stored base, the replay wrote the same content again with the next `rev` (a second server write) instead of marking `synced` | I05 |

## Test-side notes

- `test/android/backup_rules_test.dart`: expected set is now the four earlier entries plus `androidBackupExclusions()` (seven per section); the `pubspec.lock` regex failed on CRLF line endings of the working copy (pre-existing) and now normalises them.
- A transient read failure inside `read()` removes the entry from the in-process cache until the next start (`_meta.remove`); a later `put` would then not see a tombstone. Observed, not changed (secondary mechanism).
- Not verified: power-loss durability, real device backup, rename atomicity on a device (plan section: NOT_RUN by design).
