# Product hardening sprint — plan (2026-10-13)

Status: approved by the operator for implementation ("GO", 2026-10-13). One PR for the sprint. Baseline: master at the merge of PR #2 (9c4072f).
Evidence base: the nine-agent whole-project review and the four extra analyses of 2026-10-13 (see `reports/FULL_PROJECT_QA_2026-10-13.html`).

## Operator decisions (verbatim intent)

1. Fix all review findings F1–F13.
2. F1 (demo features backed only by mock repositories): **hide them in release builds** (compile-time flag; direct deep links must not bypass the hidden entry points).
3. Age: for under-18 and senior users take a **cautious path and show a warning**.
4. Exercise catalog: **fix every discrepancy and gap everywhere** (missing `purpose`, missing `muscles`, equipment that disagrees with the title, duplicated steps, truncated names, the missing clip, the quarantined id).
5. Recommendations: **make the logic use every onboarding parameter that is available**, and **add a question at recommendation time about the training context**: gym with machines; outdoors without machines or with minimal kit (bands, balls, as examples only); at home; and yoga as a separate mode that is not tied to a place.
6. Live coach: **finish all candidate exercises** on a data-driven engine.
7. Body comparison: repeat the idea of the reference video — the user photographs themselves in the gym (a trainer held the phone in the reference; a tripod works too) with an automatic countdown and shutter.

## Workstreams

| ID | Scope | Main areas | Acceptance |
|----|-------|-----------|-----------|
| WS1 | Release-safety of mock-only features (F1, F2, F9) | `mobile/lib/core/config`, router, profile/settings/exercise reference entries, marketplace booking guard, progress-photos fallback | Flag defaults to off in release; gated routes redirect home; marketplace booking cannot run against a mock listing; photo-store failure shows an explicit error, never a demo grid |
| WS2 | Deletion and webhook hardening (F3, F12) | `functions/src/index.ts`, `account_export.ts`, `scripts/ci/data_lifecycle_policy.json` | Webhook never writes user data for a deleted Auth user; tokens revoked at deletion; export and policy cover `stats/workout_sessions` and the equipment-identity server records or record an explicit exemption |
| WS3 | Silent-failure fixes (F4, F5, F6, F7, F8, F11, F13) | prefetch, reminders, router redirect, manifest, health write, batch clears, logging | Each item has a regression test or a stated reason it cannot be tested here |
| WS4 | Python tooling (F10) | `scripts/ops`, `scripts/l10n`, `scripts/catalog`, `tools/catalog` | Non-zero exit on failure, no insecure retry with credentials, timeouts, atomic writes, correct bucket names |
| WS5 | Catalog data repair | `mobile/assets/data/exercises_vendor*.json`, `scripts/catalog` | Ratchet baselines in `scripts/catalog/test_catalog_text_ratchet.py` lowered to the new, smaller gap counts; edits survive the catalog build script |
| WS6 | Honest recommendations | profile/onboarding model, safety, `plan_builder`, `suggestion_builder`, `programme_builder`, exercise filter, l10n ru/en | The 100-profile suite reports zero violations for every honesty rule it covers and no questionnaire field is dead without a documented reason; the new training-context question is persisted and drives filtering |
| WS7 | Live coach engine | `mobile/lib/features/form_check`, assets registry | Exercises load from a JSON registry through one generic classifier; at least ten exercises supported; cues in ru/en; non-clinical wording |
| WS8 | Body comparison | `mobile/lib/features/progress_photos` and a new scan flow | Guided self-timer capture with readiness checks, three-pose scan sets, aligned comparison view, consent and privacy copy updated; photos never leave the device |
| WS9 | CI signals | four failing checks on the PR #2 head (CT-1 content QA, data access policy drift guard, release build, integration emulator) | Each failure triaged: fixed, or classified as an operator-only secret/environment item |

## Order and parallelism

WS1, WS2, WS4 and WS5 touch disjoint files and start together. WS3 and WS6 share some mobile files and are sequenced by file ownership. WS7 starts with a short design step, WS8 with answers to the open product questions. WS9 runs alongside.

## Verification

Per the operator's workflow: finish the code, then test-writing agents write and run focused tests for every workstream; relevant specialist reviewers run once; valid findings are fixed in one batch; a final GPT-PM review on the exact head precedes the push and the single PR. The 100-profile and catalog ratchet suites are re-run at the end.

## Known limits

Kotlin and the emulator-based suites cannot be run on the Windows development host; they stay unverified locally and are covered by CI where it can run them.

## Revision 2 (2026-10-13): contracts and falsifiable acceptance

Added after the documentation-gate review of 07d8e4a (GPT-PM REJECT with eight MAJOR findings, all about completeness and verifiability of this plan, none about the operator decisions). Each contract below is the behaviour the implementation and its tests must show; the traceability matrix in R2-9 maps every finding to a change, a test and a recorded result.

### R2-1 Age policy contract (WS6, GPT MAJOR-01)

- One deterministic policy in `mobile/lib/features/safety/data/age_policy.dart`, carried by `SafetyContext` to every generator (plan builder, home suggestions, programme builder), so a rule reaches all three. It is a product heuristic for "be more conservative by default", never a clinical statement: no medical thresholds, no diagnosis, no claim that an age is unsafe for an exercise.
- Minor (under 18): no maximal-effort work (powerlifting group, advanced difficulty), intensity ceiling 0.8, at most 4 training days, lowered volume, difficulty ceiling for recommendations.
- Senior (65 and over): the same plus no high-impact work, intensity ceiling 0.85, at most 3 training days, balance and mobility work included.
- Birth-year precision (GPT Decision A, adopted): the questionnaire stores only a birth year, so an age is one of two values. The boundary year resolves on the cautious side: the minor band applies while the calendar-year difference is 18 or less (`PersonalInfo.lowestAgeAt` below 18; someone born in December 2008 stays on the minor path through the whole of 2026), the senior band applies from a calendar-year difference of 65. One function, `ageBandForPersonal`, serves the plan, suggestion and programme builders; a legacy stored whole-number age is used as is. Cost: a person who is already 18 (or not yet 65) can get the cautious path for up to one year.
- Warning: shown before the plan starts and states what the app does and does not do (it adapts the selection, it does not replace advice from a qualified adult or clinician). The warning never replaces the filtering.
- Missing age is treated as adult (the app does not guess a band) and the adult path shows no age warning; this is deliberate and covered by a test. The body-scan feature is the opposite: unknown age is refused.
- Falsifiable: the 100-profile suite fails on any minor or senior plan that breaks the rules above, on any adult who gets an age warning, and on a plan that exceeds the session length; four hand-written canary profiles (15-year-old, 70-year-old, screening-blocked, adult without age) assert literal expected outcomes.

### R2-2 Training-context contract (WS6, GPT MAJOR-02)

- Asked at recommendation time, not added to onboarding: the chooser is shown on the planner, the home suggestions and the programme screens, visible and changeable at every new generation.
- Values: gym with machines, outdoors with minimal kit, home, and yoga as a separate mode that is not tied to a place. Equipment is derived from the context and the profile's own equipment answers (gym means everything is available because the user stated they are at a gym; home means only what the profile says is owned; outdoors means bodyweight plus portable kit and carriable weights the profile owns; yoga ignores equipment and place).
- Three stored states per account (`training_context.v1.<uid>`): never asked, skipped, chosen. Never asked or skipped never becomes gym: generation falls back to the profile's own equipment answers exactly as before the question existed, and the chooser stays visible. An unrecognised stored value reads as never asked.
- Account switch: the answer is read per uid; while a different account's answer is loading, no answer from the previous account is used.
- Injuries, screening and the age policy apply in every context.
- Falsifiable: tests for never asked, skipped, each context, switching context between generations, the yoga mode, and a changed uid.

### R2-3 Live-coach shipping contract (WS7, GPT MAJOR-03)

- Every registry row names the origin of its thresholds (`provenance`): measured, experimentally confirmed, or authored. Authored rows ship only as `beta` + `advisory`: on-screen cues only, no speech, no rep failure, no claim that technique is correct, and a visible beta badge.
- A registry row plus localized cues is not a release criterion. Promotion of an exercise from advisory to spoken or faulting needs the recorded-set gate in `core/plans/COACH_ENGINE_SHIP_GATE_2026-10-13.md` (at least 20 sets, at least 3 camera heights, at least 3 people, fault margin above twice the tolerance, at most 5 percent false positives on good reps), per exercise, in addition to the count of ten exercises.
- When the required landmarks are missing or low quality the engine produces no assessment (the pose gate asks the user to reposition) instead of a forced verdict; rep counts stay hidden until the measured holdout is at least 80 percent.
- Exercises without usable landmarks (calf raise) are excluded rather than faked.
- Falsifiable: registry content tests (every cue has ru and en text, thresholds have a provenance, authored rows are advisory), synthetic-frame tests for good, faulty, partial-visibility and noisy input, and the debug-only recorder that produces the real sets the gate needs.

### R2-4 Body-scan privacy boundary (WS8, GPT MAJOR-04)

- Boundary: scan photos and landmarks stay on the device, AES-encrypted per account, and no network, analytics, crash-log or server path reads them. The existing server-side body-composition estimate and goal-photo paths do not read scan data (checked by a code search recorded in the change record); the scan feature itself computes no body numbers and makes no judgement about weight, body composition or appearance.
- Access priority (tested, `scan_access_test.dart`): signed out, then under-18 or unknown age (refused), then Supporter, then the existing photo consent. The age used is the LOWEST age the stored birth year allows (`PersonalInfo.lowestAgeAt`), so a person born in December 2008 is refused for the whole of 2026 and the scan never opens on 1 January from year arithmetic alone.
- A save is bound to the account that started it (GPT MAJOR-02): the initiating uid and the repositories are captured before the first write, the live uid is re-checked before each photo, before the sidecar and after each write, and on an account switch, sign-out or deletion the partial writes are removed through the original account's repositories only and nothing is committed or shown.
- Review before saving, cancel at any step, delete one scan or all, per-account isolation on account switch, a wipe on account deletion (scans, reminder preference and notification, training context, coach recordings).
- Reminders every two weeks are off until a scan exists and can be switched off; the pending notification is cancelled on switch-off, sign-out and deletion.
- Falsifiable: tests for camera permission denied, timer interrupted, partial scan set, deletion, account switch, and the access priority table with a fixed clock.

### R2-5 Release deny-by-default contract (WS1, GPT MAJOR-06)

- One compile-time flag (`kDemoFeaturesEnabled`, true outside release builds or with `--dart-define=DEMO_FEATURES=true`). In a release build every mock-only screen, provider and operation is denied:
  - routes: the router redirect sends every gated path (and sub-paths) home, so deep links, restored state and notification taps that go through the router are covered;
  - entry points: profile, settings and exercise reference hide the links;
  - operations: the marketplace service wrapper refuses booking on a mock listing even when the UI is bypassed; the progress-photos store failure shows an explicit error (a release fallback repository that throws), never a demo grid.
- Falsifiable: router tests for every gated path, wrapper tests for every booking operation, release-fallback tests, and a pure-function test of the flag derivation.

### R2-6 Deletion and webhook fence (WS2, GPT MAJOR-05)

- Order in `deleteAccount`: cancel the Stripe subscription, then revoke refresh tokens, then recursive delete, then shared-record sweep, then delete the Auth user, then one final idempotent sweep of `users/{uid}`. The final sweep closes the window in which a webhook event processed after the first wipe but before the Auth deletion could re-create subscription data; events arriving later are stopped by the Auth-user existence check done immediately before the write. A subscription write that races with the Auth deletion is re-checked after the write and removed if the user is gone.
- The final sweep is never log-only (GPT MAJOR-03). The sweep is one shared function (`users/{uid}`, `donor_wall`, `coach_listings`, plus the shared-record sweep) used by `deleteAccount` before and after the Auth deletion and by a durable reconciler. `deleteAccount` writes the durable intent record `accountDeletionRetries/{uid}` (uid, status, attempts, timestamps, bare error code only; Admin SDK only, client access denied by rules) after the first sweep and BEFORE deleting the Auth user, so a crash, timeout or kill after that point still leaves something to retry; if the write fails, the Auth user is not deleted and the call fails so the user can repeat it. A clean final sweep deletes the record and returns `finalCleanup: "complete"`; a failed one keeps it and returns `"scheduled"` (there is no unrecorded outcome). The scheduled `reconcileAccountDeletions` (every 15 minutes, no user authentication) CLAIMS each due record before sweeping (`attempts` + 1, `nextAttemptAt` pushed out, 15 minutes doubling to a 6 hour cap), so a hung or killed run still consumes an attempt and a poison record cannot starve the queue; it re-runs the sweep, deletes the record on success, terminates a record already at 12 attempts without sweeping, stops starting records after 240 s of its 300 s timeout, and at 12 attempts marks the record `failed_terminal` and logs the ERROR event `account_deletion_reconcile_exhausted` (the alert definitions are source-controlled in `functions/src/monitoring/alert_definitions.ts`, together with the `deleteAccount` final-sweep event; this repo does not deploy them, and creating the live policy and attaching a notification channel remains the separate operator step recorded in the monitoring README, DECISION FA-D1). A record whose Auth user still exists (an aborted deletion) is dropped, never swept. Records expire by TTL 30 days after creation. Lifecycle, who can read it and the operator procedure for `failed_terminal`: `core/DATA_INVENTORY_2026-08-11.md`.
- Webhook handling stays idempotent (the existing event-order guard) and answers a retryable status for any lookup error other than user-not-found.
- No tombstone collection holding user ids is introduced: it would be a new store of identifiers that needs its own lifecycle classification, and the fence above closes the same race without one.
- Export and lifecycle policy list every confirmed server store. The equipment-identity server records are documented as an export gap (recorded in the lifecycle policy) with a named follow-up owner; see the exception register.
- Falsifiable: webhook tests for every handler against a deleted uid (subscription, lifetime payment, invoice failure, booking confirmation, lookup error), and `deleteAccount` tests for call order and the final sweep, and a reconciler test that injects a raced webhook write, fails every final-sweep attempt, restores Firestore and expects the scheduled retry to remove the remaining data without user authentication.

### R2-7 Dependencies and integration order (GPT MAJOR-08)

1. WS5 (catalog) before the final WS6 and WS7 test runs: equipment and tags change what the recommendations may pick, so the 100-profile suite and the coach registry tests are re-run on the repaired catalog.
2. WS1 before the release-mode checks; WS2 before the account-switch and deletion checks.
3. WS8 adds local data, so the lifecycle reconciliation (`local_data_wipe.dart`, `core/DATA_INVENTORY_2026-08-11.md`, privacy copy) is done after WS8, not before.
4. After integration: one regression on the exact head covering the focused functional tests of every workstream, the whole mobile suite, the functions and equipment-identity suites, the Python suites, the data-lifecycle and data-access policy checks, and every check that can run on the Windows host. Release build, emulator, Kotlin and device behaviour are listed as unverified when they cannot run here.

### R2-8 Acceptance and exception register (GPT MAJOR-07, MINOR M-01..M-03)

- A ratchet is a guard against growth, not an acceptance criterion: where the plan says "fix everything" the criterion is zero confirmed defects of each listed category; unresolved cases are counted separately and named below.
- An exception needs an owner, a reason, a date and its effect on release readiness. A CI blocker that is an environment or secret problem is reported as not passed, never as passed.
- Exceptions at the time of this revision (kept current in the change records): the catalog rows that are not exercises or have no working muscle (quarantined group-label row, relaxation pose); 58 catalog ids whose steps are identical because the vendor lists one movement twice; the equipment-identity export gap; `GOOGLE_SERVICES_JSON_B64` for the release build and emulator job (operator-only secret); Health Connect declarations needing a privacy-policy and store-form update; yoga programme minimal pending product review; Russian copy pending native review; camera, ML Kit, speech, haptics and threshold calibration pending on-device checks.
- Open recommendation gap, pinned exactly: the equipment question has no bench or rack option, so the filter cannot tell a home user with dumbbells from one with dumbbells and a bench. 262 catalogue rows keep a bench or rack link on purpose (the catalogue model and its tests pin it), and the 100-profile suite counts 402 recommended rows that carry such a link for a profile without machines. The count is asserted as an exact baseline (growth and shrink both fail). Owner: product. Follow-up: add a bench/rack equipment option to the questionnaire and make the filter require it; until then these rows can appear for non-gym profiles.
- Not done, by decision, with reasons: the three F13 items listed in R2-9 (`bookingOps` race, Stripe same-second event tie-break, Firestore shape rules); moving the two visual-equipment Firestore repositories onto Riverpod-owned auth (they accept an injected auth now, default unchanged); a deletion tombstone (see R2-6).
- Android backup (GPT Decision B, adopted, no longer an exception): `FlutterSharedPreferences.xml`, `FlutterSecureStorage.xml` and `FlutterSecureKeyStorage.xml` are excluded from Auto Backup (API 30 and below) and from cloud backup and device transfer (API 31 and above), so the plaintext health profile, the corrupt-blob copy and the training-context answer never leave the device. Consequence, accepted: on a new phone the profile and training-context questions are asked again and language, theme and notification settings are not restored. Pinned by `mobile/test/android/backup_rules_test.dart` (configuration only; no device backup or restore was performed on this host).
- Age precision (GPT Decision A, adopted, no longer an exception): see R2-1 and R2-4; the boundary year is cautious for the under-18 band and the scan, and the 65 boundary is conservative. Pinned by `age_policy_test.dart`, `age_policy_journey_test.dart` and `scan_access_test.dart`.
- Authored coach rows are never evaluated as faults (all advisory, beta); the plank sag cue has a dead zone between the sag threshold and the hold-band edge. Both follow the ship gate and change only when rows are promoted on measured data.
- Minimum CI state before merge: required checks pass, or each failing check is documented as an operator-only secret or environment item with the unchanged-by-this-PR evidence.
- Body-comparison quality criteria (M-02): the capture flow requires readiness (full body in frame, steady, lit, distance) before the countdown, offers retake, and refuses alignment when landmarks are unreliable (the comparison shows the photos unaligned).

### R2-9 Traceability matrix F1..F13

Results are from the regression runs on this branch (full `flutter test`, both Jest packages, the Python suites, the two data policy checkers). `flutter test` golden files fail on this host for font and rendering reasons, 25 of them, as they did before the sprint; no other test fails.

| Finding | Change | Test evidence | Result |
|---|---|---|---|
| F1 mock-only features reachable in release | `kDemoFeaturesEnabled`, router redirect for gated paths, hidden entries | `mobile/test/router/app_router_gating_test.dart`, `mobile/test/core/config/demo_features_test.dart`, `mobile/test/features/marketplace/marketplace_page_test.dart` | pass |
| F2 booking against a mock listing | guarded marketplace service refuses booking | `marketplace_page_test.dart` (guard and banner cases) | pass |
| F3 webhook re-creates data after deletion; tokens | guard before write, recheck after write, revoke after cancel, final sweep | `functions/src/__tests__/stripe_webhook_events.test.ts`, `delete_account.test.ts` | pass |
| F4 prefetch reports an empty week while loading | prefetch awaits the schedule | `mobile/test/features/workouts/state/offline_video_providers_test.dart`, `.../offline/file_offline_video_cache_test.dart` | pass |
| F5 reminder silently not scheduled | `ReminderOutcome` returned and surfaced | `mobile/test/core/notifications/reminder_id_test.dart`, `mock_notification_service_test.dart`, `mobile/test/features/workouts/scheduled_session_providers_test.dart` | pass |
| F6 cold-start redirect race | splash hold until the profile snapshot, 5 s bound | `mobile/test/router/app_router_test.dart` (hold cases, including a second hold) | pass |
| F7 exact-alarm permission mismatch | permission removed from the manifest | no automated test possible on the host | manifest diff reviewed; Play Console check is an operator action |
| F8 calorie write permission | write and read grants declared, READ_WRITE request | no automated test possible on the host | manifest diff reviewed; device check pending |
| F9 demo grid on store failure; ownership of the current user | fallback repository throws in release; the two Firestore repositories accept an injected auth | `mobile/test/features/progress_photos/progress_photos_release_fallback_test.dart` | fallback fixed; moving the two repositories fully onto Riverpod is NOT done (see exceptions) |
| F10 Python tooling | exit codes, TLS, timeouts, buckets, streaming | `scripts/l10n/test_fix_const.py`, `scripts/ops/test_upload_and_api_hardening.py`, `tools/catalog/test_json_io*.py` | pass |
| F11 batch clear over 500 documents | `chunked_delete.dart` | `mobile/test/features/visual_equipment/chunked_delete_test.dart` | pass |
| F12 export and lifecycle policy gaps | export of `stats/workout_sessions`; equipment-identity stores marked as an export gap | `functions/src/__tests__/account_export.test.ts`; `scripts/ci/check_data_access_policy.js`, `check_data_lifecycle_coverage.js` | pass; the equipment-identity export remains a documented gap |
| F13 minor observations | see the list below | see the list below | partly done |

F13, one line per observation: swallowed errors logged (streak, health-profile migration, reminder cancel, tier parse): done, no dedicated test; booking webhook existence check: done (`update`, `stripe_webhook_events.test.ts`); reminder id from `String.hashCode`: done (FNV-1a, `reminder_id_test.dart`); dead `authListenable`: removed; unused Bluetooth and foreground-service permissions: removed (manifest); Wear debug suffix: added (Gradle, not buildable on the host); `json_io` atomic write: done (`test_json_io_atomic.py`); `git` calls without timeouts in ML, CT-1, review and equipment-identity scripts: done (script suites pass). NOT done: the `bookingOps` race when both parties delete their accounts at the same moment (needs a per-booking transaction); Stripe event ordering uses `event.created` and has no tie-break for events within one second (the real fix is to re-fetch the object from Stripe); Firestore shape rules (rules unchanged, and the emulator suite cannot run on the host to prove a rules change).
