# S02 remediation B1: read() drops a cache entry only on a verified mismatch

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/file_activity_journal.dart`: `read` re-verifies the record with `readCommit` and `readIfPresent`. A missing marker, a missing record, an undecodable record or a hash mismatch removes the entry from the cache (verified mismatch). An I/O error (`JournalUnreadable`) keeps the entry and throws `JournalIoException`. The second COMMIT read in `read` is replaced by the first result. The unused helper `_readCommitOrThrow` from the SF2 commit is removed.

## Why
Silent-failure review SF3: any `FileSystemException` dropped the entry, hiding an intact activity until restart, and a later `put` then saw no previous entry (no baseRev/baseSummary).

## Affected contracts and paths
`read` can now throw `JournalIoException` (a `JournalWriteFailure`) on a transient read error; callers must treat it as retryable, not as "absent".

## Verification state
No tests, build, lint or typecheck were run; see `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md`.
