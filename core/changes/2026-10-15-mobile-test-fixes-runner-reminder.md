# Runner owed-delete terminal state and reminder test fixes

- What: _flushPendingDeletes sets the analysis status to cancelled when it clears pendingRemoteDelete on a non-terminal scan; three UI test fakes use the named {weekday, minutes} sync signature; the account-isolation reminder test uses a per-account store.
- Why: the SF-F1 regression test showed a deleted unfinished scan stayed queued and was re-created remotely; the other changes are stale test code.
- Paths: mobile/lib/features/body_scan/state/body_scan_job_runner.dart, mobile/test/features/progress_photos/scan/**.
- Contracts: none.
- Verification: body_scan_job_runner_test 63 passed, scan_reminder_test 17, three UI tests 5/9/11 passed, run alone by the test agent.
