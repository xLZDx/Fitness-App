# S02 test epic 7: findings

## Epic 7b: client stream upload, retry and consent withdrawal (plan I15, I16, I17, I27, I28)

Files: `mobile/test/features/activity/repository/activity_stream_upload_test.dart`, `activity_stream_upload_retry_test.dart`, `activity_consent_withdrawal_test.dart`, shared fakes `mobile/test/support/stream_upload_world.dart` (fake server that refuses a commit without a complete PUT of that upload id, ordered call log, injected clock, kill hooks; real file journal on the in-memory file system).

Final run (from `mobile/`, all three new files plus the existing sync, journal, wipe, tombstone and rev tests that touch the changed files):
`flutter test test/features/activity/repository/activity_stream_upload_test.dart test/features/activity/repository/activity_stream_upload_retry_test.dart test/features/activity/repository/activity_consent_withdrawal_test.dart test/features/activity/repository/activity_sync_test.dart test/features/activity/repository/file_activity_journal_test.dart test/features/activity/repository/file_activity_journal_generation_test.dart test/features/activity/repository/file_activity_journal_recovery_test.dart test/features/activity/repository/file_activity_journal_commit_cases_test.dart test/features/activity/repository/activity_wipe_test.dart test/features/activity/repository/activity_tombstone_sync_test.dart test/features/activity/repository/activity_rev_convergence_test.dart`
Summary line: `00:55 +198: All tests passed!` (29 upload + 22 retry + 12 withdrawal tests are the new ones).

### Defects found and fixed

1. KNOWN SUSPECT CONFIRMED (MAJOR): the uploader reused the summary sync state. `runPending` only picked `pending` or `upload_failed` entries, but the summary sync (which runs first at app start) writes `synced`, so in the real flow no stream was ever uploaded. The mirror defect: the uploader wrote `synced` after a commit, which made the summary sync skip an entry whose summary had never reached the cloud. Established by code reading and by the real-sequence test (summary sync, then `runPending`); the test was not executed against the old code (no mutation runs). Fix: a dedicated stream marker in the journal: `JournalState.streamUploadedHash` (the `streamsPlainHash` the cloud holds), `streamUploadPending`, and `ActivityJournal.markStreamUploaded` (`journal_models.dart`, `activity_journal.dart`, `file_activity_journal.dart`). The uploader picks entries whose summary is in the cloud (`synced`) or whose last run failed (`upload_failed`) and whose streams are not yet marked; success writes only the stream marker; the cap writes `upload_failed` unless the entry is `sync_conflict` (a conflict is never overwritten) and only on the unchanged generation. An edit changes the hash, so edited streams are pending again.
   Design wording to amend (design 5.2 item 4, "the `synced` marker is written only after commit success" and the implementation note that the journal has no stream state): the `synced` state belongs to the summary sync; the stream has its own marker written only after commit success.
2. Provider graph needed an initialised Firebase app: `CloudFunctionsActivityStreamClient` and `cloudFunctionsSettingsCall` resolved `functionsForRegion` at construction. Now resolved at first call (wiring can be built and tested without Firebase).

Compile errors in the three client commits: none (the files compiled on the first run).

### Plan wording and limits

- I27 sentence "with the PUT incomplete restart does not create a new upload" contradicts "restart re-uploads"; implemented and tested as: a killed or incomplete PUT is never resumed, the restart creates a NEW upload and commits only its own upload id.
- Design 5.2 item 4 still says "exponential backoff and jitter" and "resumes at commit"; plan I27 and the code pin no jitter and no resume. Design text is stale.
- After `cancelQueued` (withdrawal) the uploader stays cancelled until `resume()`; nothing calls `resume()` after a re-grant in the running app (no grant UI exists yet), so uploads restart at the next app start. Test pins `resume()`; wiring of a grant path is OPEN.
- After the cap the entry is `upload_failed` although the summary may be synced; the next start's summary sync re-pushes and re-marks it (idempotent). A later successful upload does not rewrite that state back.
- Not covered: `activityCloudSyncWiringProvider` (auth listener), real Firebase callables and `httpClientPutSender` (no network in unit tests), payloads above 5 MiB, the provider-level sharing of the uploader between the settings screen and the start run (read from code only).
