# S02 remediation B1: recovery never deletes a committed generation on an I/O error

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/lib/features/activity/repository/journal_generation_writer.dart`: new `readIfPresent` (null only when the file does not exist; otherwise `JournalUnreadable`) and `JournalUnreadable`; `readCommit` now returns null only for a missing or invalid marker and throws `JournalUnreadable` on an I/O error.
- `mobile/lib/features/activity/repository/journal_recovery.dart`: `_validate` uses `readIfPresent`; an I/O error while validating any generation keeps every generation of that activity, adds `unreadable:<id>` to the report diagnostics and leaves retry to the next start. Uncommitted generations are still deleted. An I/O error on `streams.bin` is recorded in `RecoveryResult.streamsUnavailable` (diagnostic `streamsUnreadable:<id>`), is not reported as stream-lost, and older generations are kept.

## Why
Silent-failure review SF1: any exception in `readCommit` or `_validate` was read as "uncommitted", so a transient read error deleted the newest committed generation. Design section 7 deletes uncommitted generations only.

## Affected contracts and paths
`JournalRecoveryReport.diagnostics` gains `unreadable:<id>` and `streamsUnreadable:<id>`. `readCommit` can now throw `JournalUnreadable`; its caller in `file_activity_journal.dart` is adapted in the SF3 commit.

## Verification state
No tests, build, lint or typecheck were run; see `docs/phase2/s02/S02_REMEDIATION_B_TEST_NOTES.md`.
