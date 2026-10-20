# S02 release notes: Unified activity

Sprint S02 "Unified activity" (Phase 2 line). Pull request #10 was merged into `phase2/main` as merge commit `2c121242` on 2026-10-16 after GPT-PM APPROVE on exact head `72cc3803` (review round 14). Source: `core/DECISION_LOG.md` entry "docs: record operator answers after the S02 merge".

Tags: FACT = verified in the file or commit named; INFERENCE = derived from facts; UNKNOWN = not confirmed in code or records.

Related documents: design `docs/phase2/s02/S02_DESIGN.md` (revision 12, with section 17 "Implementation notes" describing what the code actually does), test plan `docs/phase2/s02/S02_TEST_PLAN.md`, sprint report `docs/phase2/s02/S02_SPRINT_REPORT_AND_RETRO.md`, operator runbook `runbooks/activity_stream_bucket.md`.

## Read this first: where the code differs from the operator decisions

Two operator decisions of 2026-10-16 (recorded in `core/DECISION_LOG.md` after the merge) were NOT reflected in the code merged in pull request #10. The second one is applied by a follow-up commit on the next sprint branch (item 2); the first is still pending. Do not assume either is in effect in a build made from `2c121242`.

1. Local journal in the default build. Decision: the journal opens in the default build regardless of the cloud flag. Merged code: `mobile/lib/core/config/activity_flags.dart` defaults both `ACTIVITY_LOCAL_JOURNAL` and `ACTIVITY_CLOUD_STREAMS` to false and `journalEnabled` is `localJournal || cloudSync` (FACT). So a default build today does NOT open the journal. The change is a follow-up, not part of S02.
2. Retention "never". Decision: "never" is not offered; default 2 years (730 days); allowed 90, 365, 730. Merged code: `functions/src/activity_streams/settings.ts` has `DEFAULT_STREAM_RETENTION_DAYS = 730` and `ALLOWED_STREAM_RETENTION_DAYS = [90, 365, 730]` (matches), but in the merged head `STREAM_RETENTION_NEVER_OFFERED = true` so the server still accepted `null` ("never") (FACT). The follow-up commit on the next sprint branch sets the constant to `false` (the server then refuses `null` with `invalid_retention`) and removes "or never" from the privacy wording at its real source `scripts/legal/legal_text.py`; the privacy wording as a whole is still a DRAFT pending the operator's approval.

## Part A: what users see

### Default build (both flags off)

- FACT (`activity_flags.dart`): both new modes are off by default; "the default build behaves exactly as before S02".
- Nothing new is shown: the sync card on the Progress page (`mobile/lib/features/activity/widgets/activity_sync_entry_card.dart`) draws nothing unless `cloudSync` is on.
- The local journal is OFF in the default build as merged (see "Read this first"). The operator decision to open it always is pending implementation.
- Nothing about activities is uploaded. The debug telemetry path changed (see Part B, telemetry) but only in debug builds.

### What S02 does NOT give users yet

- INFERENCE (no UI caller found by grep in `mobile/lib`): there is no screen to choose a retention period, grant or withdraw cloud-stream consent, delete one activity, delete all uploaded streams or export activities. The client classes exist (`ActivityCloudSettingsClient`, `ActivityConsentWithdrawal` in `mobile/lib/features/activity/repository/activity_cloud_settings_client.dart`; tombstone pusher `cloud_functions_activity_tombstone_pusher.dart`) but the screens belong to sprint S03 (design section 17 items 18, 19, 23, 25). The only S02 screen is the sync-conflict sheet below.
- No GPS recording (sprint S04), no import of other apps' data, no promise that sessions from different sources are de-duplicated (design 9).
- No cloud-to-device restore: a new device or reinstall sees no activities (design 3.5).

### When the cloud flag is on (`ACTIVITY_CLOUD_STREAMS=true`)

The server and the privacy text must be ready first (Part B). Behavior as built:

- The journal opens, summaries (numbers only, no route, no heart rate) sync to the account, and the sync-conflict entry card appears when two devices changed the same activity. The sheet "Sync needs your decision" lets the user choose "Keep this device" or "Keep cloud"; nothing is deleted until the user chooses (strings in `mobile/lib/l10n/app_en.arb`, keys `activitySync*`).
- Consent: route data (GPS, altitude, speed) is uploaded only after the user's consent is recorded on the server; withdrawing consent stops uploads at once (`consent_withdrawn`). Granting consent answers `feature-disabled` while the server bucket is not configured (design 17 item 6).
- Retention: server default 730 days (2 years), allowed 90 / 365 / 730 days; the expiry clock is the activity date. Shortening makes older streams due at the next daily purge; lengthening does not bring back expired streams (design 5.3). `null` ("never") was still accepted by the server as merged in `2c121242`; the follow-up commit refuses it (see "Read this first"). There is no client screen for this in S02 (see above).
- Deleting one activity: server callable `deleteActivity` writes a tombstone, then deletes the stream objects, the stream row and the summary. Delete wins over a copy on another device or a queued offline write (design 6.2). Erasure works even if the cloud flag or the bucket setting is off (design 17 item 8).
- Deleting all uploaded streams: callable `deleteAllActivityStreams`, a resumable job; summaries are kept. Withdrawal of consent can start it (`cloudStreams.deleteExisting`, design 17 item 6).
- Account deletion: the existing deletion flow now also removes stream objects (`streams/<uid>/` and `quarantine/<uid>/`), blocks new activity writes through a server fence, and a late sweep runs about 15 minutes later (design 6.1). On the phone, account deletion wipes only that account's journal (design 17 item 22).
- Export: callable `getActivityStreamDownloadUrls` returns short-lived download links (15 minutes) for stored streams; the account export lists streams and carries the note that heart-rate streams are on the device only (design 7, 17 item 10). INFERENCE: no screen calls it yet.

### What never leaves the phone

- Heart-rate streams and heart-rate numbers in the summary (`avgHrBpm`, `maxHrBpm`): the server validator rejects heart-rate kinds and the summary rules do not allow those keys (design 5.1a, 9). Honest limit stated in design 5.1a: heart-rate values disguised as another numeric stream cannot be detected by structure checks alone.
- Cadence, power, stroke rate and temperature streams: device-only by default (design 5.1; an operator question that the 2026-10-16 decisions did not answer, so INFERENCE: still device-only).
- Edit history, merge notes and the other local-only fields (design 5.1 `meta`).
- Laps and source records are uploaded only inside the stream object, never as summary fields (design 5.1).

## Part B: operator and deployment notes

### New server code (`functions/src/activity_streams/`, exported from `functions/src/index.ts`)

| Name | Kind | File |
|---|---|---|
| `setActivityCloudSettings` | callable | `set_settings.ts` |
| `createActivityStreamUpload` | callable | `create_upload.ts` |
| `commitActivityStream` | callable (own memory profile) | `commit_stream.ts` |
| `deleteActivity` | callable | `delete_activity.ts` |
| `deleteAllActivityStreams` | callable | `delete_all_streams.ts` |
| `getActivityStreamDownloadUrls` | callable | `download_urls.ts` |
| `sendDebugTelemetry` | callable | `telemetry.ts` |
| `purgeExpiredActivityStreams` | scheduled, `45 3 * * *` | `purge.ts` |
| `reconcileActivityStreams` | scheduled, every 5 minutes | `reconcile.ts` |
| `sweepLateActivityStreams` | scheduled, every 5 minutes | `late_sweep.ts` |

FACT for names, files and schedules (grep of `onCall` / `onSchedule`). `deleteAccount` in `functions/src/index.ts` now writes the account fence (Step 1c), records `authDeletedAt` (Step 3b) and runs `sweepActivityStreamObjects` in both existing `sweepAccountData` calls.

### Expected-account check

- Six callables require the request key `expectedUid`: `setActivityCloudSettings`, `createActivityStreamUpload`, `commitActivityStream`, `deleteActivity`, `getActivityStreamDownloadUrls`, `deleteAllActivityStreams` (helper `expected_uid.ts`, design 17 item 25). `sendDebugTelemetry` is excluded by decision.
- A missing or malformed key gives `invalid-argument` / `invalid_request`. A key different from the signed-in account gives `HttpsError("failed-precondition", "account_changed")`. The same code `failed-precondition` is also used for `account_deleting`, so a client must compare the message string `account_changed`.
- Compatibility: a client without the key gets `invalid_request` from these six callables. Ship the client and the server together (both flags are off, so no deployed client exists yet).
- `expectedUid` is a consistency check for an honest client, not the authorization boundary (that stays `request.auth`).

### Firestore and Storage rule changes

- `firestore.rules` (FACT): the owner wildcard now excludes `activities`, `activity_streams`, `activity_settings` and `activity_tombstones` in both the read and the write clause. `users/{uid}/activities/{id}` is the only client-writable path (scalar summary with a shape check, no write for a tombstoned id or while `activity_account_state/{uid}` exists). The other three are server-written. `activity_account_state` has no client rule (default deny).
- `debug_sessions`: `allow create: if false`. This is a separately revertible deploy step; deploy order is callable first, client switch second, this rule last (design 8.1).
- `storage.rules` (FACT): unchanged in behavior, still deny-all; the header comment now names the activity bucket. Stream objects live in a separate private bucket reached only through V4 signed URLs.
- `firestore.indexes.json` (FACT): composite index `activity_streams` (`state`, `expiresAt`), field overrides for `activity_settings.recomputePending`, `activity_settings.streamDeletePending`, `activity_streams.pendingSince`, and a TTL override on `activity_tombstones.expireAt`.
- Permanent floor (design 12.1): the exclusions and shape blocks must never be reverted, or the three server-written collections become client-writable. Rollback of rules is not offered.

### Config and flags

| Name | Where | Default | Effect |
|---|---|---|---|
| `ACTIVITY_CLOUD_STREAMS` | app build, `--dart-define` (`mobile/lib/core/config/activity_flags.dart`) | false | Cloud path: summary sync, tombstone push, conflict card, consent client, stream upload; also opens the journal |
| `ACTIVITY_LOCAL_JOURNAL` | app build, `--dart-define` (same file) | false | Opens the device journal with no network path |
| `ACTIVITY_STREAM_BUCKET` | server env in `functions/.env.<project>` (`functions/src/activity_streams/flags.ts`) | unset | Unset: consent grant answers `feature-disabled`, upload callables refuse, sweeps are logged no-ops. A value equal to the Body Scan bucket counts as unset |

Server code constants (not flags): `DEFAULT_STREAM_RETENTION_DAYS`, `ALLOWED_STREAM_RETENTION_DAYS`, `STREAM_RETENTION_NEVER_OFFERED` in `settings.ts`.

### Must be provisioned before any cloud deploy (all operator-owned unless noted)

Source: design sections 12.3 and 17 items 15, 17, 20; `runbooks/activity_stream_bucket.md` (sections 1 to 10); decision log "not answered yet" list. Nothing in this list has been applied (the runbook says so for the alerts).

1. Private stream bucket `<project>-activity-streams-private` with public access prevention and the soft-delete / versioning window decided; set `ACTIVITY_STREAM_BUCKET` (runbook 1, 3). Operator.
2. IAM for the runtime identity, and the decision between a dedicated `fn-activity` service account and the default identity (runbook 2; design 17 item 2). Operator.
3. Alert policies and log-based metrics from the signals table (runbook 8, design 6.3). Operator.
4. Tombstone TTL policy: declared as a `fieldOverrides` entry in `firestore.indexes.json` and deployed with the indexes; the 400-day value is a proposal awaiting operator approval (design 17 item 16 A6, runbook 5). Operator.
5. Privacy text approval and the wording change ("or never" removed): `public/privacy.html` is not edited by S02; request in `docs/phase2/s02/S02_PRIVACY_TEXT_REQUEST.md` (design 17 item 15). Operator.
6. First-release region (decision log: not answered). Operator.
7. Release gate before enabling cloud streams in production or shipping any GPS recorder: move payload build, gzip, SHA-256 and journal seal/open off the UI isolate and add a 100k-sample frame-budget test (design 17 item 20a). Operator-owned gate, work for S04 or a later sprint.
8. Blaze billing and deploy credentials for the Phase 2 project, deployment only to Firebase alias `phase2`, never to production project `fitness-app-korostelev`. Operator. UNKNOWN: current billing status of the Phase 2 project (not recorded in the files read).

Operator must never unset `ACTIVITY_STREAM_BUCKET` while objects exist (design 17 item 17, runbook 10).

### Deploy order

Server first (rules, indexes, callables, schedulers), then the client. Telemetry: callable, then debug-client switch, then the `debug_sessions` rule (design 8.1). Keep both app flags off until items 1 to 5 above are done.

### Rollback

- Turn both app flags off; summaries stay valid; stream objects remain until the daily purge or a user delete (design 12.1). Data is left in place, nothing is deleted by rollback.
- Rules exclusions are a permanent floor and are not reverted. The `debug_sessions` `create: false` step can be reverted separately.
- Server rollback of a callable would make an `expectedUid` client fail; keep client and server in step.

### Migration of existing Phase 1 users

- FACT (design 12.1 and 3.6): the new collections are additive; S02 adds no write into `workout_sessions` / `workout_logs` and no copy of old records into `activities`.
- With both flags off (default) nothing happens on first launch with S02.
- With a flag on, the journal starts empty; INFERENCE: existing Phase 1 workouts do not appear in it and there is no cloud-to-device hydrate (design 3.5). Each account has its own journal directory and key; sign-out and account switch never delete journal data (design 17 item 22).
- Phase 1 behavior change that does ship: debug telemetry. Clients write `debug_sessions` only through `sendDebugTelemetry`; the free-text log message and free-form build identity are no longer uploaded; the 64 KiB local buffer was not built (design 17 item 11).

### Known limits

- Journal default and "never" retention: see "Read this first".
- Sign-out is not wired to a wipe or export offer (S03); a plain sign-out keeps the journal (design 17 items 18, 22).
- `sendDebugTelemetry` has no expected-account check, by decision (debug builds only, closed schema, no identifiers; design 17 item 25).
- After a consent re-grant uploads resume at the next app start (design 17 item 19).
- A withdrawal whose server call was not sent leaves server consent granted until it is repeated; no durable outbox (design 17 item 25, S03 requirement).
- Heart-rate values disguised as another numeric channel cannot be detected (design 5.1a); residual numeric channels in `primarySourceId` (design 17 item 17).
- Purge throughput at very large scale is unmeasured; reconcile cursor restart, tombstone listing size and other backlog items are listed in design 17 items 17 and 25.
- The Android emulator and rules runs were made on fake or emulated backends. UNKNOWN: any run against a real Phase 2 Firebase project (none recorded).
- Test evidence: last complete run `docs/phase2/s02/S02_TEST_FINDINGS_FINAL_RUN.md` (head `45c747b0` for Dart: 1117 activity tests passed; rules emulator 953 passed on `479b7342`); latest epic `docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md` (final server run 922 activity tests and 315 related tests passed; Dart activity directory 1485 passed). The final-run file and EPIC16 are different heads; counts are not summed here. The 32 MiB stream test timeout was raised to 60 s in test code only (EPIC16 16d).
