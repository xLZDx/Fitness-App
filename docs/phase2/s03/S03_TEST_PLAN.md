# S03 test plan: shell, mode chooser, dashboard skeleton

Status: DRAFT revision 2 (revision 1 plus internal review remediation batch 1: test-plan findings TP-1 to TP-4 and TP-m1 to TP-m5, and tests guarding the design decisions RV-1 to RV-19). Date: 2026-10-17. Branch `phase2/s03d-ui-design-contract`. Plan only: no test code exists and no test was run for this document. Every result column below is empty by design; results are recorded later by the test agents in `docs/phase2/s03/S03_TEST_FINDINGS_EPICn.md`.

Inputs read: `docs/phase2/s03/S03_DESIGN.md` (final, all sections, read again in the closing pass; design citations of test ids follow this plan), `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` (sections 4, 7, 10, 14), `docs/phase2/s02/S02_TEST_PLAN.md` (style) and `docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md` (real commands).

Tags: FACT (read in a file), PROPOSED (choice of this plan), DEPENDS-ON-DESIGN (the test cannot be finalised until the named design section is written; the expected result below is the contract-level invariant only).

Plain-words glossary (ids used below, each also explained where first used):
- AC-xx-n: an acceptance criterion of the contract (one observable pass/fail check). Family letters: SH shell, REG regression, A11Y accessibility, WS window size and rail, LS large screens, KB keyboard and pointer, FAM platform family, RET retention copy, CH chooser, Q questions, SW switcher, ST strip and pill, RC Record sheet, HM Home, PR Progress, SRC sources, SO sign-out.
- S03-nn: a story (a unit of build work). EP-n: an epic (a group of stories). DT-nn-k: a test added by this plan for behaviour the contract implies but the ACs do not list (design scheme 8.2: "DT-<story number>-<seq>").
- Levels: U unit (pure Dart), W widget, I integration (router plus shell plus providers with in-memory fakes), K static check (a Dart test that reads source files).
- N: number of test entries (a `test` or `testWidgets` after parametrisation by the dimension named in the Config column). A pure data table inside one pure unit test counts as one entry; a widget case with a different window size, text scale, locale or platform is its own entry.
- Sev: H = a failure here means wrong or unsafe user-visible behaviour or data loss; M = wrong layout or state with a workaround; L = polish.

## 1. Scope, levels, conventions

### 1.1 Scope and non-goals

In scope: every one of the 124 contract acceptance criteria listed in design 1.7, the six design tests of S03-0 (DT-0-1 to DT-0-6), the negative and edge tests of section 4 of this plan, and the conditional stories S03-19 and S03-20 (design tests only, counted separately). Out of scope: any Apple build (only a faked `TargetPlatform`), real-device checks (focus ring visibility, TalkBack or VoiceOver reading order, contrast over photographs: NOT_RUN, section 8), recorder, GPS and permissions (S04 to S06), server code, retention control UI.

Operator rules that bind this plan (FACT, global contract section 5 and memory): only focused tests written by the named test agents (`functional-test-reviewer`, `e2e-runner`, `tdd-guide` as test engineer where a unit seam needs it); the coordinator never runs tests; no full suite, no CI, no CI-mimicking containers, no analyzer as an epic gate, no mutation runs; a green test is evidence only when its assertion would fail if the guarded behaviour broke (the column "Fails when" states which assertion that is, in words, for every row; no mutation was run to prove it).

### 1.2 Levels

| Level | Meaning | Share planned (see counts, section 9) |
|---|---|---|
| U | Pure Dart: mode state machine, migration table, window-size class function, week and today windows, sport groups, source labels, formatters, token contrast function, ARB parity | 10 percent |
| W | One screen or component pumped with fakes, a set `tester.view.physicalSize` (device pixel ratio 1.0), text scale, locale and `TargetPlatform` | 65 percent |
| I | Router plus shell plus providers; app restart simulated by a new `ProviderScope` over the same fake store; live resize across the rail boundary; bind, account-switch and sign-out sequences with completers | 20 percent |
| K | Source scans: no permission or location import (AC-SH-6), no `Color(0x` or `Colors.` (AC-A11Y-8), no gesture-only handlers (AC-KB-6), no `Cupertino*` (AC-FAM-2), ARB word-ban (AC-SRC-5, AC-RET-1) | 3 percent |

### 1.3 Conventions

1. Test id and name. A test that realises a contract criterion carries the contract id as the first token of its test name (design 8.2), for example `AC-WS-3/ru/1100x800/scale1.15`. Rows with several entries state the suffix scheme in Config. Rows of this plan are named by the contract id plus a lower-case letter when one AC has several rows (`AC-CH-5a`). Added tests use `DT-<story number>-<seq>`; for S03-0 the number is `0` (`DT-0-1` to `DT-0-6`), for S03-01 it is `01`.
2. One id, one story. The owner of an AC is the story in the coverage table of design 1.7; a test row appears once, under its owner (reverse check in section 10). An AC whose behaviour another story also exercises is not duplicated; the other story only needs to keep it green.
3. Files. Folders under `mobile/test/` follow design 8.2: `mobile/test/features/modes/`, `mobile/test/features/activity/{data,state,config}/`, `mobile/test/shared/widgets/`, `mobile/test/router/`, `mobile/test/android/` and `mobile/test/features/account_deletion/`. File NAMES are PROPOSED by this plan; one owner per test file (the test agent of the epic). Layout:
   - EP-0: `mobile/test/features/activity/journal_availability_test.dart` (design 4.4), `mobile/test/android/backup_rules_test.dart` and `backup_exclusion_test.dart` (existing, updated), `mobile/test/features/activity/config/activity_wiring_flag_matrix_test.dart` (existing, updated), `mobile/test/features/modes/mode_flags_test.dart`
   - EP-1: `mobile/test/features/modes/mode_state_test.dart`, `mode_migration_test.dart`, `mode_onboarding_hook_test.dart`; `mobile/test/features/account_deletion/` (the wipe test extended for DT-01-20 and DT-01-24)
   - EP-5 foundations: `mobile/test/shared/widgets/window_size_test.dart`, `hud_primitives_extension_test.dart`, `nav_config_test.dart`, `hud_side_rail_test.dart`, `adaptive_surface_test.dart`, `dock_strip_test.dart`; `mobile/test/features/workouts/active_session_status_test.dart` (status, owner, driven timers); `back_navigation_test.dart` (existing, run unchanged; path found with Glob, design 8.2 puts router tests under `mobile/test/router/`)
   - EP-2: `mobile/test/features/modes/mode_chooser_test.dart`, `mode_questions_test.dart`, `mode_switcher_test.dart`, `record_sheet_test.dart`
   - EP-3: `mobile/test/features/home/home_mode_lens_test.dart`, `mobile/test/features/activity/data/activity_aggregates_test.dart`, `mobile/test/features/activity/state/activity_dashboard_providers_test.dart`, `mobile/test/features/progress/progress_dashboard_test.dart`
   - EP-4: `mobile/test/features/modes/sources_panel_test.dart` (the Sources page lives in `features/modes/pages/`), `mobile/test/features/activity/sign_out_warning_test.dart`
   - EP-5 closing: `mobile/test/shared/widgets/keyboard_pointer_test.dart`, `mobile/test/s03_conformance/*.dart` (accessibility, text scale, family, regression, static)
   - Conditional: `mobile/test/shared/widgets/pushed_page_frame_test.dart` (S03-19), `mobile/test/core/notifications/reminder_tap_routing_test.dart` (S03-20; the notification folder is UNKNOWN in design 9.2, lane L11)
4. Fakes and seams (design 8.3 and 8.4; test code only, no test-only product paths). The test agents write: `FakeModeStore` (in-memory; a switch that makes writes throw; a write spy recording every call with a sequence number so ordering against navigation can be asserted; an optional read latency), `FakeJournal` (`list()`, `put` upsert by session id, a throwing `list()`, an opener spy counting calls, an injected availability `open` or `notEnabled` or `failedToOpen`), `FakeClock` and `FakeZone` (functions, two UTC offsets, DST case), `FakeSetTimer` and `FakeRestTimer` (overrides of `setTimerProvider` and `restTimerProvider` with chosen states and `endsAt`), `FakeScheduleProvider`, `FakeScanAccess`, `MockPermissionChannel` (counts calls), `MockAccessibilityChannel` (captures announce messages), `MockSystemChromeChannel` (records preferred-orientation calls), `MockHapticChannel`. Harness helpers: `pumpAt(size, scale, locale, platform)`, a router harness that records the current location, and a `fixedRailMeasurer(width)` helper that overrides `railLabelMeasurerProvider` (design 2.6, lane L4a) with a stub returning that width.
5. Determinism. No wall clock in assertions, no random, no network, no shared mutable fixture between tests, no order dependence. Every journal fixture is built in the test; the synthetic corpus of S02 is not reused except as a source of valid sessions (PROPOSED).
6. "No write" assertions use a write spy that would record a write if one happened (design 8.7). "Order" assertions compare real `Rect` positions or semantics traversal, never widget list order. `notEnabled` tests force the state by override and are never satisfied by the default build (which is `open` after S03-0).
7. Rail form tests compute the expectation from the contract rule (240 dp when the window is 1200 dp or wider, or when the widest of the five upper-cased labels plus 16 dp exceeds 96 dp; else 96 dp), print the measured width on failure and never hard-code 96 dp for a case whose measurement exceeds the threshold (AC-WS-3; design 8.7).
8. Word-ban. The AC-SRC-5 ban matches the exact phrases "merged", "deduplicated" and "synced with Health Connect" (inflected forms), never the stem "merge", because the required English text of `sourcesDedupNote` contains the word "merge" (design 6.8 note).
9. Copy expectations. Where a row quotes English copy it is the contract text; the Russian text is PROPOSED in design 6 and the test reads the production localisation, so a translation-pass change does not break a test unless a length budget or a key is violated.
10. K scan set (TP-4). Every K row scans a named set, not "the S03 files": `lib/features/modes/`, the new S03 files of `lib/shared/widgets/` (`window_size.dart`, `shell_layout.dart`, `shell_destinations.dart`, `hud/hud_side_rail.dart`, `shell_dock.dart`, `dock_widgets.dart`, `adaptive_surface.dart`, `app_shortcuts.dart`, `shell_back_button.dart`), `lib/features/activity/state/`, `lib/features/activity/data/activity_aggregates.dart`, `lib/features/activity/widgets/sign_out_warning_sheet.dart`, `lib/features/workouts/state/active_session_status.dart`, and the S03 additions in `lib/features/home/` and `lib/features/progress/` (the file list of design 9.2 is the source; final list fixed in the findings). The scan set is resolved once by a helper; test DT-18-7 asserts a minimum file count, that the anchor files (rail, chooser, strip, Sources screen) are in the set and that no scanned directory is empty. ARB scans read a fixed list of key prefixes (`mode`, `home`, `progress`, `activity`, `source`, `sources`, `strip`, `rail`, `record`, `signOut`, `sportGroup`, `syncChip`, `nav`). A K test turns red when an anchor file leaves the set, or when a scan points at an empty directory. Applies to AC-A11Y-8, AC-KB-6, AC-SH-6b, AC-FAM-2k, DT-02-5, AC-A11Y-6b, AC-SRC-5k, AC-RET-1a and AC-RET-1b.
11. Real controllers for timer preservation (TP-2). Rows that claim "a running timer is not reset" (AC-WS-5, AC-SW-2, AC-ST-4, DT-01-7, DT-18-1) drive the REAL `SetTimerController` and `RestTimerController` with an injected clock and assert state equality AND that the clock still ticks. Fakes are used only for pure presentation rows (AC-ST-1, AC-ST-2, AC-ST-3). These assertions would turn red if a mode switch invalidated `setTimerProvider`; this is a statement about the assertion, no mutation was run.
12. Review decisions. Tests tagged RV-n guard the decision RV-n of the internal review (batch 1) recorded in the design section "Review disposition (internal review, batch 1)"; tests tagged TP-n answer the test-plan findings of the same review.

### 1.4 Per-epic order for the test agents (design 8.6, refined)

Each step: write all test files of the listed stories, then run the COMPLETE set of files written so far for that epic (all files, not a sample), record the exact command, head revision and result in the findings file. After the last epic run everything the agents wrote once more.

| Step | Epic (stories) and implementation lanes (design 9.2) | Agent (PROPOSED) | Findings file |
|---|---|---|---|
| 1 | EP-0 and EP-1 (S03-0, S03-01); lanes L1 (S03-0 only; S03-13 belongs to step 4) and L2 | functional-test-reviewer (units: tdd-guide) | `S03_TEST_FINDINGS_EPIC0_1.md` |
| 2 | EP-5 foundations (S03-02 to S03-07); lanes L3 (S03-03, S03-02), L4a (S03-04, S03-05), L4b (S03-07, dock and `ActiveSessionStatus`), L5 (S03-06, adaptive surface) | functional-test-reviewer | `S03_TEST_FINDINGS_EPIC5A.md` |
| 3 | EP-2 (S03-08 to S03-11); lane L6 (needs L2, L5, L10 back-button interface and, for S03-10 and S03-11, the L4b strip) | functional-test-reviewer; e2e-runner for the integration rows | `S03_TEST_FINDINGS_EPIC2.md` |
| 4 | EP-3 and EP-4 (S03-12 to S03-16); lanes L7 (S03-12), L8 (S03-14), L9 (S03-15, S03-16) and L1 (S03-13) | functional-test-reviewer | `S03_TEST_FINDINGS_EPIC3_4.md` |
| 5 | Keyboard and pointer (S03-17); lane L10 (and the `AppShortcuts` splice of L2 in `main.dart`) | functional-test-reviewer | `S03_TEST_FINDINGS_EPIC5B.md` |
| 6 | Conformance (S03-18); fixes by lane L12 only after all other lanes close; if built S03-19 (router part in lane L5, serial after S03-06) and S03-20 (lane L11) | functional-test-reviewer and e2e-runner | `S03_TEST_FINDINGS_EPIC5C.md` |
| 7 | Final run of every file written in steps 1 to 6 | both | `S03_TEST_FINDINGS_FINAL.md` |

This order is design 8.6 refined with the lanes of design 9.1 and 9.2: lane L4 no longer exists (it is L4a and L4b); `app_router.dart` is owned by lane L5 alone; `hud_scaffold.dart` by L4a alone; fixes forced by S03-18 are made by L12 one file set at a time. A test failure found in step n is reported to the owning lane, never fixed in a file of another lane; after an L12 fix the agents re-run the whole file set of every step whose files the fix touched.

Rows in earlier steps that need a control built in a later story carry the tag `RUNS-AFTER S03-nn` and are written when that story lands; they are not skipped. Checked against the lane order of design 9.1: every RUNS-AFTER target lands in the same step or an earlier one than the step that runs the entry, with these placements: rail destinations and `shell.rail.record` entries (AC-KB-3, AC-WS-4, AC-WS-10, AC-WS-11) after S03-05 and S03-07, both in step 2; chooser-card and sheet-row entries (AC-KB-3, AC-KB-4, AC-LS-8b, DT-08-4) after S03-08 and S03-10, step 3; the `home.modeChip` entries (AC-KB-3 chip, AC-SW-1, AC-LS-8a) after S03-12, step 4 (S03-10 only supplies the hook point, so the S-3 tests of step 3 open the surface from a test host); the sign-out surface entry (AC-LS-8c) after S03-16, step 4; the Record popover entry (AC-WS-7c) after S03-11, step 3; the Record shortcut entry (AC-WS-7e) after S03-17, step 5. Rule (TP-3): the step that lands a RUNS-AFTER entry also runs the file the entry was added to, so the commands of steps 3, 4 and 5 in 9.2 list those earlier files; each step's findings file lists every file that received an entry during that step.

### 1.5 Focused commands

FACT (S02 findings): tests run from the Flutter root `mobile/` with `flutter test --timeout 60s <explicit file paths>`; a directory path is allowed for a directory the agents own (S02 used `test/features/activity`). The project-pinned Flutter executable path is UNGROUNDED in design 8.5 (open item in 8.5 table B): the S02 agents used the bare `flutter` name in the findings; the coordinator memory warns that bare interpreters can resolve to a sibling venv, so the agent must log the resolved `flutter --version` path with the result). Commands are listed per epic in section 9.2. Forbidden: the whole `mobile/test` tree, CI-mimicking Docker, analyzers as a gate, mutation runs.

## 2. EP-0 and EP-1 tests (journal, mode state)

Columns of every test table: Id | AC (contract id, or "none" for a design test) | Lvl | N | Sev | Config (window WxH, text scale, locale, platform) | Steps (precondition and action) | Expected (exact keys and values) | Fails when (the assertion that turns red if the behaviour breaks).

### 2.1 S03-0 Local journal opens in the default build (EP-0)

The contract has no AC for S03-0 (design gap DD-2); the fourteen design tests below (DT-0-1 to DT-0-14) are the full set. File: `mobile/test/features/activity/journal_availability_test.dart` (design 4.4); DT-0-6 to DT-0-8 live in `mobile/test/android/backup_rules_test.dart` and `backup_exclusion_test.dart`. Flags are overridden through `activityFlagsProvider` with an explicit `ActivityFlags(...)`; availability is read from `journalAvailabilityProvider` (design 2.1 item 3, 4.3). Plan ids are the ids of record; the design 1.9 citations follow them. Bind retry state machine (design 2.1 item 3, one machine for automatic and manual attempts: single flight; a manual attempt never moves the automatic deadline; success cancels the timer and resets the index; `GaveUp` has no automatic loop and a manual failure starts none; a new auth value cancels the timer; `failedToOpen` has no automatic loop): DT-0-5 and DT-0-11 to DT-0-14. Regression guard of the controller refactor in `activity_wiring.dart`: the existing `mobile/test/features/activity/repository/activity_journal_binding_retry_test.dart` is part of the EP-0 set, runs in step 1 and must stay UNCHANGED.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| DT-0-1 | none | I | 1 | H | `ACTIVITY_CLOUD_STREAMS` false (default); fake journal directory; opener spy | Build the app wiring with default providers and no availability override; read the availability provider | Availability equals `open`; opener spy called exactly once; recovery ran once | the default build still leaves the journal unopened (availability `notEnabled`, spy count 0) as in the S02 behaviour |
| DT-0-2 | none | I | 1 | H | flag false and flag true (two entries inside one test is not allowed: run as two `ProviderScope`s in sequence) | With flag false resolve the sync repository, uploader, tombstone push and conflict-card providers; spy on network and upload fakes; repeat with the flag true | With the flag false each cloud provider resolves to its inert flag-off form and the upload and network fakes record zero calls while the journal is `open`; with the flag true the same providers are the live ones; the journal availability is `open` in both | opening the journal also switched on a cloud piece (non-zero upload or network calls with the flag false), or the cloud pieces vanished with the flag true |
| DT-0-3 | none | I | 1 | H | opener throws; second sub-case recovery throws | Override the opener to throw on open, then on recovery; read availability | Availability equals `failedToOpen` in both cases; no exception reaches the zone error handler; app start continues | a throwing open crashes start-up or is reported as `open` or `notEnabled` |
| DT-0-4 | none | I | 1 | H | override forcing `notEnabled`; default scope | Pump two scopes: one with the `notEnabled` override, one default | The override scope reads `notEnabled` and a dashboard widget in it shows no error and no retry; the default scope reads `open` (guard of design 8.7: the default build must not satisfy a `notEnabled` test) | the override is ignored, or the default build ever returns `notEnabled` |
| DT-0-5 | none (retry rules 1 and 7, rewritten) | I | 1 | H | availability `failedToOpen` (the journal object could not be opened); open and bind spies with completers; `activityBindRetryTimerFactoryProvider` replaced by the fake timer factory | Call `retryNow()`; while the attempt is pending call it again (double tap); let it fail; advance the fake clock by 10 minutes; then call `retryNow()` once more and let it succeed | SINGLE FLIGHT: after the double tap the open spy and the bind spy each have count 1 and busy is true while pending, false after completion; the failed attempt leaves `failedToOpen` and the fake factory has ZERO armed timers (rule 7: `failedToOpen` has no automatic loop; this clause applies to `failedToOpen` only, NOT to the bind schedule, see DT-0-11 to DT-0-14); the later explicit retry gives `open` with count 2 | a double tap runs two attempts, the busy state is never left, or `failedToOpen` starts an automatic loop |
| DT-0-6 | none (RV-13, rewritten) | I | 1 | H | real temp directory; faked `PathProviderPlatform.getApplicationSupportPath` returning it; the three XML files `backup_rules.xml` and both sections of `data_extraction_rules.xml` read from the repository | Call `fileActivityJournalFactory()(activityJournalScopeId('u1'))`, start it, put one session, list every top-level entry of the support directory | Every top-level entry (`activity_journal` and any other written entry) has a `domain="file"` exclude with exactly that name in all three XML sections; no file exists outside the excluded set after the put | the XML names `journal` while the code writes `activity_journal/...` (the defect found by the coordinator in RV-13), or a new top-level directory is added without an exclude |
| DT-0-7 | none (RV-13) | K | 1 | H | `kActivityBackupExcludedDirs`, the factory root constant and the XML | Assert the factory and `kActivityBackupExcludedDirs` use one shared constant `activity_journal`; the three legacy names (`journal`, `sources`, `quarantine`) stay for `FileActivityJournal.openDefault`; the existing backup tests (`backup_rules_test.dart`, `backup_exclusion_test.dart`) are updated to 7 entries and run unchanged afterwards (run evidence in step 1) | Constant shared; legacy names still present; exact count assertions match 7 entries | two constants drift apart again |
| DT-0-8 | none (RV-13d) | K | 1 | H | default value of the local-journal flag (`ACTIVITY_LOCAL_JOURNAL`) and the XML | If the flag default is true, assert the `activity_journal` exclude exists in all three XML sections | The exclude is present whenever the default is on (the fix lands before the flip) | the default flip merges without the backup exclusion |
| DT-0-9 | none (RV-3, RV-10; F-40) | I | 1 | M | fake journal whose recovery report has `recoveredAbsent` 2 and `streamLost` 1; the companion bind-status Notifier of `core/wiring/activity_wiring.dart` | Bind for uid A, then call `retryNow()` after a forced failure | The bind status publishes `binding(A)`, then `bound(A)` with `recoveredAbsentCount` 2 and `streamLostCount` 1; after `gaveUp(A)` the counts are kept; `retryNow()` runs exactly one attempt | the recovery counts never leave the journal layer, so no screen can show the notice |
| DT-0-10 | none (design 2.1 item 2) | I | 1 | M | flag on (journal enabled), journal unbound (no signed-in uid yet); spies on the path provider and directory creation | Call `openActivityJournal()` and pump the app to the splash | Zero file or directory I/O happens before the bind; availability is `binding`, not `open` | start-up cost or an unbound journal touching disk |
| DT-0-11 | none (retry rule 2) | I | 1 | H | the existing fake timer factory behind `activityBindRetryTimerFactoryProvider`; a fake journal whose `bindUid` completes through completers (the test controls success or failure and counts calls); `retryNow()` of the companion bind-status Notifier | The first attempt fails, so the state is `WaitingRetry(0)` with the 5 s timer armed; advance 2 s; call `retryNow()` and fail it; advance to the ORIGINAL deadline (5 s after the first failure); fail that automatic attempt too | After the failed manual attempt availability is still `binding` and the timer deadline is unchanged; exactly one more (automatic) attempt runs at the original deadline (not at 2 s + 5 s); `bindUid` calls total 3 (initial, manual, automatic); the next armed delay is 15 s (index advanced by one, not by two) | a failed manual attempt disables, postpones or double-advances the automatic recovery |
| DT-0-12 | none (retry rule 3) | I | 1 | H | same fakes as DT-0-11 | The first attempt fails (timer armed); call `retryNow()` and let it succeed; advance past the old deadline and by 10 minutes; later force a new failure for a NEW auth value | The pending timer is cancelled (the fake factory reports zero armed timers, no further `bindUid` after the success); availability is `open` only because `boundUid == authUid`; the retry index is reset (the first retry delay for the new failure is 5 s again) | a success leaves a stale timer that rebinds later, or the index is not reset |
| DT-0-13 | none (retry rule 4) | I | 1 | H | same fakes; every attempt fails | Let the initial attempt and the five automatic retries (5 s, 15 s, 60 s, 5 min, 5 min) fail; advance the fake clock by 24 hours; tap `retryNow()` once (and double tap in a second step); fail it; then tap again and succeed | `gaveUp(uid)` after the sixth failed attempt; during the 24 hours zero automatic attempts; one tap is exactly one attempt (a double tap is one); a failed manual attempt keeps `gaveUp` and arms NO timer (no new automatic loop); the successful one gives `open` | the automatic schedule keeps running after giving up, a manual failure restarts it, or a double tap starts two attempts |
| DT-0-14 | none (retry rule 1) | I | 1 | H | same fakes; the manual attempt's completer is held pending | From `WaitingRetry(i)` call `retryNow()` (pending); advance to the automatic deadline while it is still in flight; then fail the manual attempt and advance by the same delay again | The due automatic timer does nothing while the manual attempt is in flight and is re-armed with the SAME index and delay; `bindUid` never has two calls in flight (maximum concurrency 1); after the manual failure the re-armed timer runs exactly one automatic attempt after the same delay (no lost retry, index not consumed twice) | two concurrent `bindUid` calls, or the retry is lost because the timer was consumed by the skipped firing |

### 2.2 S03-01 Mode state (EP-1)

Files: `mobile/test/features/modes/mode_state_test.dart`, `mode_migration_test.dart`, `mode_onboarding_hook_test.dart`. Store, key `activity.mode.v1.<uid>`, the three-way read result, `initIfAbsent(InitSource)` and the uid and wiped-uid guards are final in design 2.2 and 5 (table A of section 8.5).

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-CH-8a | AC-CH-8 | I | 1 | H | 360x800, `ru`; `FakeModeStore` with absent field; profile onboarded | Start the app (new `ProviderScope`), pump to the first Home frame | Store holds `chooserStatus=migrated` and `selectedMode=train` before the first Home frame; `modeChooser.*` keys absent; router location `/home` | an onboarded Phase 1 user is forced into the chooser or the status is not written |
| AC-CH-8b | AC-CH-8 | U | 1 | H | none | Run the start-up migration on a store with an absent field and a profile NOT onboarded | `chooserStatus` stays absent; write spy has zero calls | a not-onboarded user is migrated (would skip the new-account chooser) |
| AC-CH-8c | AC-CH-8 | I | 1 | H | 360x800; absent field; write spy with sequence numbers; router log with sequence numbers | Complete onboarding finish (`_submit` success) | Write of `chooserStatus=pending` has a lower sequence number than the router event to `/home` | the navigation happens before the write (write ordering broken: a kill between them loses the chooser) |
| AC-CH-8d | AC-CH-8 | I | 1 | H | 360x800; store already holds `migrated` or `resolved` | Finish onboarding from `/onboarding/edit` | Write spy has zero calls; status unchanged | an edit of the profile resets the chooser state |
| DT-01-1 | none | U | 1 | H | `FakeModeStore` loaded with corrupt values: unknown mode string, wrong JSON type, truncated JSON (three sub-cases as three loads in one unit test is allowed: pure function) | Load state from each corrupt value | No exception; `selectedMode=train`; `chooserStatus` is a valid enum value; the store read reports `unreadable(corrupt)` and the migration and onboarding hook do nothing; ZERO writes (RV-2); never both chooser and intro card | a corrupt stored value crashes start-up, selects an unknown mode, or is overwritten |
| DT-01-2 | none | U | 1 | H | stored `selectedMode` equal to `ride` or `explore` (unavailable) | Load state | `selectedMode` is coerced to `train` in memory only; no `modeChanged` event; the write spy records ZERO writes (RV-2: the stored value is not rewritten) | an unavailable mode becomes the active lens |
| DT-01-3 | none | U | 1 | M | store read throws; store missing | Load state in both cases | A missing store reads `missing` and the migration decides as in AC-CH-8; a read that throws is `AsyncError` handled as in DT-01-19 (default state, no writes); no exception reaches start-up | a missing or unreadable store blocks start-up |
| DT-01-4 | none | U | 1 | H | availability table of contract 4.1 and a test table with `ride` available | `setMode` for each of the four modes with the real table, then with the test table | Real table: `train` and `body` accepted; `ride` and `explore` rejected with no write and no event. Test table: `ride` accepted (one-place change for S05 and S06) | the availability table is not the single gate, so S05 needs a code change in several places or a coming-later mode can be selected |
| DT-01-5 | none | U | 1 | H | event spy | Select `body`, then `body` again, then `train`; then a store whose write throws | Events: `modeChanged(train,body)` once, nothing for the repeat, `modeChanged(body,train)` once; with a throwing write the in-memory mode still changes and the event is emitted once | duplicate events, or an event for selecting the current mode, or a failed write blocks the session lens |
| DT-01-6 | none | U | 1 | H | two account ids A and B on one fake preferences backend; account-scoped key per design 5.2 (DD-6 default) | A resolves with `selectedMode=body`; sign out; sign in as B (new account); sign out; sign in as A | B starts absent and follows the new-account rule; A returns with `body` and `resolved` intact; no field of A is readable under B | state of one account leaks into another account on the same device |
| DT-01-7 | none | I | 1 | H | 360x800; REAL `SetTimerController` with an injected clock (TP-2), started by account A | Switch to account B through the app account-switch path (RV-4: owner uid captured at start); advance the fake clock 5 s | The mode store never writes to a timer (spy zero calls); the timer keeps ticking exactly as the pre-S03 account switch leaves it (design 2.6: S03 never touches the timers); mode of B is read from B's state; the strip is hidden for B (see DT-07-8) | mode logic resets or edits a running timer on account change (breaks R-M1) |
| DT-01-8 | none | I | 1 | H | `FakeModeStore` with a delayed write (completer) | Tap Continue in the chooser; before completing the write, pump | Router location is still the chooser; after completing the write the location becomes `/home` | navigation is not awaited behind the write (contract 4.2: writes are awaited before the navigation they precede) |
| DT-01-9 | none | I | 1 | H | stored `body`; store read delayed by 50 ms (fake async) | Pump the first frame, then settle | No frame shows the TRAIN lens order (`home.section` order of `train`) before the BODY order; either a loading frame or the final BODY order | a flash of the wrong mode (contract 4.2: restore before the first Home frame) |
| DT-01-10 | none | U | 1 | M | store states `migrated`, `resolved`, `pending` | Run the start-up migration twice on each | `migrated` stays `migrated`; `resolved` stays `resolved`; `pending` stays `pending`; absent becomes `migrated` once | a second start regresses `resolved` to `migrated` or `pending` (intro card shown twice) |
| DT-01-11 | none | U | 1 | M | answers per mode | Set BODY answer unanswered, then skipped, then answered(food), then skipped again; change mode between steps | Three-state pattern holds; `skipped` is never cleared by app start; answers are per mode and survive a mode change | a skipped question is asked again, or an answer of one mode overwrites another |
| DT-01-12 | none (RV-1) | I | 2 | H | `FakeModeStore` and a fake profile repository; the profile flips to onboarded DURING the onboarding submit; entries `/migrationFirst`, `/hookFirst` (the two interleavings forced with completers) | Run `ModeNotifier.initIfAbsent` from the migration event and from the onboarding hook in each order | Final `chooserStatus` is `pending` in both orders; exactly one write; the second caller sees the field set | the race gives `migrated` to a brand-new user (no chooser) or writes twice |
| DT-01-13 | none (RV-1) | I | 1 | H | fake profile whose FIRST loaded value for the uid already has `hasCompletedOnboarding == true` | Cold start | `chooserStatus=migrated`, one write, no chooser | an upgrader is forced into the chooser |
| DT-01-14 | none (RV-1) | I | 1 | H | fake profile whose first loaded value is NOT onboarded; later in the same process the profile flips to onboarded | Emit the flip | The migration does NOT write (the hook owns that transition); write spy zero calls from the migration | a mid-session profile change migrates a new user |
| DT-01-15 | none (RV-1, RV-16) | I | 2 | H | `/hookThrows` (store write throws), `/unmounted` (widget disposed during the awaited `modeStateProvider.future`) | Finish onboarding | `/hookThrows`: navigation to `/home` still happens; a log entry with a fixed message, a reason code and the exception type only (no message, path, key or id). `/unmounted`: no navigation call after the await (`context.mounted` checked) | the hook blocks `/home`, uses a disposed context, or logs content |
| DT-01-16 | none (RV-2) | U | 2 | H | `/corrupt` (non-parseable string), `/v2` (string with `v:2`) in the fake store; write spy | Start-up and migration with a missing-profile and with an onboarded profile | ZERO writes after start-up and migration; no chooser push; a content-free reason code is logged | an unreadable value is overwritten (user choice lost) |
| DT-01-17 | none (RV-2) | I | 1 | H | stored `v:2` | The user selects `body`, then restarts the scope | The in-memory mode is `body` for the run; the write spy has zero calls; after restart the stored value is untouched (read-only for the whole run) | a newer-version value is downgraded |
| DT-01-18 | none (RV-2) | I | 1 | H | stored corrupt value | Start (no write), then the user chooses a mode, then answers a question | Writes occur only after each explicit action; the corrupt value is replaced then | start-up replaces it silently, or an explicit action cannot repair it |
| DT-01-19 | none (RV-2) | I | 1 | H | the store read completes with an error (`AsyncError`) | Start and pump to Home | Default state; no chooser push; zero writes | a read error crashes start-up or shows the chooser |
| DT-01-20 | none (RV-14) | I | 1 | H | `selectMode(body)` write in flight (completer); then `wipe(uid)`; then the migration is re-run | Release the write after the wipe | The key is absent afterwards (the wiped uid is refused) | a late write resurrects state after sign-out and deletion |
| DT-01-21 | none (RV-18a) | W | 1 | M | 360x800; a build counter on `FitnessApp.build` | Call `selectMode` three times | The counter does not change (the app root watches only the warm-up `Provider<void>`) | every mode choice rebuilds `MaterialApp` |
| DT-01-22 | none (F-4) | I | 2 | H | fake profile repository; `/neverLoads`, `/arrivesLate` (first value onboarded after 3 s of fake time) | Start with a `missing` store | `/neverLoads`: status stays `absent`, zero writes, no chooser push, no intro card; `/arrivesLate`: when the first profile value (onboarded) arrives, the migration writes `migrated` once | the migration decides before the profile is known, or a user is sent to the chooser without a profile |
| DT-01-23 | none (F-9) | I | 1 | H | `FakeModeStore` write spy; the notifier loaded for uid A | Sign in as B, then call `selectMode(body)` on the stale reference before the notifier rebuilds | The call returns `saveFailed`; the spy has zero writes under A or B; after the rebuild B's state is B's own | a write lands under the wrong account |
| DT-01-24 | none (F-18) | I | 1 | H | the existing `DeviceLocalDataWipe` test harness (folder `mobile/test/features/account_deletion/`), a stored `activity.mode.v1.<uid>` key | `wipe(uid)` | Seeded keys: the departing account's `activity.mode.v1.<uid>` with a real value, and a SECOND account's key. After `wipe(uid)` the departing key is absent and the second account's key is still present with its value | account deletion leaves the mode key behind |
| DT-01-25 | none (design 5.4) | K | 1 | M | the K scan set (section 1.3 item 10) over `features/modes/` | Scan for `SharedPreferences` and any other storage API (secure storage, files, `AppSettings`) | The mode key is read and written only through `PrefsModeStore`; no other storage is used | the mode leaks across accounts through a device-wide setting, or lands in an unexcluded store |

Level and count for EP-0 and EP-1 after the closing pass: S03-0 14 (I 12, K 2), S03-01 33 (U 11, W 1, I 20, K 1); total 47 (batch 1: 36; revision 1: 21).

## 3. EP-5 foundation tests (window class, primitives, navigation list, rail, surfaces, dock)

A row with N above 1 is one parametrised group: its Config column lists the N parameter values and each value is one separate test entry named with the suffix shown (`/<value>`). Layout of sizes: "WxH" is logical dp with device pixel ratio 1.0.

### 3.1 S03-02 Window-size class and `ShellLayout` (file `window_size_class_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-WS-1a | AC-WS-1 | U | 1 | H | pure function; width table 599, 600, 839, 840 with height 800 | Call the class function for each pair (one table-driven unit test) | 599 compact; 600 medium; 839 medium; 840 expanded; short flag false for all | a boundary moves by 1 dp (off-by-one at 600 or 840) |
| AC-WS-1b | AC-WS-1 | W | 2 | H | `/700x420`, `/500x420` | Pump a probe widget under the real `tester.view` size and read the provider | 700x420: class medium, short true. 500x420: class compact, short true | height 420 is ignored (short flag false) or short changes the class |
| DT-02-1 | none | U | 1 | M | heights 479, 480, 481 at width 700 | Call the function | short true at 479; false at 480 and 481 ("under 480") | the short threshold is inclusive or at another value |
| DT-02-2 | none | W | 1 | M | width 599.5 and 839.5 (fractional, DPR 1.0) | Pump the probe | 599.5 is compact; 839.5 is medium (comparison on the unrounded logical width, lower end inclusive only for the exact boundary values) | fractional widths are rounded into the wrong class |
| DT-02-3 | none | W | 1 | M | live resize 360x800 to 700x900 to 1100x800 to 360x800 | Pump a consumer counting builds | Class sequence compact, medium, expanded, compact; one rebuild per class change, none for a resize inside one class | no update on resize, or a rebuild storm inside one class |
| DT-02-4 | none | W | 1 | M | provider override `expanded` with a 360x800 view | Pump a consumer | Consumer sees `expanded` (the override wins over the view; a documented seam) | the seam is not overridable, so every later layout test is forced onto real sizes |
| DT-02-5 | none | K | 1 | M | source scan of new S03 files | Scan for `MediaQuery.of(...).size.width`, `MediaQuery.sizeOf` and `LayoutBuilder` width comparisons with numeric literals 600 or 840 outside the class function file | Zero matches | a screen reads raw widths and drifts from the single class function (design: "no screen reads raw widths") |

### 3.2 S03-03 HUD primitive extensions (file `hud_primitives_extension_test.dart`)

All extensions are optional parameters; defaults must equal today. DT-03-1 rows compare against measurements recorded from the pre-change widgets (size, semantics flags, cursor) captured in the test as literals before the change is made (the test agent records them ONCE from the base head and commits them; the literals are never regenerated to make a failing test pass, TP-m2).

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-KB-3 | AC-KB-3 | W | 5 | M | 360x800 and 1100x800, `en`; entries: `/primitives` (HudButton, HudChip, HudSettingRow with `showFocusRing`), `/rail` (five destinations and `shell.rail.record`; RUNS-AFTER S03-05), `/modeChip` (`home.modeChip`; RUNS-AFTER S03-12), `/chooserCard` (RUNS-AFTER S03-08), `/sheetRow` (RUNS-AFTER S03-10) | Send a Tab key event to focus the control, find the ring decoration; then, in a fresh pump, tap the control with a pointer | After Tab: the focused node paints the 2 px outline (`showFocusRing` decoration found); after a pointer tap: not found | no ring on keyboard focus, or the ring also shows after a mouse tap |
| AC-KB-4 | AC-KB-4 | W | 3 | M | 1100x800, `en`, `TargetPlatform.macOS`; entries `/hoverEnabled`, `/disabled`, `/hoverNoChange` | Enabled `modeChooser.card.train` (RUNS-AFTER S03-08): mouse gesture hover; disabled control: hover; compare selection and semantics before and after hover | Enabled: `MouseRegion` cursor is `SystemMouseCursors.click` and the hover style applies; disabled: `SystemMouseCursors.basic`; hover changes no `isSelected` and no label | wrong cursor, hover on a disabled control, or hover that mutates selection or semantics |
| DT-03-1 | none | W | 4 | H | `/HudChip`, `/HudButton`, `/HudPanel`, `/HudSettingRow`; 360x800, `en` and `ru` text | Pump each with only its pre-S03 parameters | Rendered size, semantics flags, label, tap behaviour and cursor equal the values recorded from the base head; no new semantics node appears | a new default silently changes an existing screen (breaks AC-REG-3 and every Phase 1 flow) |
| DT-03-2 | none | W | 1 | M | 160 dp wide box, text scale 2.0, `ru` | Pump a chip with `maxLines: 1`, then one without | With the parameter: `didExceedMaxLines` is false only if the text fits, otherwise the test records the overflow handling the contract demands (ellipsis allowed only where the contract allows); without: today's behaviour | `maxLines` is ignored or changes the default |
| DT-03-3 | none | W | 1 | M | `HudButton` with `minHeight: 48`, and without | Measure with `tester.getSize` | With: height at least 48; without: the pre-S03 height | the 48 dp hit target of the Record pill is not met, or the default grew |

### 3.3 S03-04 Navigation list and bottom bar (file `nav_config_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-SH-1 | AC-SH-1 | U | 1 | H | pure list | Read the configuration list | Exactly five entries, paths `/home`, `/workouts`, `/scan`, `/progress`, `/profile` in that order, label keys `homeHome`, `navWorkouts`, `navScan`, `progressProgress`, `profileProfile` | a tab is added, removed, reordered or relabelled (breaks every Phase 1 flow) |
| AC-SH-2 | AC-SH-2 | I | 5 | H | 360x800; entries `/fromWorkouts`, `/fromScan`, `/fromProgress`, `/fromProfile`, `/onHome` (TP-m3: parametrised per tab); seam: the mocked `SystemNavigator.pop` platform channel records pop requests | Send system Back from each tab; then Back on `/home` | Back from a non-home tab lands on `/home` and the pop channel has zero calls; Back on `/home` records exactly one pop request | Back leaves the app from a tab, or `/home` swallows Back |
| AC-SH-3 | AC-SH-3 | W | 1 | H | 360x800; a 4-item test list injected | Pump the shell with the 4-item list | `shell.bottomBar` shows exactly 4 destinations in list order; tapping each reaches its path | the bar still has hard-coded five tabs |
| DT-04-1 | none | W | 1 | M | 360x800, `ru` and `en` | Pump the shell; read the bar container semantics; tap each of the five tabs | The container has the label `navMainLabel` ("Main navigation" / "Основная навигация") and is a container node; each tab navigates to its path and `HudNavBar.selectedIndex` equals its index | the container label is missing, or a tab navigates to a neighbour's path |
| DT-04-2 | none | W | 1 | M | list reordered in the test (Profile first) | Navigate to `/profile` | Selection derives from the path, not from a fixed index: the first destination is selected | selection is index-based and breaks if the list changes (contract 5.3: a later tab-set change is a one-place edit) |

### 3.4 S03-05 Side rail and presentation swap (file `side_rail_test.dart`)

Rail form rule (contract 10.4 and AC-WS-3): 240 dp when the window is 1200 dp or wider, or when the widest of the five upper-cased labels, measured with a `TextPainter` in the production nav-label style at the current text scale and locale, plus 16 dp, exceeds 96 dp; otherwise 96 dp. Labels in `ru`: Главная, Тренировки, Скан, Прогресс, Профиль.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-WS-2a | AC-WS-2 | W | 2 | H | `/360x800`, `/700x900`, `en` | Pump the shell on `/home` | `shell.bottomBar` found, `shell.rail` not found; at 700x900 the bar width is at most 560 dp | the bar is shown with the rail, or the bar stretches across a tablet |
| AC-WS-2b | AC-WS-2 | W | 3 | H | `/700x420`, `/900x400`, `/1100x800` | Pump the shell on `/home` | `shell.rail` found, `shell.bottomBar` not found | rail missing in the short or expanded window, or both navigations at once |
| AC-WS-3a | AC-WS-3 | W | 3 | H | font-measured entries (TP-1: under the default test font Ahem every label is wider than 96 dp, so these entries expect the extended form and are NOT evidence for the 96 dp form), 1100x800, `ru`, scales `/1.0`, `/1.15`, `/1.29` | Compute the expected width from the rule with a `TextPainter` in the same test; pump; read the width of `shell.rail`; scan for overflow | Width equals the computed form (96 or 240); no `RenderFlex` overflow; failure message prints the measured label width | the form is hard-coded, or a label overflows |
| AC-WS-3b | AC-WS-3 | W | 2 | H | 1100x800, `ru`, scale 1.0; `ProviderScope` override `railLabelMeasurerProvider` (`typedef RailLabelMeasurer = double Function(String label, TextStyle style, TextScaler scaler)`, `mobile/lib/shared/widgets/shell_layout.dart`, lane L4a) with a stub returning a fixed width for every label; entries `/seam70`, `/seam90` (TP-1). The default measurer is TextPainter-based; the project's tests load no real font (Ahem), so under the default measurer every label would be wider than 96 dp and the 96 dp form would never be reached | Override the provider with the stub (70 or 90) instead of measuring the font; pump; read the width of `shell.rail` | `/seam70` (70 + 16 = 86, not above 96): the rail is exactly 96 dp (compact form). `/seam90` (90 + 16 = 106, above 96): exactly 240 dp. No overflow | the 96 dp form is never reached (a test font making every label wide would hide it), or the threshold uses the wrong comparison |
| AC-WS-3c | AC-WS-3 | W | 1 | H | 1200x800, `ru`, scale 1.0 | Pump, read width | Exactly 240 dp whatever the measurement says | the 1200 dp rule is lost |
| AC-WS-3d | AC-WS-3 | W | 1 | H | 1100x800, `ru`, scale 2.0 | Measure; pump | The measurement selects the extended form (240 dp); if not the test fails and prints the measured width; no overflow | the measured-width rule does not fire under large text |
| AC-WS-4 | AC-WS-4 | W | 2 | H | RUNS-AFTER S03-07 for the `shell.rail.record` position assertion (TP-3: the step that lands it also runs this file), 1100x800, `/fiveItems`, `/fourItemList` | Pump; list the destination nodes in `shell.rail` and the position of `shell.rail.record` | Five destinations in the order of AC-SH-1 with `shell.rail.record` above them; the 4-item list gives 4 rail destinations | the rail is not built from the same list as the bar |
| AC-WS-5 | AC-WS-5 | I | 1 | H | 1100x800 to 360x800 and back; `/progress`; REAL `SetTimerController` started with an injected clock (TP-2); focus on the Progress destination | Resize twice; advance the fake clock by 5 s after each resize | Router location stays `/progress`; `HudNavBar.selectedIndex` is 3 and equals the rail selection; the timer state is equal by value after the swap and the elapsed value increased by 5 s after each advance (the clock still ticks); the focused destination is Progress in both presentations | presentation swap loses the route, selection, focus or a running timer |
| AC-WS-6 | AC-WS-6 | I | 2 | H | 1100x800; `/workout/:id`, `/settings` | Push each route from a tab | Neither `shell.rail` nor `shell.bottomBar` exists | shell chrome shows on a pushed route (contract F5) |
| AC-WS-8 | AC-WS-8 | W | 2 | M | 1100x800, `/endClearance`, `/startInset` ; Home with a tall list | Scroll Home to the end; read `Rect`s | Last child bottom is at most 24 dp plus bottom inset above the window bottom (no dock space); first child left is at least rail width + 12 + 16 from the start edge | content hidden under the rail, or dock padding reserved while the rail is shown |
| AC-WS-9 | AC-WS-9 | W | 2 | M | `/overflow` (800x360 then 360x800, every tab, `ru`), `/orientation` (mocked `SystemChrome` channel) | Pump each tab at both sizes; during pumping record channel calls | No overflow on any tab at either size; zero preferred-orientation calls | an orientation lock or a tab that overflows in landscape |
| AC-WS-10 | AC-WS-10 | W | 4 | H | RUNS-AFTER S03-07 for every assertion about `shell.rail.record` (TP-3), `ru`; `/640x360@1.0`, `/640x360@2.0`, `/800x360@1.3`, `/800x360@2.0` | Pump; Tab through the rail; arrow keys; scroll the rail list | No overflow; the five destinations and `shell.rail.record` are all reachable by Tab, the five by arrow keys; each destination hit height at least 48 dp; a destination focused by Tab is fully inside the window; `shell.rail.record` keeps the same top `Rect` while the list scrolls | a destination is unreachable or clipped in a short window |
| AC-WS-11 | AC-WS-11 | W | 2 | H | RUNS-AFTER S03-07 for the `shell.rail.record` semantics (TP-3), `/rail` at 1100x800, `/bar` at 360x800; `en` | `matchesSemantics` on the container and each destination; for rail also `shell.rail.record` | Container label "Main navigation" and container node; each destination is a button with a non-empty label, `isSelected` true only for the current tab, `hasTapAction`; `shell.rail.record` is a button labelled "Record" when idle | a destination announces as plain text, or two destinations are selected |
| AC-KB-2 | AC-KB-2 | W | 1 | M | 1100x800, `en` | Focus the first destination; send Down, End, Home, Enter, Tab | Down focuses the next destination, End the last, Home the first; Enter changes the router location; Tab leaves the rail to the content | arrow navigation or Enter is missing, or Tab traps focus in the rail |
| AC-KB-9 | AC-KB-9 | U | 2 | M | token level, light and dark `HudTokens`; entries `/ratios`, `/exception` | Compute contrast with the contrast function from token values (no pixels) | Inactive ink over the rail surface at least 4.5:1, selected ink at least 4.5:1, accent dot at least 3:1 in both themes; if the literal bar ink is kept the recorded 4.40 exception value is asserted and must not worsen | the rail ink contrast falls under the stated ratios (token-level only, section 8.4) |
| DT-05-1 | none | U | 1 | M | label widths 79.9, 80.0, 80.1 dp (rule: label width + 16 > 96) | Call the form function with a stub measurer | 80.0 gives compact (96); 80.1 gives extended (240) | the threshold is off by a unit |
| DT-05-2 | none (TP-1 guard) | U | 1 | H | the set of all AC-WS-3 cases (3a, 3b, 3c, 3d) recorded by a shared helper | After the cases ran in the same file, assert the set of resolved rail widths | The set contains both 96 and 240 | every case resolved to the same form (the 96 dp branch is untested) |
| DT-05-3 | none (RV-6) | W | 2 | H | 1100x800 with a tab page holding a stateful marker (a `ScrollController` offset of 300 and `TextField` text "abc"); entries `/across840` (1100x800 to 700x900), `/acrossShort` (700x900 to 700x420) | Resize across the boundary and back | The same `State` object instance (identity) and the same offset and text after each change; the router location unchanged. Run evidence: `back_navigation_test.dart` unchanged (step 2 command) | the presentation swap rebuilds the page element tree and loses scroll position and typed text |
| DT-05-5 | none (RV-18c) | U | 1 | M | the DEFAULT measurer behind `railLabelMeasurerProvider` wrapped by a counting spy on the TextPainter call (the stub is not used here) | Request the rail form for 20 successive window widths with one (locale, text scale, font family, label set) key, then change the key (for example the text scale) | The underlying measurement runs once per key (twice in total) | measurement is re-run per pixel of a resize |
### 3.5 S03-06 Adaptive surface (file `adaptive_surface_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-LS-8a | AC-LS-8 | W | 3 | H | `/360x800`, `/700x900`, `/1100x800`; `en` | Open S-3 from `home.modeChip` (RUNS-AFTER S03-12; before that, from a test host with the same anchor) | 360x800 bottom sheet; 700x900 bottom sheet of at most 560 dp; 1100x800 `modeSwitcher.popover` whose rectangle lies inside the window and below `home.modeChip` | wrong surface for the class, or a popover that leaves the window |
| AC-LS-8b | AC-LS-8 | W | 2 | M | `/700x900`, `/1100x800` | Open the Coming-later sheet from the chooser card `ride` (RUNS-AFTER S03-08) | Centred dialog, width at most 480 dp | the dialog fills the screen or is not centred |
| AC-LS-8c | AC-LS-8 | W | 2 | M | `/700x900`, `/1100x800`; RUNS-AFTER S03-16 | Open `signOut.warningSheet` | Centred dialog at most 480 dp | sign-out surface wrong for the class |
| AC-LS-8d | AC-LS-8 | W | 1 | H | 1100x800; write spy | Open the popover and the dialog in turn; press Esc | Each closes; zero writes to every fake store; focus returns to the opening control | Esc writes state or leaves focus on a removed node |
| AC-WS-14a | AC-WS-14 | W | 1 | M | `disableAnimations` true; 360x800 | Open S-3 and S-5, each with a single `pump` (no `pumpAndSettle`) | Both are in their final state after one pump | animations still run under reduced motion |
| AC-WS-14b | AC-WS-14 | W | 1 | M | `disableAnimations` true; resize 360x800 to 1100x800 with S-3 open and scrolled | Resize and pump | The surface changes from bottom sheet to popover, focus remains on the surface title, the sheet scroll offset is preserved, one instance only | the open surface closes or loses focus on resize |
| AC-A11Y-6a | AC-A11Y-6 | W | 1 | M | `MediaQuery(disableAnimations: true)` | Read `context.hudMotionDuration(d)` as used by the new widgets; call `pumpAndSettle` on an open surface | Duration equals the documented reduced or zero value of `hud_tokens.dart`; `pumpAndSettle` returns at once | a new widget bypasses the helper with a hard-coded duration |
| AC-A11Y-6b | AC-A11Y-6 | K | 1 | L | S03 files | Scan for indeterminate `CircularProgressIndicator` and `LinearProgressIndicator` | Zero matches (determinate ones are allowed) | a looping spinner is introduced (contract: nothing loops) |
| DT-06-1 | none | W | 1 | M | 1100x800 with the anchor near the right and bottom edges (a probe anchor) | Open the popover | The popover `Rect` lies fully inside the window in every anchor position | a popover is clipped at a window edge |
| DT-06-2 | none (RV-9) | W | 2 | H | S-3 open from `home.modeChip`; entries `/across600` (590x800 to 610x800), `/across840` (830x800 to 850x800) | Select a row focus, resize across the boundary | The surface is still open (re-placed live as bottom sheet, popover or dialog by the new class), same selection and same focus | the surface closes or loses selection when the placement changes |
| DT-06-3 | none (RV-9) | I | 1 | H | S-3 open; router log; open-surface depth counter exposed by the component | System Back | The surface closes; depth returns to 0; the route is unchanged | Back pops the page under the surface |
| DT-06-4 | none (RV-9) | I | 5 | H | S-3 open; entries `/back`, `/scrim`, `/esc`, `/programmatic`, `/accountChange` | Close by the named path | Depth is 0 after each; a second open works | a leaked depth counter makes later surfaces refuse to open |
| DT-07-8 | none (RV-4) | I | 1 | H | `SetTimerController` started as uid A through the real start path (owner captured at start); auth switched to B without clearing the timers | Pump `/home` and `/workouts` | No `shell.dock.strip`, no `shell.dock.recordPill` for B; the destination and owner are cleared by the status listener; the timers themselves are untouched (state equal and still ticking). The test is built so that it fails if `ownerUid` were read from the current auth | account B sees or can open account A's running session |
| DT-07-9 | none (RV-8) | W | 1 | H | REAL `RestTimerController` with an injected clock and the status timer factory seam; no manual rebuild, no provider poke | Advance fake time through `endsAt`, then through `endsAt + 10 min` | The strip text changes to `stripRestDone` at `endsAt` and the strip is gone after 10 minutes | the strip never changes state without a user action |
| DT-07-10 | none (RV-8) | U | 1 | M | the timer factory seam with a spy | Start, pause, resume, dispose the provider | One-shot timers are re-armed on each state change and cancelled on dispose (zero pending timers) | leaked timers keep the test or the app alive |
| DT-07-11 | none (RV-18e) | W | 1 | M | 360x800 Home scrolled; idle to running | Show the dock | The last child's `Rect` moves by a continuous animated padding (or immediately by the dock height with reduced motion), never above the strip, and content already visible does not jump upward by more than the dock height | content jumps when the dock appears |
| DT-07-12 | none (F-13) | U | 1 | M | `setTimerProvider` and `restTimerProvider` read in a container | Read the provider, drop all listeners, pump a microtask, read again | The same controller instance (neither provider is auto-dispose); fails if either is declared `autoDispose` | the strip silently loses a running timer between listeners (contract F23 relied on) |
| DT-07-13 | none (F-13, R8, behavioural twin of DT-07-12) | I | 1 | H | REAL `SetTimerController` and `RestTimerController` with an injected clock, started on `/workouts`; 360x800 then 1100x800 | Visit all five tabs, rebuild every shell page (hot-swap each tab page, resize across the rail boundary, open and close S-3 and S-5), advance the fake clock 5 s each time | The same controller instances (identity) and still ticking; fails if either provider disposes when no page listens | a rebuild of a shell page silently resets a running timer |
### 3.6 S03-07 Dock: Record pill, Recording strip, rail Record slot (file `dock_strip_test.dart`)

Fakes: `FakeSetTimer` with `{phase, running}`, `FakeRestTimer` with `{state, endsAt}` and a fake clock. Routes are the five tab paths.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-ST-1 | AC-ST-1 | W | 1 | H | 360x800, idle timers; loop over five paths | Pump each tab | `shell.dock.recordPill` on `/home`, `/workouts`, `/progress`; not on `/scan`, `/profile`; `shell.dock.strip` nowhere | the pill is on the wrong tab or a strip shows when idle |
| AC-ST-2 | AC-ST-2 | W | 1 | H | 360x800; set timer `{phase: work, running: true}`; five paths | Pump each tab | `shell.dock.strip` on all five tabs; `shell.dock.recordPill` on none | the strip is limited to some tabs (contract finding U7) |
| AC-ST-3 | AC-ST-3 | W | 10 | H | 360x800; `/a-setWorkRunning`, `/b-setWorkPaused`, `/c-setRestRunning`, `/d-setGettingReady`, `/e-restRunning`, `/f-restPaused`, `/g-restFinished1min`, `/h-restFinished11min`, `/i-restIdle`, `/j-setDone` | Override the providers per entry with presentation fakes; entry c is exactly `setTimer {phase: rest, running: true}` with the rest timer idle (TP-m4); pump on `/home` | a, c, d: strip with `stripWorkout` ("Workout in progress"); b: `stripPaused` ("Paused"); e: `stripResting` plus remaining time; f: `stripPaused`; g: `stripRestDone` ("Rest finished"); h, i, j: no strip, pill shown | any row of the "running" table has the wrong state word or presence (including `done`, `idle` and 11 minutes, which design gap 3 requires) |
| AC-ST-4 | AC-ST-4 | W | 1 | H | 360x800; REAL `SetTimerController` and `RestTimerController` running with an injected clock (TP-2); `en` | Switch mode through S-3 (RUNS-AFTER S03-10); advance the fake clock by 5 s | Strip semantics label identical before and after; both states equal by value; elapsed and remaining values changed by 5 s afterwards (the controllers still tick) | a mode switch invalidated `setTimerProvider` or `restTimerProvider` (a recreated controller gives an idle state and a frozen clock, which turns these assertions red) |
| AC-ST-5 | AC-ST-5 | I | 2 | H | `/storedDestination`, `/emptyDestination` | Tap the strip | Router location equals the stored route string; with the destination provider empty the location is `/workouts` | the strip opens a wrong page or nothing |
| AC-ST-6 | AC-ST-6 | W | 1 | M | 360x800; strip visible; Home with a long list | Scroll to the end; compare `Rect`s | The last child's bottom edge lies above the strip's top edge | the last item hides under the strip |
| AC-ST-7 | AC-ST-7 | I | 1 | H | 360x800 | Pump `/workout/:id` | No `shell.dock` | the dock shows over a pushed page |
| AC-ST-8 | AC-ST-8 | I | 1 | H | 360x800 | Start a timer, then build a new `ProviderScope` (process-death simulation). TP-m1: the test first records whether any persisted copy of timer state exists; if one exists the second scope shares that fake store, otherwise the timers are memory-only (the expected case per contract R-S5) and the second scope is simply fresh | No strip; no text claiming recovery | the strip survives process death or a recovery claim appears |
| AC-ST-9 | AC-ST-9 | W | 2 | M | 360x480, scale 2.0; `/pill`, `/strip` | Pump idle (pill) and running (strip) | Pill is the 48x48 icon variant; strip is one line; both have a non-empty accessible name | the compaction rule fails at large text or the icon loses its name |
| AC-SH-5 | AC-SH-5 | W | 1 | H | 360x800; sequence idle, running, idle on `/home` | Pump at each stage | `shell.dock.recordPill` and `shell.dock.strip` are never in the tree together, including the frame of the transition | both widgets present in one frame |
| AC-WS-7a | AC-WS-7 | W | 1 | H | 1100x800; idle; five paths | Pump each tab | `shell.rail.record` exists and is enabled on all five tabs; `shell.dock` does not exist | the Record slot is missing on a tab or a dock shows in the rail presentation |
| AC-WS-7b | AC-WS-7 | W | 1 | H | 1100x800; set timer running; five paths | Pump each tab | `shell.rail.record` shows the strip on all five tabs | strip missing in the rail |
| AC-WS-7c | AC-WS-7 | W | 1 | H | 1100x800 | Tap `shell.rail.record` while idle | `recordSheet.popover` opens (S-5 as an anchored popover), RUNS-AFTER S03-11 | wrong surface at Expanded |
| AC-WS-7d | AC-WS-7 | W | 2 | M | `/700x420` (rail), `/360x800` (bar) | Open S-5 | 700x420: bottom sheet of at most 560 dp; 360x800: bottom sheet and AC-ST-1 still holds | sheet too wide, or pill shown on Scan or Profile |
| AC-WS-7e | AC-WS-7 | W | 1 | M | 1100x800 on `/scan`; Record shortcut (RUNS-AFTER S03-17) | Send the modifier + Shift + R | S-5 opens; the popover `Rect` lies fully inside the window | the popover clips on `/scan` |
| AC-WS-12 | AC-WS-12 | W | 2 | M | 1100x800; `/idle`, `/running` | On each of the five tabs read the top `Rect` of the Progress destination | Identical on all five tabs, in both states; `shell.rail.record` exists and enabled on all five tabs when idle | the rail shifts when the strip appears |
| AC-WS-13 | AC-WS-13 | W | 1 | M | 1100x800, scale 1.0, `ru` | Set timer running, read `shell.rail.record` text nodes; then paused | State word and minutes exist, differ between running and paused, no overflow; idle shows "Record" ("Запись") | the compact slot omits the state, or overflows in `ru` |
| DT-07-1 | none | W | 1 | H | a provider overridden to throw (set timer, then rest timer) | Pump `/home` | The strip is hidden, no error text, no exception reaches the framework (contract S-4 ERROR row); the Workouts tab and the workout page stay reachable; a log entry holds a fixed message, a content-free code and the exception type only (RV-16, F-14) | a throwing provider breaks the shell, or the log leaks content |
| DT-07-2 | none | W | 1 | M | set timer paused and rest timer finished | Pump | The strip shows the set timer's state ("Paused"), not the rest's (priority rule) | wrong priority |
| DT-07-3 | none | U | 1 | M | pure derivation of the strip state from rest `endsAt` and an injected clock; one table of 9:59, 10:00, 10:01 after finish | Call the derivation for each table row | Visible at 9:59; hidden at 10:00 and 10:01 (rule: hidden when finished more than 10 minutes ago; design 2.6 fixes the hide timer at `endsAt + 10 min`, so exactly 10:00 is HIDDEN (RV-8); the test fails on a change, TP-m4) | the 10-minute window is off, or the strip never expires |
| DT-07-4 | none | W | 1 | M | device zone changes by +3 h while a rest timer is finished 5 minutes ago; DST jump case | Change the injected zone, pump | Visibility and elapsed values unchanged (they derive from `endsAt` in UTC) | a zone or DST change shows or hides the strip |
| DT-07-5 | none | I | 1 | M | destination provider written by the workout start, then the timer ends (`done`) | Tap where the strip was, start another timer from a different page | The destination provider is cleared on end and replaced on the next start; the strip never opens a stale route (`activeSessionOwnerProvider` written by the `workout_player_page.dart` start paths, design 2.6) | the strip opens the wrong workout page |
| DT-07-6 | none | W | 1 | M | rotate 360x800 to 800x360 and back with the strip visible | Pump | Strip collapses to a single line when the visible height is under 240 dp and returns; timer text continuous; no overflow | rotation breaks the strip |
| DT-07-7 | none | W | 1 | L | `disableAnimations` true; idle to running | Pump once | The strip is in the tree after one pump without an animation | appearance animation ignores reduced motion |

Level and count for EP-5 foundations after remediation batch 1: S03-02 8 (U 2, W 5, K 1); S03-03 14 (W 14); S03-04 9 (U 1, W 3, I 5); S03-05 35 (U 5, W 27, I 3); S03-06 21 (W 14, I 6, K 1); S03-07 43 (U 3, W 33, I 7). Totals U 11, W 96, I 21, K 2 = 130 (batch 1: 128; revision 1: 108).

Note on K rows of this plan: every K scan uses the scan set of section 1.3 item 10 (TP-4). Note on DT-05-3: the file `back_navigation_test.dart` is run unchanged as part of step 2 (RUNS evidence, no new entry).

## 4. EP-2 tests (chooser, questions, switcher, Record sheet)

Default Config for this section: `ru` locale first, then `en` (each row runs in `ru` and `en` unless stated; the second locale is not counted as a separate entry, because only copy differs: a failure is reported with the locale in the name). Fakes: `FakeModeStore`, `MockPermissionChannel`, `FakeSetTimer`, `FakeScanAccess`, `FakeScheduleProvider`.

### 4.1 S03-08 Mode chooser S-1 (file `mode_chooser_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-CH-1 | AC-CH-1 | W | 1 | M | 360x800 | Pump S-1 | Keys `modeChooser.card.train`, `.ride`, `.explore`, `.body` exist; `Rect` order is train, ride (same top, to the end side), explore, body (below) and the semantics traversal order is the same | a card is missing or reordered |
| AC-CH-2 | AC-CH-2 | W | 1 | H | 360x800; write spy | Tap `modeChooser.card.ride` with nothing selected | The Coming-later sheet opens (title `modeComingLaterSheetTitle` for ride); zero store writes; `modeChooser.continue` disabled | a coming-later mode is saved or enables Continue |
| AC-CH-3 | AC-CH-3 | W | 1 | M | 360x800 | Tap train then body; read semantics of the four cards | Exactly one card has `isSelected` (body) | two cards selected |
| AC-CH-4 | AC-CH-4 | I | 1 | H | 360x800; `pending` store | Tap `modeChooser.decideLater`; then start a new `ProviderScope` over the same store | Store holds `selectedMode=train` and `chooserStatus=resolved`; after restart the chooser is not pushed | Decide later does not resolve, so the chooser returns forever |
| AC-CH-5 | AC-CH-5 | I | 3 | H | 360x800; entries `/pending`, `/resolved`, `/migrated` | Restart (new scope, same store) without tapping anything, pump to the first Home build | `pending`: chooser is pushed once on the first Home build; `resolved` and `migrated`: not pushed | the chooser is lost after a kill or shown to a resolved user |
| AC-CH-6 | AC-CH-6 | W | 1 | H | 360x800; store whose write throws | Select train, tap Continue | `modeChooser.saveError` shown; the route reaches Home; stored `chooserStatus` stays `pending` | a failed save blocks the user or marks the chooser resolved |
| AC-CH-7 | AC-CH-7 | W | 1 | H | 360x800 and 1100x800; `MockPermissionChannel` | Pump S-1, hover, focus and select cards | Zero permission-channel calls | S-1 asks for a permission |
| AC-CH-9 | AC-CH-9 | W | 1 | M | 360x800 | Pump | Cards 1 and 2 share a top; card 3 is below card 1; `modeChooser.detailPanel` absent | wrong grid at Compact |
| AC-CH-10 | AC-CH-10 | W | 5 | H | `/700x900`, `/700x420`, `/640x360`, `/600x400`, `/360x420` | Pump S-1; measure | 700x900: 2x2, content width at most 640, no panel. 700x420 and 640x360 (grid width 608): 4x1, each card at least 136 dp wide, blurb absent from the card face, no overflow. 600x400 (grid 568) and 360x420 (grid 328): 2x2, `modeChooser.continue` reachable by scrolling, every card at least 136 dp, horizontal scroll extent zero, no overflow | the column rule uses the height alone, or a grid of 4 columns is forced into a narrow width |
| AC-CH-11 | AC-CH-11 | W | 1 | M | 1100x800 | Pump | `modeChooser.detailPanel` is at the end side of `modeChooser.grid`; `modeChooser.continue` is inside the panel; overall width at most 960; card order train, ride, explore, body | panel missing or wrong place |
| AC-CH-12 | AC-CH-12 | W | 3 | H | `/599x800`, `/839x800`, `/840x800` | Pump | 599: no panel, 2x2; 839: no panel; 840: panel present | a boundary of 840 or 599 is off by one |
| AC-CH-13 | AC-CH-13 | W | 2 | M | `/hoverFocus` (1100x800), `/scale2ru` (1100x800, scale 2.0, `ru`) | Hover then focus `modeChooser.card.body`; check selection; second entry pump at scale 2.0 | Panel text becomes the body description (`modeBodyDesc`); `isSelected` unchanged; second entry: no overflow and `didExceedMaxLines == false` for card names | hover selects, or Russian card names are cut |
| AC-CH-14 | AC-CH-14 | W | 1 | H | 1100x800 to 360x800; card body selected and focused; write spy | Pump the resize | Selected card, Continue enabled state and focus unchanged; zero writes during the resize | resize loses the selection (rotation mid-flow) |
| AC-LS-7 | AC-LS-7 | W | 0 | L | pointer to AC-CH-9 to AC-CH-14 | Each of those entries carries the tag `AC-LS-7` in its test name; no separate entry | The six tests exist under their own ids; the findings file lists AC-LS-7 as covered by them | an AC-CH-9..14 entry is renamed away or deleted (checked by name in the findings file) |
| AC-LS-11 | AC-LS-11 | W | 2 | M | 1100x800; `/idle`, `/touchSelect` | First run, nothing hovered; then tap `modeChooser.card.body` with a touch event only (no hover) | Idle: `modeChooser.detailPanel` shows `modeDetailIdle`, Continue disabled, no card `isSelected`, no illustration placeholder node. Touch: body selected and panel shows the body description | no idle text, or touch devices cannot fill the panel |
| DT-08-1 | none | W | 1 | M | 1100x800 | Focus the first card; send Right, Down, Left, Up | Focus order train, ride, body, explore, train... follows the grid (Right/Left within a row, Down/Up between rows) | arrow navigation is missing or reversed |
| DT-08-2 | none | W | 1 | M | 360x800 | Space on an available card; Enter on Continue | Space selects; Enter on Continue confirms and routes to Home | keyboard-only users cannot finish |
| DT-08-3 | none | W | 1 | M | store read delayed 400 ms (fake async) | Pump | After 300 ms four card outlines with buttons disabled and no spinner; the grid never reorders after load | a spinner appears or the grid reorders |
| DT-08-4 | none | W | 1 | M | store holds `body`; opened from the switcher "See all modes" (RUNS-AFTER S03-10) | Pump S-1 | The body card is selected and the panel or description shows the body text | a returning visit shows the idle state |
| DT-08-5 | none | W | 1 | H | 360x800 | Read semantics of `modeChooser.card.ride` | Enabled, focusable; label and hint contain `modeComingLater`; `isSelected` stays false after a tap | a coming-later card looks selectable to a screen reader |
| DT-08-6 | none | W | 1 | M | store `resolved` (opened from the switcher); and `pending` | Pump both | `modeChooser.decideLater` exists only when `chooserStatus` is `pending` | Decide later offered to a resolved user |
| DT-08-7 | none (RV-7) | I | 1 | H | `pending` status; chooser opened by Home with `go('/mode-chooser')` (design 2.3: replace, as contract J1) | System Back on the chooser (`PopScope`) | The write is exactly that of "Decide later": `selectedMode=train`, `chooserStatus=resolved` (design 2.3, F-39, AC-CH-4); a failing write leaves `pending` (F-1); the landing route is `/home`; a process kill instead leaves `pending` | Back leaves the chooser in an undefined state or exits the app |
| DT-08-8 | none (RV-7) | I | 1 | H | `pending`; the `offeredThisRun` keep-alive set per uid | Chooser pushed, closed with Back, then Home to Profile to Home | The chooser is pushed exactly once per run per uid | the chooser reappears on every Home build |
| DT-08-9 | none (RV-7) | I | 1 | H | `pending`; the Day-3 modal decision pending (completer), then shown, then settled | Build Home at each stage | No chooser while the modal decision is pending or the modal is shown; after it settles the chooser is pushed once | the chooser and the Day-3 modal compete |
| DT-08-10 | none (F-10) | I | 1 | M | `pending`; chooser open with card `body` selected (not saved); write spy | Switch the signed-in account to B | The surface re-reads B's mode state; the pending selection is discarded; zero writes; Continue is disabled again | the old account's selection is saved under the new account |

### 4.2 S03-09 First-run questions S-2 (file `mode_questions_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-Q-1 | AC-Q-1 | I | 1 | H | 360x800; `TrainingContext` answered, then skipped (two runs in the entry) | Select TRAIN and Continue | Zero question screens; router goes straight to Home | a known answer is asked again |
| AC-Q-2 | AC-Q-2 | W | 1 | M | 360x800 | Tap `modeQuestion.skip`; reopen S-1 or S-3 for that mode | Store holds `skipped`; no question screen on the second visit | Skip does not stick |
| AC-Q-3 | AC-Q-3 | W | 2 | M | `/food`, `/photos`; 360x800 | Answer the BODY question; read Home lens key order | `/food`: `home.card.nutrition` precedes `home.card.bodyScan`; `/photos`: the reverse | the answer changes nothing visible (contract: each question visibly changes something) |
| AC-Q-4 | AC-Q-4 | W | 1 | M | each available mode | Walk all question screens | Never more than 3 screens; the text of `modeQuestion.progress` shows the true index and total ("Question 1 of 2") on each screen | a fourth question or a wrong counter |
| AC-Q-5 | AC-Q-5 | W | 1 | H | store whose write throws | Answer an option | The inline error `modeQuestionSaveError` shows; `modeQuestion.skip` and Back are enabled (`isEnabled`) | a failed save traps the user |
| AC-Q-6 | AC-Q-6 | W | 1 | H | `FakeScanAccess` refuses an option | Pump the BODY question | The option is present, `isEnabled == false`, and the existing reason text is in that node's value or hint | the option is hidden or enabled |
| DT-09-1 | none | W | 1 | L | write delayed 400 ms | Tap an option | Button busy and disabled; the text `modeQuestionSaving` is visible for at least 300 ms; no looping indicator | double submit or a spinner |
| DT-09-2 | none | W | 1 | M | store throws once, then succeeds | Tap Retry (`modeQuestionRetry`) | The second write stores the answer and the flow continues | Retry does nothing |
| DT-09-3 | none | W | 1 | M | TRAIN with `TrainingContext` unknown and BODY with two unknown | Walk the flow | Counter shows "Question 1 of 1" for TRAIN and "Question 1 of N" matching only unknown questions | answered questions counted |
| DT-09-4 | none | W | 1 | M | two-question flow | Answer the first, press Back, answer again | One stored answer, no duplicate, no reset of the second question | Back loses or duplicates answers |
| DT-09-5 | none | I | 1 | M | kill between the first and second question (new scope, same store) | Restart | The answered question is not asked again; the remaining one is offered once | answers lost on kill |
| DT-09-6 | none (RV-15) | I | 2 | H | write spy; entries `/xyz` (unparseable), `/ride` (unavailable mode) | Open `/mode-questions/<value>` by deep link | Redirect to `/home`; zero store writes | a crafted link writes state or opens a question for an unavailable mode |

### 4.3 S03-10 Mode switcher S-3 and Coming-later sheet (file `mode_switcher_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-SW-1 | AC-SW-1 | I | 1 | H | RUNS-AFTER S03-12 (the chip lives in Home; before that step the switcher is opened from a test host through the S-3 show function), 360x800; Home | Tap `home.modeChip`, then `modeSwitcher.row.body` (count taps) | Exactly two taps; Home `home.section.*` order equals the BODY order; store holds `body` | the switch needs more than two taps or does not persist |
| AC-SW-2 | AC-SW-2 | W | 1 | H | 360x800; REAL `SetTimerController` and `RestTimerController` started with an injected clock (TP-2) | Switch to body; advance the fake clock by 5 s | Both states equal by value after the switch; `shell.dock.strip` shows the same label; elapsed and remaining changed by 5 s afterwards (the clock still ticks) | a mode switch touches or recreates a timer (R-M1); a provider invalidation would give an idle or frozen state |
| AC-SW-3 | AC-SW-3 | W | 2 | H | `/scrim`, `/sameMode`; write spy; `modeChanged` spy | Dismiss by scrim; tap the current mode's row | Zero writes; zero `modeChanged` events | dismissal or re-selection writes or emits |
| AC-SW-4 | AC-SW-4 | W | 1 | M | 360x800 | Call the show function twice quickly | Exactly one `modeSwitcher.sheet` in the tree | stacked duplicate sheets |
| AC-SW-5 | AC-SW-5 | W | 2 | H | `/ride`, `/explore`; write spy | Tap each unavailable row | Coming-later sheet opens; zero writes | an unavailable mode is stored |
| AC-SH-4 | AC-SH-4 | I | 1 | H | 360x800 on `/progress` | Switch mode | Router location and `HudNavBar.selectedIndex` unchanged | a mode switch navigates |
| DT-10-1 | none | W | 1 | M | store write throws | Switch to body | Lens changes for the session; a snackbar with `modeSwitchSaveError` shows | a failed save blocks the lens or is silent |
| DT-10-2 | none | W | 1 | L | `ru` and `en`; unanswered counts 1, 2, 5, 21 | Pump the switcher | `modeSwitcherQuestions` shows the plural form for each count (`ru`: one, few, many, other) | wrong Russian plural |
| DT-10-3 | none | W | 1 | M | Coming-later sheet for explore | Tap `modeComingLaterSheetAction` | The mode is train; the sheet closes; one write of `train` is allowed only if the mode actually changes | the action does not change to Train or writes when already Train |
| DT-10-4 | none | W | 1 | M | 360x800 | Read semantics of rows | Rows form a mutually exclusive group; only the current mode's row is selected | a row announces as unselected current |
| DT-10-5 | none (F-10, switcher half) | I | 1 | M | S-3 open from the test host or `home.modeChip`; account A mode `train`, B mode `body`; write spy | Switch the signed-in account to B while S-3 is open | The surface re-reads B's state (the selected row is `body`); a tap on a row afterwards writes only under B; zero writes under A | the old account's selection or mode is shown or saved for the new account |

### 4.4 S03-11 Record sheet S-5 (file `record_sheet_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-RC-1 | AC-RC-1 | I | 1 | H | 360x800 TRAIN; `MockPermissionChannel` | Open S-5 and tap `recordSheet.row.trainScan` | Router location `/scan`; zero permission calls from the sheet | row goes elsewhere or asks permission |
| AC-RC-2 | AC-RC-2 | W | 2 | M | `/none`, `/scheduled`; `FakeScheduleProvider` | Open S-5 | `/none`: `recordSheet.row.trainToday` absent; `/scheduled`: present and enabled | a row for a non-existent workout |
| AC-RC-3 | AC-RC-3 | W | 2 | H | BODY; `/flagsOff` (`FOOD_AI`, `FOOD_LOOKUP` off), `/refused` (`FakeScanAccess` refuses) | Open S-5 | `/flagsOff`: meal rows equal the tile set of the existing `add_food_page` rules; `/refused`: row present, `isEnabled == false`, reason in value | S-5 creates a capability the existing flow forbids |
| AC-RC-4 | AC-RC-4 | W | 1 | H | all repository fakes with write spies | Open and close S-5 | Zero writes | opening writes state |
| AC-RC-5 | AC-RC-5 | I | 1 | M | 360x800 on `/progress` | Open S-5, follow a row, pop | Router location is the originating tab; no `recordSheet` in the tree | the sheet stays or the tab changes |
| DT-11-1 | none | W | 1 | M | BODY with every tile flag-hidden | Open S-5 | `recordNothingHere` and a button "Open Train" (`recordOpenTrain`); no rows | an empty sheet with no way out |
| DT-11-2 | none | W | 1 | M | strip visible | Try to open S-5 (pill absent; shortcut) | S-5 does not open while the strip shows | two competing start surfaces |
| DT-11-3 | none | W | 1 | L | BODY answer "Food diary" | Open S-5 | The meal row is first and primary (contract S-2: first row in the Record sheet) | the question answer does not reach S-5 |
| DT-11-4 | none (design 2.3) | I | 1 | M | real `app_router.dart` with fakes; destinations `/scan`, `/workouts`, `/form-check`, `/body-scan`, `/nutrition/add`, `/nutrition/weight` (the last two UNGROUNDED paths in design 2.3, asserted here) | Navigate to each destination from the Record sheet row table | Every destination resolves to a real route (no unknown-route page) | a Record row points to a route that does not exist |

Level and count for EP-2 after the closing pass: S03-08 34 (W 26, I 8); S03-09 14 (W 10, I 4); S03-10 13 (W 10, I 3); S03-11 11 (W 8, I 3). Totals W 54, I 18 = 72 (batch 1: 69; revision 1: 64). The row `AC-LS-7` has N=0 (alias).

## 5. EP-3 tests (Home, aggregates, Progress)

Fakes: `FakeJournal` (sessions built per test with explicit `startedAt`, sport, `distanceM`, `movingTimeS`, provenance), `FakeClock`, `FakeZone`, `FakeModeStore`. The `strength` fake entry is a session with sport `strength`. Aggregate definitions, the state matrix and the gates are final in design 3 (table A of section 8.5); the values below come from contract 7 S-7 and 8 and design 3.4.

### 5.1 S03-12 Home: chip, lens, activity today, intro card, two-pane (file `home_mode_lens_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-HM-1 | AC-HM-1 | W | 1 | H | 360x800; TRAIN; `chooserStatus=resolved`; journal `notEnabled` override and, in a second pump, empty `open` | Pump Home; list `home.section.*` keys by `Rect` order | Equals the golden list recorded from the pre-S03 order, plus `home.modeChip` only (TP-m2: the golden list is captured ONCE from the base head and committed; nobody regenerates it when the test fails) | a Phase 1 Home section moved, disappeared or gained an element |
| AC-HM-2 | AC-HM-2 | W | 1 | M | 360x800; BODY | Pump Home | `home.section.bodyScan` and `home.section.nutrition` precede `home.section.quickScan`; the key set equals the TRAIN set | the BODY lens removes or fails to reorder |
| AC-HM-3 | AC-HM-3 | W | 3 | H | `FakeClock` "today" fixed, zone fixed; `/startsToday`, `/startsYesterday`, `/strengthToday` | Pump Home | `/startsToday`: `home.activityToday` exists; `/startsYesterday`: absent; `/strengthToday`: absent and no rows | a card for another day, or a strength entry shown |
| AC-HM-4 | AC-HM-4 | W | 5 | H | 360x800; `/migrated`, `/pending`, `/resolved`, `/absent`, `/day3Modal` | `/migrated`: card present, tap "Not now" (`modeIntroDismiss`), rebuild; others: pump | `/migrated`: store holds `resolved` and the card is gone after rebuild; `/pending`, `/resolved`, `/absent`: `home.modeIntro` never exists; `/day3Modal`: with `Day3WelcomeModal` open the card is not in the tree | the intro card shows to a new user, twice, or beside the Day-3 modal |
| AC-HM-5 | AC-HM-5 | W | 1 | H | 360x800; fake journal whose `list()` throws | Pump Home | No text equal to any new key (`activityJournalFailed`, `activityNoData`, ...); every pre-S03 section key present; no exception text | Home shows a new error or loses a section when the journal fails |
| AC-HM-6 | AC-HM-6 | W | 2 | M | `/traversal` 360x800, `/scale2` 360x800 scale 2.0 `ru` | Tab from `home.section.greeting`; then pump at scale 2.0 | Next focus is `home.modeChip`; at scale 2.0 its top is below the greeting's bottom and no overflow | the chip overlays or truncates the greeting |
| AC-LS-1 | AC-LS-1 | W | 3 | M | scale 1.0; `/1100x800`, `/700x900`, `/360x800` | Pump Home | 1100x800: `home.pane.main` and `home.pane.side` side by side, side pane 340 dp, content width at most 1120, union of `home.section.*` equals the Compact key set. 700x900 and 360x800: neither pane key exists, order equals the Compact order | a section is lost in the two-pane layout |
| AC-LS-2 | AC-LS-2 | W | 2 | M | 1100x800; `/body`, `/train` | Read the main-then-side reading order | BODY: `bodyScan` and `nutrition` precede `quickScan`; TRAIN: equals the pre-S03 relative order | lens ordering ignored in the wide layout |
| AC-LS-3 | AC-LS-3 | W | 1 | M | 900x800, scale 2.0, `ru` | Pump Home | The side pane is below the main column (single column); no overflow | a cramped two-pane layout at large text |
| DT-12-1 | none | W | 1 | M | `migrated`; Day-3 modal shown in the first Home build | Close the modal, rebuild Home | The intro card appears on the next build, not in the same session as the modal | the card never appears, or competes with the modal |
| DT-12-2 | none | W | 1 | M | Home scrolled; journal resolves with a session today (fake async) | Resolve the journal | `home.activityToday` is inserted without moving the viewport offset; no skeleton | the content jumps when the card arrives |
| DT-12-3 | none | I | 1 | M | `migrated` | Tap "Choose a mode" (`modeIntroChoose`) | S-1 opens; store holds `resolved`; the card is gone after returning | the intro stays after being used |
| DT-12-4 | none (F-35) | W | 1 | M | `modeStateProvider` still loading (completer); stored mode would be `body` | Pump Home before the value arrives, then after | While loading: the pre-S03 TRAIN order, no `home.modeChip`, no chooser push; after the value: the BODY order and the chip, no frame in between shows the wrong lens | a flash of the wrong lens or a chooser on a healthy account |

### 5.2 S03-13 Aggregates, sport groups, source labels (file `activity_aggregates_test.dart`)

Rows AC-PR-5 to DT-13-7 are pure unit tests (injected clock and zone); rows DT-13-8 to DT-13-24 guard the review decisions and failure rows (providers with fakes, levels as stated; DT-13-23 is MEASURE-ONLY). Week starts on Monday in the device zone, shared with `progress_stats.dart` (design 3.2); the Home week rule is DD-9 (open) and is not tested.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-PR-5 | AC-PR-5 | U | 1 | H | one `strength` session plus one run | Aggregate the week and the recent list | The strength entry produces no group, no tile, no row; the run is counted | strength leaks into the dashboard (OD-5) |
| AC-PR-7 | AC-PR-7 | U | 4 | H | zones `/UTC+0`, `/UTC-8`; entries `/sundayLate`, `/mondayEarly` for each zone | Session at 23:30 local Sunday and at 00:10 local Monday; clock fixed in the following week | 23:30 Sunday belongs to the week of the preceding Monday; 00:10 Monday belongs to the new week, in both zones | boundary uses UTC or Sunday as the first day |
| AC-PR-11 | AC-PR-11 | U | 1 | H | 3 running and 2 cycling sessions this week | Group | Run count 3, Ride count 2, sum 5; no session in two groups | double counting |
| AC-SRC-6 | AC-SRC-6 | U | 6 | M | unknown `sourceId`; `/platformHealth`, `/bleSensor`, `/vendorCloud`, `/companionApp`, `/fileImport`, `/unknownKindName` | Resolve the label | "Health platform", "Sensor", "Service", "App", "File import", and an unrecognised stored kind name gives "File import"; never an empty label | an empty or wrong label (contract 8.1) |
| DT-13-1 | none | U | 1 | M | DST change inside the week (23-hour Sunday, 25-hour Sunday) | Assign sessions near the boundary | Each lands in the correct week by local calendar day | a DST day shifts a session into the neighbour week |
| DT-13-2 | none | U | 1 | M | session stored at one zone, read after the device zone changed | Aggregate | Assignment follows the rule chosen by design 3 (device zone at read time per contract); the test fails on a change of rule (design 3.2: device zone at read time, Monday week) | a silent third week rule (contract forbids) |
| DT-13-3 | none | U | 1 | M | provenance list empty or missing | Label | "Unknown source" (`sourceLabelUnknown`) | an empty label |
| DT-13-4 | none | U | 1 | L | provenance with 1, 2, 5, 21 records, `ru` and `en` | Format the source line | Primary source plus the plural form of "+{k} sources" (`ru` one, few, many, other); none for one record | wrong plural or missing count |
| DT-13-5 | none | U | 1 | M | 5 sessions, 3 with `movingTimeS` | Aggregate time | Sum covers only the 3; hint `activityTimeFrom` with k=3, n=5 (plural by locale) | sessions without time counted as zero |
| DT-13-6 | none | U | 1 | M | no data this week, one older session | Build week state | State "no data this week but older data": `progressThisWeekEmpty` is shown; with no sessions at all the state is "none" | the sentence shown when nothing was ever recorded |
| DT-13-7 | none | U | 1 | L | `sourceId` table: `app`, `health_connect`, `healthkit`, `wear_os`, `ble_hr` | Label | "Recorded in this app", "Health Connect", "Apple Health", "Watch", "Sensor" | a known id falls to the generic kind label |
| DT-13-8 | none (RV-3) | I | 1 | H | `FakeJournal` whose bind completes later (completer); Progress and Home pumped | Pump while availability is `binding`; then complete the bind with no other trigger | While binding the dashboards show LOADING and never EMPTY text; after the bind the real sessions appear without a manual refresh | a false "no activity" while the journal is still binding |
| DT-13-9 | none (RV-3) | I | 2 | H | account A signs in, `list()` slow (completer); `/neverShows`, `/lateCompletion` | Switch to B while A's list is pending; (a) pump Home, Progress and Sources for B; (b) then complete A's future | (a) none of A's session ids, digests or counts appear in the trees of Home, Progress, Sources; (b) B's state is unchanged by A's late completion (discarded by uid and generation) | account B sees A's activity |
| DT-13-10 | none (RV-3) | I | 1 | H | A's data loaded, then B signs in with a throwing or unbound journal | Pump Progress | No A data; B shows LOADING or the error panel | stale A digests reused for B (`ownerUid` ignored) |
| DT-13-11 | none (RV-3) | I | 1 | H | bind that always fails (fake), the fake timer factory of `activityBindRetryTimerFactoryProvider` | Advance fake time through the whole schedule (5 s, 15 s, 60 s, 5 min, 5 min) | Initial attempt plus five automatic retries (six `bindUid` calls), then `gaveUp` (retry rule 4) and the error panel with Try again; no endless LOADING; no timer afterwards (detail of the state machine: DT-0-11 to DT-0-14) | the user waits forever on a spinner |
| DT-13-12 | none (RV-3, RV-11) | I | 1 | H | first `list()` succeeds for uid A, the refresh throws | Trigger a refresh | The previous value is kept (state not `AsyncError`); `lastLoadFailedAt` set (the visible line is DT-14-6) | a failed refresh blanks good data |
| DT-13-13 | none (RV-3) | U | 1 | H | the availability function over (bind status, auth uid) | Evaluate `notEnabled`, `binding`, `open`, `gaveUp`, `failedToOpen`; bound uid equal and different | `open` only when bound and `boundUid == authUid`; a different bound uid is `binding` or `notEnabled`, never `open` | a journal bound to another account is reported open |
| DT-13-14 | none (RV-3) | I | 1 | M | five refresh triggers fired together (bind event, resume via the existing lifecycle callback, stale tab after 60 s, Try again, revision) | Fire them within one frame, then fire 10 more requests while the first load is still pending (completer) | One in-flight load plus one dirty rerun: at most ONE extra `list()` call however many requests arrive during a load (two calls in total); `refreshIfStale` is called from `initState` or `didChangeDependencies`, never from `build` | a refresh storm, or a second lifecycle observer |
| DT-13-15 | none (RV-3) | I | 1 | H | signed-in A with data, sign-out | Pump the first frame after sign-out and under B | Availability and digests are already LOADING in that first frame (synchronous reset); the pending bind retry timer of the departed generation is cancelled (zero armed timers in the fake factory) and a stale in-flight completion is discarded (retry rule 5) | one frame of the previous account's data |
| DT-13-16 | none (RV-10) | I | 1 | M | fake journal whose start report has `absent={id}` | Load, then refresh | `recoveredAbsentCount` is 1 and survives the refresh | the recovery report is lost |
| DT-13-17 | none (RV-11) | U | 1 | H | a session whose `SummaryProjection.effective` throws among 4 good ones | Build the digest | It is counted in `unreadableSessions`, not in the "k of n" count (n counts only readable sessions); it is added to the RV-10 notice count | an unreadable session is shown as an ordinary missing value |
| DT-13-18 | none (RV-16) | I | 1 | M | `list()` throws; log capture | Load and refresh | Captured logs contain a fixed message, a reason code and the exception type; no session id, source id, path or message | log content leaks identifiers |
| DT-13-19 | none (RV-19) | U | 1 | L | a `SourceKind` value without a label mapping (test seam for a future value) | Label it | "Unknown source" (`sourceLabelUnknown`), never "File import". Note: the contract 8.1 rule that `SourceKind.parse` maps an unrecognised stored name to `fileImport` stays; AC-SRC-6 entry `/unknownKindName` still expects "File import" | an unmapped value is shown as an import |
| DT-13-20 | none (F-17, design 3.7) | U | 1 | M | `activityJournalRevisionProvider` and the digests notifier with a fake journal | Bump the revision counter once, then three times quickly | One reload per quiet bump; the quick bumps coalesce into one in-flight plus one dirty rerun; no bump on a uid change (that is a reset) | the refresh seam for S04+ writers does nothing |
| DT-13-21 | none (F-27, design 3.4) | U | 1 | H | the 12 `SportType` values and one unknown stored name | Group each | Each of the 11 non-strength values maps to exactly one of Walk and hike, Run, Ride, Swim, Row, Other; `strength` is excluded; an unknown stored name degrades to `other` | a sport falls in two groups or in none |
| DT-13-22 | none (F-28, design 3.4) | U | 1 | H | sessions: one with `distanceM` 0, one with `distanceM` null, one with `movingTimeS` null | Aggregate | A reported 0 is summed and shown as 0; null is missing (never summed as zero); the "k of n" counts count only non-null values; `timeContributing == 0` gives "No data" | missing is shown as zero, or a real zero is shown as "No data" |
| DT-13-23 | none (F-30, gate G1) | U | 1 | M | the synthetic corpus generator for 5,000 and 20,000 digests; median of 20 runs; MEASURE-ONLY release gate G1: the numbers are the evidence, the test agents run it ONCE at the end (step 7), the coordinator never runs it; it cannot be a deterministic unit test because wall time varies | Time `aggregateWeek` | At most 2 ms for 5,000 and at most 10 ms for 20,000 digests in the Dart VM harness (a regression tripwire, not a device claim); the exact head, command, corpus size, median and worst values are written to the findings file | the aggregation grows super-linear. Flake guard: thresholds are the design's PROPOSED values; a miss is reported with numbers and re-measured once, never loosened silently |
| DT-13-24 | none (design 3.5) | U | 1 | L | a session with two provenance records in a known order | Label it | The label is the FIRST record's label, plus "+1 sources" (plural form); pins current behaviour (priority after a merge is UNGROUNDED) | the label silently switches to another record |

### 5.3 S03-14 Progress dashboard (file `progress_dashboard_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-PR-1 | AC-PR-1 | W | 1 | H | 360x800; journal forced to `notEnabled` by override | Pump Progress | `progress.slot.sources` present; `progress.allActivity` and `progress.journalError` absent; no "empty" or "unavailable" string; existing blocks in the original order | a Phase 1 user sees a message implying nothing was recorded |
| AC-PR-2 | AC-PR-2 | W | 2 | H | `/once`, `/doubleTap`; `failedToOpen` fake with pending opener | Tap `progress.journalRetry`; second tap while pending | Opener called exactly once; the button is disabled while pending; the second tap adds no call | retry loops or double-opens |
| AC-PR-3 | AC-PR-3 | W | 2 | H | `/zeroSessions`, `/oneSession`; `open` journal | Pump | Zero: same tree as AC-PR-1. One: `progress.allActivity` exists, `progress.slot.sources` does not, it follows `ActivitySyncEntryCard` and precedes `BodyScanEntryCard` | wrong placement or demotion |
| AC-PR-4 | AC-PR-4 | W | 1 | H | one run (5000 m, 1500 s) and one walk (600 s, no distance) this week | Pump | `progress.tile.run` shows both values; `progress.tile.walk` shows "No data" (`activityNoData`) for distance and still counts the 600 s; no calorie figure in any text node | an unknown shown as zero, or energy invented |
| AC-PR-6 | AC-PR-6 | W | 1 | M | `put` of the same session id twice | Pump | Exactly one `progress.recent.row.<id>` | duplicate rows |
| AC-PR-8 | AC-PR-8 | W | 1 | H | 360x800 | Compare child keys of the original Progress list with the new list | First and last children unchanged; only the inserted children differ | S03 reshuffles the gym dashboard |
| AC-PR-9 | AC-PR-9 | W | 1 | M | strip visible (`FakeSetTimer` running) | Scroll to the end; compare `Rect`s (TP-m5: no constant such as 120 + dock height is asserted) | The last child's bottom edge lies above the strip's top edge, with and without the strip | content hidden under the strip |
| AC-PR-10 | AC-PR-10 | W | 2 | M | `/ru`, `/en`; run 5.2 km | Read the distance text | `ru` uses the comma separator, `en` the dot; unit is kilometres (metric only), no hard-coded "km" literal outside the formatter | a fixed separator or imperial units |
| AC-LS-4 | AC-LS-4 | W | 3 | M | one session; `/1100x800`, `/700x900`, `/360x800` | Compare `Rect.left` and tile columns | 1100x800: `progress.allActivity` left, body-scan card right, tile columns equal clamp(floor((available + 12) / 172), 1, 3) (3 at scale 1.0); 700x900: one column with the same rule on 640 dp; 360x800: order exactly AC-PR-3 | the two-column layout reorders or tiles get narrower than 160 dp |
| AC-LS-5 | AC-LS-5 | W | 4 | M | 1100x800; `/failed`, `/zero`, `/offline`, `/loading` | Pump each state | failed: `progress.journalError` and `progress.journalRetry` in the left column; zero: only `progress.slot.sources` (right column), no `progress.allActivity`; offline fake: tree equals the online one; loading: the Sources row first | state mapping lost in the column layout |
| DT-14-1 | none | W | 1 | M | the error panel is shown only in the states `gaveUp` and `failedToOpen`; the retry attempt fails again; fake timer factory | Tap retry in each of the two states | Stays in the error state, exactly one attempt per tap; no timer is armed afterwards in either state (after `gaveUp` a manual failure starts no new loop, retry rule 4; `failedToOpen` has no loop, rule 7); the `binding` state shows LOADING, never this panel | a retry storm, or a manual failure re-starting the automatic schedule |
| DT-14-2 | none | W | 1 | M | loading then data (fake async), list scrolled | Resolve | Block inserted above the body-scan card; the viewport offset is preserved | the content jumps |
| DT-14-3 | none | W | 1 | M | journal flips `open` with data to `failedToOpen` and back (refresh) | Pump the three states | The tree follows each state; the state flip leaves no stale block or panel | a stale error or a stale block |
| DT-14-4 | none | W | 1 | M | the predicate `isEstimate(field, session)` for time and distance of a recorded session and of a session with an explicit user value (design 3.4: no value is an estimate in S03) | Evaluate the predicate; pump the tile with the real predicate and then with a predicate forced to true | Real predicate: false for every field and the "Estimate" marker (`activityEstimate`) is never rendered; forced true: the marker renders (the component capability exists) | recorded data labelled as estimate, or the capability missing |
| DT-14-5 | none (RV-10) | W | 1 | M | journal with `recoveredAbsentCount` 2 | Pump Progress | One plain line `activityStreamLost`-style count variant ("2 activities could not be restored on this device") and a "may be incomplete" marker on the aggregates; absent when the count is 0 | the dashboard claims completeness over lost data |
| DT-14-6 | none (RV-11) | W | 1 | H | first `list()` succeeds, the second throws (same uid) | Refresh | The values stay; one line "Showing data from <time>" with Try again | a failed refresh blanks the data or is silent |
| DT-14-7 | none (F-17) | W | 1 | M | journal with 3 sessions on screen; one is deleted in the fake journal | Pump, then trigger a refresh (pull or revision bump) | The deleted row stays until the refresh and is gone after it; no tombstone is ever read (`listTombstones()` spy zero calls) | a deleted activity stays forever, or tombstones reach the dashboard |
| DT-14-9 | none (design 3.7, old DT-14-10) | W | 1 | M | spy on `refreshIfStale()` and `build` counts; Home and Progress pumped | Pump each page, rebuild it 5 times without a lifecycle change, then re-enter the tab after 61 s of fake time | `refreshIfStale()` is called from `initState` or `didChangeDependencies` only (zero calls attributable to `build`); after 61 s exactly one refresh; within 60 s none | the page reloads inside `build` (a load storm) or never refreshes a stale tab |
| DT-14-8 | none (F-30, gate G2) | I | 1 | M | real temporary journal directory with 5,000 sessions (fixtures `scoped_journal_world.dart`, `journal_harness.dart`); MEASURE-ONLY release gate G2, run ONCE at the end (step 7) by the test agents; the coordinator never runs it | Time `list()` plus digest conversion; record await points | At most 250 ms end to end in the harness and no more than 16 ms of continuous synchronous work between awaits; numbers written to the findings file. A miss does not fail the sprint (design DD-10): it is recorded as an S02 carry-over | a slow journal read blocks the first paint unnoticed. Flake guard: one warm-up run, then the median of 5 |

Level and count for EP-3 after the closing pass: S03-12 23 (W 22, I 1); S03-13 37 (U 27, I 10); S03-14 27 (W 26, I 1). Totals U 27, W 48, I 12 = 87 (batch 1: 78; revision 1: 63).

## 6. EP-4 tests (Sources, sign-out)

### 6.1 S03-15 Sources panel S-8 (file `sources_panel_test.dart`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-SRC-1 | AC-SRC-1 | W | 2 | H | 360x800; `/emptyOpen`, `/oneSession` | Pump Sources | `sources.row.app` semantics contain `sourceStatusReady` ("Ready") with an empty journal and `sourceStatusInUse` ("In use") after one session | the status does not follow the journal |
| AC-SRC-2 | AC-SRC-2 | W | 1 | H | `notEnabled` forced by override | Pump | App row contains `sourcesNotActiveLine` ("Activity history is not active in this build."); no `sources.app.retry`; no "Problem" text anywhere | an error is shown for a not-enabled build |
| AC-SRC-3 | AC-SRC-3 | W | 1 | H | `failedToOpen`; opener spy | Pump; tap `sources.app.retry` | "Problem" (`sourceStatusError`) and `sources.app.retry` exist; the opener is called once | no way to retry, or a retry loop |
| AC-SRC-4 | AC-SRC-4 | W | 1 | M | 360x800 | Read all non-app rows | Semantics contain "Not connected" (`sourceStatusNotConnected`); no tap action (the optional health-sync link excepted) | a row looks actionable |
| AC-SRC-5 | AC-SRC-5 | W | 1 | H | `en` and `ru` | Pump | `sources.dedupNote` exists | the dedup limit is not disclosed |
| AC-SRC-5k | AC-SRC-5 | K | 1 | H | ARB additions of S03 (listed in the sprint change record) | Search the added `en` and `ru` values for the exact phrases "merged", "deduplicated", "synced with Health Connect" (and the Russian equivalents added by the translation pass) | Zero matches; the stem "merge" is allowed (design 6.8 note) | copy promises dedup or a Health Connect sync that does not exist |
| AC-SRC-7 | AC-SRC-7 | W | 1 | M | 360x800 | Read the semantics of every row | One node per row; its label contains the name and the status | name and status read as separate nodes |
| AC-LS-6 | AC-LS-6 | W | 2 | M | `/1100x800`, `/700x900` | Pump | 1100x800: all `sources.row.*` in the main column, `sources.dedupNote` in the side pane, width at most 880 dp, AC-SRC-1..7 still hold; 700x900: one column | wide layout loses a row or the note |
| DT-15-1 | none | W | 1 | L | journal read pending (fake async) | Pump and advance 1 s | The app chip reads `sourceStatusChecking` for at most 1 s, plain text, then the final status | a spinner, or "Checking" forever |
| DT-15-2 | none | W | 2 | M | `TargetPlatform.iOS`, `TargetPlatform.macOS` | Pump | No Apple Health row (`sources.row.healthkit` absent) | an Apple row is listed with no Apple adapter |
| DT-15-3 | none | W | 1 | M | adapter spy | Pump | `healthStatus()` is never called; no source adapter is touched | S03 queries sources that do not exist |
| DT-15-4 | none (RV-10) | W | 1 | M | recovery report with 2 absent activities | Pump Sources | The plain line with the count (variant ARB key) shows; absent at 0 | lost data is silent |
| DT-15-5 | none (RV-11) | W | 1 | H | first `list()` succeeds, the second throws | Refresh | The app row shows the "Problem" chip (`sourceStatusError`) and the stale line, not "In use" | a stale state is shown as healthy |
| DT-15-6 | none (RV-19) | W | 1 | M | Health Connect row, `en` and `ru` | Pump | The row text equals the approved contract wording (AC-SRC-4: "Not connected") and no stronger claim; the known false-status risk is recorded in DD-7, not hidden by wording | the row claims an integration that does not exist |

### 6.2 S03-16 Sign-out warning S-10 (file `sign_out_warning_test.dart`)

Design 2.5: the guard is `confirmSignOutWithLocalData(context, ref)`, export reuses `activity_local_export.dart`, delete uses `ActivityWipeCoordinator.onSignOut`; the sign-out call sites and the export write location are found in the S03-16 first step (open item in 8.5 table B; DD-8 may drop the story).

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-SO-1 | AC-SO-1 | W | 2 | H | `/threeActions`, `/nothingDeletedFirst`; fake journal with 3 sessions; delete spy | Trigger sign-out; then choose "Sign out and delete from this device" and stop at the second confirmation | `signOut.warningSheet` offers `signOutExportFirst`, `signOutAndDelete`, `signOutCancel` with the count text for n=3; the delete spy has zero calls until the second confirmation (`signOutConfirmDelete`) is accepted | activity is deleted on the first tap |
| AC-SO-2 | AC-SO-2 | W | 1 | H | empty fake journal | Trigger sign-out | The sign-out call happens at once; no `signOut.warningSheet` | an empty-journal user is blocked by a prompt |
| DT-16-1 | none | W | 1 | H | non-empty journal | Choose Cancel | The user stays signed in; delete spy zero; sheet closed | Cancel signs out |
| DT-16-2 | none | W | 1 | M | journal `notEnabled` only (RV-12 replaces the contract J10 reading for the other states; see DT-16-4) | Trigger sign-out | No prompt, sign-out proceeds | a not-enabled build blocks sign-out |
| DT-16-3 | none | I | 1 | H | account A with local activity signs out and deletes; account B signs in; journal binding by account per design 2.1 and 3.1 | Compare the journal seen by B | B sees none of A's sessions; A's sessions are gone after the delete path; with the delete path NOT taken (Export only) A's sessions are not visible to B either | local activity of one account is shown to another |
| DT-16-4 | none (RV-12) | W | 3 | H | availability `/failedToOpen`, `/binding`, `/gaveUp` | Trigger sign-out | A "cannot check" sheet with the sentence "We could not check the activity stored on this device" and actions Try again / Sign out anyway; no silent sign-out | sign-out passes silently when the journal cannot be counted |
| DT-16-5 | none (RV-12) | W | 1 | H | `wipe` throws after the user confirmed | Confirm delete | The user stays signed in; an error sheet with Retry; no "deleted" text | data left behind while the user believes it is gone |
| DT-16-6 | none (RV-12) | W | 1 | H | export throws | Choose Export first | No sign-out; an error sheet with Retry | sign-out after a failed export loses the only copy |
| DT-16-7 | none (RV-12) | W | 1 | M | wipe returns normally | Confirm delete | The "deleted" text appears only after the normal return; order: wipe first, sign-out after | the UI claims deletion before it happened |
| DT-16-8 | none (RV-16) | I | 1 | H | export with the real export path and a temp directory layout (backup-included directories named in the layout) | Export then share (fake share) | The file is outside every backup-included directory (cache or temp), bound to the departing uid, and deleted after the share | an exported route stays in a backed-up folder |
| DT-16-9 | none (F-20) | K | 1 | H | the K scan set extended with the sign-out call-site files named in the S03-16 first step | Scan for calls to the auth sign-out method | Every call site goes through the guard function `confirmSignOutWithLocalData(context, ref)`; the list of call sites in the test equals the list recorded in the S03-16 change record | a sign-out path skips the warning |

Level and count for EP-4 after the closing pass: S03-15 17 (W 16, K 1); S03-16 14 (W 11, I 2, K 1). Totals W 27, I 2, K 2 = 31 (batch 1: 30; revision 1: 20).

## 7. EP-5 closing tests (keyboard and pointer, conformance, conditional stories)

### 7.1 S03-17 Keyboard shortcuts, scroll, Back on Apple desktop, touch-only (file `keyboard_pointer_test.dart`)

Modifier: Cmd on faked iOS and macOS, Ctrl on faked Android. 1100x800 unless stated.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-KB-1a | AC-KB-1 | W | 2 | M | `/macOS`, `/android` | Modifier + 1 to 5 | Locations `/home`, `/workouts`, `/scan`, `/progress`, `/profile` in order | the wrong modifier or a wrong target |
| AC-KB-1b | AC-KB-1 | W | 1 | M | idle timers; macOS | Modifier + Shift + M, then Escape; modifier + Shift + R | `modeSwitcher.popover` opens; the Record surface opens | shortcut missing |
| AC-KB-1c | AC-KB-1 | W | 1 | M | set timer running; macOS | Modifier + Shift + R | The strip destination is pushed (no Record surface) | a second start surface while a session runs |
| AC-KB-1d | AC-KB-1 | I | 1 | M | non-home tab; pushed page | Modifier + `[` | On a non-home tab: `/home`; on a pushed page: pops it (AC-SH-2 behaviour) | shortcut and system Back differ |
| AC-KB-1e | AC-KB-1 | W | 2 | H | `/textField`, `/modalOpen` | Focus a `TextField` (or open a sheet), send modifier + 1 | No navigation | a shortcut fires while typing |
| AC-KB-1f | AC-KB-1 | W | 3 | M | `/iOS`, `/macOS`, `/android` | Modifier + `,` | iOS and macOS: `/settings` is pushed; Android: nothing | the settings shortcut leaks to Android |
| AC-KB-1g | AC-KB-1 | W | 1 | H | popover open; then a focused popup menu; then nothing open | Esc each time | Popover closes alone; the menu or field closes first; with nothing open Esc does NOT navigate back | Esc acts as Back |
| AC-KB-1h | AC-KB-1 | W | 1 | M | scrolled Home, selected destination | Click or Enter on the selected destination | The page scrolls to top; no route change | re-select navigates or does nothing |
| AC-KB-1i | AC-KB-1 | W | 1 | M | focus in the rail, then in a page | Home and End | Rail focus moves only with focus in `shell.rail`; with focus in the page they scroll it | keys hijacked in the page |
| AC-KB-5 | AC-KB-5 | W | 2 | M | `/wheel` (Home, Progress, Sources), `/scrollbar` (1100x800) | Send a `PointerScrollEvent`; look for `Scrollbar` | Each scrolls; a `Scrollbar` exists on each main scroll view | wheel does not scroll or no scrollbar |
| AC-KB-7 | AC-KB-7 | I | 1 | M | 360x800, touch events only | Run first run, switch mode, open Record sheet, follow a row | All flows pass unchanged | a flow needs hover or a key |
| AC-KB-8 | AC-KB-8 | W | 1 | M | `TargetPlatform.macOS`, 1100x760; pages S-1, S-2, S-8 | Pump each pushed page | `shell.back` found with a button role and label "Back" ("Назад") | no visible Back on a desktop pushed page (Apple part: faked platform only) |
| DT-17-1 | none | I | 1 | M | 1100x800, pointer only | First run: click through the chooser to Home, switcher, Record popover | Complete with clicks only | a path needs a key |
| DT-17-2 | none | I | 1 | M | 1100x800, keyboard only | Same flow with Tab, Arrow, Space, Enter, Esc | Complete with keys only; focus order logical | a keyboard trap |
| DT-17-3 | none (RV-18d) | W | 1 | M | 1100x800, nothing focused after the first pump | Modifier + 2 | `/workouts` is reached (the autofocus root `Focus` receives the key) | shortcuts work only after the user clicks something |
| DT-17-4 | none (RV-18d) | W | 1 | M | `/workout/:id` pushed (the scanner camera page is checked by the same assertion if it is a pushed route in the code map) | Modifier + 1 to 5 | No navigation (tab shortcuts act only on a shell route) | a shortcut leaves the workout player or scanner |

### 7.2 S03-18 Cross-cutting conformance (files under `mobile/test/features/s03_conformance/`)

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| AC-SH-6a | AC-SH-6 | W | 1 | H | `MockPermissionChannel`; 360x800 | Pump S-1, S-2, S-3, S-5 (without following a row), S-6, S-7, S-8 | Zero calls | any S03 screen asks for a permission |
| AC-SH-6b | AC-SH-6 | K | 1 | H | new S03 files | Scan imports | No location or permission package imported | a permission package sneaks in |
| AC-REG-1 | AC-REG-1 | I | 1 | H | existing scanner and equipment test files run unchanged (listed in the findings; no edit allowed); plus one new routing assertion | Route to `/scan` | `/scan` routes as before; the existing files pass | the shell breaks scanning (G-5) |
| AC-REG-2 | AC-REG-2 | U | 1 | H | `isDemoGatedPath` | Call for `/community`, `/celebrity-plans`, `/contribute`, `/moderate`, `/team/x` and for ordinary paths | Results equal the recorded pre-S03 values | gating changed |
| AC-REG-3 | AC-REG-3 | W | 0 | H | existing Home and Progress widget test files, default providers | Run unchanged; no new entry | The existing files pass without edits; edited expectations are a defect | the change forces existing tests to be edited (run evidence only, see section 8.4) |
| AC-REG-4 | AC-REG-4 | W | 2 | H | `/cloudOff`, `/cloudOn` | Pump S03 screens, search text | cloud off: no "sync", "Waiting to sync", "Could not sync" or `syncChip*` text; cloud on: the sync chips can appear | sync wording in the default build |
| AC-A11Y-1 | AC-A11Y-1 | W | 6 | H | 360x800 and 1100x800 as stated: `/chooserCards`, `/modeChip`, `/sheets` (rows and buttons), `/dock` (pill, strip), `/rail` (five destinations, `shell.rail.record`, container), `/recordRows` | `tester.getSemantics` with `matchesSemantics`; size of the tappable ancestor | Role button, non-empty label, expected hint, `isSelected` and `isEnabled` where specified, `hasTapAction`, hit region at least 48x48 | an icon-only or small target without a name |
| AC-A11Y-2 | AC-A11Y-2 | W | 1 | M | S-1, S-3, S-5, S-7b, S-8 | Read semantics | `isHeader` true for each title ("All activity" for S-7b) | a title is not a header |
| AC-A11Y-3 | AC-A11Y-3 | W | 3 | M | `/tabOrder` (S-1), `/focusReturn` (S-3 from `home.modeChip`), `/firstFocus` (sheet) | Tab events; open and close | Order: four cards, Continue, Decide later; focus returns to `home.modeChip`; first focus inside a sheet is its header | lost or wrong focus order |
| AC-A11Y-4 | AC-A11Y-4 | W | 4 | M | `MockAccessibilityChannel`; `/modeChange`, `/stripTransitions`, `/thirtySeconds`, `/labelStable` | Change mode; start, pause, resume, end a timer; advance the fake clock 30 s | One message with the new mode name; one message per strip transition; none for 30 s; the strip label unchanged until the minute boundary | announcement spam or silence |
| AC-A11Y-5 | AC-A11Y-5 | W | 4 | H | 360x640, scale 2.0; `/ru-A`, `/ru-B`, `/en-A`, `/en-B` (A: S-1, S-2, S-3, S-4; B: S-5, S-6, S-7a/b, S-8) | Pump each screen | No `RenderFlex` overflow; `didExceedMaxLines == false` for the keyed status-chip words, chip texts, button labels and headers | large text breaks a screen or clips a word |
| AC-A11Y-7 | AC-A11Y-7 | W | 2 | M | `TextDirection.rtl`; `/S-1`, `/S-4` | Pump | No overflow | RTL layout broken |
| AC-A11Y-8 | AC-A11Y-8 | K | 2 | M | new S03 files; `/literals`, `/semanticColours` | Scan for `Color(0x` and `Colors.`; scan for `warning`, `danger` or zone colours in a text style | Zero matches | raw colours or status colours as text |
| AC-KB-6 | AC-KB-6 | K | 1 | M | new S03 files | Scan for `onLongPress`, `onHorizontalDrag*`, `onScale*`, `Dismissible`, `onPan*` | Zero matches | a gesture-only path |
| AC-FAM-1 | AC-FAM-1 | I | 2 | M | `TargetPlatform.android`; `/360x800`, `/1100x800` | System Back on a non-home tab; AC-ST and S-5 flows | Back goes to `/home`; the strip and Record criteria hold | platform branch breaks Android |
| AC-FAM-2 | AC-FAM-2 | W | 2 | M | `/iOS-390x844`, `/macOS-1100x760` | Collect keyed nodes and labels; compare with the Android run | Identical key sets, copy and semantics; Apple Health row absent | an Apple branch changes copy or keys |
| AC-FAM-2k | AC-FAM-2 | K | 1 | M | new S03 files | Scan for `Cupertino` | Zero matches | a Cupertino widget appears |
| AC-FAM-3 | AC-FAM-3 | W | 2 | M | `/iPhoneInsets` (top 59, bottom 34), `/macTitleArea` (top 28, bottom 0) | Compare `Rect` of dock or rail and first and last child with the insets | No overlap | content under the home indicator or title area |
| AC-FAM-4 | AC-FAM-4 | W | 6 | H | scale 2.0; `/ru-360x800`, `/ru-700x900`, `/ru-1100x800`, `/en-360x800`, `/en-700x900`, `/en-1100x800`; screens S-1, S-3, S-5, S-6, S-7, S-8 and the rail | Pump | No overflow; `didExceedMaxLines == false` for status words, chip texts, button labels, headers and rail labels | one class breaks at large text |
| AC-FAM-5 | AC-FAM-5 | W | 2 | L | `/iOS` with `MockHapticChannel`, `/macOS` with the channel absent | Select a mode; tap Continue | iOS: haptic called once for each; macOS: no failure | haptics crash a desktop |
| AC-FAM-6 | AC-FAM-6 | W | 2 | M | 1100x800; `/reducedMotion`, `/rtl` | Pump S-1 | No animation under `disableAnimations`; RTL puts the rail on the right and the detail panel on the left with no overflow | motion or RTL ignored on large windows |
| AC-LS-9 | AC-LS-9 | W | 10 | H | `ru`; `/home840-2.0`, `/progress900-1.3`, `/sources840-2.0`, `/chooser900-1.3` (each: no overflow, horizontal scroll extent zero, below the pane minimum the key order equals Compact and `home.pane.side`, the Progress right column and `modeChooser.detailPanel` are absent; the chooser has its panel at exactly 840), `/home1100-1.0` (two panes, pane 980), `/home1100-1.3` (one column when the measured rail is extended, else two panes: follows AC-WS-3), `/home1200-1.0` (two panes, pane 936), `/tiles360`, `/tiles700`, `/tiles1100` (every tile width at least 160 dp) | Pump | As listed in each name | a two-pane layout that overflows at large text, or tiles under 160 dp |
| AC-LS-10 | AC-LS-10 | W | 2 | M | `/home`, `/progress`; 700x900 to 1100x800 and back | Scroll so `home.section.upcoming` (or `progress.recent`) is first visible; resize twice | The section is still on screen after each change | the scroll anchor is lost |
| AC-RET-1a | AC-RET-1 | K | 1 | H | ARB additions of S03 | Search for "never keep", "forever", "indefinitely" and "never" in any retention sentence | Zero matches | forbidden retention wording |
| AC-RET-1b | AC-RET-1 | K | 1 | H | S03 widgets, fixtures, constants | If any names a retention value, assert the allowed set is exactly {90, 365, 730} and the default 730 | Set and default hold (or no retention value exists) | a wrong retention constant |
| AC-RET-1c | AC-RET-1 | W | 1 | M | S-8 | Pump Sources | No retention text | retention copy appears before the consent centre exists |
| DT-18-1 | none | I | 1 | H | 360x800; REAL `SetTimerController` and `RestTimerController` with an injected clock (TP-2); Home | Switch mode, go to Workouts, tap the strip, switch mode back; advance the fake clock 5 s after each step | Timers equal by value at every step and still ticking (elapsed grows by 5 s each time); the strip opens the stored route; no dialog appears | the sprint gate "mode switch never resets a running session" is broken |
| DT-18-2 | none | U | 1 | M | `app_en.arb` and `app_ru.arb` additions | Parse | Every `en` key has an `ru` key with the same placeholders; `ru` plurals have one, few, many, other; budgets of design 6 hold for the keys listed there | a missing translation or plural form |
| DT-18-3 | none | W | 1 | M | pseudo-locale and long Russian strings at 320 dp and scale 2.0 | Pump S-1, S-3, S-5 | No overflow; `modeBodyDesc` wraps to at most 3 lines and is never ellipsised (design DD-4) | long text clipped |
| DT-18-4 | none | W | 1 | M | rotation 360x800 to 800x360 with S-3 open | Pump | One surface instance; focus and scroll kept; no write | a sheet is lost or duplicated on rotation |
| DT-18-5 | none (RV-5) | K | 1 | M | the file-ownership table of design 9.2 (path to lane) | Parse the table | Each path appears in at most one lane; `app_router.dart` only in lane L5; `hud_scaffold.dart` only in L4a (design 9.2, table "path to lane") | two agents edit one file in parallel |
| DT-18-6 | none (RV-17) | K | 1 | L | `core/DATA_INVENTORY_2026-08-11.md` and `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md` | Search | Both name `activity_journal` and the mode key row exists | the on-device journal is missing from the data inventory |
| DT-18-7 | none (TP-4) | K | 1 | H | the K scan set of section 1.3 item 10 | Resolve the file list | Count at least the recorded minimum; the anchor files (rail, chooser, strip, Sources) are in the set; no scanned directory is empty; the scanner finds a planted sentinel token in an in-memory sample | a scan goes green over an empty or truncated file list |

Row `AC-REG-3` has N=0 (run evidence only, no new entry).

### 7.3 Conditional stories (counted separately; built only if the design question is answered yes)

Open (DD-3, DQ-12): the width cap value of the pushed-page frame (design 9.2 places the frame in lane L5, no value is written) and the notification routing callback location (lane L11, files UNKNOWN). The payload rules (fixed allow-list, own session id, ignored while signed out or in onboarding) are final in F-44.

| Id | AC | Lvl | N | Sev | Config | Steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|---|
| DT-19-1 | none | W | 1 | M | 1100x800; pushed page (not camera) | Pump | Content is capped at the DQ-12 width and centred | pushed pages stretch to the window |
| DT-19-2 | none | W | 1 | M | a camera page | Pump | Not framed | a frame breaks the camera preview |
| DT-19-3 | none | W | 1 | M | 360x800 and 700x900 | Pump a framed page | Identical to the unframed layout | a regression on phones |
| DT-19-4 | none | W | 1 | M | macOS faked | Pump | `shell.back` visible on the framed page (AC-KB-8 extension) | no Back on a framed page |
| DT-19-5 | none | W | 1 | L | 1100x800 to 360x800 | Resize | No overflow; scroll offset kept | resize loses the position |
| DT-19-6 | none | W | 1 | L | scale 2.0 `ru` | Pump | No overflow | large text breaks the frame |
| DT-20-1 | none | I | 1 | M | tap with a valid scheduled session id | Invoke the tap callback | Router location equals the Home start card target (`/workout/:id?day=...`) | the tap opens nothing |
| DT-20-2 | none | I | 1 | H | mode `body` | Invoke the tap | The mode is still `body` and no `modeChanged` event (R-M4) | a notification changes the user's mode |
| DT-20-3 | none | W | 1 | M | unknown session id | Invoke the tap | Home and a snackbar with `homeScheduledGone` | a dead link opens a broken page |
| DT-20-4 | none | I | 1 | M | signed out or onboarding pending | Invoke the tap | The target is dropped (no deferred routing, DQ-8) | the target is replayed after login |
| DT-20-5 | none (RV-15) | I | 1 | H | payload carrying an arbitrary route string (`/settings`, `//evil`) | Invoke the tap | Ignored; only the fixed allow-list of route templates with an existing own session id is routed | a payload navigates to any route |
| DT-20-6 | none (RV-15, F-44) | I | 1 | H | payload with a well-formed session id that is not among the signed-in user's own sessions (another uid's id) | Invoke the tap | Treated like an unknown id: Home and the `homeScheduledGone` snackbar; no navigation to `/workout/:id` | a user opens someone else's scheduled session |

Level and count after remediation batch 1: S03-17 21 (W 17, I 4); S03-18 68 (W 52, K 10, I 4, U 2); S03-19 6 (W 6); S03-20 6 (I 5, W 1). Unconditional totals for this section: W 69, K 10, I 8, U 2 = 89 (unchanged by the closing pass); conditional W 7, I 5 = 12 (batch 1: 11).

## 8. Failure-row map, cross-cutting negative matrix, flakiness, Android limits

### 8.1 Failure rows of the design (section 7) mapped to tests

Source: design section 7.1, failure rows F-1 to F-45 (the table is final). The plan owns every test id; the "Tests" column uses the plan's ids, not the design's earlier citations (the design writer rewrites its citations to these ids). Every row has at least one test; rows that had none got a new test in the closing pass (marked NEW).

| Row | Cause -> required effect (short) | Tests |
|---|---|---|
| F-1 | Mode write throws -> mode active for the session, `modeChooser.saveError`, `pending` kept | AC-CH-6, DT-01-5 |
| F-2 | Switcher write throws -> lens changes, snackbar `modeSwitchSaveError` | DT-10-1 |
| F-3 | Stored value corrupt, unknown shape or newer version -> `unreadable`, no write | DT-01-1, DT-01-2, DT-01-3, DT-01-16, DT-01-17, DT-01-18 |
| F-4 | Profile not loaded at start -> migration waits, no chooser while `absent` | DT-01-22 (NEW), DT-01-13, DT-01-14 |
| F-5 | App killed during the chooser -> `pending` persists | AC-CH-5, DT-08-8 |
| F-6 | Onboarding finish write fails or page unmounted -> `/home` still reached, content-free log | DT-01-15, AC-CH-8c |
| F-7 | `/onboarding/edit` for an onboarded user -> no-op | AC-CH-8d |
| F-8 | Mode changed while a gym timer runs -> timers untouched | AC-SW-2, AC-ST-4, DT-18-1 |
| F-9 | Account switches while a mode write is in flight -> write refused | DT-01-23 (NEW), DT-01-20 |
| F-10 | Account switches while the chooser or switcher is open -> re-read, no write | DT-08-10 (NEW), DT-10-5 (NEW) |
| F-11 | Account switches while a timer runs -> strip and pill hidden for the other account | DT-07-8, DT-01-7 |
| F-12 | Process killed while a timer ran -> no strip, no recovery claim | AC-ST-8 |
| F-13 | A timer provider becomes auto-dispose | DT-07-12 (NEW, declaration check), DT-07-13 (NEW, behavioural) |
| F-14 | Strip or pill provider throws -> strip hidden, timers reachable, content-free log | DT-07-1 |
| F-15 | Journal `list()` throws or the bind fails -> per-state handling, same-uid value kept, other uid's never | AC-HM-5, AC-PR-2, AC-SRC-3, DT-13-10, DT-13-11, DT-13-12, DT-14-1, DT-14-6 |
| F-16 | Try again tapped repeatedly -> one attempt (single flight) | AC-PR-2, AC-SRC-3, DT-0-5, DT-0-13, DT-0-14, DT-14-1 |
| F-17 | Deleted entry still on screen -> refresh removes it, revision seam | DT-14-7 (NEW), DT-13-20 (NEW) |
| F-18 | Account deletion -> mode key removed | DT-01-24 (NEW), DT-01-20 |
| F-19 | Sign-out with local-only sessions -> warning, export first, second confirmation | AC-SO-1, AC-SO-2, DT-16-1, DT-16-2 |
| F-20 | Sign-out call site misses the guard | DT-16-9 (NEW) |
| F-21 | Live window resize across a boundary -> route, selection, mode, timers, focus, surface kept | AC-WS-5, AC-WS-14b, AC-CH-14, AC-LS-10, DT-05-3, DT-06-2 |
| F-22 | Text scale 2.0 in Russian | AC-A11Y-5, AC-WS-3, AC-FAM-4 |
| F-23 | Very short window -> rail fits | AC-WS-10 |
| F-24 | Shell restructure breaks Android first-Back | AC-SH-2, `back_navigation_test.dart` unchanged |
| F-25 | Dock padding double-counted or missing | AC-ST-6, AC-WS-8, AC-PR-9, DT-07-11 |
| F-26 | Question save fails -> Skip and Back enabled | AC-Q-5, DT-09-2 |
| F-27 | Unknown sport or kind -> exhaustive grouping, `other`, `fileImport` | AC-SRC-6, DT-13-21 (NEW), DT-13-19 |
| F-28 | Session lacks time or distance -> never zero | AC-PR-4, DT-13-22 (NEW), DT-13-17 |
| F-29 | Clock or zone change -> calendar-date comparison | AC-PR-7, DT-13-1, DT-13-2 |
| F-30 | Large journal -> gates G1 and G2 | DT-13-23 (NEW, MEASURE-ONLY G1), DT-14-8 (NEW, MEASURE-ONLY G2), DT-14-9 (NEW, G3: no load in `build`), DT-13-14 (coalescing) |
| F-31 | Backup exclusion does not match the real tree | DT-0-6, DT-0-7, DT-0-8 |
| F-32 | A shortcut fires under a modal or in a text field | AC-KB-1e |
| F-33 | Reminder tap during sign-in or onboarding | DT-20-4 |
| F-34 | Cloud flag off but sync text shown | AC-REG-4, DT-0-2 |
| F-35 | Mode state read before profile or auth is ready -> no wrong-lens flash | DT-12-4 (NEW), DT-01-9 |
| F-36 | Stored mode unreadable or load fails | DT-01-16, DT-01-17, DT-01-18, DT-01-19, DT-01-2 |
| F-37 | Journal binding or gave up -> LOADING never EMPTY, error panel | DT-13-8, DT-13-11, DT-13-13, DT-0-9, DT-0-11, DT-0-12, DT-0-13 |
| F-38 | A load for the previous account completes after a switch | DT-13-9, DT-13-10, DT-13-15 (also retry rule 5: timer cancelled, stale completion discarded) |
| F-39 | Chooser re-offered, or offered during the Day-3 modal | DT-08-7, DT-08-8, DT-08-9 |
| F-40 | Recovery lost activities -> notice and "may be incomplete" | DT-0-9, DT-13-16, DT-14-5, DT-15-4 |
| F-41 | Refresh fails after success -> stale line, Problem chip, unreadable sessions apart | DT-13-12, DT-13-17, DT-14-6, DT-15-5 |
| F-42 | Sign-out guard cannot check the journal | DT-16-4, DT-16-2 |
| F-43 | Mode write or migration for a wiped uid | DT-01-20 |
| F-44 | `/mode-questions/:mode` or a payload outside the allow-list | DT-09-6, DT-20-5, DT-20-6 (NEW) |
| F-45 | Export or wipe fails during sign-out | DT-16-5, DT-16-6, DT-16-7, DT-16-8 |

Other failure situations from the contract kept from revision 1: process killed during questions (DT-09-5), window resize with the strip (DT-07-6, DT-18-4).

### 8.2 Negative and edge matrix (what the contract implies but the ACs do not list)

| Situation | Tests | Assertion that would fail |
|---|---|---|
| Account switch during a running session | DT-01-7 (timers not touched by mode logic), DT-16-3 (journal not shown to another account) | a timer notifier call from the mode store; session rows visible under account B |
| Mode switch during a running session | AC-SW-2, AC-ST-4, DT-18-1 | timer provider states differ by value, or a dialog appears |
| Sign-out with local activity | AC-SO-1, AC-SO-2, DT-16-1, DT-16-2, DT-16-3 | delete spy called before the second confirmation; prompt for an empty journal |
| Corrupt or missing stored mode state | DT-01-1, DT-01-2, DT-01-3, DT-01-10 | an exception, an unavailable mode selected, or the chooser and the intro card shown together |
| Journal closed/open flips | DT-0-3, DT-0-5, DT-0-11 to DT-0-14, DT-14-1, DT-14-3, AC-LS-5 | stale block or panel after a flip; a second concurrent attempt; the automatic schedule disabled by a manual attempt or restarted after giving up |
| Clock and time zone at week boundaries | AC-PR-7, DT-13-1, DT-13-2, DT-07-3, DT-07-4, AC-HM-3 | session in the wrong week or day; strip visibility changes with the zone |
| Empty / loading / partial / error / offline | AC-PR-1, AC-PR-3, AC-PR-4, AC-LS-5, DT-14-2, DT-15-1, AC-SRC-2, AC-SRC-3, AC-HM-5, DT-08-3 | zero shown for unknown, spinner, new error text on Home |
| Text scale 2.0 | AC-A11Y-5, AC-FAM-4, AC-LS-9, AC-CH-13, AC-HM-6, AC-LS-3, AC-ST-9, DT-03-2 | `RenderFlex` overflow or `didExceedMaxLines == true` |
| Russian long strings and plurals | DT-18-2, DT-18-3, DT-10-2, DT-13-4, DT-13-5, AC-A11Y-5 | missing plural form, clipped text |
| Reduced motion | AC-A11Y-6a, AC-WS-14a, AC-FAM-6, DT-07-7 | `pumpAndSettle` waits, animation present |
| Rotation and resize mid-flow | AC-CH-14, AC-WS-5, AC-WS-9, AC-WS-14b, AC-LS-10, DT-02-3, DT-07-6, DT-18-4 | lost route, selection, focus, scroll or a write |
| Keyboard-only and pointer paths | AC-KB-1a..i, AC-KB-2, AC-KB-5, AC-KB-7, DT-17-1, DT-17-2, DT-08-1, DT-08-2 | a trap, a hijacked key, a path needing hover |

### 8.3 Flaky-test risks and how the test agents avoid them

| Risk | Where | Avoidance |
|---|---|---|
| Wall-clock timers, minute boundaries | strip (AC-A11Y-4, DT-07-3), 300 ms loading rules (DT-08-3, DT-09-1), 1 s "Checking" (DT-15-1) | `FakeClock` and `tester.pump(Duration)` with fixed steps; no `Future.delayed` against the real clock; no `sleep` |
| Open-ended animations and `pumpAndSettle` | sheets, popovers, strip | Use `disableAnimations` where the row allows, otherwise `pump` with explicit durations; never `pumpAndSettle` on a tree with a looping animation; the S03 tree has no looping indicator (AC-A11Y-6b) |
| Timeouts under parallel load (large payloads of the 32 MiB class, journals of thousands of sessions, the S02 run of 21 minutes in the findings) | aggregates, Progress with many sessions, any journal fixture | S03 fixtures stay small (at most 200 sessions; the week and recent rules need only a handful); run with `--timeout 60s` as in S02 and add `--concurrency=1` for the conformance suite if load causes timeouts; a timeout is a defect to report, not a retry-until-green |
| Window size and device pixel ratio leaks between tests | every size row | `tester.view.physicalSize` and `devicePixelRatio` set in a helper and reset in `addTearDown` |
| Shared mutable fixtures and singleton providers | stores, flags | Every test builds its own `ProviderScope` and fakes; no static state; no order dependence |
| Platform override leaks | FAM rows | `debugDefaultTargetPlatformOverride` set and reset in the same test with `addTearDown`; asserted null at the end of the file |
| Focus and hover state | KB rows | Create a fresh `TestGesture` per test; `addTearDown(gesture.removePointer)`; send key events with `tester.sendKeyEvent` and `pump` once |
| Random | none | no random in any test; the S02 corpus seed is not reused |
| Real controllers under FakeAsync (TP-2, RV-8) | timer-preservation rows, DT-07-9, DT-07-10 | The REAL `SetTimerController`, `RestTimerController` and the status timer factory run under `FakeAsync` or `tester` time with an injected clock. At the end of each such test, and for the 300 ms and 400 ms loading rules (DT-08-3, DT-09-1) and the 1 s "Checking" wait (DT-15-1), the test agents check that no timer is left pending (`tester.binding.hasScheduledFrame` false and the `FakeAsync` pending-timer count zero, or the test disposes the scope first); a leftover timer is a defect to report |
| Interleavings (RV-1, RV-3) | DT-01-12, DT-13-9 | Orders are forced with `Completer`s, never with sleeps |
| Bind retry schedule (5 s, 15 s, 60 s, 5 min, 5 min) | DT-0-5, DT-0-11 to DT-0-14, DT-13-11, DT-14-1 | Only the fake `activityBindRetryTimerFactoryProvider` is used; time advances by explicit steps, never by real time; each test ends with zero armed timers or disposes the scope first; the manual and automatic orders are forced with `bindUid` completers |
| Font metrics | AC-WS-3, A11Y-5, FAM-4, LS-9 | The expectation is computed with the same `TextPainter` in the same test (so the rule holds under whatever font the test uses); see 8.4 for what this does not prove |

### 8.4 What is only partly proved on Android (and what is not run)

None of the 124 criteria is wholly untestable; the following can be proved only up to the stated limit and must be recorded as "faked" or NOT_RUN, never as passed on a device (design 1.8 extended).

| Criteria | Exact limit |
|---|---|
| AC-FAM-1 to AC-FAM-6 (Apple parts) | A faked `TargetPlatform` and injected `MediaQuery` insets exercise only Dart branches. No iOS, iPadOS or macOS build exists, so real Apple rendering, safe-area behaviour (AC-FAM-3 uses injected numbers 59 and 34, 28 and 0), real haptics (AC-FAM-5 uses a mocked channel) and the macOS menu bar are NOT_RUN |
| AC-KB-1 (Apple modifier, `Cmd+,`), AC-KB-8 | Cmd versus Ctrl comes from a faked platform and synthetic key events; real macOS key routing and trackpad are NOT_RUN |
| AC-KB-5 | Wheel events are synthetic `PointerScrollEvent`s; real trackpad inertia is NOT_RUN |
| AC-A11Y-1, AC-A11Y-2, AC-A11Y-3, AC-A11Y-4 | Flutter semantics tree and a mocked accessibility channel only; TalkBack and VoiceOver reading order and spoken text are NOT_RUN (go to the independent a11y review, contract 14) |
| AC-KB-3 | The ring is checked as a painted decoration found in the tree, not as visible contrast on a device |
| AC-KB-9 | Token-level contrast from `HudTokens` values; contrast over the photograph panel is not measured (contract 17.8) |
| AC-WS-3, AC-A11Y-5, AC-FAM-4, AC-LS-9, AC-LS-4 | Verified by the review (TP-1): the project loads no real font in `mobile/test` (no `loadFont`, `FontLoader`, `flutter_test_config` or `google_fonts`), so the default test font Ahem is used and a font-measured label is wider than 96 dp. Font-measured expectations for AC-WS-3 are therefore vacuous for the 96 dp form; the 96 dp and 240 dp forms are proved only through the `railLabelMeasurerProvider` stub (AC-WS-3b: 70 dp and 90 dp) plus the guard DT-05-2; the default TextPainter measurer is exercised only by the font-measured entries and by DT-05-5. Russian string widths measured in the test are Ahem widths; real Roboto widths on devices are not proved |
| AC-ST-8 | Timers are memory-only (expected per contract R-S5); the process-death simulation is a fresh scope, not a real kill |
| DT-0-6, DT-0-7, DT-0-8 (backup exclusion) | The test proves that the XML names match what the code writes (names and paths); Android's actual Auto Backup and device-transfer behaviour is NOT_RUN |
| AC-WS-9 | Asserts the app issues no preferred-orientation call; manifest `resizeableActivity` and Android 16 behaviour are not tested (contract 17.16) |
| AC-A11Y-6, AC-WS-14, AC-FAM-6 | Reduced motion is simulated with `MediaQuery.disableAnimations`; the Android "remove animations" system setting is NOT_RUN |
| AC-SH-6 | A mocked method channel proves no call; a real OS permission dialog is never opened by any test |
| AC-REG-1, AC-REG-3 | Evidence is the run of the existing test files unchanged (plus one new routing assertion for REG-1); there is no new assertion for REG-3, and the criterion cannot detect a regression in code the existing tests do not cover |
| AC-LS-7 | An alias of AC-CH-9 to AC-CH-14; proved only through those entries (N=0) |
| AC-RET-1 | Copy and static checks only; the retention control UI belongs to the consent-centre sprint |

### 8.5 DEPENDS-ON-DESIGN items

Closing pass: the items below were read against the final design (sections 2, 3, 4, 5, 7, 8, 9). Table A lists the names and values that replace the old tags (the test agents use these names); table B lists what the design still leaves open, with the decision it waits for. A row tagged OPEN-NAME means the design fixes the behaviour but not the identifier; the identifier is read from the interface commit of the named lane (design 9.2, "Pre-agreed interface commits") and is not guessed.

**A. Resolved (final names and values)**

| Item | Final name or value | Rows | Design section |
|---|---|---|---|
| Flag override and defaults | Tests override `activityFlagsProvider` with an explicit `ActivityFlags(...)` (constructor defaults stay false); `ActivityFlags.compileTime` reads `ACTIVITY_LOCAL_JOURNAL` with `defaultValue: true`, `ACTIVITY_CLOUD_STREAMS` stays false; `ModeFlags` (`modeFlagsProvider`, `rideEnabled`, `exploreEnabled`, defines `MODE_RIDE`, `MODE_EXPLORE`, false) in `features/modes/state/mode_flags.dart`; one unit test pins the unmodified compile-time defaults (journal on, cloud off, ride and explore off) | DT-0-1 to DT-0-4, AC-REG-4 | 2.1 item 1, 4.2, 4.3 |
| Journal availability | `journalAvailabilityProvider` (Notifier, `features/activity/state/journal_availability.dart`), sealed `JournalAvailability` = `notEnabled`, `binding`, `open`, `gaveUp`, `failedToOpen`; `open` only when bound and `boundUid == authUid`; `retryNow()`; the companion bind-status Notifier in `core/wiring/activity_wiring.dart` publishes `binding(uid)`, `bound(uid)`, `gaveUp(uid)`, `recoveredAbsentCount`, `streamLostCount` | DT-0-3, DT-0-4, DT-0-5, DT-0-9, DT-13-8, DT-13-11, DT-13-13 | 2.1 item 3 |
| Digest provider | `activityDigestsProvider` (AsyncNotifier, `features/activity/state/activity_dashboard_providers.dart`); `DigestSnapshot{ownerUid, loadedAt, lastLoadFailedAt, digests, unreadableSessions, recoveredAbsent, streamLost}`; `refreshIfStale()`; `activityJournalRevisionProvider`; pure functions in `features/activity/data/activity_aggregates.dart`: `groupOf`, `aggregateWeek`, `todaySessions`, `recentSessions`, `sourceLabelOf`; predicate `isEstimate`; `SessionDigest` | DT-13-6 to DT-13-24 (plan ids), DT-14-x | 2.4, 3.1, 3.4, 3.5, 3.7 |
| Time rules | Week = Monday 00:00 local (inclusive) to next Monday (exclusive), shared with `progress_stats.dart` (helpers extracted without behaviour change); zone through a `ZoneFn` parameter; "now" from `homeNowProvider`; calendar-date comparison across DST | AC-PR-7, DT-13-1, DT-13-2 | 3.2 |
| Perf gates | G1: 5,000 digests at most 2 ms and 20,000 at most 10 ms (median of 20); G2: `list()` plus conversion of 5,000 sessions at most 250 ms and at most 16 ms of continuous synchronous work; G3: no load in `build` | DT-13-23, DT-14-8, DT-13-14 | 3.8 |
| Mode state API | `ModeStore.read(uid)` returns `missing`, `value(state)` or `unreadable(corrupt | newerVersion | unknownShape)`; `ModeNotifier`: `selectMode`, `resolveChooser`, `decideLater`, `answerQuestion`, `skipQuestion`, `markResolved`, `initIfAbsent(InitSource.migration | onboarding)` (migration writes `migrated`, onboarding writes `pending`); `modeStateProvider`, `modeChangedProvider`, `modeWarmUpProvider` (one `Provider<void>`); files under `mobile/lib/features/modes/` | DT-01-x, AC-CH-8x | 2.2 |
| Mode storage and scoping | SharedPreferences key `activity.mode.v1.<uid>`, value `{"v":1,"mode":..,"chooser":..,"answers":{..}}`; uid guard and wiped-uid guard on write and `initIfAbsent`; sign-out writes nothing; account switch gives a new key; account deletion removes the key through the `activity.` prefix of `DeviceLocalDataWipe`; key excluded from backup through `FlutterSharedPreferences.xml` | DT-01-6, DT-01-7, DT-01-20, DT-01-23, DT-01-24, DT-01-25 | 5.1 to 5.4 |
| Restore before the first frame | Warm-up during splash; Home renders the pre-S03 TRAIN order without a chip while loading | DT-01-9, DT-12-4 | 2.2, F-35 |
| Chooser trigger and Back | Home opens the chooser with `go('/mode-chooser')` (replace, contract J1); `offeredThisRun` keep-alive set per uid; Home waits for the Day-3 decision; system Back through `PopScope` equals "Decide later" (`selectedMode=train`, `chooserStatus=resolved`) | DT-08-7, DT-08-8, DT-08-9 | 2.3, F-39 |
| Route validation | `/mode-questions/:mode` must parse to an AVAILABLE `AppMode`, else redirect `/home` with no write; new routes `/mode-chooser`, `/mode-questions/:mode`, `/sources` (names PROPOSED) outside the shell | DT-09-6 | 2.3 |
| Active session | `activeSessionStatusProvider` and `activeSessionOwnerProvider` (`ActiveSessionOwner{uid, destination}`) in `features/workouts/state/active_session_status.dart`, written by `workout_player_page.dart` start paths; hide when `owner.uid` differs; owner cleared by `ref.listen`; one-shot timers at `endsAt` and at `endsAt + 10 min` (strip hidden at exactly 10:00 after finish; visible at 9:59); cancelled with `ref.onDispose` | DT-07-3, DT-07-8, DT-07-9, DT-07-10, AC-ST-3 | 2.6, contract S-4 |
| Rail label measurer seam (TP-1) | `typedef RailLabelMeasurer = double Function(String label, TextStyle style, TextScaler scaler);` and `final railLabelMeasurerProvider = Provider<RailLabelMeasurer>` in `mobile/lib/shared/widgets/shell_layout.dart` (lane L4a); default TextPainter-based, memoised by (locale, text scale, font family, label set); tests override it with a fixed-width stub (70 dp gives the 96 dp rail, 90 dp the 240 dp rail). The project's tests load no real font (Ahem), so the default measurer under test would make every label wider than 96 dp | AC-WS-3b, DT-05-2, DT-05-5 | 2.6, 8.3 |
| Shell types | `classifyWindow`, `WindowSizeInfo{sizeClass, isShort, usesRail}`, `windowSizeOverrideProvider`, `ShellLayout`, `kShellDestinations`, `HudSideRail`, `AdaptiveSurface.show`, `s03Routes`; the override seam for window class is `windowSizeOverrideProvider` | S03-02 to S03-06 rows | 2.6 |
| Sign-out | Guard `confirmSignOutWithLocalData(context, ref)` (`features/activity/state/sign_out_guard.dart`), sheet `features/activity/widgets/sign_out_warning_sheet.dart`; delete through `ActivityWipeCoordinator.onSignOut` after a second confirmation; export through `activity_local_export.dart` (`ActivityExportFormat`) | AC-SO-1, DT-16-x | 2.5 |
| Backup exclusion | One shared constant `activity_journal` (scoped root) used by `fileActivityJournalFactory` and `kActivityBackupExcludedDirs`; `<exclude domain="file" path="activity_journal" />` in `backup_rules.xml` and both sections of `data_extraction_rules.xml`; legacy names kept; the updated tests are `mobile/test/android/backup_rules_test.dart` and `backup_exclusion_test.dart` | DT-0-6, DT-0-7, DT-0-8 | 2.1 item 6, 4.4 |
| Failure table | F-1 to F-45 final | section 8.1 | 7.1 |
| File ownership and lanes | Table "path to lane" and lanes L1 to L12 (L4a, L4b, L12 included) | DT-18-5, sections 1.4, 9.2 | 9.2 |
| Test folders | `mobile/test/features/modes/`, `mobile/test/features/activity/{data,state,config}/`, `mobile/test/shared/widgets/`, `mobile/test/router/`, `mobile/test/android/`, `mobile/test/features/account_deletion/` (design 8.2); the focused-command form `flutter test --timeout 60s <paths>` from `mobile/` (design 8.5) | section 1.3 item 3, section 9.2 | 8.2, 8.5 |

**B. Still open (waiting for a named decision or a first step)**

| Item | Rows | Waits for |
|---|---|---|
| Project-pinned Flutter executable path | section 9.2 | Design 8.5 UNGROUNDED (R12); the test agent logs `flutter --version` and the resolved path |
| OPEN-NAME identifiers: the companion bind-status Notifier class, the shared backup constant identifier, the status timer-factory seam, the destination provider (now `activeSessionOwnerProvider`), the shell label style | DT-0-9, DT-0-7, DT-07-9, DT-07-10 | Interface commits of lanes L1 and L4b (design 9.2) |
| Sign-out call sites; the write location of `activity_local_export.dart`; whether `ActivityWipeCoordinator.onSignOut` deletes the departing uid's journal (if not, S03-16 stops) | AC-SO-1, DT-16-5, DT-16-8, DT-16-9 | First step of S03-16 (R12); DD-8 (the operator may drop S03-16) |
| Health Connect row wording and the false-status risk | AC-SRC-4, DT-15-6 | DD-7 (default option A: contract wording "Not connected") |
| Home week-start rule (the new blocks use Monday; Home's own strip is not changed) | AC-HM-3, DT-13-2 | DD-9 |
| Journal read cost; a G2 miss does not block S03 | DT-14-8 | DD-10 |
| Pushed-page frame width cap and the notification payload mapping and callback location | DT-19-1 to DT-19-6, DT-20-1 to DT-20-6 | DD-3 and DQ-12; design 2.6 does not list the frame, 9.2 puts it in lane L5 |
| `/nutrition/add` and `/nutrition/weight` paths, scheduled-session provider item shape, `ob_shell` and `inputs` paths, `Back` and `Cancel` keys, Flutter SDK version (sheet animation style) | DT-11-4, AC-RC-2, AC-RC-3, AC-Q-x, AC-LS-8, AC-WS-14 | UNGROUNDED facts with a named first step in S03-09, S03-11, S03-06 (design 9.3 R12) |
| `modeBodyDesc` length (three lines allowed) | DT-18-3 | DD-4 (default taken) |
| Account-scoped mode state instead of per-device | DT-01-6 | DD-6 (default taken: account-scoped) |

### 8.7 Review decisions (RV) and test-plan findings (TP) mapped to tests

| Item | Tests |
|---|---|
| RV-1 migration vs onboarding race | DT-01-12, DT-01-13, DT-01-14, DT-01-15, AC-CH-8a to 8d |
| RV-2 unreadable stored mode | DT-01-1, DT-01-2, DT-01-3, DT-01-16, DT-01-17, DT-01-18, DT-01-19 |
| RV-3 journal availability, digests, account safety | DT-13-8 to DT-13-15, DT-13-13 (availability); bind retry state machine (single flight, schedule kept, gave up): DT-0-5, DT-0-11, DT-0-12, DT-0-13, DT-0-14 |
| RV-4 owner uid at start | DT-07-8, DT-01-7 |
| RV-5 build lanes | DT-18-5 |
| RV-6 swap keeps element tree | DT-05-3 (and `back_navigation_test.dart` unchanged) |
| Design "plan gap" items 1 to 11 (closing pass) | 1 DT-07-12, DT-07-13; 2 DT-01-24; 3 DT-01-25; 4 DT-14-7; 5 DT-16-9; 6 DT-08-10, DT-10-5; 7 DT-13-14, DT-13-20; 8 DT-13-24; 9 DT-13-23, DT-14-8 (MEASURE-ONLY); 10 DT-14-9; 11 DT-0-10 |
| RV-7 chooser route semantics | DT-08-7, DT-08-8, DT-08-9 |
| RV-8 driven strip transitions | DT-07-9, DT-07-10, DT-07-3 |
| RV-9 surface is a route | DT-06-2, DT-06-3, DT-06-4, AC-WS-14b |
| RV-10 recovery report surfaced | DT-13-16, DT-14-5, DT-15-4 |
| RV-11 stale marker, unreadable sessions | DT-13-12, DT-13-17, DT-14-6, DT-15-5 |
| RV-12 sign-out guard | DT-16-4, DT-16-5, DT-16-6, DT-16-7, DT-16-2 |
| RV-13 backup exclusion | DT-0-6, DT-0-7, DT-0-8 |
| RV-14 wiped-uid guard | DT-01-20 |
| RV-15 route and payload validation | DT-09-6, DT-20-5 |
| RV-16 export location and logging | DT-16-8, DT-13-18, DT-01-15 |
| RV-17 docs follow-up | DT-18-6 |
| RV-18 Flutter minors | DT-01-21 (a), AC-WS-3 and DT-02-3 (b), DT-05-5 (c), DT-17-3, DT-17-4 (d), DT-07-11 (e) |
| RV-19 labels | DT-13-19, DT-15-6 (AC-SRC-6 keeps "File import" for an unrecognised stored name, contract 8.1) |
| TP-1 rail 96 dp | AC-WS-3b, DT-05-2, section 8.4 |
| TP-2 real controllers | AC-WS-5, AC-SW-2, AC-ST-4, DT-01-7, DT-18-1, convention 11 |
| TP-3 RUNS-AFTER | AC-WS-4, AC-WS-10, AC-WS-11, section 1.4 rule, section 9.2 |
| TP-4 K scan sets | convention 10, DT-18-7 |
| TP-m1 to TP-m5 | AC-ST-8, AC-HM-1 and DT-03-1, AC-SH-2, DT-07-3 and AC-ST-3, AC-PR-9 |

### 8.6 Which assertion fails if the guarded behaviour breaks (by group)

Stated per row in the column "Fails when". The groups and their load-bearing assertions: (1) write ordering and "no write" (write spy with sequence numbers: AC-CH-2, AC-CH-4, AC-CH-8c, AC-SW-3, AC-SW-5, AC-RC-4, AC-CH-14, AC-LS-8d); (2) layout class and form (computed expectation from the rule and `Rect` comparisons: AC-WS-2, AC-WS-3, AC-CH-9 to AC-CH-12, AC-LS-1, AC-LS-4); (3) state tables (value-equality of provider states and presence or absence of keys: AC-ST-3, AC-PR-1 to AC-PR-3, AC-SRC-1 to AC-SRC-3); (4) data honesty (text search for "No data", absence of calorie figures, per-group counts: AC-PR-4, AC-PR-5, AC-PR-11); (5) accessibility (`matchesSemantics`, hit sizes from `tester.getSize`, captured announcements: AC-A11Y-1 to AC-A11Y-4, AC-WS-11); (6) static checks (zero-match scans that would turn red the moment a forbidden token is added: AC-A11Y-8, AC-KB-6, AC-SH-6b, AC-FAM-2k, AC-SRC-5k, AC-RET-1a). Every K scan must first prove it can fail: the test asserts that the scanner finds a planted sentinel token in an in-memory sample string (so an empty file list or a broken glob cannot give a green).

## 9. Counts and focused commands

### 9.1 Counts

N is the number of test entries after parametrisation (section 1). The design estimate is "about 340" in total; its story column (design 1.5) sums to 352 including the two conditional stories.

| Story | Epic | U | W | I | K | Total | Design estimate |
|---|---|---|---|---|---|---|---|
| S03-0 | EP-0 | 0 | 0 | 12 | 2 | 14 | 6 |
| S03-01 | EP-1 | 11 | 1 | 20 | 1 | 33 | 14 |
| S03-02 | EP-5 | 2 | 5 | 0 | 1 | 8 | 8 |
| S03-03 | EP-5 | 0 | 14 | 0 | 0 | 14 | 14 |
| S03-04 | EP-5 | 1 | 3 | 5 | 0 | 9 | 6 |
| S03-05 | EP-5 | 5 | 27 | 3 | 0 | 35 | 30 |
| S03-06 | EP-5 | 0 | 14 | 6 | 1 | 21 | 10 |
| S03-07 | EP-5 | 3 | 33 | 7 | 0 | 43 | 34 |
| S03-08 | EP-2 | 0 | 26 | 8 | 0 | 34 | 30 |
| S03-09 | EP-2 | 0 | 10 | 4 | 0 | 14 | 12 |
| S03-10 | EP-2 | 0 | 10 | 3 | 0 | 13 | 12 |
| S03-11 | EP-2 | 0 | 8 | 3 | 0 | 11 | 10 |
| S03-12 | EP-3 | 0 | 22 | 1 | 0 | 23 | 20 |
| S03-13 | EP-3 | 27 | 0 | 10 | 0 | 37 | 18 |
| S03-14 | EP-3 | 0 | 26 | 1 | 0 | 27 | 22 |
| S03-15 | EP-4 | 0 | 16 | 0 | 1 | 17 | 14 |
| S03-16 | EP-4 | 0 | 11 | 2 | 1 | 14 | 6 |
| S03-17 | EP-5 | 0 | 17 | 4 | 0 | 21 | 16 |
| S03-18 | EP-5 | 2 | 52 | 4 | 10 | 68 | 60 |
| Unconditional total | | 51 | 295 | 93 | 17 | 456 | 342 |
| S03-19 (conditional) | EP-5 | 0 | 6 | 0 | 0 | 6 | 6 |
| S03-20 (conditional) | EP-1 | 0 | 1 | 5 | 0 | 6 | 4 |
| Grand total with conditional | | 51 | 302 | 98 | 17 | 468 | 352 |

Per epic (unconditional stories only):

| Epic | Stories | U | W | I | K | Total |
|---|---|---|---|---|---|---|
| EP-0 | S03-0 | 0 | 0 | 12 | 2 | 14 |
| EP-1 | S03-01 | 11 | 1 | 20 | 1 | 33 |
| EP-2 | S03-08 to S03-11 | 0 | 54 | 18 | 0 | 72 |
| EP-3 | S03-12 to S03-14 | 27 | 48 | 12 | 0 | 87 |
| EP-4 | S03-15, S03-16 | 0 | 27 | 2 | 2 | 31 |
| EP-5 | S03-02 to S03-07, S03-17, S03-18 | 13 | 165 | 29 | 12 | 219 |
| Total | | 51 | 295 | 93 | 17 | 456 |

Delta against revision 1 of this plan (unconditional): batch 1 added 70 (360 to 430); the closing pass added 22 (430 to 452): EP-0 +2, EP-1 +5, EP-2 +3, EP-3 +9, EP-4 +1, EP-5 +2. Conditional stories: 10 to 11 (batch 1) to 12 (DT-20-6). Gate round 1 (retry state machine) added 4 more (DT-0-11 to DT-0-14; DT-0-5 rewritten, still one row): 452 to 456. Totals to quote: 456 unconditional, 468 with the conditional stories.

Share by level (unconditional): U 11 percent, W 65 percent, I 20 percent, K 4 percent. The unconditional total (456) is 33 percent above the sum of the unconditional story estimates (342) and 34 percent above the headline 340; the design estimates predate the review decisions (RV-1 to RV-19), which added guarded behaviour (journal availability and account safety, mode-state safety, backup exclusion, sign-out guard, lifecycle of surfaces and strip) mostly at the integration level; the design owner should raise the story estimates (DD-1). Before batch 1 the excess was 5 percent and came from the negative tests (section 8.2) and the parametrised AC-LS-9 and AC-FAM-4 cases. Two criteria carry no new entry by design: AC-LS-7 (alias, N=0) and AC-REG-3 (run evidence of existing files, N=0). Number of acceptance-criteria ids with at least one row: 124 (section 10).

### 9.2 Focused commands (per epic; run from `mobile/`; PROPOSED file lists, final names set by the test agents)

All commands have the form `flutter test --timeout 60s <explicit files>` (FACT: S02 findings). The agent also records `flutter --version` and the resolved executable path, the git head and the result line verbatim in the findings file. A directory argument is allowed only for a directory the agents created for S03.

| Step | Command (files relative to `mobile/`) |
|---|---|
| 1 EP-0 and EP-1 (lanes L1, L2) | `flutter test --timeout 60s test/features/activity/journal_availability_test.dart test/features/activity/repository/activity_journal_binding_retry_test.dart test/features/activity/config/activity_wiring_flag_matrix_test.dart test/android/backup_rules_test.dart test/android/backup_exclusion_test.dart test/features/modes/mode_flags_test.dart test/features/modes/mode_state_test.dart test/features/modes/mode_migration_test.dart test/features/modes/mode_onboarding_hook_test.dart test/features/account_deletion` (the two backup tests and the wipe test are existing files updated by RV-13 and DT-01-20/24; exact paths of `backup_exclusion_test.dart` found with Glob) |
| 2 EP-5 foundations (lanes L3, L4a, L4b, L5) | `flutter test --timeout 60s test/shared/widgets/window_size_test.dart test/shared/widgets/hud_primitives_extension_test.dart test/shared/widgets/nav_config_test.dart test/shared/widgets/hud_side_rail_test.dart test/shared/widgets/adaptive_surface_test.dart test/shared/widgets/dock_strip_test.dart test/features/workouts/active_session_status_test.dart` plus `back_navigation_test.dart` unchanged (RV-6 evidence; path found with Glob under `test/router/`) |
| 3 EP-2 (lane L6) | `flutter test --timeout 60s test/features/modes/mode_chooser_test.dart test/features/modes/mode_questions_test.dart test/features/modes/mode_switcher_test.dart test/features/modes/record_sheet_test.dart` plus, by the TP-3 rule, the earlier files that received entries in this step: `test/shared/widgets/hud_primitives_extension_test.dart test/shared/widgets/adaptive_surface_test.dart test/shared/widgets/dock_strip_test.dart test/shared/widgets/hud_side_rail_test.dart` |
| 4 EP-3 and EP-4 (lanes L1 S03-13, L7, L8, L9) | `flutter test --timeout 60s test/features/home/home_mode_lens_test.dart test/features/activity/data/activity_aggregates_test.dart test/features/activity/state/activity_dashboard_providers_test.dart test/features/progress/progress_dashboard_test.dart test/features/modes/sources_panel_test.dart test/features/activity/sign_out_warning_test.dart` plus the earlier files that received entries (`hud_primitives_extension_test.dart`, `adaptive_surface_test.dart`, `mode_switcher_test.dart`, `mode_chooser_test.dart`) |
| 5 S03-17 (lane L10) | `flutter test --timeout 60s test/shared/widgets/keyboard_pointer_test.dart` plus `hud_side_rail_test.dart` and `dock_strip_test.dart` (entries AC-WS-7e and AC-KB-2 depend on the shortcuts) |
| 6 S03-18 (lane L12 fixes) and conditional stories | `flutter test --timeout 60s test/s03_conformance` (the directory is created by the agents for S03 only; `--concurrency=1` allowed if load causes timeouts), plus `test/shared/widgets/pushed_page_frame_test.dart test/core/notifications/reminder_tap_routing_test.dart` if built, plus every earlier file that received an entry or was touched by an L12 fix during this step (the findings file lists them) |
| Measure-only gates (step 7, once) | DT-13-23 (G1) and DT-14-8 (G2): run by the test agents at the end, numbers recorded with the head revision and corpus size; never by the coordinator |
| Regression evidence (AC-REG-1, AC-REG-3) | `flutter test --timeout 60s <the existing scanner, equipment, Home and Progress test files, named by exact path in the findings after the agent lists them with Glob>` (no edits to those files) |
| 7 Final | every file of steps 1 to 6 in one command line, run once after the last epic |

Steps are re-run in full when a defect fix touches a file of an earlier step. Forbidden: the whole `mobile/test` tree, CI-mimicking containers, an analyzer as an epic gate, mutation runs, repeated reruns until green.

## 10. Requirements traceability

### 10.1 Story -> acceptance criteria -> test ids

The AC column is the coverage table of design 1.7 (one owner per AC). Test ids are the row ids of sections 2 to 7; "x N" is the number of entries of a parametrised row.

| Story | ACs owned (design 1.7) | Test ids (rows) |
|---|---|---|
| S03-0 | none (gap DD-2) | DT-0-1 to DT-0-14 (DT-0-5 rewritten by the retry state machine, DT-0-6 by RV-13) |
| S03-01 | AC-CH-8 | AC-CH-8a, AC-CH-8b, AC-CH-8c, AC-CH-8d, DT-01-1 to DT-01-25 (DT-01-12 x2, DT-01-15 x2, DT-01-16 x2, DT-01-22 x2) |
| S03-02 | AC-WS-1 | AC-WS-1a, AC-WS-1b (x2), DT-02-1 to DT-02-5 |
| S03-03 | AC-KB-3, AC-KB-4 | AC-KB-3 (x5), AC-KB-4 (x3), DT-03-1 (x4), DT-03-2, DT-03-3 |
| S03-04 | AC-SH-1, AC-SH-2, AC-SH-3 | AC-SH-1, AC-SH-2 (x5), AC-SH-3, DT-04-1, DT-04-2 |
| S03-05 | AC-WS-2, 3, 4, 5, 6, 8, 9, 10, 11; AC-KB-2, AC-KB-9 | AC-WS-2a (x2), AC-WS-2b (x3), AC-WS-3a (x3), AC-WS-3b (x2), AC-WS-3c, AC-WS-3d, AC-WS-4 (x2), AC-WS-5, AC-WS-6 (x2), AC-WS-8 (x2), AC-WS-9 (x2), AC-WS-10 (x4), AC-WS-11 (x2), AC-KB-2, AC-KB-9 (x2), DT-05-1, DT-05-2, DT-05-3 (x2), DT-05-5 |
| S03-06 | AC-LS-8, AC-WS-14, AC-A11Y-6 | AC-LS-8a (x3), AC-LS-8b (x2), AC-LS-8c (x2), AC-LS-8d, AC-WS-14a, AC-WS-14b, AC-A11Y-6a, AC-A11Y-6b, DT-06-1, DT-06-2 (x2), DT-06-3, DT-06-4 (x5) |
| S03-07 | AC-ST-1 to AC-ST-9, AC-SH-5, AC-WS-7, AC-WS-12, AC-WS-13 | AC-ST-1, AC-ST-2, AC-ST-3 (x10), AC-ST-4, AC-ST-5 (x2), AC-ST-6, AC-ST-7, AC-ST-8, AC-ST-9 (x2), AC-SH-5, AC-WS-7a, 7b, 7c, 7d (x2), 7e, AC-WS-12 (x2), AC-WS-13, DT-07-1 to DT-07-13 |
| S03-08 | AC-CH-1 to 7, AC-CH-9 to 14, AC-LS-7, AC-LS-11 | AC-CH-1 to AC-CH-7 (AC-CH-5 x3), AC-CH-9, AC-CH-10 (x5), AC-CH-11, AC-CH-12 (x3), AC-CH-13 (x2), AC-CH-14, AC-LS-7 (alias), AC-LS-11 (x2), DT-08-1 to DT-08-10 |
| S03-09 | AC-Q-1 to AC-Q-6 | AC-Q-1 to AC-Q-6 (AC-Q-3 x2), DT-09-1 to DT-09-6 (DT-09-6 x2) |
| S03-10 | AC-SW-1 to 5, AC-SH-4 | AC-SW-1, AC-SW-2, AC-SW-3 (x2), AC-SW-4, AC-SW-5 (x2), AC-SH-4, DT-10-1 to DT-10-5 |
| S03-11 | AC-RC-1 to AC-RC-5 | AC-RC-1, AC-RC-2 (x2), AC-RC-3 (x2), AC-RC-4, AC-RC-5, DT-11-1 to DT-11-4 |
| S03-12 | AC-HM-1 to 6, AC-LS-1, 2, 3 | AC-HM-1, AC-HM-2, AC-HM-3 (x3), AC-HM-4 (x5), AC-HM-5, AC-HM-6 (x2), AC-LS-1 (x3), AC-LS-2 (x2), AC-LS-3, DT-12-1 to DT-12-4 |
| S03-13 | AC-PR-5, AC-PR-7, AC-PR-11, AC-SRC-6 | AC-PR-5, AC-PR-7 (x4), AC-PR-11, AC-SRC-6 (x6), DT-13-1 to DT-13-24 (DT-13-9 x2) |
| S03-14 | AC-PR-1, 2, 3, 4, 6, 8, 9, 10; AC-LS-4, AC-LS-5 | AC-PR-1, AC-PR-2 (x2), AC-PR-3 (x2), AC-PR-4, AC-PR-6, AC-PR-8, AC-PR-9, AC-PR-10 (x2), AC-LS-4 (x3), AC-LS-5 (x4), DT-14-1 to DT-14-9 |
| S03-15 | AC-SRC-1, 2, 3, 4, 5, 7; AC-LS-6 | AC-SRC-1 (x2), AC-SRC-2, AC-SRC-3, AC-SRC-4, AC-SRC-5, AC-SRC-5k, AC-SRC-7, AC-LS-6 (x2), DT-15-1, DT-15-2 (x2), DT-15-3, DT-15-4, DT-15-5, DT-15-6 |
| S03-16 | AC-SO-1, AC-SO-2 | AC-SO-1 (x2), AC-SO-2, DT-16-1 to DT-16-9 (DT-16-4 x3) |
| S03-17 | AC-KB-1, 5, 7, 8 | AC-KB-1a to AC-KB-1i, AC-KB-5 (x2), AC-KB-7, AC-KB-8, DT-17-1 to DT-17-4 |
| S03-18 | AC-SH-6, AC-REG-1 to 4, AC-A11Y-1, 2, 3, 4, 5, 7, 8, AC-KB-6, AC-FAM-1 to 6, AC-LS-9, AC-LS-10, AC-RET-1 | AC-SH-6a, AC-SH-6b, AC-REG-1, AC-REG-2, AC-REG-3 (N=0), AC-REG-4 (x2), AC-A11Y-1 (x6), AC-A11Y-2, AC-A11Y-3 (x3), AC-A11Y-4 (x4), AC-A11Y-5 (x4), AC-A11Y-7 (x2), AC-A11Y-8 (x2), AC-KB-6, AC-FAM-1 (x2), AC-FAM-2 (x2), AC-FAM-2k, AC-FAM-3 (x2), AC-FAM-4 (x6), AC-FAM-5 (x2), AC-FAM-6 (x2), AC-LS-9 (x10), AC-LS-10 (x2), AC-RET-1a, AC-RET-1b, AC-RET-1c, DT-18-1 to DT-18-7 |
| S03-19 (conditional) | none | DT-19-1 to DT-19-6 |
| S03-20 (conditional) | none | DT-20-1 to DT-20-6 |

Forward check (every AC has a test): the 124 ids by family are CH 14 (1 to 14), Q 6, SW 5, ST 9, RC 5, HM 6, PR 11, SRC 7, SO 2, SH 6, REG 4, A11Y 8, WS 14, LS 11, KB 9, FAM 6, RET 1. Each id above appears in a row of the story that owns it in design 1.7: the 124 ids = 14+6+5+9+5+6+11+7+2+6+4+8+14+11+9+6+1; rows with a letter suffix (for example AC-CH-8a to 8d, AC-WS-3a to 3d, AC-SRC-5 and AC-SRC-5k, AC-FAM-2 and AC-FAM-2k) carry the same AC. The two ACs with no new entry (AC-LS-7, AC-REG-3) have a row stating how they are evidenced.

### 10.2 Reverse check (every test id appears in exactly one story)

1. A row id is unique in the file. An id of the form `AC-xx-n` (with an optional lower-case suffix) is placed under the one story that owns `AC-xx-n` in design 1.7; an id of the form `DT-<story number>-<seq>` carries its story number in its name (`DT-07-3` is S03-07, `DT-0-1` is S03-0, `DT-18-2` is S03-18, `DT-20-4` is S03-20). The two checks agree for every row (the id prefix and the owning story never conflict).
2. Rows with several entries (x N) repeat their id in the test name with a suffix (`/value`), so the entries of one row are never counted under another story.
3. Cross-story timing is not cross-story ownership: entries tagged `RUNS-AFTER S03-nn` (AC-KB-3 entries, AC-KB-4, AC-LS-8a to 8c, AC-ST-4, AC-WS-7c, AC-WS-7e, DT-08-4) stay under their owner and are written when the later story lands. The test agent checks this at the end by listing all test names that start with `AC-` or `DT-` from the test files (one `grep`-style listing with the Grep tool, not a test run), confirming that no id occurs under two stories and that all 124 AC prefixes are present; the listing is recorded in `S03_TEST_FINDINGS_FINAL.md`.
4. The sum of the per-story totals of section 9.1 equals the sum of the N of the rows in sections 2 to 7 (456 unconditional, 12 conditional); a difference means a row was added or removed without updating one of the two places.
