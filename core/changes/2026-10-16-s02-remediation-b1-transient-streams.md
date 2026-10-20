# S02 remediation B1: transient stream failures are never persisted as streamLost

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/file_activity_journal.dart`: second set `_unavailableIds` (transient) next to `_lostIds` (persisted-lost). A key store exception or an I/O error reading `streams.bin` adds the id to `_unavailableIds` only; `read` returns a summary entry with `streamsLoaded` false and retries on the next read. Only `_lostIds` (checksum mismatch, decryption failure, absent key, missing `streams.bin`, stored flag) feeds `_commitStateOnly` and the early return. A fully verified read removes the id from both sets. `start()` fills `_unavailableIds` from the recovery result; `wipe()` clears it. New helper `_readCommitOrThrow` maps `JournalUnreadable` to `JournalIoException`.

## Why
Silent-failure review SF2: a one-off key store or read failure was recorded in `_lostIds`, then persisted as `streamLost: true` by the next metadata edit, permanently hiding intact streams.

## Affected contracts and paths
`streamLostCount` and sign-out assessment count only persisted-lost ids. No on-disk format change.

## Verification state
No tests, build, lint or typecheck were run; see `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md`.
