# S02 remediation E test notes

Expectations for the test agents. No tests were run by the implementation agents. Sections are per sub-batch.

## E2

Scope: MAJOR-03, bulk local deletions must reach the cloud promptly and be observable.

Client (`mobile/lib/features/activity/repository/activity_sync_repository.dart`, `sync_models.dart`), with fake journal, fake backend, fake pusher and a fake timer factory passed as `retryTimerFactory` (record delay and callback; fire manually):

- Offline backlog of 9, 30, 100 and 1000 local tombstones, then one `syncAll()`: the pusher is called for every id exactly once (9 -> 2 rounds, 30 -> 4, 100 -> 13, 1000 -> 125 rounds), `pendingTombstones` is 0 afterwards, no retry timer is scheduled.
- 1100 tombstones: one `syncAll()` pushes exactly 1024 (128 rounds of 8), stops, `pendingTombstones` = 76, ONE timer is scheduled with 60 s; firing it pushes the remaining 76.
- Restart: tombstones persist in the journal (new repository instance over the same journal); the first `syncAll()` resumes with only unconfirmed ids; ids listed by `listTombstoneIds` are never pushed again.
- Quota exhaustion: pusher throws a `resource-exhausted` error on call N: no further push call in that pass (no hot loop), `lastTombstonePushError` = `resource-exhausted`, the timer delay is 15 min (the longest), local tombstones stay.
- Partial server failure: in round 1 a non-systemic error on one id does not stop the other ids of the batch but no continuation round starts; the failed id is tried last in the next pass; a failure inside a continuation round stops the pass at once; `unavailable` or `permission-denied` stops the round at once.
- Unknown server tombstone list (`SummaryBackendUnavailable`): nothing is pushed, a retry is scheduled when tombstones are owed.
- Backoff schedule with the fake timer: successive failing attempts schedule 60 s, 2 min, 4 min, 8 min, 15 min, 15 min, then no 7th scheduled attempt in the same process; only one timer exists at any time.
- `dispose()` cancels the pending timer (callback never runs the pass); `cancelTombstoneRetry()` cancels too; no timer when pending is 0 or the pusher is null.
- Observability: `watch()` emits a state whose `pendingTombstones` changes from N to 0 and carries `lastTombstonePushError`; `ActivitySyncState` equality includes both fields; `isEmpty` ignores them.
- Existing behaviour kept: denial rules, fence outcome, unknown state never deletes a local entry.

Server (`functions/src/abuse_guard.ts`):

- `QUOTAS.activityDelete` is 1000. Pinned values to update in the test files (production-only batch, not edited here): `functions/src/__tests__/abuse_guard.test.ts` line 288 (`activityDelete: 100`), `functions/src/__tests__/activity/support/seven.ts` line 58 (`limit: 100`), the `activityDelete: 100` seeds and expectations in `settings_consent.test.ts` line 247 and `callable_hardening.test.ts` line 170 (exhaust at 1000), and the F82 row in `S02_TEST_PLAN.md`.
- Behaviour kept: quota is per user, refunded on fence refusals, other quotas unchanged, `activityDeleteAll` still 10.
