# S02 remediation E1 (a): account-scoped activity journal class

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Responds to GPT-PM final code gate MAJOR-01 (sign-in of another account wipes the device-wide journal) and MAJOR-02 (the owner marker can be missing or corrupt, so another account adopts the journal).

## What changed
- `mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart` (new): `AccountScopedJournal` (`bindUid`, `wipeForUid`), `UidScopedActivityJournal` (implements `ActivityJournal`, holds no data, delegates to the journal bound to the signed-in uid), `activityJournalScopeId(uid)` (first 32 hex chars of sha256(uid)), `fileActivityJournalFactory()` (production root `<app support>/activity_journal/<scopeId>`, key suffixed with the scope id).
- `mobile/lib/features/activity/repository/journal_cipher.dart`: `SecureStorageJournalKeyProvider` gains an optional `scopeId`; the key name becomes `activity_journal.key.v1.<scopeId>`. Without a scope the behaviour is unchanged. New getter `keyNameInUse`.
- `mobile/lib/features/activity/repository/journal_errors.dart`: new `JournalUnbound extends JournalWriteFailure`.

## Why
Ownership is now the location, not a separate preference marker. Sign-out and account switch only close a journal, never delete it. While nothing is bound, reads are empty and every write throws `JournalUnbound`, so a write cannot land in the wrong account.

## Affected contracts and paths
New public symbols above. `bindUid` is serialized with `JournalMutex`, idempotent per uid, returns false (nothing bound) when opening or recovery throws. `wipe()` wipes only the bound journal; `wipeForUid(uid)` wipes that uid's scope bound or not. Nothing is wired yet in this commit.

## Verification state
No tests, analyze or build were run (test agents follow, per development rules v4).
