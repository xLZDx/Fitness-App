# S02 remediation E1 (b): wiring, binding listener, owner marker removed

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Responds to GPT-PM MAJOR-01 and MAJOR-02.

## What changed
- `mobile/lib/core/wiring/activity_wiring.dart`: `openActivityJournal` now returns an UNBOUND `UidScopedActivityJournal` (no I/O, cannot fail app start) when `journalEnabled`; new optional `factory` parameter for tests. New `activityJournalBindingProvider`: always on with `journalEnabled`, independent of `cloudSync`; binds the signed-in uid (anonymous included), unbinds on sign-out (no data deleted), ignores auth states without a value. The cloud sync wiring now does `await journal.bindUid(uid)` for the same uid and does not start sync or upload when it returns false; the remediation-C behaviour (cancelQueued, resume only after a successful bind, uid-bound uploader, try/catch) is kept. `activityAwareLocalDataWipe(inner, journal)` loses `ownerStore`.
- `mobile/lib/main.dart`: the app root watches `activityJournalBindingProvider`.
- Removed `mobile/lib/features/activity/repository/activity_journal_owner.dart`: `ActivityJournalOwnerStore`, `PrefsActivityJournalOwnerStore`, `InMemoryActivityJournalOwnerStore`, `claimActivityJournal`; removed `activityJournalOwnerStoreProvider`.

## Why
The device-wide journal was wiped when another account signed in and its ownership lived in a separate preference marker. Both are replaced by account-scoped journals (see the (a) record).

## Affected contracts and paths
Public symbols removed or changed are listed above. Wipe decorator and docs follow in (c); between (b) and (c) the decorator still references the removed marker, so only the (c) head is meant to compile.

## Verification state
No tests, analyze or build were run (test agents follow).
