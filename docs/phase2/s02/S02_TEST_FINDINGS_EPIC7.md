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

## Epic 7a: E01 round trip, E02 account wipe, rules-parsing parity tests

Files: `mobile/test/features/activity/e2e/s02_roundtrip_e2e_test.dart` (E01), `mobile/test/features/activity/e2e/s02_account_wipe_e2e_test.dart` (E02 plus the Dart half of E05).

### E01 notes (plan versus code)

- The 100 sessions that come out of `merge(rawCandidates)` are NOT equal to `corpus.valid` (14 differ in id or provenance, some in summary). The oracle for the merge is therefore the count of 100, distinct ids and the plan sport quotas; the journal and export oracles are the merged objects as constructed.
- The cloud `distanceM` is the effective projection (streams, explicit values, overrides), not the stored `summary.distanceM`; compared with a 10 percent tolerance. The exact preservation check is on the journal.
- After the first sync the repository stamps the three calculation-version keys on the record (`formulaVersion` moves from `formula-0` to `formula-1`); nothing else changes. The post-sync comparison neutralises exactly those keys.
- Production defects found by E01: none.

### E02: what the app shell does NOT wire (precise)

Facts (grep over `mobile/lib`, nothing else calls them): `ActivityWipeCoordinator` (`onSignOut`, `onAccountDeleted`, `onAuthFailureAtLaunch`) and `ActivityJournal.wipe()` have no caller outside `activity_journal.dart`.

1. Account deletion: `AccountDeletionAction.deleteAccount` calls only `localDataWipeProvider`, which `main.dart` binds to `DeviceLocalDataWipe`. That class erases prefs keys, progress photos, coach recordings and the photo key; it knows nothing about the activity journal (journal root is `getApplicationSupportDirectory()`, not the documents directory). After a successful deletion the journal, `sources/`, `quarantine/` and the journal key remain on the device (privacy defect while `ACTIVITY_CLOUD_STREAMS` is on).
2. Kill after the server confirmed: the pending-wipe marker relaunch (`finishInterruptedWipe`) goes through the same `LocalDataWipe`, so the journal also survives that path.
3. Relaunch with an auth failure (the exact 085 criterion): no code detects "no valid session for the stored uid" or user-not-found and calls `onAuthFailureAtLaunch`.
4. Sign-out: no sign-out flow calls `onSignOut`, no UI implements `ActivitySignOutHooks`. A sign-out of account A followed by a sign-in of account B on the same device keeps A's journal, and the start-up sync (`activityCloudSyncWiringProvider`) would push A's summaries into B's account (the journal is device-wide, not uid-scoped). Not exercised by a test (needs the unwritten sign-out flow); recorded as a risk.
5. With the flag off no journal is opened, so a journal left by an earlier flagged run is never wiped either.

Suggested smallest fix (not done, `activity_wiring.dart` and the repository folder belong to epic 7b): a `LocalDataWipe` decorator that wraps `DeviceLocalDataWipe`, calls `ActivityWipeCoordinator(journal).onAccountDeleted()` (best effort, after the inner wipe) and is installed in `main.dart` with the journal opened there; this covers items 1 and 2. Items 3 and 4 need an auth-state hook and the sign-out UI.

Tests: group 1 of the E02 file tests the real seam on files (kill, relaunch with the auth failure, kill at every file-system operation of the wipe, stale repository, sign-out with export offer, declined sign-out) and passes. Group 3 holds the two real app-flow tests (`AccountDeletionAction` empties the journal; kill after confirmation then relaunch empties it). They are SKIPPED with the marker `NOT WIRED (owner: sprint lead, 2026-10-16)` and no external issue exists (no tracker in the repository). Run `flutter test --dart-define=S02_E02_WIRED=true test/features/activity/e2e/s02_account_wipe_e2e_test.dart` to see them fail: both end with `journal after deletion` / `journal after relaunch` expected true, actual false (observed 2026-10-16).

### E02 production defect fixed

- `mobile/lib/features/account_deletion/data/local_data_wipe.dart`: the per-account consent cache `activity.cloudStreamsConsent.<uid>` survived account deletion (the prefix list lacked `activity.`). Prefix `activity.` added to the per-uid feature prefixes (the uid must be the last segment, so another account's key stays). Test: "the per-account activity consent cache is erased with the account and another account keeps its own"; the 90 tests of `test/features/account_deletion` still pass.

### E05 Dart half

A queued offline summary put replayed while the fence exists (stages: between step 1 and the first sweep, after Auth deletion, after `lateSweepDone`) is refused by the fake rules gate with reason `fence`, is not read as deletion (outcome neither `synced` nor `deletedLocal`), keeps the local data, makes at most two write attempts per pass, stays refused after a restart, and the wipe then removes the data. The slipped-in-document and `removeFenceAfter` parts are functions-side (epic 6b) and the rules half is the emulator (epic 5, not run here).

### Quarantine list (new)

| Test | Marker | Date | Owner | Issue |
|---|---|---|---|---|
| E02 group 3: "deleting the account empties the activity journal" | skip `NOT WIRED` | 2026-10-16 | sprint lead | none exists; finding above |
| E02 group 3: "killed after the server confirmed ... including the journal" | skip `NOT WIRED` | 2026-10-16 | sprint lead | none exists; finding above |

### Epic 7a final run (git head before this commit: d973a6ed, from `mobile/`)

Command: `flutter test test/features/activity/e2e/s02_roundtrip_e2e_test.dart test/features/activity/e2e/s02_account_wipe_e2e_test.dart test/features/activity/data/summary_allowlist_parity_test.dart test/features/activity/data/summary_golden_test.dart test/features/activity/data/activity_cloud_summary_test.dart test/features/activity/repository/firestore_activity_repository_test.dart test/features/safety/health_rules_parity_test.dart test/adversarial/n07_team_activation_test.dart test/features/account_deletion`
Summary line: `02:03 +148 ~2: All tests passed!` (148 passed, 2 skipped = the two NOT WIRED tests, 0 failed). The rules-parsing tests (parity, golden, cloud summary, repository, health rules parity, team activation) pass after the let-binding fix of `firestore.rules`.

Remaining: wire the journal wipe (items 1 to 4 above) and un-skip the two tests; run the rules half of E05 on the Firestore emulator (epic 5 files, not run here); plan wording: E01 says the oracle is the corpus, but the merge result differs from `corpus.valid` in 14 records (count and quotas are the true oracle).
