# S02 remediation F2 (2/4): key deletion failure fails the wipe

## What changed

`mobile/lib/features/activity/repository/journal_cipher.dart`: `SecureStorageJournalKeyProvider.forget()` no longer swallows a secure-storage delete failure. The only caller is `FileActivityJournal.wipe()`, so `wipeForUid` now throws, `ActivityAwareLocalDataWipe` reports `activity_journal` in `LocalWipeIncomplete`, and the pending account-deletion marker stays for the next launch. The key name (default and scoped) is unchanged. Closing and disposing a journal never call `forget()`, so those paths stay best effort.

## Why

A keystore failure was hidden: the wipe reported success while the account's key remained and the marker was dropped (reliability and silent-failure reviewers).

## Contracts

`JournalKeyProvider.forget()` now documents that it throws on a platform failure. Retry is idempotent: directory deletion and recreation, and deleting an absent key, succeed on a second run.

## Verification state

Not compiled and not run. Tests listed in `docs/phase2/s02/S02_REMEDIATION_F_TEST_NOTES.md`.
