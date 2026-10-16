# S02 test epic 12a (1): pass identity, caches, unbound, tombstone retry

Date: 2026-10-16. Branch phase2/s02-unified-activity. Area: F1
(`activity_sync_repository.dart`, `activity_sync_resolution.dart`).

## What changed

- New `mobile/test/features/activity/repository/activity_sync_pass_identity_test.dart`
  (33 tests): a real `UidScopedActivityJournal` over temp directories with a spy subclass
  (write log with the bound uid, gates on `read`, `list`, the n-th `listTombstones`) and a
  recording backend whose calls can block on a completer. Groups: tombstone phase and entry
  phase switches, `authUid` mismatch, pusher blocked during a switch, conflict operations during
  a switch, caches, unbound journal visibility (including the presenter), tombstone retry
  (counter reset, fallback timer, phase exceptions, epoch re-check, error code,
  `requestTombstoneSync`).
- `activity_tombstone_continuation_test.dart`: the E2 assertion "no seventh attempt" encoded the
  pre-F1 contract; it now expects six scheduled attempts plus exactly one 60-minute fallback timer
  and never two active timers (design 17 item 23).

## Why

Remediation F1 was written without a compiler or a test run. These tests state the user promise
"a sync of account A that is still running never touches account B's data" at the repository seam.

## Affected contracts / paths

Tests only; no production file changed in this commit.

## Verification state

First compile of the F1 area: the production code compiled unchanged. See
`docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md` (Epic 12a) for commands and summary lines.
