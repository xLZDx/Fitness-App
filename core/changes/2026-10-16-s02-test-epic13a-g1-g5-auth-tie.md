# S02 test epic 13a: G1 auth tie and G5 skip-reason logs

Date: 2026-10-16. Area: tests only.

## What changed

- New `mobile/test/features/activity/repository/activity_sync_auth_tie_test.dart` (17 tests), real
  `UidScopedActivityJournal` over temp directories with a recording backend and pusher.
- G1: journal bound to A while `authUid` returns B: syncEntry, syncAll, syncBatch, resolveConflict,
  resolveCandidate, applyExplicitEdit, saveSession return pending/empty with zero backend and pusher calls and zero
  journal puts; case sensitivity; retry timer after an unannounced flip (plus a positive control that the same timer
  runs under matching uids); flip between `listTombstoneIds` and the pusher; flip while the first of two writes is
  blocked; null auth, unbound journal, matching uids, null supplier, plain journal.
- G5: the skip log lines for journal-unbound, journal-auth-mismatch, auth-null, auth-changed, pass-identity; no uid
  and no entry id in any logged line; a successful pass logs no skipped line.

## Why

Oracles come from the F test notes heading G1 and G5, not from the code.

## Verification state

`flutter test --timeout 60s test/features/activity/repository/activity_sync_auth_tie_test.dart`: `00:03 +17: All tests passed!`
(first run after one import fix in the test).
