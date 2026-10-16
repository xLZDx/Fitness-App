# S02 test findings, epic 11

## 11b: remediation E2 (MAJOR-03, bulk tombstone propagation and erasure quota)

Oracles: `S02_REMEDIATION_E_TEST_NOTES.md` heading E2, design section 17 item 21 and sections 5.4 and 6.2, the MAJOR-03 text. Head of the runs: HEAD after commit `670b6a2a` plus the fake fix of the final commit of this epic part.

### Files
- `mobile/test/features/activity/repository/activity_tombstone_continuation_test.dart` (new, 34 tests, commit 96b9f6e7): backlogs 9/30/100/1000 (2/4/13/125 rounds, pending 0, no timer), boundaries 8 and 1024, 1100 (1024 first call, 76 pending, one 60 s timer, the timer pass pushes 76), restart resume, quota and other systemic refusals, partial failures and bad-id-last ordering, unknown tombstone list, backoff 60 s to 15 min with no seventh attempt and one timer at a time, dispose and cancel, `watch()` state fields and equality, existing semantics (server tombstone, fence, denial without tombstone), account change (3 tests).
- `mobile/lib/features/activity/repository/activity_sync_repository.dart` (production fix, 96b9f6e7) and one line in `mobile/lib/core/wiring/activity_wiring.dart` (landed in agent 11a's commit).
- `functions/src/__tests__/abuse_guard.test.ts`, `.../activity/support/seven.ts`, `.../activity/settings_consent.test.ts`, `.../activity/callable_hardening.test.ts` (pinned 100 changed to 1000, plus one new test: 1000th call accepted, 1001st refused, per user, fence refusal refunds), `docs/phase2/s02/S02_TEST_PLAN.md` F82 row (commit 670b6a2a).
- `mobile/test/features/activity/state/sync_conflict_view_errors_test.dart` (fake fix, final commit).

### Defects
1. Account-scoped state outlived the account (shortcoming of the E2 design against E1). The E2 agent noted that nothing called `cancelTombstoneRetry()` on sign-out or uid change. Evidence: the repository is one instance for the whole process (`activityRootOverrides`), the retry timer, `_confirmedTombstones`, `_failedTombstones`, the backoff budget and `lastTombstonePushError` are fields of it, and nothing reset them. Consequences: a timer scheduled for account A fires an unattended pass under account B (or against an unbound journal, where it lists nothing and fails the tombstone list as unknown); and an id A confirmed (activity ids are deterministic) is treated as confirmed for B, so B's local tombstone for the same id is never pushed and `pendingTombstones` shows 0. Fix: `ActivitySyncRepository.onAccountChanged()` with an epoch counter (cancels the timer, clears the sets, budget and error, a pass in flight stops before its next push and schedules nothing), called from `activityCloudSyncWiringProvider` when the previous uid goes away or changes. Tests: three in the account-change group (state drop, in-flight pass, wiring sign-out and switch). Layer that missed it: E2 author and design review (E2 was designed per process while E1 made the journal per account); the E2 test notes did not list it; found by the epic test.
2. Stale test fake: `_FlakyJournal` in `sync_conflict_view_errors_test.dart` (epic 10a) did not implement `listTombstones()`, which `refreshState()` calls since E2 (pending count). 4 tests failed with `UnimplementedError: Symbol("listTombstones")` and two follow-on timeouts. Fix: the fake forwards `listTombstones()`. Layer that missed it: the E2 implementation commit changed the state refresh without running the existing state tests (by process, tests run after sprint coding); caught by the complete run of this epic.
3. No defect in the E2 continuation logic itself: it compiled and all notes-derived expectations held first time.

### Runs
Dart, from `D:\Repo\Fitness_App_Phase2_s01\mobile`:
`flutter test test/features/activity/repository/activity_tombstone_continuation_test.dart test/features/activity/repository/activity_sync*_test.dart test/features/activity/repository/activity_tombstone*_test.dart test/features/activity/state test/features/activity/widgets`
First run: `+87 -4: Some tests failed.` (the 4 stale-fake failures). After the fake fix: `00:28 +91: All tests passed!`

Jest, from `D:\Repo\Fitness_App_Phase2_s01\functions`:
`npx jest src/__tests__/activity src/__tests__/abuse_guard.test.ts src/__tests__/callable_hardening.test.ts`
First run: `Test Suites: 1 failed, 26 passed, 27 total` / `Tests: 1 failed, 790 passed, 791 total`; the one failure is `remediation_a_validate_bound.test.ts` (32 MiB filler, 5000 ms test timeout) while the machine also ran the Dart suite; the file alone passed (`Tests: 6 passed, 6 total`). Classification: environment (CPU load), not a product bug, no test change. Second full run: `Test Suites: 27 passed, 27 total` / `Tests: 791 passed, 791 total`.

### What remains
- The wiring tests of agent 11a that use a `Fake implements ActivitySyncRepository` (for example `_ThrowingSyncRepo`) must tolerate the new `onAccountChanged()` call in the account-change block (a `Fake` throws `UnimplementedError` for it); the full Dart run above passed, so none currently fails.
- A push already in flight at the moment of an account switch is still sent with the credentials current at that instant (the pusher cannot be cancelled); only later pushes and the bookkeeping are stopped.
- `lastTombstonePushError` is sticky after a later success (documented as "last failed in this process"); not changed.
- Real Firebase quota behaviour (`resource-exhausted` from the live callable) is not exercised; the fake raises the same code.
- Not run: `flutter analyze`, full suite, mutation runs (by instruction).
