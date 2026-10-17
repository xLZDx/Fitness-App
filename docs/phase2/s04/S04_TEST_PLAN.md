# S04 test plan: GPS recorder without a map

Status: DRAFT revision 8 (revision 7 plus the GPT-PM verification round 4 findings Z13 to Z15; revision 7 was revision 6 plus the round 3 findings Z9 to Z12; revision 6 was revision 5 plus the round 2 findings Z7 and Z8; revision 5 was revision 4 plus the findings Z5 and Z6; revision 4 was revision 3 plus the GPT-PM documentation gate findings Z1 to Z4; revision 3 was revision 2 plus the Round 2 batch: decisions Y1 to Y11 of the review findings, the Round 2 additions of the Contract (109 criteria) and of the Design (16.2); revision 2 was one batch for the revised inputs: requirements S04-R-001 to S04-R-058, stories S04-01 to S04-38, Contract revision 2 with 98 criteria (109 after Round 2 and the gates), and the design answers to the revision 1 findings TP-S04-1 to TP-S04-15). Date: 2026-10-17. Branch `phase2/s04-docs`. Plan only: no test code exists and no test was run for this document. Every result column is empty by design; results are recorded later by the test agents in `docs/phase2/s04/S04_TEST_FINDINGS_EPIC_<letter>.md` and `S04_TEST_FINDINGS_FINAL.md`. The S04-D contract and the S04 design may still receive a fix pass: this plan cites ids (S04-R-nnn, AC-D4-x-n, DT-xx-n, design section numbers), never line numbers. A row tagged DEPENDS-ON-DESIGN states only the contract-level invariant; the exact value is read from the final design.

Inputs read: `S04_REQUIREMENTS.md` (Req), `S04_STORIES.md` (Stories, 38 stories S04-01 to S04-38, acceptance criteria AC-n per story), `S04_DESIGN.md` (Design, including section 16.1 Round 2 additions), `S04D_UI_DESIGN_CONTRACT.md` (Contract revision 2 and its Round 2 additions, 109 criteria AC-D4-*), `S04_ANDROID_PLATFORM_STUDY.md` (Study), and, for format and rules, `docs/phase2/s03/S03_TEST_PLAN.md`.

Tags: FACT (read in a file), PROPOSED (choice of this plan), DEPENDS-ON-DESIGN (cannot be finalised until the named design item is settled), NOT_RUN (needs a device, a build or an operator decision; never PASS without an artifact).

Plain-words glossary:
- S04-R-nnn: a requirement. S04-nn: a story (a unit of build work). EP-A to EP-I: epics of Stories section 3. AC-n: an acceptance criterion of one story. AC-D4-x-n: an acceptance criterion of the Contract (family letters: P permission journey, S states, G glance, B battery, T stop and finish, R recovery, V revocation, N notification, H shell, Z privacy zone, Y accessibility, W window sizes, C copy).
- DT-xx-n: a test row of this plan; xx is the story number (`DT-17-4` belongs to S04-17); `DT-00-n` are cross-cutting rows (compile smoke, scan set). DL-n: a device-lab item (section 6).
- Levels: U unit (pure Dart), W widget (one screen or component with fakes), I integration (controller, journal, router or providers with in-memory or fault-injecting fakes, restart simulated by a NEW object over the same fake file system), K static check (a Dart test that reads source, manifest, ARB or documents), D device-lab (needs a physical phone; NOT_RUN until a phone is named).
- N: number of test entries after parametrisation (suffix `/value` in the test name). A pure data table inside one unit test counts as one entry.
- Sev: H wrong or unsafe user-visible behaviour, privacy leak or data loss; M wrong state or layout with a workaround; L polish.
- Fault injection (FI): the fake file system drops or tears bytes at a chosen point. Replay: a stored track is fed through the SAME `RecorderPipeline` class the live recorder uses, with a fake clock.

## 1. Scope, levels, conventions

### 1.1 Scope and non-goals

In scope: every requirement S04-R-001 to S04-R-058 (each maps to at least one row, or is explicitly NOT_RUN in whole or in part with the reason, section 7.1), every AC of the 38 stories, all 109 AC-D4 ids (section 7.2), the three retro rules (section 4) and the device-lab and battery protocol (section 5). Out of scope: map, EXPLORE and RIDE, sharing, privacy-zone editor, heart rate, GPX/FIT, upload, consent centre, iOS (rows read NOT_RUN, never PASS), mutation runs, repo-wide runs.

Operator rules that bind this plan (FACT, global contract): the coordinator runs no test; test-writing agents (`functional-test-reviewer`, `e2e-runner`, `tdd-guide` for pure seams, `performance-optimizer` for S04-26) write detailed functional scripts for EVERY epic and run the COMPLETE set of files they wrote after each epic, and once more after the last epic on the exact head to be approved; no CI, no analyzer as a gate, no mutation run, no full suite. A green test counts only if its assertion would fail when the guarded behaviour breaks; the column "Fails when" states that assertion in words (no mutation was run to prove it).

### 1.2 Levels and planned share

| Level | Meaning | Share (section 8) |
|---|---|---|
| U | gate boundaries, state tables, calculators, codec, mapper, consent record, constants | 10 percent |
| W | S4-1 to S4-6 and the strip with fakes at fixed window sizes, text scale, locale, `TextDirection` | 33 percent |
| I | recorder controller, journal with a fault-injecting file system, recovery, hand-off, providers, sequences with completers | 48 percent |
| K | source, manifest, ARB and document scans | 7 percent |
| D | phone only | 2 percent |

### 1.3 Conventions

1. Id and name. A test name starts with its row id, then `/suffix` for parametrised entries (`DT-05-8/backwards`). A row covers the ids named in its Covers column; one id is owned by one story (reverse check, section 7.4).
2. Files (PROPOSED names; one owner per file, the test agent of the epic). Folders: `mobile/test/features/recording/{location,permissions,pipeline,journal,state,consent,pages,widgets}/`, fixtures in `mobile/test/features/recording/fixtures/` (track files plus expected-result files), `mobile/test/s04_conformance/`, manifest and backup tests in `mobile/test/android/`, architecture guards in `mobile/test/core/architecture/`, strip tests in `mobile/test/features/workouts/` and `mobile/test/shared/widgets/`. Exact paths are fixed by the test agents after listing the tree with Glob.
3. Fakes and seams (test code only; Design 2.2): `FakeLocationSource` (scripted fixes on a fake clock; can emit an error event, close the stream unexpectedly, flip behaviour mid-run; counts `activeSubscriptions` and `start` requests with their interval), `FakePermissionService` (scripted answers per call, a status that can be flipped mid-run, request counter per method), `FakeBatteryMonitor` (stream of percent and charging, can emit equal values, can throw), `FakeClock` (`nowUtcMs` and monotonic `elapsedMs`, settable backwards and forwards), `FaultFileSystem` over the `JournalFileSystem` seam with a DURABLE view and a VOLATILE view (a write that was not fsynced is lost on a simulated crash; modes: crash after N bytes, crash before fsync, crash between rename steps, crash after K operations, disk full, throw on Nth call), `InlineHeavyWorkRunner` (runs synchronously and records the function id and the isolate-identity of every call), `FakeNotificationHost`, `FakeNetwork` (all adapters throw), `LogCapture` (overrides `debugPrint`, collects zone errors and `FlutterError` reports), `TelemetrySpy` (fake crash-reporting recorder), `FakeShare` (not used: S04 has no Export), `FakeSdkInt` (12, 13, 14), `FakeAuthStream` (null, loading, a uid, a different uid, sign-out and deletion events), `FakeConsentStore`, `FakeConnectivity`, `FakeDeviceCapabilities` (`hasGps`), `MockHapticChannel`, `MockAccessibilityChannel` (captures announce text, direction and assertiveness), write spy with sequence numbers, router log with sequence numbers, route observer. Two real scope directories (two uids) are used for every account test (Design 12.3).
4. Determinism. No wall clock, no `Random`, no network, no order dependence. Pseudo-random offsets and noise come from a documented linear congruential generator with a fixed seed written in the fixture spec (section 2), so "random offsets" (Req S04-R-015) are fixed and reproducible. `pumpAndSettle` is never used on the S4-2 tree. Every test that uses `tester.view.physicalSize` resets it in `addTearDown`. A test that leaves a pending timer is a defect to report.
5. "No call" assertions use a counter that would record a call if one happened (permission service, location source, network, write spy). "Order" assertions compare sequence numbers or real `Rect` positions, never widget list order.
6. Recovery tests (Design 12.3): the journal is always re-opened as a NEW object over the same fake file system after the injected crash; a recovery test that reads from the object that wrote proves nothing and is rejected in review. The file system must model non-durable tails; a fake that persists everything cannot fail the kill test.
7. Copy: rows that quote copy read the production localisation by key (`gps*` ids of Contract section 16), so a translation change does not break a test unless a length budget, a key or a forbidden word is violated. Forbidden words on recovery paths: "restored" and "recovered" in any inflection, except `gpsAnnResumedRecovered` after the first kept fix (AC-D4-R-3).
8. K scan set. Every K row scans a named set resolved once by one helper: `lib/features/recording/**`, the S04 changes in `lib/features/workouts/state/active_session_status.dart`, `lib/shared/widgets/dock_widgets.dart`, `shell_dock.dart`, `main_shell.dart`, `lib/core/router/**`, `lib/core/config/recording_defaults.dart`, the Android manifest and backup XML, the ARB files. DT-00-2 asserts a minimum file count, that anchor files (location adapter, permission adapter, journal, controller, recording screen) are in the set, and that no scanned directory is empty. A K test turns red when an anchor file leaves the set or a scan points at an empty directory.
9. Platform limits are stated, not hidden: the K manifest rows read the SOURCE manifest only; plugin manifest merges are visible only in a built artifact (DL-11, NOT_RUN: no build is run by the agents of this plan).

### 1.4 Order for the test agents

Each step: write all files of the listed stories, then run the COMPLETE set of files written so far for that epic (all files, not a sample); record exact command, `flutter --version` with the resolved executable path (the bare `flutter` name can resolve to a sibling project), git head and the result line in the findings file. After the last epic run everything once more.

| Step | Epic (stories); implementation lanes of Stories 9 | Agent (PROPOSED) | Findings file |
|---|---|---|---|
| 0 | Compile smoke (DT-00-1, DT-00-2, DT-00-3) after wave 1 (R1, R3, R4 interface commits) and after every later batch of agent edits | functional-test-reviewer | `S04_TEST_FINDINGS_EPIC_0.md` |
| 1 | EP-A (S04-01 to S04-04); R1, R2 manifest, R3 and R4 interfaces; fixtures and the replay harness (S04-02) are written first | functional-test-reviewer; tdd-guide for fakes and the pipeline harness | `..._EPIC_A.md` |
| 2 | EP-B and EP-C (S04-05 to S04-10); R3 | tdd-guide (units), functional-test-reviewer (replay) | `..._EPIC_B.md`, `..._EPIC_C.md` |
| 3 | EP-D (S04-11 to S04-16); R5 (and the two S02 touches of Design 4.7 and 2.5). Data protection before data on: DT-15-1 to DT-15-3 are written and run FIRST in this step, before any journal-writing row is accepted | functional-test-reviewer | `..._EPIC_D.md` |
| 4 | EP-E (S04-17, S04-19, S04-21; S04-18 and S04-20 only when their question is answered); R1, R8, R10 | functional-test-reviewer, e2e-runner (widget flows) | `..._EPIC_E.md` |
| 5 | EP-F (S04-22, S04-23); R4, R11 | functional-test-reviewer | `..._EPIC_F.md` |
| 6 | EP-G (S04-24, S04-25); R6, R7, R9 (strip tests of S03 run UNCHANGED as regression evidence) | functional-test-reviewer, e2e-runner | `..._EPIC_G.md` |
| 7 | EP-H (S04-26 to S04-28); R5, R8 | performance-optimizer (S04-26), functional-test-reviewer | `..._EPIC_H.md` |
| 7b | EP-J (S04-30 to S04-38); lanes R5, R8, R9 and the new lane R13 | functional-test-reviewer, e2e-runner | `..._EPIC_J.md` |
| 8 | EP-I (S04-29): templates and validators run now; device items DL-1 to DL-9 stay NOT_RUN until a phone is named | e2e-runner | `..._EPIC_I.md` |
| 9 | Final run of every file of steps 0 to 8 in one command line, on the exact head to be approved | both | `S04_TEST_FINDINGS_FINAL.md` |

Rows that need a control built in a later story carry `RUNS-AFTER S04-nn` and are written when that story lands (they are not skipped). A defect found in step n is reported to the owning lane and never fixed in a file of another lane; after a lane R12 fix the agents re-run every step whose files the fix touched. Each test agent writes to its own private output file name; runs are sequenced or in two waves (retro action 10).

### 1.5 Focused commands

FACT (S02 and S03 findings): from the Flutter root `mobile/`, `flutter test --timeout 60s <explicit file paths>`; a directory path only for a directory the agents created. Commands per epic: section 8.2. Forbidden: the whole `mobile/test` tree, CI-mimicking containers, analyzers as a gate, mutation runs, repeated reruns until green.

## 2. Replay fixtures specification (Req S04-R-035; story S04-02)

### 2.1 Format and generation rules

1. A track fixture is a CSV file (one header line, then rows): `t_ms,lat,lon,acc_m,alt_m,speed_mps,inject` with empty cells for absent altitude and speed; `inject` is empty or one of `drop` (no delivery for the interval), `dup` (delivered twice), `back` (timestamp earlier than the previous), `kill` (the kill marker for journal tests). A header comment block carries `truth_length_m`, `truth_moving_s`, `truth_ascent_m`, `truth_descent_m` where the fixture has a truth, and the sport.
2. An expected-result file is JSON beside it: kept count, the four reject counters (accuracy, speed, invalid, non-monotonic), the gap list with start and end offsets, the state timeline (state name with entry offset), pause and resume events, distance, moving time, ascent and descent (or `null`), pace samples at listed offsets, and the formula version string. Keys are sorted and numbers are formatted with a fixed number of decimals so two runs are byte-equal.
3. No `Random`, no `DateTime.now`, no unordered iteration in generation or in the pipeline. Noise comes from a fixed LCG (PROPOSED: a=1664525, c=1013904223, m=2^32, seed written in the file header); the generator code lives in the test tree, the generated CSV is committed, and the expected files are committed. Expected files are recorded ONCE from the first green head after the contract values are accepted and are never regenerated to make a failing test pass (same discipline as S03 TP-m2); a change of a threshold needs a reviewed re-record with the reason in the findings.
4. Truth lengths are computed from the noise-free polyline with the SAME haversine model as the calculators (mean Earth radius 6 371 008.8 m, Design 3.7), so the sphere-versus-ellipsoid difference does not enter the synthetic tolerance. The coordinates are neutral and fixed (not a real private place).
5. "Real-shaped" means: a hand-built polyline with realistic turns and slopes, a speed profile with accelerations, accuracy values of 5 to 15 m in the open and 20 to 40 m in the built-up part, and spatially correlated noise (a first-order autoregressive error, so errors do not average out). It is NOT a recording of a real surveyed route. The surveyed-route tolerance (Req S04-R-032, 2 percent) on a real walked or ridden known route is a device-lab item (DL-1, DL-2).
6. The replay driver feeds the same `RecorderPipeline` class through `FakeLocationSource` and `FakeClock`; DT-02-6 asserts this by construction.

### 2.2 Track fixtures (21)

| Fixture | Content | Truth or key property | Used by |
|---|---|---|---|
| F-noise-line | 1000 m straight line, walk 1.4 m/s, 1 Hz, accuracy 5 to 12 m, LCG noise up to 8 m | truth length 1000 m; smoothed length within 3 percent; no point moved over 15 m | DT-02-1, DT-06-1, DT-06-3, DT-08-1 |
| F-turns | polyline with a 90-degree corner and two shallow bends, 1.4 m/s | apex of the corner within 15 m after smoothing | DT-06-3, DT-06-4 |
| F-stop-go | walk, three full stops of 7 s, 20 s and 60 s, plus a 90 s span of 0.6 to 0.9 m/s jitter | exact pause and resume event count; none inside the 7 s stop; none on jitter | DT-07-1, DT-08-3, DT-09-3 |
| F-tunnel | ride, accuracy 8 m, then 60 s with no delivery, then fixes again 700 m on | one poor-accuracy span, 0 m added in the gap, one gap with start and end offsets | DT-05-6, DT-08-3 |
| F-urban-canyon | walk with accuracy spikes 45 to 120 m for 40 non-consecutive fixes | none of the injected fixes is kept | DT-05-5 |
| F-jump | walk with one fix 2 km away (implied about 2000 m/s) and one 50 m accuracy fix | none of the injected fixes is kept | DT-05-5 |
| F-climb | walk up a 100 m staircase profile (steps of 5 m), altitude noise 1 m | truth ascent 100 m, descent 0 (reversed copy gives descent 100 m); spike variant `F-climb-spike` with one +100 m altitude sample | DT-10-2 |
| F-ride-30kmh | ride at a constant 8.33 m/s, 20 min | truth length known; pace and speed constant | DT-08-1, DT-09-1 |
| F-walk | walk at a constant 1.4 m/s, 20 min | truth length known | DT-08-1, DT-09-1 |
| F-kill-mid-run | 600 s walk at 1 Hz with altitude; journal-level, killed at the 50 offsets of section 2.4 | recovered track ends within 6 s of the kill | DT-11-6 |
| F-still | 10 min standing still with GPS drift of 3 to 8 m at accuracy 5 to 15 m and provider speed 0.0 to 0.4 m/s | auto-pause enters; no distance after it; distance before it bounded by the drift | DT-07-6 |
| F-clock-jump | 5 min walk with: one fix with a timestamp 3 s earlier than its predecessor, one fix with an equal timestamp but a different position, a forward jump of 1 h in the device clock, then normal fixes | backwards and equal-time fixes dropped and counted; forward jump becomes a gap, no interpolation | DT-05-8 |
| F-dup-fix | the same fix (same time and position) delivered 5 times in a row, then normal fixes | one kept, four counted as non-monotonic | DT-05-9 |
| F-flat-alt-noise | 10 min flat walk, altitude noise plus or minus 4 m | ascent at most 5 m, descent at most 5 m | DT-10-1 |
| F-no-alt | walk with the altitude column empty | ascent and descent undefined (null) | DT-10-3, DT-08-7 |
| F-walk-real | real-shaped walk, 3 km, with turns and slopes | surveyed-style truth length (from the noise-free polyline); error at most 2 percent | DT-08-2 |
| F-ride-real | real-shaped ride, 10 km, with a descent at 12 m/s and stops | same | DT-08-2 |
| F-long-3600 | 3600 s walk at 1 Hz | exactly 3600 location requests in the run | DT-05-1 |
| F-100k | 100 000 samples at 1 Hz (about 28 h) with altitude and speed | live list never above 600; seal and open round trip equal | DT-11-10, DT-26-5, DT-26-6 |
| F-bad-anchor | one kept-looking first fix with accuracy 10 m but 5 km from the true start, followed by 120 s of true fixes | after 5 consecutive speed-only rejections or 30 s without a kept fix the gate re-anchors, only among rejected fixes with accuracy 30 m or better (Design 3.3, TP-S04-1 and Y9 resolved) | DT-05-11 |
| F-sentinel | 60 s walk around the sentinel point 12.3456789, -98.7654321 | used only by the log and telemetry capture | DT-27-1 |

### 2.3 Journal corruption fixtures (built in the test from a good journal; the original bytes are hashed first)

J-1 truncated `meta.json`; J-2 zero-byte `meta.json`; J-3 `meta.json` with schema version above the supported one; J-4 `meta.json` whose cipher tag fails; J-5 key unavailable (`JournalKeyUnavailable`); J-6 segment files without `meta.json`; J-7 a bit flipped inside a MIDDLE frame with valid frames and a later segment after it; J-8 torn tail variants of section DT-11-7 (short length prefix, truncated payload, bad CRC, payload bit flip, zero length, length field larger than the remaining bytes) at the end of the LAST segment; J-9 a missing middle segment; J-10 a torn end of an EARLIER segment with no `segmentBreak` in the next one; J-11 a torn end of an earlier segment announced by a `segmentBreak` naming the previous segment and its valid frame count (valid); J-12 a `SEALED` whose counts disagree with the log; J-13 a directory with a plain `DISCARDING` marker and any subset of its files (section DT-12-13); J-14 a duplicate frame counter (the first occurrence is kept) and a segment that does not start with a `segmentBreak` after an unclean close.

### 2.4 Kill-injection plan (Req S04-R-015: 50 runs)

50 kill points over the 600 s of F-kill-mid-run, from the fixed LCG plus these forced points: every flush boundary of the first minute (5 s, 10 s, ...), one byte before and one byte after each frame end, mid-frame (length prefix written, payload not), after write and before fsync, and exactly at the event frames (pause, resume). Each run: replay until the kill point, simulate the crash on the `FaultFileSystem` (volatile bytes lost), open a NEW `RecordingJournal` object, read all, then assert: every recovered record is complete; the recovered last offset is at most 6 s (the 5 s flush interval plus one sample) before the kill offset; offsets are strictly increasing; the unsynced tail is the only loss. One test loops all 50 points and reports the worst gap and every failing point (DT-11-6).

## 3. Tests by epic

Columns: Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when.

### 3.1 EP-A Foundations (S04-01 to S04-04)

#### S04-01 Location seam and import guard (R-003, R-005)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-01-1 | S04-R-003; S04-01 AC-1 | I | 4 | H | `FakeLocationSource` in the app scope; entries `/launch` (cold start to Home), `/sign-out` (signed in user signs out), `/boot-start` (simulated start with no user action), `/recording-end` (a recording started then stopped) | `activeSubscriptions` is 0 and `start` request count is 0 at every moment except while recording; after the end 0 within 2 s fake time | a subscription exists before Start, after Stop, after sign-out or at start-up (passive collection) |
| DT-01-2 | S04-R-003; S04-01 AC-2 | K | 1 | H | K scan set; scan for imports of any location plugin API (the chosen package and the known candidate names) | the only file importing it is the adapter under `recording/location/`; sanity: the adapter file is in the set | an import appears outside the one seam file |
| DT-01-3 | S04-R-005; Design 11.2 (4) | K | 1 | H | scan `recording/**` for map packages, `dio`, `http`, socket and connectivity-based branching | zero matches | a map or network import enters the recorder's import graph |
| DT-01-4 | S04-R-005, S04-R-046; S04-01 AC-3 | I | 1 | H | `FakeNetwork` (every adapter throws) and cloud flag false; full run: Start, 120 s of fixes, pause, resume, Stop, hand-off, Done | the run succeeds, one session is stored, upload and network fakes record zero calls | the recorder needs the network or touches an upload path |
| DT-01-5 | Design 12.3 | U | 1 | M | self-check of the fakes | `FakeLocationSource` can emit an error event, close its stream, and change the permission it reports mid-run; `FakeJournal` file system drops unsynced bytes on crash | a fake that never throws or never loses bytes makes the revocation and kill tests unfalsifiable |
| DT-01-6 | S04-R-003, S04-R-021; Design 11.2 (2) | K | 1 | H | scan for location and notification permission symbols outside `recording/permissions/` (the camera code legitimately uses `permission_handler`, so only those symbols are scanned) and for permission calls in launch, onboarding or tab code | zero matches | a permission request exists outside the one folder or at launch |
| DT-01-7 | Design 2.1 | K | 1 | M | read `pure_data_layer_guard_test.dart` and `import_graph_guard_test.dart` | `recording` is a known feature and `pipeline/` is covered by the pure-layer rule (no Flutter, no `dart:io`, no Riverpod) | the pipeline can import Flutter or `dart:io` unnoticed |

#### S04-02 Replay harness and fixtures (R-035)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-02-1 | S04-R-035; S04-02 AC-1 | I | 21 | H | one entry per fixture of section 2.2 (`/F-noise-line` and so on); replay through `RecorderPipeline` with the fake clock | an expected-result file exists and the replay output equals it key by key | an expected file is missing, or the pipeline output drifts from the stored result |
| DT-02-2 | S04-R-035; S04-02 AC-2 | I | 1 | H | replay F-noise-line, F-stop-go and F-kill-mid-run twice each and once in reversed test order | the serialised outputs are byte-equal | output depends on run order, time or hash order |
| DT-02-3 | S04-R-035; S04-02 AC-3 | I | 8 | H | sensitivity probe through the official test seam of `recording_constants.dart` (not a source edit, no mutation): entries `/accuracy-30`, `/speed-30`, `/poor-10s`, `/pause-enter-0.5-8s`, `/pause-leave-1.0-3s`, `/hysteresis-3m`, `/pace-window-10s`, `/pace-min-10m`; each replays the fixture the constant belongs to with the value moved one step | at least one stored expected file mismatches per constant | a threshold change cannot be seen by any fixture (the suite does not guard the constant) |
| DT-02-4 | S04-R-035; Design 12.2 | K | 1 | M | scan `recording/pipeline/**` | no `DateTime.now`, no `Random`, no `Stopwatch`, no iteration over an unordered map or set whose order reaches output | nondeterminism enters the pipeline |
| DT-02-5 | S04-R-035 | U | 1 | M | validator over every fixture file | header truth keys present where a truth exists; `t_ms` strictly increasing except rows marked `back` or `dup`; lat and lon in range except rows meant to be invalid; columns exact | a malformed fixture silently weakens a replay |
| DT-02-6 | Design 12.2 | I | 1 | H | build the live `RecorderController` and the replay driver through a spy factory | both obtain the pipeline from one factory and one class; a second implementation does not exist | the replay tests a copy of the pipeline, not the live path |

#### S04-03 Recorder state machine (R-004, R-013)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-03-1 | S04-R-004; AC-D4-S-2; S04-03 AC-1 | U | 1 | H | table-driven over the legal phase transitions of Design 5.2 (idle, preparing, acquiring, recording, pausedManual, pausedAuto, stopping, restoring, recoveryFailed, finished, permissionRevoked) | each legal transition is accepted and yields exactly the table's target | a legal transition is rejected or goes elsewhere |
| DT-03-2 | S04-R-004; AC-D4-S-2 | U | 1 | H | every ordered pair of phases NOT in the table (121 minus the legal ones) | each is rejected with no state change and no side effect (subscription count, write spy and service start unchanged) | an undefined transition is accepted |
| DT-03-3 | S04-R-004; AC-D4-S-1; S04-03 AC-2 | U | 1 | H | the display-state function `displayState(phase, flags)` over all reachable inputs | its set of outputs equals, as an ordered list, the 13 names `idle, acquiring, recording, poorAccuracy, offline, pausedManual, pausedAuto, background, restoring, recoveryFailed, batteryCritical, permissionRevoked, finished` | a display state is renamed, dropped or added without the contract |
| DT-03-4 | S04-R-004; AC-D4-S-1 | K | 1 | M | parse the backticked name list of the Contract section "The 13 states" and compare with the code list (DEPENDS-ON-DESIGN: the Contract may be reworded; the test finds the list by its heading, not by line) | equal | code and contract drift apart |
| DT-03-5 | S04-R-004; AC-D4-S-3 | U | 1 | H | pairwise table of overlaps from the Contract priority channels: headline order `permissionRevoked, recoveryFailed, restoring, pausedManual, pausedAuto, acquiring, poorAccuracy, recording`; banner `storage write failing, batteryCritical, notification off`; chips `offline, background` (max two) | headline, banner and chips equal the order for every combination, including battery plus poor accuracy (headline weak signal, banner battery) and paused manual plus offline plus battery. (resolved: Design 5.1 now uses the three Contract channels, TP-S04-2) | a lower-priority fact hides a higher one, or a fact is lost instead of moved to another channel |
| DT-03-6 | S04-R-013; AC-D4-S-7; S04-03 AC-3 | U | 1 | H | pausedManual, then the auto rule fires (speed below 0.5 m/s for 8 s, and 1.0 m/s for 3 s), then Resume | state stays pausedManual under both auto triggers; Resume returns to the prior moving state | an auto trigger overrides the user's pause |
| DT-03-7 | S04-R-013; S04-03 AC-4 | I | 1 | H | `FakeLocationSource`; manual pause for 120 s with fixes arriving | `activeSubscriptions` stays 1, the service is not stopped, no fix is journaled during the pause, `pause` and `resume` events are journaled with offsets | manual pause releases the subscription or journals fixes |
| DT-03-8 | S04-R-004; retro rule 6 | U | 1 | M | repeated and equal events: Pause while pausedManual, Resume while recording, Stop twice, Start while recording or stopping, Resume from restoring twice | idempotent or rejected, never a second event frame, never a second service start | a double tap changes state twice |
| DT-03-9 | S04-R-004; Contract 5.1 | U | 1 | M | flags: `poorAccuracy` set in idle or pausedManual; `offline`, `background`, `batteryCritical` set in idle | `poorAccuracy` only while recording; the others only while acquiring, recording or paused; set in other phases they are ignored and cleared on entering idle | a stale flag survives into the next recording |
| DT-03-10 | S04-R-004; AC-D4-S-4 (state half) | U | 1 | M | transitions pausedAuto to pausedManual (legal), pausedManual to pausedAuto (illegal), Pause in acquiring (illegal) | as stated | Pause is accepted before the first fix |
| DT-03-11 | S04-R-004 | U | 1 | M | for every arrow of the Contract diagram (including recording to idle on Discard and restoring to acquiring on Resume) find a path in the Design table whose projection matches | a path exists for every arrow and none shows a name outside the 13 (TP-S04-3 resolved by the Design 5.2 mapping paragraph: `preparing` and `stopping` project onto the 13 names; the old internal name `stoppedRevoked` is replaced by the display state `permissionRevoked`) | the two documents describe different machines |
| DT-03-12 | S04-R-004, S04-R-009; AC-D4-S-12 | U | 1 | M | `poorAccuracy` flag set while the phase is `pausedManual` or `pausedAuto` | the headline is never `poorAccuracy` in those phases; the signal indicator still shows the real signal word | a paused recording shows a signal-problem headline |
| DT-03-13 | S04-R-004; AC-D4-S-15 | U | 1 | H | the full overlap table of Contract 5.3: every phase crossed with every condition (`poorAccuracy`, `offline`, `background`, `batteryCritical`) | each possible cell yields the headline, banner and chips of the priority channels; each impossible cell (for example `poorAccuracy` in idle) is rejected | an impossible overlap is accepted or a possible one is lost |

#### S04-04 Foreground service, manifest, notification (R-001, R-002, R-050 manifest half)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-04-1 | S04-R-050, S04-R-022; S04-04 AC-1 | K | 1 | H | parse the source `AndroidManifest.xml` | declared set equals the approved list: existing permissions plus `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`; absent: `ACCESS_BACKGROUND_LOCATION`, `ACTIVITY_RECOGNITION`, `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`; the manifest comment block lists the new permissions with the privacy text note | an extra or missing permission (declared set differs from used set, GPS-PRIV-011) |
| DT-04-2 | S04-R-001; S04-04 AC-1 | K | 1 | H | parse the manifest for `<service>` elements (DEPENDS-ON-DESIGN D-1: the plugin may declare the service, then the test reads the plugin manifest copy in the pub cache or is NOT_RUN) | exactly one location-type service, `exported="false"`, `foregroundServiceType="location"`, when the app declares it | a second or exported service, or a missing type |
| DT-04-3 | S04-R-001; S04-04 AC-3; Design 11.2 (5) | K | 1 | H | scan call sites of the service-start function and of `requestStart`; scan the boot receiver, launch code and push handlers | the only callers are the enumerated Start entry points of Design 7.3; none from boot, launch, a push or a notification tap | a code path starts location collection without a user tap |
| DT-04-4 | S04-R-002, S04-R-003; S04-04 AC-4; AC-D4-T-2 (service half) | I | 5 | H | controller in `recording`; entries `/stop`, `/discard`, `/permission-loss`, `/battery-finish`, `/sign-out`; fake time advanced by 2 s | `activeSubscriptions` 0, service stop called once, notification cancelled, timers cancelled, all within 2 s | any stop path leaves a subscription, a notification or a timer behind |
| DT-04-5 | S04-R-002; Design 5.3 | I | 2 | H | `/service-stop-throws`, `/subscription-cancel-throws`; run Stop | the other release steps still run (single `finally`); count 0 within 2 s; error reduced to a bare code | one failing release step skips the others |
| DT-04-6 | S04-R-044, S04-R-001; Contract 17 | U | 3 | M | notification content builder: `/content-per-state` (acquiring, recording, paused, battery), `/throttle` (updates at most every 30 s plus on every state change, fake clock), `/no-coordinate-or-place-in-any-state` (lock-screen versions: DT-32-1) | title and text from the `gpsNotif*` keys; never a coordinate, place name or image; throttle holds | the notification floods updates, or carries a coordinate |
| DT-04-7 | AC-D4-T-5; DN-7 | I | 1 | H | `FakeNotificationHost`; deliver the Stop action while recording. (TP-S04-4 resolved: the private version has exactly Pause/Resume and `Finish...`, detail rows DT-32-2 and DT-32-3) | `Finish...` opens the stop panel; no stop, no release, no write happens | the notification stops the recording by itself |
| DT-04-8 | S04-R-001 (b); AC-D4-N-1; S04-04 AC-2 | D | 1 | H | DL-3 shared run: notification present from first sample to Stop; lock-screen detail is DT-32-6 | present from the first sample until Stop | NOT_RUN until a phone |
| DT-04-9 | S04-R-001 (a); S04-04 AC-5 | D | 1 | H | DL-3 shared run: screen off 60 min | continuous track (no gap over 10 s without a recorded cause) | NOT_RUN until a phone |
| DT-04-10 | S04-R-002 (device); S04-04 AC-4 | D | 1 | H | DL-3: tap Stop, look at the system location indicator | indicator off within 2 s | NOT_RUN until a phone |
| DT-04-11 | S04-R-050, S04-R-022 | D | 1 | M | DL-11: dump the MERGED manifest of a built APK (`aapt dump` or the build merge report) and compare with DT-04-1 | merged permission set equals the approved list (plugin additions visible) | a plugin silently adds `ACCESS_BACKGROUND_LOCATION` (NOT_RUN: needs a build) |

### 3.2 EP-B Sample quality (S04-05 to S04-07)

#### S04-05 Sampling, fields, gate, gaps (R-006 to R-009)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-05-1 | S04-R-006; S04-05 AC-1 | I | 1 | H | F-long-3600 through the controller with the fake clock | exactly 3600 location requests in 3600 s; the request interval is 1000 ms | more or fewer requests, or the rate is raised "for diagnostics" |
| DT-05-2 | S04-R-006, Design 3.1 | U | 1 | M | the request configuration object | high accuracy priority, interval 1000 ms, no min distance, no batching; at battery critical 5000 ms | a wrong priority or interval ships |
| DT-05-3 | S04-R-007; S04-05 AC-2 | U | 2 | H | `/reject-extra-field` (journal record with an extra key), `/adapter-drops` (a platform fix with bearing, provider, satellite count, device id) | the schema validator rejects the extra key; after the adapter none of the dropped fields exists on `Fix` or in any journal frame | bearing, provider or device id is stored |
| DT-05-4 | S04-R-008; S04-05 AC-3 | U | 1 | H | one table: accuracy 30.0 kept, 30.1 rejected, 0, negative, NaN, infinite, missing (rejected as invalid, counted); lat 90.0 kept and 90.0001 rejected; lon 180.0 kept and 180.0001 rejected; implied speed 30.0 m/s kept and 30.1 rejected; first fix after start has no previous fix and passes the speed rule | per row as stated; rejected fixes are not journaled and only counted | a boundary moves by one unit, or an invalid fix reaches the journal (accuracy 0 treated as valid is DEPENDS-ON-DESIGN) |
| DT-05-5 | S04-R-008; S04-05 AC-4 | I | 2 | H | `/F-jump`, `/F-urban-canyon` | zero of the injected fixes is kept; counters appear only as integers in the frame and in logs | an injected bad fix enters the track |
| DT-05-6 | S04-R-009; AC-D4-S-6 (pipeline half); S04-05 AC-5 | I | 1 | H | F-tunnel | `poorAccuracy` entered at 10 s without a kept fix and left on the next kept fix; 0 m added across the gap; exactly one gap with start and end offsets; `gapStart` and `gapEnd` events journaled | distance is interpolated across the tunnel, or no gap marker is stored |
| DT-05-7 | S04-R-009 | U | 1 | M | no kept fix for 9.9 s, then for 10.0 s | no state at 9.9 s; state at 10.0 s | the threshold is off by one tick |
| DT-05-8 | S04-R-007; Design 3.2, F11 | I | 3 | H | F-clock-jump entries `/backwards`, `/duplicate-timestamp`, `/forward-1h` | backwards and equal-time fixes dropped and counted as non-monotonic; the 1 h forward jump becomes a gap (no interpolation); offsets strictly increasing so `SampleStream.validate` passes | a clock jump produces a negative offset, a teleport segment, or a failed validation at hand-off |
| DT-05-9 | S04-R-007; retro rule 6 | I | 1 | M | F-dup-fix | one fix kept, four counted | an identical repeated fix inflates the track |
| DT-05-10 | S04-R-007; S04-05 AC-6 | U | 2 | H | `/with-altitude`, `/no-altitude`: map a journal to `ActivitySession` | offsets strictly increasing; `SampleStream.validate` passes; kinds gps, altitude and speed present only when data exists; `sourceId` is the native source id | the mapped session is invalid or carries an empty stream |
| DT-05-11 | S04-R-008; TP-S04-1 (resolved, Design 3.3); Y9 | I | 5 | H | F-bad-anchor; entries `/four-speed-rejections-no-reanchor`, `/five-speed-rejections-reanchor`, `/thirty-seconds-without-kept-fix-reanchor`, `/fixes-rejected-for-accuracy-are-never-the-anchor`, `/gap-already-open-gets-no-second-pair` | after 4 consecutive speed-only rejections the anchor is kept; at the 5th, or after 30 s (both PROPOSED) with no kept fix, the gate drops the anchor and re-anchors on the best-accuracy fix among the rejected ones with accuracy 30 m or better; only speed-only rejections count; the anchor fix is journaled; one `gapStart`/`gapEnd` pair surrounds the break, or none extra when the 10 s rule already opened a gap; no distance across it; the event is counted in the speed counter; the wrong anchor already journaled stays in the raw journal | one wrong fix makes the recorder discard every later fix, a poor-accuracy fix becomes the anchor, or the raw journal is edited |

#### S04-06 Smoothing, raw kept (R-010, R-011)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-06-1 | S04-R-010; S04-06 AC-1 | I | 1 | H | recorded journal of F-noise-line; recompute with a second smoothing algorithm id | derived distance changes; the raw journal frames are byte-identical (hash before and after); the session stores the id in `formulaVersion` | re-smoothing needs re-recording, or smoothing alters raw data |
| DT-06-2 | S04-R-010; S04-06 AC-3; Design 3.8 | U | 1 | M | formula version strings | length at most 32 characters (the S02 limit); stored with the session | a long id fails S02 validation at hand-off |
| DT-06-3 | S04-R-011; S04-06 AC-2 | I | 2 | H | `/F-noise-line`, `/F-turns` | smoothed length within 3 percent of truth; no kept point moved more than 15 m from its raw position | smoothing under-smooths (zig-zag inflates distance) or moves the route |
| DT-06-4 | S04-R-011; S04-06 AC-2 | I | 1 | H | the 90-degree apex of F-turns | smoothed apex within 15 m of the raw apex | the corner is cut |
| DT-06-5 | S04-R-011; Design 3.5 | U | 1 | M | smoothing across a gap and across a pause | segments split at gaps and pauses; no averaging across them | points either side of a tunnel are blended |
| DT-06-6 | S04-R-011 | U | 1 | M | lists of length 0, 1, 2, 4 (shorter than the 5-fix window) | no exception; short windows at the ends; empty in, empty out | a short track crashes the finalizer |
| DT-06-7 | S04-R-011 | U | 1 | M | weights 1/accuracy squared with accuracy at the lowest value that passes the gate | finite output, no NaN or infinity | division by a tiny or zero accuracy |
| DT-06-8 | S04-R-010; Design 3.5 | U | 1 | M | live strategy (lag of 2 fixes) versus the final worker result | same algorithm id; final values are the stored ones; the live value may differ slightly | live and final use different algorithms |

#### S04-07 Auto-pause (R-012)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-07-1 | S04-R-012; AC-D4-S-8; S04-07 AC-1 | I | 3 | H | F-stop-go entries `/event-count`, `/no-event-in-7s-stop`, `/no-flap-on-jitter` | exactly the expected pause and resume event count; none inside the 7 s stop; none flapping on 0.6 to 0.9 m/s | the pause flaps at a traffic light or fires too early |
| DT-07-2 | S04-R-012; S04-07 AC-2 | U | 4 | H | `/enter-speed` (0.49 and 0.50 m/s for 8 s), `/enter-time` (7.9 and 8.0 s below 0.5), `/leave-speed` (0.99 and 1.0 m/s for 3 s), `/leave-time` (2.9 and 3.0 s) | enters only at below 0.5 for 8 s; leaves only at 1.0 or more for 3 s | a boundary moves by one tick |
| DT-07-3 | S04-R-012; S04-07 AC-3 | I | 1 | H | F-stop-go: moving time and distance during paused spans | moving time equals elapsed minus paused within 1 s; paused distance 0 | pause time enters moving time |
| DT-07-4 | S04-R-012; S04-07 AC-4; AC-D4-S-8 | U | 5 | M | `/walk`, `/run`, `/hike`, `/ride`, `/switched-off` | default on for walk, run, ride; off never enters pausedAuto. hike and every other sport value default OFF (TP-S04-5 resolved); a settings test shows no sport outside walk, run and ride with the default on | auto-pause is on when switched off, or off by default |
| DT-07-5 | S04-R-012; Design 3.6 | U | 2 | M | `/provider-speed` (used when present), `/implied-speed` (from the last two fixes when absent or null) | the right source per fix; provider speed 0 with a moving position does not pause | the wrong speed source drives the rule |
| DT-07-6 | S04-R-012 | I | 1 | M | F-still with auto-pause on | pausedAuto entered; no distance added after entry; distance before entry at most the drift of 8 s | drift while standing still adds distance |
| DT-07-7 | S04-R-012; Design 3.6 | I | 1 | M | the finalizer receives journaled pause events that differ from a recomputation (edited event offsets) | the events are the truth for moving time | the finalizer recomputes and disagrees with the live state |
| DT-07-8 | AC-D4-S-8; DN-12 | U | 1 | L | user Resume out of pausedAuto, speed stays below 0.5 m/s | the auto rule may pause again only after another full 8 s | an immediate re-pause |

### 3.3 EP-C Calculators (S04-08 to S04-10)

#### S04-08 Distance and summary (R-032, R-036)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-08-1 | S04-R-032; S04-08 AC-1 | I | 3 | H | `/F-walk`, `/F-ride-30kmh`, `/F-noise-line` | error at most 0.5 percent or 5 m, whichever is larger | the metric is wrong beyond tolerance |
| DT-08-2 | S04-R-032; S04-08 AC-2 | I | 2 | H | `/F-walk-real`, `/F-ride-real` | error at most 2 percent against the polyline truth (the surveyed-route check on a real route is DL-1, DL-2) | real-shaped noise breaks the calculator |
| DT-08-3 | S04-R-032; S04-08 AC-3 | I | 3 | H | `/gap` (F-tunnel), `/auto-pause` (F-stop-go), `/manual-pause` | gap, auto-pause and manual-pause spans add 0 m | distance accrues in a gap or a pause |
| DT-08-4 | S04-R-032 | U | 1 | M | haversine table: equator 1 degree of longitude, pole region, antimeridian 179.9 to -179.9, identical points, 0.1 m apart | known lengths within 0.01 m; no NaN; antimeridian short way | the formula fails at the antimeridian or for tiny steps |
| DT-08-5 | S04-R-036; S04-08 AC-4 | U | 1 | H | summary builder output | distance, moving time, elapsed time, ascent, descent, average speed, `formulaVersion`, `metricDefinitionVersion` all pass the real S02 validator | the produced summary is rejected at hand-off |
| DT-08-6 | S04-R-036; S04-08 AC-4 | U | 3 | H | `/over-bound` (distance above 10^7 m), `/negative`, `/nan` | the session is flagged and NOT written clamped; the user sees a failure reason | a clamped wrong value is stored |
| DT-08-7 | S04-R-036, S04-R-034 | I | 2 | M | `/no-altitude` (F-no-alt), `/zero-moving-time` | ascent and descent absent (not 0); average speed undefined (not infinity); validator passes | an undefined value is written as 0 |
| DT-08-8 | S04-R-032; D-8 | I | 1 | M | F-tunnel moving time. DEPENDS-ON-DESIGN D-8 (default: gap time counts as moving time) | moving time equals the decision recorded in the design; average speed uses it | the two documents disagree silently |
| DT-08-9 | S04-R-036 | I | 3 | M | `/zero-fixes`, `/one-fix`, `/two-fixes` | zero fixes: nothing saved and the reason `gpsNothingRecorded`; one fix: distance 0; two fixes: one segment | a degenerate track crashes the finalizer or saves an empty activity |

#### S04-09 Pace and speed (R-033)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-09-1 | S04-R-033; S04-09 AC-1 | I | 3 | H | `/walk-1.4`, `/run-3.0`, `/ride-8.33` constant-speed segments | after the 10 s window is full, pace within 3 s/km | the window is wrong or unfilled values are shown |
| DT-09-2 | S04-R-033; S04-09 AC-2 | U | 3 | H | `/under-10m` (9.99 vs 10.0 m of moving distance), `/stopped`, `/window-not-full` | undefined (null), never 0 or infinity; before the window fills the value is undefined (DEPENDS-ON-DESIGN) | "0:00" or infinity is shown |
| DT-09-3 | S04-R-033; S04-09 AC-3 | I | 3 | M | `/no-pause`, `/manual-pause`, `/auto-pause` | moving time equals elapsed minus paused within 1 s | moving time includes paused time |
| DT-09-4 | S04-R-033 | U | 1 | M | average pace with moving time 0 | undefined, no division by zero | a NaN or infinity reaches the UI |
| DT-09-5 | S04-R-033; Contract 8.1 | U | 1 | L | pace formatter at 5:59.6 and 6:00.0 | `6:00`, never `5:60` | rounding shows an invalid time |

#### S04-10 Elevation (R-034)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-10-1 | S04-R-034; S04-10 AC-1 | I | 2 | H | `/ascent`, `/descent` on F-flat-alt-noise | each at most 5 m | noise inflates elevation gain |
| DT-10-2 | S04-R-034; S04-10 AC-2 | I | 2 | H | `/F-climb` and `/F-climb-reversed` | ascent within 10 percent or 5 m of 100 m; reversed gives descent 100 m and ascent 0 | hysteresis loses real gain |
| DT-10-3 | S04-R-034; S04-10 AC-3 | I | 2 | H | `/none` (F-no-alt), `/partial` (altitude on half the fixes) | ascent undefined (null) for none; partial per design (DEPENDS-ON-DESIGN) and never silently 0 | missing data is shown as 0 m |
| DT-10-4 | S04-R-034 | U | 1 | M | hysteresis: 2.9 m vs 3.0 m change; reversal exactly at 3 m | counted only after 3 m from the last counted extreme | the threshold is off |
| DT-10-5 | S04-R-034; TP-S04-6 (resolved, Design 3.7) | I | 2 | M | F-climb-spike (one +100 m altitude sample); entries `/spike-ignored` (5-sample running median over kept altitudes, then a step above 10 m between consecutive medians in 1 s is ignored; both PROPOSED), `/real-climb-still-counted` | ascent with the spike equals ascent without it within the tolerance of DT-10-2; the 3 m hysteresis applies after the outlier rule | a GPS altitude glitch adds 100 m of climb, or the outlier rule swallows a real climb |

### 3.4 EP-D Journal, kill, recovery (S04-11 to S04-16)

Ordered-write points FP-1 to FP-12 are in section 4.3; rows cite them.

#### S04-11 Journal append and flush (R-014, R-015, R-043)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-11-1 | S04-R-014; S04-11 AC-1; Design 12.3 | K | 1 | H | scan the WHOLE `recording/` tree except `journal/` for `dart:io`, `File`, `Directory`, `path_provider`, `RandomAccessFile` | zero matches | a helper in another folder writes files directly |
| DT-11-2 | S04-R-014 | K | 1 | M | scan `recording/journal/` | file access only through the `JournalFileSystem` seam | the journal bypasses the fault-injectable seam, so FI tests prove nothing |
| DT-11-3 | S04-R-014; S04-11 AC-2 | I | 2 | H | `/append-first`, `/put-first`: a recorder append and an unrelated `ActivityJournal.put` released in forced order with completers | both land, neither lost, no deadlock | one mutation overwrites or blocks the other |
| DT-11-4 | S04-R-014, S04-R-015; FP-1 | I | 2 | H | `/meta-before-first-sample` (call-order spy: meta temp write, fsync, rename, then the first frame), `/begin-failure` (meta write throws) | `meta.json` is sealed and durable before any sample; a failed begin leaves no recording directory | samples exist without a readable meta |
| DT-11-5 | S04-R-015; Design 4.4; FP-2 | I | 3 | H | `/10-fixes` (flush at the 10th fix), `/5-seconds` (fake clock, 5 s, fewer than 10 fixes), `/event-forces-flush` (pause, resume, gap and stop events flush at once) | the earlier of the two triggers flushes; events flush immediately; each flush is write then fsync | the durability bound is longer than promised |
| DT-11-6 | S04-R-015; S04-11 AC-3; FP-2 | I | 1 | H | the 50 kill points of section 2.4 on F-kill-mid-run, FI with durable and volatile views; recover with a NEW journal object; the test loops all points and reports the worst gap | every run: recovered end at most 6 s before the kill; every recovered record complete; offsets strictly increasing; a torn last record dropped, not half-read | the promise is longer than 5 s, or a half record is read |
| DT-11-7 | S04-R-015; F4 | I | 6 | H | tail variants `/short-length-prefix`, `/truncated-payload`, `/bad-crc`, `/payload-bit-flip`, `/zero-length`, `/length-larger-than-remaining` | earlier frames valid, tail dropped (tolerated only at the end of the LAST segment, Design 4.2), no exception to the caller; an enormous length field does not allocate (bounded by remaining bytes) | a corrupt length crashes or exhausts memory |
| DT-11-8 | S04-R-015; Design 4.2 | I | 1 | H | after a torn tail restart and continue | the journal opens the NEXT segment; the dirty segment is never appended to; records written after the restart are recovered | new frames are appended after garbage and become unreadable |
| DT-11-9 | S04-R-015; Design 4.2 | I | 2 | M | `/rotation` (segment constant lowered by the test seam to a few frames), `/missing-middle-segment` (J-9) | rotation: segments numbered 1 to N without gaps, order preserved; missing middle: `recoveryFailed`, no partial track (TP-S04-7 resolved) | a gap in segments is hidden |
| DT-11-10 | S04-R-043; S04-11 AC-4 | I | 1 | M | F-100k through the controller; sample the live list length at every fix | never above 600 entries | memory grows with session length |
| DT-11-11 | S04-R-014; F17 | I | 1 | H | open the same recording directory twice | the second open fails with the already-open error; no interleaved writes | two writers corrupt one segment |
| DT-11-12 | S04-R-014; F6 | I | 1 | H | key provider throws `JournalKeyUnavailable` at begin | recording refused with a reason; no service started; no directory left | a recording starts that cannot be read later |
| DT-11-13 | S04-R-015; F7 | I | 1 | H | an append fails halfway (a partial frame reaches the volatile view), then succeeds on retry | the next frame goes to a NEW segment; no frame follows a torn frame in the same segment; no duplicated frame counter | a retry after a failed write produces an unreadable middle |
| DT-11-14 | S04-R-007; Design 4.2 | U | 2 | H | frame codec `/samples-schema` (columns `t, la, lo, ac, al, sp` plus four integer counters), `/event-kind` (closed set of event kinds) | an extra field or unknown event kind is rejected on write and on read | a stray field (place name, device id) can enter a frame |
| DT-11-15 | S04-R-007 | U | 1 | M | codec round trip: null altitude and speed per sample, negative latitude, offsets above 2^31 ms | decode equals encode exactly | precision or integer width loss |
| DT-11-16 | S04-R-015; S04-11 AC-5; T2 | D | 3 | H | DL-4: `/am-kill`, `/swipe-away`, `/phone-restart` during recording on the reference phone, then start the app | everything flushed before the kill is offered; loss at most about 5 s (PROPOSED); result recorded for each path | NOT_RUN until a phone |
| DT-11-17 | S04-R-015, S04-R-017; Design 4.2 (TP-S04-7, TP-S04-9 resolved) | I | 4 | H | `/torn-end-of-earlier-segment-announced` (J-11), `/torn-end-of-earlier-segment-unannounced` (J-10), `/frame-counter-gap`, `/segmentBreak-count-mismatch` | the announced torn end is tolerated and every frame counted; the other three are `recoveryFailed` (files untouched, no track shown, no partial offer) | a damaged middle is read as a short complete track |
| DT-11-18 | S04-R-015, S04-R-017; Y7 (Design 4.2) | I | 4 | H | `/segmentBreak-is-the-first-frame-after-resume`, `/segmentBreak-after-seal-after-kill`, `/segmentBreak-after-write-error-rotation`, `/duplicate-frame-counter-keeps-the-first-occurrence` (J-14) | every segment opened after an unclean close starts with a `segmentBreak`; a duplicate counter keeps the first frame and does not fail the recording | a missing break makes a legitimate torn end look like damage, or the duplicate replaces the first frame |

#### S04-12 Recovery offer and resume (R-016, R-054)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-12-1 | S04-R-016; AC-D4-R-2; S04-12 AC-1 | I | 2 | H | `/offer`, `/start-blocked`: journal from a killed run (NEW scope over the same file system); app start | `restoring` then the three choices; `requestStart` refuses while an unfinished recording exists | another recording can start over an unfinished one |
| DT-12-2 | S04-R-016; AC-D4-R-4; S04-12 AC-2; FP-6, FP-9 | I | 3 | H | `/resume` (same recording uuid, new segment, `restart` event, gap pair with offsets, time and distance across the gap not counted; the phase becomes `acquiring`, never straight `recording`), `/save-as-finished` (seal and hand-off; exactly one session), `/discard` (directory removed; file listing empty). The discard entry injects a crash after EACH file deletion of the discard | stored results as stated; after a crash in the middle of a discard no leftover is offered as a recording (order fixed by Design 4.5, TP-S04-8 resolved; the per-step rows are DT-12-13) | a discarded recording comes back, or a sample stays on disk |
| DT-12-3 | S04-R-016; Design 4.5 | I | 1 | M | readable journal with no kept fix | silent delete, no offer | the user is asked about an empty recording |
| DT-12-4 | S04-R-013; AC-D4-R-10; F18; Z1 | I | 2 | H | `/killed-while-manual-paused`, `/killed-while-auto-paused`; recover with a NEW object, choose Resume | Resume enters `acquiring` (never straight `recording` and never the earlier paused phase); the pause origin (manual or auto, pause offsets) is preserved in the journal; the accumulated moving time and distance values are unchanged by the recovery; a `restart` gap pair is journaled and adds neither moving time nor distance | the recorder resumes straight into recording or into the paused state, loses the preserved values, or counts the interrupted interval |
| DT-12-5 | S04-R-016; D-7 | I | 2 | M | `/gap-5-min`, `/gap-2-hours` | resume offered whatever the gap; the age is shown; gap markers have offsets; no distance or moving time for the gap | a long gap is refused, interpolated or counted |
| DT-12-6 | S04-R-016, S04-R-023; AC-D4-R-6 | I | 2 | H | `/permission-denied`, `/services-off` at Resume | Resume opens S4-1 at the matching denial panel; the request counter is unchanged | Resume starts a service without permission or re-requests by itself |
| DT-12-7 | S04-R-039; AC-D4-R-3 | I | 2 | H | `/fix-arrives`, `/no-fix-arrives` after Resume | `gpsAnnResumedRecovered` emitted only after the first kept fix and only on the verified path; not emitted when no fix arrives | the word "resumed" or "recovered" is claimed before verification |
| DT-12-8 | AC-D4-R-1; S04-R-016, S04-R-037 | W | 6 | H | entries `/tab-home`, `/tab-workouts`, `/tab-scan-or-third`, `/tab-progress`, `/tab-more` (the five shell tabs, names per `kShellDestinations`) and `/launch-no-dialog`; journal present | `gpsStripUnfinished` strip on every tab; Home card `home.gpsRecovery` with one button; no dialog or forced route at launch; gym flows unaffected | the offer is invisible on a tab or blocks start-up |
| DT-12-9 | AC-D4-P-12 (R-2); S04-R-016 | W | 1 | H | S4-1 with an unfinished journal | `blockedByJournal` panel with Review and Add manually; zero service starts | Start works while a recording waits |
| DT-12-10 | S04-R-016, S04-R-017; Contract 12 | W | 1 | M | S4-5 content | loading text `gpsRestoringLoading` (no spinner); body with kept time and distance, age, caveat `gpsRecoveryCaveat`; Resume shows `gpsResumeGapNote` | the caveat or gap note is missing |
| DT-12-11 | S04-R-016 | I | 1 | M | start the app twice without choosing | same offer; the journal is read-only until a choice; no duplicate | reading changes the journal |
| DT-12-12 | S04-R-016 | I | 1 | M | two unfinished recording directories. DEPENDS-ON-DESIGN: order and one-at-a-time rule | deterministic order, one offer at a time, none silently deleted | a recording is hidden |
| DT-12-13 | S04-R-016, S04-R-018; TP-S04-8 (resolved, Design 4.5); Y8; FP-9 | I | 7 | H | Discard with a crash injected after each ordered step: `/after-1-DISCARDING-marker`, `/after-2-segments-deleted`, `/after-3-SEALED-and-QUARANTINED-deleted`, `/after-4-meta-deleted-last`, `/after-5-directory-removed`; `/delete-works-when-the-key-is-lost` (the marker is a plain content-free file written without the key), `/hand-off-step-6-uses-the-same-ordered-delete`; then a NEW app start | the next `listUnfinished()` deletes a directory that has `DISCARDING` (completing steps 2 to 5) and never offers it; the listing shows no sample; `meta.json` is the last file to go, so a directory without `DISCARDING` that still has `meta.json` is a normal unfinished recording | a discarded recording returns as an offer, or a sample stays on disk |
| DT-12-14 | AC-D4-P-18; S04-R-016, S04-R-023 | W | 2 | M | S4-1 in resume mode: `/resume-title-no-sport-row-matching-denial-panel`, `/grant-continues-into-acquiring-recovered-origin` | resume title, no sport row, the matching denial panel and no `blockedByJournal`; a grant continues into `acquiring` with the recovered origin (kept time and distance shown) | the user must pick a sport again, or is blocked by their own recording |

#### S04-13 Recovery failed is honest (R-017)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-13-1 | S04-R-017; AC-D4-R-5; S04-13 AC-1 | I | 8 | H | J-1 to J-7 and J-12 (`/truncated-meta`, `/zero-meta`, `/schema-v2`, `/meta-tag-fails`, `/key-unavailable`, `/segments-no-meta`, `/mid-log-bit-flip`, `/sealed-disagrees-with-log`); hash the directory first | state `recoveryFailed`; no exception reaches the UI isolate (zone handler spy empty); bytes unchanged. For `/mid-log-bit-flip` (TP-S04-7 and TP-S04-9 resolved): `recoveryFailed`, no partial offer, no track shown | a corrupt journal crashes, is overwritten, or is shown as recovered |
| DT-13-2 | S04-R-017; S04-13 AC-2 | I | 2 | H | `/three-restarts`, `/only-two-actions` | bytes unchanged across restarts; only Keep (quarantine) and "Delete file" are offered, no Export | the user can be offered a track the app could not verify |
| DT-13-3 | S04-R-017, S04-R-039; AC-D4-R-5; S04-13 AC-3 | W | 1 | H | pump S4-5 in `recoveryFailed` | body `gpsRecoveryFailedBody`; no "restored" or "recovered" in any visible text, semantics label or announcement | the failure screen claims success |
| DT-13-4 | S04-R-039 | K | 1 | H | scan ARB keys and call sites reachable from the recovery-failed path | no forbidden word on that path | a success word is reachable from failure |
| DT-13-5 | S04-R-017; AC-D4-R-8 | I | 2 | H | `/keep` (a `QUARANTINED` marker is written; the files stay byte-identical; the strip, Home card and Start block clear; Start is allowed), `/delete-file` (second inline confirmation, then the directory is gone) | as stated; no Export exists in S04 | Keep alters the files or leaves the strip up, or delete happens without confirmation |
| DT-13-6 | AC-D4-Y-3; Contract 15 | W | 1 | M | the screen turns into `recoveryFailed` | focus moves to the new headline and is read by focus (zero `announce` calls for the same text); `gpsAnnRecoveryFailed` only where focus does not move | a double reading, or no signal at all |
| DT-13-7 | S04-R-017, S04-R-019; Design 4.5 | I | 1 | M | a quarantined recording; fake clock at 29 days 23 hours and then at 30 days | present before 30 days; at 30 days (PROPOSED) deleted by the ordinary owner-only recording deletion, no sample left | quarantined data lives forever or goes early |
| DT-13-8 | AC-D4-R-8, AC-D4-C-1; S04-R-017 | W | 2 | H | `/only-keep-and-delete-controls` (no Export control or string on the `recoveryFailed` screen), `/strip-and-home-card-persist-until-a-button` | exactly Keep and Delete file; the strip word and Home card persist until a button is pressed | an Export control returns, or the offer vanishes without a decision |

#### S04-14 Finish hand-off (R-018)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-14-1 | S04-R-018; S04-14 AC-1; FP-4, FP-5 | I | 1 | H | sequence spy over Stop | order: subscription released, last flush, stop event, `SEALED`, worker, `put`, verify read, delete directory, revision bump | the journal is deleted before the session is committed |
| DT-14-2 | S04-R-018; S04-14 AC-2; FP-5 | I | 7 | H | crash injected after each step of Design 4.3 (`/after-step-1` to `/after-step-7`); restart with a NEW object | never neither copy; `SEALED` plus stored id: silent delete after verify; `SEALED` without a stored session: re-run from step 3; before `SEALED`: treated as unfinished and offered | data loss in the hand-off window, or a duplicate activity |
| DT-14-3 | S04-R-018, S04-R-020; S04-14 AC-3; AC-D4-T-3 | I | 3 | H | `put` fails with `/storage-full`, `/key-unavailable`, `/io` | journal kept; user text `gpsSaveFailed`; retry once per tap; never a claim of saved | a failed save is reported as saved or deletes the journal |
| DT-14-4 | S04-R-018 | I | 2 | H | `/double-tap-finish` (two Finish taps with a held completer), `/re-put-after-crash` | one hand-off in flight; one session; an identical re-put is a no-op | two activities for one recording |
| DT-14-5 | S04-R-018 | I | 1 | H | verify step returns absent or `streamLost` | the recording directory is NOT deleted | deletion after an unverified save |
| DT-14-6 | S04-R-018, S04-R-036; Design 4.3 | I | 1 | M | the produced session | id from `nativeActivityId(recordingUuid)`; provenance from `nativeSourceRecord`; sport, `startUtc`, `endUtc`, versions set | wrong id breaks idempotency |
| DT-14-7 | S04-R-041; F16 | I | 1 | H | the worker function throws | journal kept; bare error code; retry offered; UI isolate unaffected | a worker failure loses the recording |
| DT-14-8 | S04-R-018; Design 4.3 | I | 2 | M | `/success`, `/failure` | `activityJournalRevisionProvider` bumped once on success, not on failure | dashboards do not reload, or reload on a failure |
| DT-14-9 | S04-R-036; F19 | I | 1 | M | session reaching 190 000 samples (counter seam) | stops with a visible reason and hands off; never exceeds 200 000 | the S02 sample bound is exceeded |
| DT-14-10 | S04-R-045; Design 6.3 | I | 1 | H | account switch during `stopping` | the hand-off writes to the owner's scope captured at Start | the activity lands in the new account |
| DT-14-11 | S04-R-018; Design 4.3 step 5 | I | 1 | M | the user deletes the handed-off activity from the S02 store (a tombstone exists) after step 4, then a retry runs | outcome `tombstoned`: step 6 still deletes the recording directory and the activity is NOT re-created | a deleted activity comes back |
| DT-14-12 | S04-R-018; Design 4.3 step 2 (ARCH5) | I | 2 | H | `/stop-event-without-sealed-reseals-once` (crash between the stop event and `SEALED`), `/importedAt-reused-on-repeat` (hand-off repeated after a crash) | `SEALED` is re-written once with the stop reason and an `importedAt` fixed once; a repeated hand-off builds an identical record and the `put` stays a no-op; a `SEALED` whose counts disagree with the log is `recoveryFailed` (DT-13-1) | a repeat creates a second activity, or `importedAt` changes between attempts |

#### S04-15 Journal lifecycle and owner-only storage (R-019, R-045)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-15-1 | S04-R-019; S04-15 AC-1; FP-8 | I | 3 | H | real temp directory and the real factory; begin and append; entries `/sign-out-and-delete`, `/account-deletion`, `/device-wipe` (a plain sign-out and the event rows are DT-30-2); then walk the tree | `recording/` is gone after the wipe (the fourth directory of Design 4.7 is in the wipe list); no undecryptable leftover | recorded location data survives sign-out |
| DT-15-2 | S04-R-019; S04-15 AC-2 | I | 1 | H | real temp directory (path provider faked); start a recording; list EVERY top-level entry of the support directory | every top-level entry has a `domain="file"` exclude in the three XML sections (the S03 DT-0-6 rule) | location history can leave through backup |
| DT-15-3 | S04-R-019 | K | 1 | H | constants and XML | one shared scoped-root constant; the recording directory is under it | the backup list and the factory drift apart |
| DT-15-4 | S04-R-045; S04-15 AC-3 | I | 1 | H | two real scope directories (uid A and B); A has an unfinished recording | `listUnfinished` for B is empty | another user's recording is listed |
| DT-15-5 | S04-R-045; AC-D4-R-7 | W | 3 | H | `/strip`, `/home-card`, `/start-block` after switching A to B | none of the three shows A's offer | a foreign recording or offer is visible |
| DT-15-6 | S04-R-019; F15 | I | 0 | H | moved to S04-30: DT-30-2 (different uid, sign-out, deletion events) and DT-30-4 (deletion order) | n/a | n/a |
| DT-15-7 | S04-R-019; FP-8 | I | 1 | H | a flush in flight (completer); `wipe(uid)`; release the write | no file or directory is recreated after the wipe | a late write resurrects location data |
| DT-15-8 | S04-R-045 | I | 1 | M | the factory root | under the app-private support directory, not external storage or cache | wrong storage class |
| DT-15-R | S04-R-019 regression | I | 0 | M | run existing S02 journal tests and backup tests UNCHANGED (list found with Glob) after the S02 touches (wipe list, `put` CPU move) | green, no edit | the S02 touches broke S02 |
| DT-15-9 | S04-R-019; AC-D4-R-11; Z3; GPS-PRIV-014 | I | 6 | H | lifecycle on a real temp tree with two real scopes; the state is asserted after EACH step: `/successful-hand-off-then-the-recording-journal-is-deleted`, `/failed-hand-off-the-unsealed-recording-stays-encrypted-in-its-own-scope`, `/explicit-sign-out-hands-off-first-then-deletes-and-names-the-leftover-with-gpsSignOutNotice-30-days-PROPOSED-when-hand-off-failed`, `/account-deletion-deletes-the-leftover`, `/expiry-at-30-days-deletes-the-leftover`, `/subsequent-sign-in-of-the-same-account-offers-recovery-and-another-account-sees-nothing` | as stated; never readable by another account | an unhanded recording leaks, never expires, or is lost silently |
| DT-15-10 | S04-R-019; Z3 | K | 2 | M | `/privacy-contract-carries-the-proposed-clarification-note-next-to-GPS-PRIV-014`, `/requirements-record-the-operator-question-strict-deletion-versus-the-30-day-leftover` | both notes exist, marked PROPOSED | the amendment is silent |

#### S04-16 Storage full (R-020, SHOULD)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-16-1 | S04-R-020; S04-16 AC-2; F7 | I | 2 | H | `/space-returns` (write failure for 20 s, then success), `/stops-after-60s` | recovers without loss within 60 s; after 60 s the recorder stops and saves everything up to the stop | samples dropped on a recoverable failure, or recording continues forever |
| DT-16-2 | S04-R-020 | I | 1 | H | stop on persistent failure | the stop reason `stoppedStorage` is stored if possible and shown on S4-4 (`gpsReasonStorage`) | a silent stop |
| DT-16-3 | S04-R-020, S04-R-043 | I | 1 | M | sustained failure for 60 s at 1 Hz | in-memory buffer bounded (600 fixes plus the batch) | unbounded memory |
| DT-16-4 | S04-R-020; F6 | I | 1 | M | disk full at begin (meta write fails) | recording refused with a reason | a recording starts that cannot be saved |
| DT-16-5 | S04-R-020; Contract 16.2 | W | 2 | M | `/banner` (`gpsStorageBanner`, no dialog), `/finish-reason` | as stated | a modal appears while recording |
| DT-16-6 | S04-R-020; D-9 option B | I | 1 | L | CONDITIONAL on D-9 option B: free space under 20 MB | warning shown | n/a if option A (early warning skipped; reason recorded) |

### 3.5 EP-E Permission flow and consent (S04-17 to S04-21)

#### S04-17 Foreground permission flow and denial paths (R-021, R-023)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-17-1 | S04-R-021; AC-D4-P-1; RS-1; S04-17 AC-1 | W | 5 | H | `/launch`, `/onboarding`, `/tab-switches`, `/record-sheet-open`, `/start-screen-render`; `FakePermissionService` and `FakeLocationSource` | zero permission calls and zero location calls in each | a prompt appears before the user chose a location feature |
| DT-17-2 | S04-R-021; AC-D4-P-2; S04-17 AC-2 | W | 2 | H | `/pre-prompt-shown`, `/not-now` | the first Start shows `gps.start.panel.preprompt` with `gpsPrePromptReason` and `gpsPrePromptPrecise`; the privacy line `gpsPrivacyLine` (where stored, who sees) is on screen and in the semantics tree in the same view; request count 0 until Continue; Not now ends with 0 requests | the system dialog appears without the reason |
| DT-17-3 | S04-R-021, S04-R-025; AC-D4-P-3 | I | 1 | H | call-order spy on a first Start with every grant | order: pre-prompt, consent write, location request (fine and coarse together), notification request (SDK 13 and later), meta write, service start, `acquiring` | wrong order (notification after the service, request before consent) |
| DT-17-4 | S04-R-023; AC-D4-P-4 | W | 3 | H | `/denied-once-panel`, `/try-again-one-request`, `/double-tap-try-again` | `deniedOnce` with Try again and Add manually; Try again sends exactly one request; a double tap still one | a request loop |
| DT-17-5 | S04-R-023; AC-D4-P-5 | W | 2 | H | `/five-start-taps` (permanently denied), `/open-settings` | `deniedForever`; zero requests over five taps; Open settings calls `openSettings` once | the app re-requests after a permanent denial |
| DT-17-6 | S04-R-023; AC-D4-P-6 | W | 1 | H | approximate only | no service; explanation `gpsApproxBody`; Open settings and Add manually | recording starts with coarse accuracy |
| DT-17-7 | S04-R-023, S04-R-008; AC-D4-P-6 | I | 1 | H | the controller receives the approximate status directly | `requestStart` refuses, no subscription | the UI is bypassed by another entry point |
| DT-17-8 | S04-R-023; AC-D4-P-7 | W | 1 | M | location services off | `servicesOff` panel, no request, Open location settings | a request is sent when the real cause is the switch |
| DT-17-9 | S04-R-023; AC-D4-P-10 | W | 13 | H | one entry per panel `/deniedOnce`, `/deniedForever`, `/approximateOnly`, `/servicesOff`, `/notifOff`, `/noGps`, `/blockedByJournal`, `/batteryTooLow`, `/restricted`, `/consentWithdrawn`, `/cannotStart`, `/startFailed`, plus `/preparing-back-only` | Add manually reachable on every panel except `preparing` (Back only, no buttons); Back never blocked; focus goes to the panel header | a dead end in a denial path |
| DT-17-10 | AC-D4-P-11; S04-R-040 | W | 1 | M | `FakeDeviceCapabilities(hasGps: false)`. DEPENDS-ON-DESIGN: the detection source is UNGROUNDED (Contract 23) | Start replaced by `noGps`; no service start | a device without GPS gets a Start button |
| DT-17-11 | AC-D4-P-12; S04-R-016 | W | 1 | H | unfinished journal; tap Start on S4-1 (the panel itself is DT-12-9) | zero service starts and zero permission requests | Start is accepted while a recording waits for a decision |
| DT-17-12 | AC-D4-P-13; S04-R-030 | W | 5 | H | battery `/3-percent-refuses`, `/4-percent-note`, `/10-percent-note`, `/11-percent-no-note`, `/charging-ignores` | at 3 percent or less unplugged Start is refused (`batteryTooLow`); 4 to 10 shows `gpsBatteryStartNote`; charging ignores both | boundaries off by one |
| DT-17-13 | AC-D4-P-14; RS-4 | W | 3 | H | `/dialog-result-differs-from-tapped-button`, `/return-from-settings-granted`, `/return-from-settings-revoked` | the panel matches the real status read after the dialog or the resume, not the tapped button | stale UI after the user changed settings |
| DT-17-14 | S04-R-021; retro rule 6 | I | 3 | H | permission stream: `/repeated-identical-status` (denied, denied), `/denied-then-granted-on-panel` (the Start flow continues without another tap), `/granted-then-denied-before-service` | no duplicate panel or transition; no double service start | an equal event restarts the flow |
| DT-17-15 | S04-R-023 | I | 1 | H | 20 scripted Start taps across all states | request count never above 1 per tap | any loop |
| DT-17-16 | S04-R-023; AC-D4-P-20 (TP-S04-10 resolved) | W | 3 | H | `FakePermissionService` returns `restricted`; entries `/panel-and-only-add-manually` (panel `restricted` with `gpsRestrictedTitle` and `Body`; no Open settings button exists), `/zero-requests-over-many-taps`, `/focus-and-single-announcement` (focus on the panel header, `gpsAnnRestricted` once) | as stated | a restricted user is sent to a settings page that cannot help, or a request is sent |
| DT-17-17 | RS-6 | W | 1 | M | double tap on Start with a held start | one service start | duplicate foreground service start |
| DT-17-18 | S04-R-023 | I | 1 | M | `requestLocation` throws a platform error | neutral failure panel, no loop, the error reduced to a bare code | an exception escapes to the UI |
| DT-17-19 | S04-07 AC-4; DN-15 | W | 2 | M | `/auto-pause-default-on`, `/last-sport-remembered` | toggle on by default; the last sport is preselected | defaults reset every time |
| DT-17-21 | AC-D4-P-19; S04-R-023 | D | 1 | M | DL-15: approximate-only, switch to Precise in system settings, return to S4-1; record whether a re-request is allowed after a downgrade (F7) | continues without a new request; the outcome is recorded | NOT_RUN until a phone |
| DT-17-22 | AC-D4-P-23; S04-R-023 | W | 1 | M | pairwise table of blocking conditions true at once (RS-11 order: `consentWithdrawn`, `blockedByJournal`, `preparing`, `cannotStart`, `batteryTooLow`, `noGps`, `restricted`, `servicesOff`, `deniedForever`, `approximateOnly`, `deniedOnce`, `preprompt`, `notifOff`, `startFailed`, `backgroundAsk`) | the panel shown is the highest in the order; after it is resolved the next applicable one shows | the wrong panel hides the real cause |

#### S04-18 Background-location decision (R-022) - CONDITIONAL

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-18-1 | S04-R-022; AC-D4-P-9 (default); S04-18 AC-1 | K | 2 | H | `/manifest` (covered with DT-04-1), `/code` (no reference to the background-location permission symbol or its request outside an excluded branch folder) | none declared, none requested | a background request exists in the default build |
| DT-18-2 | S04-R-022; AC-D4-P-9 (branch B); S04-18 AC-2 | W | 3 | H | built only if D-2 picks B: `/after-foreground-grant`, `/separate-call-on-start-tap`, `/decline-still-records` | requested only after the foreground grant, as a separate call, only at a Start tap; declining still records in foreground-service mode | the background step blocks recording |

#### S04-19 Revocation mid-recording (R-024)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-19-1 | S04-R-024; AC-D4-V-1; S04-19 AC-1 | I | 4 | H | status flipped to denied in `/acquiring`, `/recording`, `/pausedManual`, `/pausedAuto` | `activeSubscriptions` 0 within 2 s; session saved and flagged `permission revoked`; phase `permissionRevoked`; request counter unchanged; S4-6 offers Keep and Delete only (no Export), focus on the S4-6 headline read by focus with zero `announce` calls for the same text | collection continues, data is lost, or the app re-requests |
| DT-19-2 | S04-R-024; Design 6.1 | I | 4 | H | detection channels `/poll-per-fix`, `/stream-error`, `/stream-closed-unexpectedly`, `/app-resume` | each channel detects within 2 s of fake time and takes the same path | revocation is seen on one channel only |
| DT-19-3 | S04-R-024; Design 6.1 (T3) | I | 1 | M | process restart with no observed revocation | recovery path with copy "interrupted", not "revoked" | the app claims a revocation it did not observe |
| DT-19-4 | S04-R-024; retro rule 6 | I | 1 | M | sequence denied, denied, granted, denied | one save, one announcement; granting again does not auto-resume | repeated events double-save or resume by themselves |
| DT-19-5 | S04-R-024; FP-5 | I | 1 | M | revocation while `stopping` | hand-off completes; no double release | races between release paths |
| DT-19-6 | S04-R-024; AC-D4-V-1; S04-19 AC-2 | W | 3 | H | `/keep` (Keep = seal and hand off the data up to the revocation as a finished partial activity, D-19 resolved; reason `gpsReasonRevoked`), `/delete` (inline confirmation then idle), `/open-settings-is-not-a-request` | exactly Keep and Delete (no Export); Open settings opens settings only | a re-request path or an Export control exists |
| DT-19-7 | S04-R-024; AC-D4-V-2 | I | 3 | H | app in background: `/notif-allowed` (`gpsRevokedNotif` posted), `/notif-denied` (strip and Home card carry it), `/no-decision` (Keep is the default outcome) | as stated | a revoked recording is lost or invisible |
| DT-19-8 | S04-R-024; AC-D4-V-3; S04-19 AC-3 | D | 2 | H | DL-5: `/revoke-in-settings`, `/precise-to-approximate` while recording; record how fast the app learns | latency recorded; process restart case recorded | NOT_RUN until a phone |
| DT-19-9 | AC-D4-Y-3 | W | 1 | M | revocation while the app is `/in-the-background` | `gpsAnnRevoked` (assertive) only where focus does not move; zero `announce` calls when S4-2 turns into S4-6 (the focus move is read) | a double reading, or silence |
| DT-19-10 | AC-D4-V-4; S04-R-024, S04-R-037 | W | 3 | M | a pending revoked decision: `/strip-row-on-five-tabs-and-home-card`, `/start-not-blocked`, `/keep-and-delete-each-clear-both` | `gpsStripRevoked` on all five tabs and the Home card until Keep or Delete; Start works and the pending item is excluded from the unfinished-recording precondition; both decisions clear both | a pending decision is invisible, or blocks recording |
| DT-19-11 | S04-R-024, S04-R-018; D-19 | I | 2 | H | `/keep-hands-off-as-finished-partial` (one session stored under the owner scope, journal deleted after confirmed hand-off), `/delete-removes-all` (journal gone, file listing empty) | as stated | Keep quarantines readable data, or Delete leaves samples |
| DT-19-12 | S04-R-024, S04-R-018; AC-D4-V-5; Z2; FP-18 | I | 6 | H | a recording revoked mid-run, a fault or a kill injected at each step of the canonical sequence: `/fault-at-revocation`, `/fault-after-seal` (the partial recording is durably SEALED as a pending decision), `/process-death-while-pending`, `/fault-during-keep`, `/fault-during-hand-off`, `/fault-during-delete`; NEW objects after each fault | collection is stopped; the pending decision is listed by `listUnfinished`, survives a kill and is not offered as a normal Resume; Keep runs the ordered, idempotent, owner-checked hand-off; Delete runs the ordered delete (`DISCARDING` marker); after every fault the durable state is exactly one of: pending decision, or one finished activity (never both, never two activities) | a revoked recording is lost, duplicated, or comes back after Delete |
| DT-19-13 | S04-R-024; Z2 | I | 3 | H | `/keep-repeated-and-keep-after-restart-give-one-activity`, `/delete-after-a-started-hand-off-never-resurrects`, `/pending-decision-does-not-block-start-and-is-not-listed-for-another-uid` | one activity; no resurrection; no leak across accounts; a Delete arriving after a durable `KEEP` is a no-op refused with "already decided" and never removes the finished S02 activity, even when the journal cleanup is unfinished (Z8) | a second Keep creates a second activity, or Delete is undone by a retry |
| DT-19-14 | S04-R-024; AC-D4-V-6; Z5, Z7; S04-19 AC-5, AC-6, AC-8, AC-9; FP-20 | I | 10 | H | Keep and Delete on a pending-decision recording with a durable `DECISION` marker (`KEEP` or `DELETE`, one file created exclusively, never renamed over; `DISCARDING` is only the progress marker of the DELETE path and is valid only together with `DECISION` = `DELETE`): `/concurrent-keep-and-delete-keep-marker-first`, `/concurrent-keep-and-delete-delete-marker-first`, `/crash-before-put-with-keep-marker`, `/crash-before-put-with-delete-marker`, `/crash-immediately-after-a-successful-put`, `/crash-before-journal-cleanup`, `/replayed-keep-is-a-no-op-already-decided`, `/replayed-delete-is-a-no-op-already-decided`, `/two-concurrent-keeps-give-one-activity`, `/loser-does-nothing-irreversible` (no `put`, no delete step, no overwrite of `DECISION`); NEW objects after each crash | the first durable marker wins; a crash before `put` is completed by recovery (KEEP: idempotent upsert on the deterministic activity id; DELETE: ordered delete); after `put` or before cleanup exactly one S02 activity exists; a replay or the other choice reports `gpsAlreadyKept` or `gpsAlreadyDeleted` and changes nothing; exactly one deterministic result, no duplicate activity and no resurrected data; the loser's exclusive create fails and it reports "already decided" | a race produces two activities, a deleted recording returns, or a replay acts twice |
| DT-19-15 | AC-D4-V-6; Z5; S04-19 AC-6 | I | 2 | H | `/forced-delete-after-KEEP-is-durable` and `/keep-after-DELETE-is-durable` | the forced Delete is refused and the S02 activity is intact (deleting that finished activity later is a separate S02 action); Keep is refused and the delete completes on recovery | Delete removes the activity that Keep created, or Keep revives a deleted recording |
| DT-19-16 | AC-D4-V-6; Z5; S04-19 AC-6 | W | 1 | H | after `KEEP` is durable: S4-6, the strip row and the Home card | no Delete control exists on any of the three | Delete is offered after Keep |
| DT-19-17 | S04-R-024; Z5; Z7; S04-19 AC-5, AC-7 | I | 3 | H | `/decision-created-exclusively-never-renamed-over`, `/file-then-directory-fsync-before-the-first-irreversible-step` (a barrier hook records the order of events; the only invariant asserted is that no irreversible operation, that is the hand-off `put`, a deletion step or the `DISCARDING` marker, begins before both durability barriers, the file fsync and the parent-directory fsync, have completed; no claim is made about which state a crash between the two barriers leaves, Z12), `/recovery-reads-the-marker` (KEEP completes then cleans up, DELETE completes the ordered delete, no marker means still a pending decision) | as stated | an action starts before its marker is durable, a torn marker is trusted, or the decision file is replaced by a rename |
| DT-19-18 | S04-R-024; AC-D4-V-6; Z7; S04-19 AC-10; FP-20 | I | 4 | H | forced two-writer interleaving: a test hook pauses both callers after each has checked for a marker and before either creates `DECISION`; released in both orders: `/barrier-keep-released-first`, `/barrier-delete-released-first`, `/barrier-two-keeps`, `/barrier-two-deletes`; NEW objects afterwards | in each order exactly one exclusive create succeeds and exactly one `DECISION` exists, equal to the winner's choice; the loser's create fails, it reads the winner and does nothing irreversible; the final durable state is the single consistent result of DT-19-12; a rename-based implementation fails this row | both callers see absence and the later one overwrites the earlier decision |
| DT-19-19 | S04-R-024; Z7; S04-19 AC-9 | I | 2 | H | the in-process per-recording mutex bypassed in the test so the file arbitration stands alone: `/mutex-bypassed-keep-vs-delete`, `/mutex-bypassed-two-keeps` | exactly one winner, one `DECISION`, one activity at most, no loser action; the mutex is defence in depth, not the arbiter | correctness depends on the mutex |
| DT-19-20 | S04-R-024; Z7, Z10, Z11; S04-19 AC-11 | I | 4 | H | a malformed `DECISION` found by `listUnfinished()` at recovery (no writer is alive; the process-wide journal lock is held by this process, so recovery and the writer are the same process): `/empty-file-at-recovery`, `/truncated-file-at-recovery`, `/unknown-token-at-recovery`; and `/live-loser-finds-empty-file` (fallback path without hard-link publish; fake clock: the reader waits on the process-wide journal lock for a bounded time, then reports "decision in progress, try again" without acting) | the first three: the recording is QUARANTINED with a user notice, the `DECISION` file is never removed or rewritten (bytes unchanged), nothing is deleted and nothing is handed off; the live loser acts on nothing; ordinary permission revocation never quarantines | a malformed file is removed, read as a decision, or leads to a delete or a hand-off |
| DT-19-21 | S04-R-024; Z7, Z9; S04-19 AC-12 | I | 6 | H | the full recovery matrix, each state built on disk with NEW objects and driven through `listUnfinished()` itself (no private helper called directly): `/DELETE-with-DISCARDING`, `/DELETE-without-DISCARDING`, `/KEEP-without-DISCARDING`, `/KEEP-with-DISCARDING`, `/DISCARDING-without-a-valid-DELETE-decision`, `/no-DECISION-and-no-DISCARDING` | per row: DELETE plus DISCARDING completes the ordered deletion; DELETE without DISCARDING writes `DISCARDING` and then deletes; KEEP without DISCARDING completes the idempotent hand-off (one activity) and then cleans up; KEEP plus DISCARDING and DISCARDING without a valid DELETE decision are QUARANTINED with a visible notice, no delete, no hand-off, file bytes unchanged; no files at all is a pending decision, listed and untouched | a malformed combination deletes data or hands off, a valid state is not completed, or the matrix is only tested through a helper |
| DT-19-22 | S04-R-024; Z10, Z13, Z14; S04-19 AC-11, AC-13; FP-20 | I | 3 | H | regression of the rule "a `DECISION` is never unlinked or replaced on its own; it disappears only together with its whole recording directory, after DELETE completion or after verified KEEP cleanup": the writer is paused between the temp-file fsync and the hard-link publish (primary path) or after its exclusive create and before it writes content (fallback path); `/recovery-runs-while-the-writer-is-paused`, `/retrying-caller-runs-while-the-writer-is-paused`; the writer is then released; and `/recovery-cannot-run-concurrently-with-a-live-fallback-writer` (Keep and Delete are gated on `recoveryComplete`; recovery runs before they are enabled) | no `DECISION` is ever removed or replaced in either case and the callers report "decision in progress"; the writer commits and wins; the retrying caller and recovery observe the committed winner and take no irreversible action of their own; Keep and Delete are refused until `recoveryComplete` | recovery or a retry removes the claim and a second decision is made, or an action runs before recovery completes |
| DT-19-23 | S04-R-024; Z10, Z14; S04-19 AC-11, AC-13 | I | 3 | H | publish-whole property: `/reader-never-sees-an-empty-decision-with-hard-link-publish` (a reader polls at every step of the winner's temp write, fsync, publish and directory fsync), `/fallback-without-hard-link-reader-waits-on-the-journal-lock` (exclusive create then write, guarded by the process-wide journal lock), `/second-journal-instance-in-another-process-or-isolate-fails-to-open` (while the first instance holds the process-wide exclusive file lock) | with hard-link publish no reader ever observes an empty or partial `DECISION`; on the fallback path a reader that sees an empty file waits on the lock (bounded) instead of acting; the second instance fails closed with a visible error and records nothing | a reader acts on an empty file, the fallback publishes without the lock, or two processes open one journal |
| DT-19-24 | S04-R-024; Z13; S04-19 AC-5, AC-7 | I | 2 | H | KEEP cleanup: `/completed-keep-cleanup` (the hand-off is verified, that is the S02 repository holds the activity with the deterministic id for the pinned owner, and only then the whole recording directory is removed by the tombstone-first ordered removal), `/crash-and-restart-during-keep-cleanup` (a crash injected after each step of the removal; NEW objects) | after cleanup the directory and its `DECISION` are gone together and exactly one activity exists; after a crash recovery sees KEEP without `DISCARDING` (or a tombstone) and repeats the idempotent hand-off check and the cleanup; a removed directory is no longer actionable, so no opposite decision becomes possible and a live writer cannot be invalidated | the directory is removed before the hand-off is verified, a second activity appears, or Delete becomes possible after Keep |

#### S04-20 Notification permission (R-025) - CONDITIONAL (default branch: refuse)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-20-1 | S04-R-025; S04-20 AC-1 | W | 2 | H | `FakeSdkInt`: `/sdk-13-asks-before-service`, `/sdk-12-no-step` | asked after the location grant and before the service on 13 and later; no step below 13 | wrong order or a needless prompt |
| DT-20-2 | S04-R-025; S04-20 AC-2 | W | 1 | M | granted | the notification shows, service starts | no visibility of collection |
| DT-20-3 | S04-R-025; AC-D4-P-8 (variant A); S04-20 AC-3 | W | 3 | H | `/denied-once`, `/denied-permanent` (Open settings instead of Allow), `/later-enabled-in-settings` | no service; `notifOff` panel; RS-4 picks up a later change without a new prompt | recording without a visible notification |
| DT-20-4 | S04-R-025; AC-D4-P-8 (variant B) | W | 2 | M | built only if D-5 picks B: `/record-without-notification-explicit-tap`, `/banner-shown` | service starts only after the explicit tap; `gpsNotifOffBanner` is the lowest banner item | silent recording without notification |
| DT-20-5 | S04-R-025 | W | 1 | L | pre-line `gpsNotifReason` shown before the request | present | wording missing |
| DT-20-6 | S04-R-025; T4 | D | 1 | H | DL-6: deny the notification permission on Android 13 or later; does the service keep running | outcome recorded in the Study | NOT_RUN until a phone |

#### S04-21 Two consent rows (R-026, R-027)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-21-1 | S04-R-026; S04-21 AC-1 | U | 2 | H | `/record-fields` (purpose, UTC timestamp, text version, state), `/background-row-not-written` | one record with the four fields; the background row exists in the schema and is written only when D-2 picks B | a missing field or a premature background row |
| DT-21-2 | S04-R-026; S04-21 AC-2 | I | 2 | H | `/withdraw-then-start` (no request, Start refused), `/no-data-deleted` (the surface and the links are DT-33-*; there is no Export) | as stated | withdrawal deletes data or Start still collects |
| DT-21-3 | S04-R-026; Design 6.2 | I | 1 | H | the consent write throws | the system permission request is NOT made | collection starts without a stored consent |
| DT-21-4 | S04-R-026; retro rule 2; FP-7 | I | 3 | H | `/ordered-writes` (older write cannot land after a newer one, completers), `/uid-guard` (write refused if the signed-in uid differs), `/wiped-uid-guard` | as stated | a stale write changes the wrong account's consent |
| DT-21-5 | S04-R-026; Design 6.2 | I | 3 | M | `/key-shape` (`activity.locationConsent.v1.<uid>`), `/no-collision` with the cloud-streams consent keys, `/wipe-erases` | key shape fixed; no collision; the existing wipe removes it | consent survives account deletion |
| DT-21-6 | S04-R-027; AC-D4-C-2; S04-21 AC-3 | U | 2 | M | `/version-equal` (record versus string file), `/draft-marker` (`gpsPrivacyLine`, `gpsPrePromptReason`) | equal versions; DRAFT marker present | a text change without a version bump |
| DT-21-7 | S04-R-026; Design 6.2 | I | 4 | H | 2x2 table: consent granted or not by permission granted or not | Start allowed only when BOTH are granted | one of the two is enough to start |
| DT-21-8 | S04-R-026 | I | 2 | M | `/corrupt-value`, `/unknown-version` | treated as no consent (fail closed); not overwritten until an explicit action | a corrupt value grants consent |
| DT-21-9 | S04-R-027 | I | 1 | L | stored text version older than the string version. DEPENDS-ON-DESIGN | the pre-prompt is shown again | an old consent stands for new wording |
| DT-21-10 | AC-D4-P-22; S04-R-026, S04-R-027 | I | 2 | H | `/continue-writes-the-consent-record-with-the-text-version-before-the-location-request`, `/not-now-writes-none` | as stated (call-order spy) | collection starts without a stored consent |

### 3.6 EP-F Battery (S04-22, S04-23)

#### S04-22 Battery-critical behaviour (R-030)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-22-1 | S04-R-030; AC-D4-B-1, AC-D4-B-3, AC-D4-B-4; S04-22 AC-1 | I | 6 | H | `/10`, `/9`, `/3`, `/2` percent unplugged on a recording, plus `/11` and `/4` (the other side of each boundary) | at 11 no critical state; at 10 and 9: `batteryCritical`, banner with percentage, request interval 5 s, flush 1 s; at 4 critical and still recording; at 3 and 2: finish and save with the stop reason `stoppedBattery` and `gpsReasonBattery` on S4-4 | a threshold is off by one on either side |
| DT-22-2 | S04-R-030; AC-D4-B-2; S04-22 AC-2 | I | 5 | H | `/charging-at-8`, `/charging-starts-after-critical`, `/exit-at-12`, `/oscillate-and-repeat-equal` (9, 10, 11, 12, 10, 10, 10), `/jump-15-to-2` | charging at 8 does not enter; charging or 12 percent exits and restores 1 s; no chatter on repeated equal values; a jump from 15 to 2 still finishes and saves | missed thresholds on a jump, or flapping |
| DT-22-3 | AC-D4-B-1; AC-D4-G-3; S04-22 AC-3 | W | 3 | H | `/not-a-dialog` (route observer), `/not-dismissible`, `/percentage-updates-once-per-percent` | banner only; no `DialogRoute` or sheet | a modal while recording |
| DT-22-4 | S04-R-030; AC-D4-B-3 | I | 2 | H | `/reason-visible-and-stored`, `/save-fails-at-3-percent` | the reason is stored and shown; with a failed save the journal stays and the reason is still shown | a silent stop |
| DT-22-5 | AC-D4-B-3; AC-D4-Y-3 | W | 2 | M | `/gpsAnnBattery`, `/gpsAnnBatteryFinish` | each once, assertive (or fallback) | missing or repeated |
| DT-22-6 | S04-R-030; Design 8.1 | I | 2 | M | `/monitor-throws`, `/monitor-unavailable` | no crash, no false critical state, recording continues | a battery source failure kills the recording |
| DT-22-7 | S04-R-006, S04-R-030 | I | 1 | M | 600 s replay with a critical window | request interval 1 s outside, 5 s inside; request count equals the expected sum | the interval does not change on the live source |
| DT-22-8 | S04-R-030 | I | 1 | L | critical while paused or acquiring. DEPENDS-ON-DESIGN | banner shown; interval change rule per design | undefined behaviour |

#### S04-23 Battery protocol document (R-028)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-23-1 | S04-R-028; S04-23 AC-1 | K | 1 | M | read `docs/phase2/s04/S04_BATTERY_PROTOCOL.md` (written by lane R11) | contains each required field name of section 5.3 | a field of the protocol is missing |
| DT-23-2 | S04-R-028; S04-23 AC-2 | K | 2 | M | `/complete-record-accepted`, `/record-missing-a-field-rejected` (one table over the required fields) | the record validator accepts a full record and rejects one missing any field | an incomplete run is accepted as evidence |

### 3.7 EP-G Shell integration and minimal surface (S04-24, S04-25)

#### S04-24 Strip shows the GPS recording; independent sources (R-037 to R-039)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-24-1 | S04-R-037 (a); S04-24 AC-1 | I | 1 | H | a fake second source in `activeSessionSourcesProvider` | `activeSessionStatusProvider` shows it | the provider cannot show a new source (the S03 claim was false) |
| DT-24-2 | S04-R-037 (b); AC-D4-R-7; S04-24 AC-2 | I | 2 | H | `/account-switch-hides`, `/foreign-skipped-not-cleared` | foreign source hidden; its owner slot not cleared | a foreign session is visible, or cleared by the switch |
| DT-24-3 | S04-R-037 (c); S04-24 AC-3 | I | 2 | H | `/end-gps-keeps-gym-owner`, `/end-gym-keeps-gps-owner` | the other source's owner is untouched | one source erases the other's owner |
| DT-24-4 | S04-R-038; AC-D4-H-2; S04-24 AC-4 | I | 3 | H | `/both-active-gps-wins`, `/end-gps-shows-gym`, `/end-gym-shows-gps` | as stated (priority 20 versus 10; one number change flips it, D-12) | a recording is hidden by a timer |
| DT-24-5 | S04-R-037; Design 7.2 | I | 3 | H | table of four combinations for `activeSessionForeignOwnerProvider`: foreign running with or without an own visible source | foreign-only: pill and rail slot hidden; foreign plus own: not hidden merely because of the foreign timer | pill hidden wrongly, or a foreign session shown |
| DT-24-6 | S04-R-039; S04-24 AC-5 | K | 2 | H | `/recovery-string-single-path`, `/no-gym-path-references-it` | the recovery word is reachable only from the recovery-succeeded path; no gym path references it | the gym timer claims a recovery (S03 R-S5) |
| DT-24-7 | Design 7.2 | U | 3 | H | iterate every value of `ActiveSessionState` and `ActiveSessionKind`: `/state-word`, `/rail-word`, `/icon` | non-empty word, icon and rail word (at most 8 Russian characters) for each, no exception | a new enum value falls through an exhaustive switch |
| DT-24-8 | AC-D4-H-1; S04-R-037 | W | 6 | H | `/tab-1` to `/tab-5` with a GPS recording, `/gym-plus-gps` | `shell.dock.strip` with the GPS word on every tab; `shell.dock.recordPill` on none; gym plus GPS shows GPS | the recording is invisible on a tab |
| DT-24-9 | AC-D4-H-3 | W | 2 | M | `/label-form`, `/stable-within-a-minute` | label is "state, sport, whole minutes" without seconds, hint `gpsStripOpenHint`; unchanged within a minute | seconds read aloud every tick |
| DT-24-10 | AC-D4-H-4; SH-3, SH-6 | W | 4 | H | `/strip-tap-navigates-no-modal`, `/mode-change`, `/tab-change`, `/rotation` | strip tap opens `/record/gps` by navigation; the other three leave the recording unchanged and write nothing | the recording is altered by shell actions |
| DT-24-11 | AC-D4-H-6 | W | 1 | M | 1100x800: every `gpsRail*` word in `ru` and `en` | no overflow; at most 8 Russian characters | a rail word is clipped |
| DT-24-12 | S04-24 AC-6; Design 7.3 | I | 8 | H | entry-point rows for "recording visible" with a foreign-account session present: `/dock-strip`, `/rail-slot-compact`, `/rail-strip-extended`, `/record-pill`, `/record-shortcut`, `/record-sheet-opener`, `/notification-tap`, `/home-recovery-card` | each hides or refuses for the foreign session and works for the own one | one entry point leaks or ignores the rule (the S03 gate failure of this class) |
| DT-24-13 | S04-24; Design 7.2 | I | 1 | M | table of phases: restoring, recoveryFailed, revoked, finished, idle | restoring gives `gpsStripUnfinished`, recoveryFailed gives `gpsStripNotRestored`, revoked, finished and idle give no strip | the wrong word or a stale strip |
| DT-24-14 | AC-D4-Y-3; SH-7 | W | 2 | M | `/transitions-announce-once`, `/ticking-announces-nothing` (advance 120 s) | start, pause, resume, end once each; nothing per second | screen-reader spam |
| DT-24-15 | Design 7.2 | I | 1 | M | `activeSessionDestinationProvider` | reads the winning source's destination | a strip tap opens the gym page for a GPS source |
| DT-24-16 | S04-R-039; S03 R-S5 | I | 2 | M | `/gps-survives-process-death` (fresh scope with an unfinished journal gives `restoring`), `/gym-timers-do-not` | GPS source persists through recovery; gym timers are memory-only | recovery claimed for gym timers |
| DT-24-17 | AC-D4-H-7; S04-R-038, S04-R-040 | W | 3 | H | Record sheet while a source is active (DN-17 option A): `/sheet-opens-with-gps-recording-and-row-reads-open-recording`, `/gym-timer-row-disabled-gpsRowGymRunning-with-open-workout`, `/no-second-recording-can-start` | the sheet opens with a GPS recording, an unfinished recording or a gym timer active; no second recording starts | the sheet is silently closed, or a second recording starts |
| DT-24-18 | AC-D4-H-8; S04-R-038, S04-R-040 | W | 2 | M | `/only-a-pending-revoked-decision-shows-the-normal-enabled-gps-start-row`, `/recording-or-unfinished-shows-the-enabled-gpsOpen-row-never-disabled` | as stated | the user cannot reach the pending decision or the recording from the sheet |
| DT-24-19 | Contract SH-8, SH-9; S04-R-037 | W | 2 | M | `/strip-has-one-slot-precedence-recording-then-unfinished-then-pending-revoked-then-gym`, `/home-shows-at-most-one-gps-card` | as stated; a lower item is reached from S4-5 after the first is resolved | two competing strips or cards |
| DT-24-R | S04-R-037 regression | W | 0 | H | run the existing S03 strip and dock tests UNCHANGED (found with Glob) | green, no edit apart from the new source | the strip contract change broke S03 |

#### S04-25 Minimal start, pause, stop, recover surface (R-040) and the Contract

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-25-1 | S04-R-040; S04-25 AC-1 | K | 1 | H | registry of surfaces S4-1 to S4-7 (test constant) versus the screen and route files under `recording/pages` and `recording/widgets` | every screen maps to a surface; an unmapped screen fails | a screen outside the contract |
| DT-25-2 | S04-R-040; S04-25 AC-3 | K | 1 | M | scan for a new top-level shell path list, a back rule or sheet-flag copy | recording code reads `kShellDestinations`; no duplicate | another copy of the tab path list |
| DT-25-3 | AC-D4-S-4; S04-R-008 | W | 3 | H | acquiring: `/time-and-no-data`, `/pause-disabled`, `/stop-with-zero-fixes` | `0:00` frozen and "No data"; Pause `isEnabled == false` with the hint `gpsPauseDisabledHint`; Stop (a fresh Start, not a recovery) saves nothing and shows `gpsNothingRecorded` | metrics shown as zero |
| DT-25-4 | AC-D4-S-5 | W | 1 | M | fake time 60 s in acquiring | hint becomes `gpsAcquiringLong`; the recording is not cancelled | a timeout ends the recording |
| DT-25-5 | AC-D4-S-6 (UI half) | W | 2 | M | `/headline-weak-and-distance-frozen`, `/repeat-within-30s-not-announced` | as stated | distance moves in a gap, or announcement spam |
| DT-25-6 | AC-D4-S-8 (UI half) | W | 2 | M | `/auto-paused-word`, `/auto-off-never` | headline "Auto-paused"; with the switch off never | wrong label |
| DT-25-7 | AC-D4-S-9 | W | 2 | M | `/chip-only`, `/recording-continues-with-network-throwing`. offline is not shown by default (Design 5.1, TP-S04-14 resolved); these rows use a fake connectivity signal | only the chip; headline unchanged; run continues | offline treated as an error |
| DT-25-8 | AC-D4-S-10 | W | 2 | M | `/chip-once`, `/chip-clears-after-10s` | as stated | a stale chip |
| DT-25-9 | AC-D4-S-3 (UI half) | W | 4 | H | worked overlaps of Contract 5.3 rendered: battery plus poor accuracy, paused manual plus offline plus battery, auto-pause plus poor accuracy, anything plus revoked | headline, banner and chips as the contract | the screen disagrees with the priority function |
| DT-25-10 | AC-D4-G-1 | W | 9 | H | count `RenderParagraph`s of the live layout in `/acquiring`, `/recording`, `/poorAccuracy`, `/pausedManual`, `/pausedAuto`, `/with-battery-banner`, `/with-offline-chip`, `/with-background-chip`, `/all-conditions` | each element class within its cap (headline 1, signal word 1, primary metric 1, second row 2, hint 1, banner 1, chip row 1) and at most 8 for the classes (at most 10 with the Details label and the gym-timer row), control labels excluded, a chip row counts as one, counted by key | the live screen becomes a dashboard |
| DT-25-11 | AC-D4-G-2 | W | 2 | H | `/geometry` (Pause/Resume and Stop at least 72 dp high, 120 dp wide, 16 dp apart, inside the bottom 40 percent), `/banner-does-not-move-controls` | as stated, positions compared as `Rect`s | a control moves when a banner appears |
| DT-25-12 | AC-D4-G-3 | W | 1 | H | route observer scoped to the `/record/gps` route over every live state | no `DialogRoute`, `ModalBottomSheetRoute` or snackbar pushed by the app while recording | a modal while recording |
| DT-25-13 | AC-D4-G-4 | W | 1 | M | scan the S4-2 widget tree | no repeating `AnimationController`, no scan-line or bracket widget, no indeterminate progress indicator | looping motion on the live screen |
| DT-25-14 | AC-D4-G-4 | K | 1 | M | scan the S4-2 files for repeating controllers and indeterminate indicators | zero matches | the tree test misses a lazily built widget |
| DT-25-15 | AC-D4-G-5 | W | 4 | H | text scale 2.0 at 360x640 and 640x360, `ru` and `en` | the controls are visible without scrolling | controls scroll away |
| DT-25-16 | AC-D4-T-1 | W | 3 | H | `/panel-inline`, `/keeps-counting` (advance 10 min), `/keep-recording-restores` | inline panel `gps.rec.stopPanel`; no timer closes it | a dialog or timed close |
| DT-25-17 | AC-D4-T-2 | I | 1 | H | Finish and save; fake time 2 s | service and notification gone within 2 s | service lingers |
| DT-25-18 | AC-D4-T-2 | W | 1 | M | S4-4 content | summary rows, "No data" for undefined values, `gpsSavedOnDevice`, Done | zeros instead of "No data" |
| DT-25-19 | AC-D4-T-3 | W | 3 | H | `/save-failed-text`, `/try-again-once-per-tap-disabled-while-busy`, `/not-now-keeps-journal` | as stated | a retry storm |
| DT-25-20 | AC-D4-T-4 | W | 3 | H | `/discard-shows-distance-and-time`, `/delete-removes-journal-and-service` (file listing empty), `/keep-returns` | second inline step; Delete ends service and notification | discard without confirmation |
| DT-25-21 | AC-D4-T-5 | W | 1 | H | route extra from the notification Stop action | Finish opens the stop panel with focus on its header, a plain tap opens the recording screen with focus on the headline; zero `announce` calls; nothing stops (same behaviour as DT-04-7 from the UI side) | a notification can end the recording |
| DT-25-22 | S04-R-018, S04-R-024, S04-R-030 | W | 3 | M | S4-4 reason lines `/battery`, `/storage`, `/revoked` | the reason text for each automatic stop | a silent automatic stop |
| DT-25-23 | AC-D4-Y-1 | W | 7 | M | `matchesSemantics` for `/pause`, `/resume`, `/stop`, `/sport-chips`, `/auto-pause-toggle`, `/panel-buttons`, `/strip` | role, non-empty label, hint, enabled and selected state, tap action | an unlabeled control |
| DT-25-24 | AC-D4-Y-2 | W | 5 | M | headlines of `/S4-1`, `/S4-2`, `/S4-4`, `/S4-5`, `/S4-6` | `isHeader` | headings not exposed |
| DT-25-25 | AC-D4-Y-3 | W | 6 | M | `/each-transition-one-announcement` (ids and kinds of Contract 16.4), `/suppress-machine-kind-within-30s`, `/focus-moving-transition-does-not-also-announce-the-same-text` (zero `announce` calls), `/offline-announced-once-per-recording`, `/suppressed-announcement-whose-state-still-differs-is-announced-once-when-the-window-ends`, `/assertive-or-documented-fallback` (DEPENDS-ON-DESIGN F12) | as stated | chatter, or a missing assertive message |
| DT-25-26 | AC-D4-Y-4 | W | 3 | M | text scale 2.0 in `/ru`, `/en`, `/longest-ru-button` ("Сохранить как завершённую" wraps) | no overflow; `didExceedMaxLines` false for headline, banner, chip and button texts | truncated status words |
| DT-25-27 | AC-D4-Y-5 | W | 8 | M | focus order for `/S4-1`, `/S4-2`, `/S4-3`, `/S4-5`, `/S4-6`, `/S4-7`, `/panel-open-close`, `/automatic-screen-swap-focuses-the-new-headline` | order per Contract 15; opening a panel focuses its header; closing returns focus to the opener | focus lost |
| DT-25-28 | AC-D4-Y-6 | W | 1 | L | `disableAnimations` | state swaps complete in one `pump` | animation under reduced motion |
| DT-25-29 | AC-D4-Y-7 | W | 9 | M | `TextDirection.rtl` for `/S4-1`, `/S4-2`, `/S4-3`, `/S4-4`, `/S4-5`, `/S4-6`, `/S4-7`, `/strip`, `/rail-slot` | no overflow | RTL layout break |
| DT-25-30 | AC-D4-Y-8 | K | 2 | M | `/colour-literals` (no `Color(0x`, no `Colors.` in new files), `/warning-danger-not-text` | zero matches | off-token colours or colour-only status |
| DT-25-31 | AC-D4-W-1 | W | 6 | M | S4-2 at `/320x640`, `/360x800`, `/640x360`, `/700x900`, `/1100x800`; `/numeral-width-max-640` | no overflow; pinned controls visible; numeral content at most 640 dp | clipped controls on small phones |
| DT-25-32 | AC-D4-W-2 | W | 1 | H | resize 1100x800 to 360x800 during `recording`; write spy | state, sport, focus and timers kept; zero writes | a resize alters the recording |
| DT-25-33 | AC-D4-W-3; S04-R-050 | W | 2 | M | `/faked-apple-platform`, `/no-gps-device` | no Start row (or a disabled row) | an iOS capability is implied |
| DT-25-34 | AC-D4-C-1 | K | 3 | M | `/ids-in-en-and-ru`, `/plural-select-branches` (all required branches, Russian one, few, many, other, including the summary node, strip label, units, recovery age and battery percent), `/withdrawn-ids-absent` (`gpsExportRaw` and `gpsExport` do not exist) | every `gps*` key exists in both languages with all branches | a missing translation or branch |
| DT-25-35 | AC-D4-C-3 | W | 6 | M | manual entry `/empty`, `/three-errors-inline-focus-on-first-field` ("Enter a duration longer than zero" and the other two), `/saving`, `/success-no-gps-stream-gpsManualSaved-one-announcement`, `/cancel-saves-nothing`, `/back-saves-nothing` | states per Contract 20; saved session has no GPS stream and a manual provenance | an invalid manual activity is saved |
| DT-25-36 | AC-D4-C-4; Contract 16 length budgets | K | 2 | L | entries `/ru`, `/en`; ARB lengths measured against the budgets (Russian figures): headline 22, banner 120, chip 40, button 24 (25 allowed to wrap where not centred), rail 8, panel header 40, strip 22 | within budgets | text too long for its slot |
| DT-25-37 | Contract 15 haptics | W | 2 | L | `/light-haptic-on-start-pause-resume-stop-battery`, `/no-op-without-haptics` | channel calls; never the only feedback | a crash without a haptic engine |
| DT-25-38 | Contract 19 | W | 2 | M | `/landscape-two-columns`, `/under-320-dp-second-row-behind-details` | no overflow; controls pinned | clipped landscape layout |
| DT-25-39 | Contract 8.1 | W | 3 | M | signal indicator `/good-10m`, `/weak-above-10m-to-30m-or-no-fix`, `/none-after-10s` | semantics "GPS signal: Good/Weak/None"; bars excluded from semantics | the indicator disagrees with the gate |
| DT-25-40 | Contract 15 | W | 1 | M | summary node | one readable node, re-read on focus, not a live region | the ticking clock is read aloud |
| DT-25-41 | SH-6; Contract 4.2 JP-8 | W | 2 | H | `/back-arrow`, `/system-back` | leaves the screen only; recording continues | Back stops a recording |
| DT-25-42 | AC-D4-H-2 (UI half); SH-2 | W | 2 | M | `/gym-row-visible-only-while-gym-source-active`, `/gym-row-opens-workout` | `gpsGymTimerRow` appears only while a gym source is active | the gym timer is lost |
| DT-25-43 | AC-D4-H-5; Contract 14.2 | W | 5 | H | `/row-present-flag-on-android`, `/row-absent-flag-off`, `/open-writes-nothing-asks-nothing`, `/blocked-reason-and-no-gps-reason`, `/order-last-in-train-and-body` (flag `GPS_RECORDER`, TP-S04-11 resolved) | per Contract 14.2 | the sheet requests a permission when opened |
| DT-25-44 | Contract 4.1 | K | 1 | L | `/record/gps` against the router table | no collision with an existing route | a duplicate route name |
| DT-25-45 | AC-D4-S-11; S04-R-016, S04-R-008 | W | 2 | H | recovery-origin `acquiring`: `/kept-time-and-distance-shown`, `/stop-panel-offers-finish-and-discard-never-nothing-recorded` | kept time and distance shown (not 0:00); Stop opens the stop panel with Finish and save and Discard; `gpsNothingRecorded` never appears; recovered data is dropped only by Discard | recovered data is silently dropped |
| DT-25-46 | AC-D4-S-14; S04-R-009 | W | 2 | M | `/hint-after-30s-in-poorAccuracy` (`gpsWeakLongHint` with the settings link), `/link-sends-no-permission-request` | as stated | the link re-requests permission |
| DT-25-47 | AC-D4-G-6 | W | 1 | M | 320x640 at text scale 2.0, S4-2 | primary time numerals on one line, not clipped, not ellipsised, size not above the scale-1.3 size (`didExceedMaxLines == false`, no overflow) | the clock is cut off at large text |
| DT-25-48 | AC-D4-G-7 | W | 3 | H | `/stop-panel-and-discard-confirm-visible-320x640-scale-2`, `/same-in-640x360`, `/system-back-sequence` | the focused button fully visible; Keep recording reachable; system Back closes the discard confirmation, then the stop panel, then leaves the screen, returning focus to the opener each time | a button is scrolled out of reach, or Back skips a step |
| DT-25-49 | AC-D4-T-7; X10 | W | 2 | M | `/user-actions-announced-every-time` (Pause, Resume, Stop, Finish, Discard twice within 30 s), `/machine-kinds-suppressed-within-30s` | user kinds always announced; machine kinds suppressed | a user's second tap is silent |
| DT-25-50 | AC-D4-Y-9 | W | 1 | L | keyboard focus on each new control | the ring uses the S03D token, thickness and offset (decoration compared) | an off-token ring |
| DT-25-51 | AC-D4-Y-11 | W | 1 | M | all panels and views | no two buttons share a visible label while naming different actions | ambiguous labels |
| DT-25-52 | AC-D4-Y-10 | D | 1 | M | DL-14: TalkBack walk of JP-1, JP-8, JP-9, JP-11 and JP-12 on the reference phone; live numerals against the 7:1 target (PROPOSED) | every task completes | NOT_RUN until a phone |
| DT-25-53 | AC-D4-Y-12; C6 | D | 1 | M | DL-14: TalkBack on; a focus move to a new headline (S4-6, S4-4, the stop panel from the notification) | read once and promptly, no duplicate reading | NOT_RUN until a phone |
| DT-25-54 | AC-D4-C-6; C8 | W | 1 | M | every undefined value in the summary and the live layout | `gpsNoData` visible and `gpsNoDataSpoken` in the summary node | zeros or blanks for missing data |
| DT-25-55 | AC-D4-C-6; C8 | K | 1 | L | copy ids and lengths | rail word `Choose`/`Выбор` and the RU strip word for revoked (22 characters) pass the length test; the notification action ids are `gpsNotifPause`, `gpsNotifResume`, `gpsNotifFinish`; `gpsNotifStop` does not exist | a stale action id or an over-long word |

### 3.8 EP-H Performance and privacy (S04-26 to S04-28)

#### S04-26 Off the UI isolate and 100k budget (R-041, R-042)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-26-1 | S04-R-041; S04-26 AC-1 | I | 1 | H | `InlineHeavyWorkRunner` spy over a full finish and a recovery read | payload build, gzip, SHA-256, seal and open, smoothing, full-session calculators and the recovery decode all ran through the runner | heavy work runs on the UI isolate |
| DT-26-2 | S04-R-041 | K | 1 | H | scan: these functions are referenced only through the runner | zero direct calls from `state/` or `pages/` | a direct call bypasses the runner |
| DT-26-3 | S04-R-041; Design 2.5 | I | 2 | H | `/bytes-identical` (golden bytes of a fixed session with fixed IV and key from the old and new `put` path), `/s02-tests-unchanged` (evidence, runs the existing journal tests) | identical bytes; green | the S02 isolate move changed stored bytes |
| DT-26-4 | S04-R-041 | I | 1 | M | per-fix work counter at 1 000 and 100 000 fixes in | constant per fix | a full pass per update on the UI isolate |
| DT-26-5 | S04-R-042 | I | 1 | M | measure-only: F-100k main-isolate synchronous slices (profile-like timing in the test environment); numbers recorded with head and corpus size, not a gate | recorded; a proxy for DL-8 | NOT a frame-budget proof (JIT test timing) |
| DT-26-6 | S04-R-042 | I | 1 | M | F-100k seal then open | equal content; no exception | corruption at scale |
| DT-26-7 | S04-R-042; S04-26 AC-2; T6 | D | 3 | H | DL-8 in profile mode: `/max-frame-16ms`, `/seal-plus-open-3s`, `/peak-memory-100mb` | PASS, FAIL or NOT_RUN with the number | NOT_RUN until a phone |

#### S04-27 No coordinates in logs or telemetry (R-044)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-27-1 | S04-R-044; S04-27 AC-1 | I | 10 | H | F-sentinel (12.3456789, -98.7654321, also the rounded, comma-decimal and geohash forms); flows `/record`, `/pause`, `/resume`, `/kill-recover`, `/finish`, `/storage-fail`, `/revoked`, `/put-fail`, `/worker-throws`, `/recovery-failed`; collect `LogCapture`, zone errors, `FlutterError` reports, `TelemetrySpy`, notification payloads and announcements | no captured text contains any sentinel form | a coordinate in a log, exception, notification or crash report |
| DT-27-2 | S04-R-044; S04-27 AC-2 | U | 3 | H | `/mapper-table` (every typed journal and permission exception maps to a bare code), `/unknown-type` (generic code), `/to-string-content-free` (`Fix`, meta and frame classes) | codes only; `toString` shows no coordinates | an exception message is logged |
| DT-27-3 | S04-R-044; Design 11.2 (6) | K | 1 | H | scan `recording/**` for `print`, `debugPrint` or logging with interpolated `$e`, `.message`, fix or path | zero matches | a leaking log line |
| DT-27-4 | S04-R-044; Design 10 | K | 1 | H | scan for crash-reporting calls with a raw exception | only bare codes | a raw exception goes to the crash reporter |
| DT-27-5 | AC-D4-N-2 | I | 1 | M | every notification, announcement and string with placeholders rendered with sentinel values | no coordinate | a coordinate in a user-facing string |
| DT-27-6 | S04-R-007, S04-R-044 | I | 1 | M | list the recording directory and read `meta.json` plaintext fields | names carry the recording uuid only; no place name, device id or heart rate | metadata leaks |
| DT-27-7 | S04-R-044; F16 | I | 1 | M | an uncaught error inside the worker | reaches the crash reporter as a bare code | a raw message through the isolate boundary |

#### S04-28 Upload off, constants, Android-only claim (R-046 to R-050)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-28-1 | S04-R-046; S04-28 AC-1 | U | 2 | H | `/cloud-streams-default-false`, `/recorder-flag-default-off` (`GPS_RECORDER`) | both false by default | upload or recorder on by default |
| DT-28-2 | S04-R-046 | K | 1 | H | import graph | `recording/**` has no import of the uploader, sync repository or tombstone code | an upload entry is reachable |
| DT-28-3 | S04-R-046; S04-28 AC-1 | I | 1 | H | full run with the flag false (also DT-01-4) | zero upload and network calls | upload attempted |
| DT-28-4 | S04-R-046; S04-28 AC-1 | K | 1 | H | scan `recording/**` | no heart-rate or BLE symbols; no heart-rate field in any frame | heart rate recorded |
| DT-28-5 | S04-R-047; S04-28 AC-2 | W | 1 | M | finish screen | `gpsSavedOnDevice` present | the privacy line is missing |
| DT-28-6 | S04-R-048, S04-R-049; S04-28 AC-3 | U | 2 | M | `/privacy-zone-200m-and-key`, `/expiry-24-months-from-activity-date-and-key` | constants and keys exist | a default changes unnoticed |
| DT-28-7 | S04-R-048, S04-R-049 | K | 2 | M | `/no-application` (nothing reads the constants except the settings row and tests), `/no-scheduler` (no deletion or expiry rule) | zero matches | an unapproved behaviour appears |
| DT-28-8 | S04-R-050; S04-28 AC-4 | K | 1 | M | scan release notes, test names and reports for an iOS pass claim | none; iOS rows read NOT_RUN | an unproved platform claim |
| DT-28-9 | AC-D4-Z-1; S04-R-048 | W | 1 | L | privacy-zone row in Settings | shows 200 m, not interactive, note says nothing is shared (page name UNGROUNDED, Contract 23) | a switch that changes nothing |

### 3.9 EP-I Device-lab evidence (S04-29) - CONDITIONAL on a named reference phone

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-29-1 | S04-R-032 to S04-R-034 | D | 1 | H | DL-1: walked known route (section 5) | tolerance results recorded | NOT_RUN |
| DT-29-2 | S04-R-032 to S04-R-034 | D | 1 | H | DL-2: ridden known route | recorded | NOT_RUN |
| DT-29-3 | S04-R-028, S04-R-029 | D | 1 | H | DL-3: 60 min walk battery run | percent per hour versus 8 | NOT_RUN |
| DT-29-4 | S04-R-028, S04-R-029 | D | 1 | H | DL-3b: 60 min ride battery run | same | NOT_RUN |
| DT-29-5 | S04-R-031 | D | 1 | M | DL-9: did a vendor task killer end a screen-off run, and which settings | yes or no per run plus settings | NOT_RUN |
| DT-29-6 | S04-R-005 | D | 1 | M | DL-7: airplane mode with location on | a saved track | NOT_RUN |
| DT-29-7 | S04-R-006 | D | 1 | M | DL-3 data: median interval between delivered fixes | 0.9 to 1.5 s (PROPOSED) | NOT_RUN |
| DT-29-8 | Study 7 item 9; T5 | D | 1 | M | DL-10: `dumpsys deviceidle force-idle` and `am set-inactive` during auto-pause | cadence recorded | NOT_RUN |
| DT-29-9 | Study 7 item 1 | D | 1 | L | second brand if available | recorded | NOT_RUN |
| DT-29-10 | S04-R-051; S04-29 AC-1 to AC-3 | K | 2 | H | `/template-complete` (device and OS, build id and head, kill survival, screen-off continuity, tolerance walked and ridden, battery vs target, OEM kill, each PASS, FAIL or NOT_RUN), `/no-pass-without-artifact` (a PASS needs a linked artifact; missing is NOT_RUN) | validator over `docs/phase2/s04/S04_DEVICE_LAB_RECORD.md` | a PASS without evidence |
| DT-29-11 | S04-R-031; S04-29 AC-4 | K | 1 | M | scan for `REQUEST_IGNORE_BATTERY_OPTIMIZATIONS` and the exemption intent | none (default) | an unapproved exemption request |

### 3.10 Cross-cutting rows (retro rules)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-00-1 | retro rule 1; Stories 6.2 | K | 2 | H | `/compile-smoke` (one test file importing every library under `lib/features/recording/**` and the changed shell files; its only assertion is that it loads), `/exhaustive-switch` (iterates every `ActiveSessionState` and `ActiveSessionKind` through the dock word, rail word and icon functions) | loads and runs | a new enum value breaks a switch (Design 7.2) or a lane left code that does not compile |
| DT-00-2 | convention 8 | K | 1 | M | scan-set resolver | minimum file count; anchor files present; no empty scanned directory | a scan passes vacuously |
| DT-00-3 | retro rule 2; Design 7.3 | K | 1 | H | call sites of `requestStart` | equal to the enumerated entry points of section 4.2; none from boot or launch | a new start entry point without a row |
| DT-00-4 | Z4, Z6; set comparison | K | 3 | M | `/ac-d4-ids` (every `AC-D4-<family>-<n>` id found in the Contract appears in full in this plan), `/s04-r-ids` (every `S04-R-nnn` id of the requirements appears), `/story-ac-ids` (every story AC id, including suffixed ones such as AC-1b, appears in the section 7.3 row of its story) | both sets equal or the missing ids are listed | a criterion or requirement has no trace |

### 3.11 EP-J Round 1 additions (S04-30 to S04-38; lane R13 new)

#### S04-30 Sign-out, account switch and account deletion with a recording (R-019, R-014; X1, X2)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-30-1 | S04-R-019 (b); S04-30 AC-1 | I | 3 | H | `FakeAuthStream` on a running recording: `/null`, `/loading`, `/null-then-same-uid` | nothing stops, nothing is written to another scope, subscription count stays 1; appends refused while the scope is unbound go to the bounded buffer (DT-30-11) and the recording stays recoverable | a flaky auth state stops or loses a recording |
| DT-30-2 | S04-R-019 (c); S04-30 AC-2 | I | 3 | H | `/different-nonnull-uid`, `/explicit-sign-out`, `/deletion-event`; two real scope directories; sequence spy | `releaseAll()`, stop, seal and hand-off commit into the OWNER's store occur BEFORE the scope unbinds (commit sequence number below unbind); nothing in any other uid's store; the journal is deleted after the confirmed hand-off | the session lands in the wrong store, or the hand-off follows the unbind |
| DT-30-3 | S04-R-019 (d); S04-30 AC-3 | I | 2 | H | `/hand-off-impossible-leftover-invisible-to-other-uid`, `/expires-at-30-days` (fake clock at 29 days 23 hours and at 30 days, PROPOSED) | the unsealed recording stays in its own scope, no other uid can list or open it; deleted at 30 days with no sample on disk | a stuck recording leaks to another user, or never expires |
| DT-30-4 | S04-R-019 (e), S04-R-014 (d); S04-30 AC-4; FP-8 | I | 6 | H | account deletion with fault injection: `/ordering-spy` (recorder shutdown, then recording journal close and refuse-after-wipe, then the S02 wipe), `/fault-after-shutdown`, `/fault-after-journal-close`, `/fault-after-s02-wipe`, `/late-append-refused`, `/late-hand-off-put-refused` | after every fault point no key is resurrected and no readable journal remains; `recording/` is empty at the end; a late append or `put` after the wipe is refused (the shared wiped-uid marker) | a late write recreates the key or location data after deletion |
| DT-30-5 | S04-R-014 (c); S04-30 AC-5; FP-13 | I | 5 | H | the scope is unbound or wiped between steps: `/append`, `/seal`, `/hand-off-put`, `/recovery`, `/delete` | each step writes nothing to the old or any other uid's store and keeps the recording | a step writes under the wrong or a wiped scope |
| DT-30-6 | S04-R-019 (f); S04-30 AC-6; AC-D4-R-9 (guard half) | I | 3 | H | `/counts-an-active-recording` (the warning sheet names it), `/unfinished-only-is-not-a-silent-pass` (finished-activity count 0 but an unfinished recording exists), `/cannot-check-keeps-sign-out-anyway-with-explicit-text` (TP-S04-19 resolved: the user can always leave; the text says the recording stays on this phone in this account's scope) | the guard counts and names the recording; the unchecked case is visible, not silent | a sign-out proceeds silently over a recording |
| DT-30-7 | S04-30 AC-7; Design 7.3 | I | 5 | H | entry points of "sign-out with a recording": `/settings-sign-out`, `/guard-sheet-sign-out-and-delete`, `/account-deletion-flow`, `/auth-stream-event`, `/notification-action-while-signed-out` | each follows the rules of DT-30-2 and DT-30-4; the notification action while signed out opens nothing and writes nothing | one entry bypasses the order |
| DT-30-8 | AC-D4-R-9; S04-30 | W | 2 | M | `/transient-null-leaves-strip-and-S4-2-unchanged`, `/explicit-sign-out-stops-and-seals-then-strip-leaves` | as stated | the strip flickers on a flaky auth state |
| DT-30-9 | S04-R-019 (b) | U | 1 | M | pure auth-event classifier table: null, loading, same uid, different non-null uid, signed out, deleting | stop only for the last three | a transient value is treated as an event |
| DT-30-10 | S04-R-019 (c), S04-R-014; Y2 | I | 4 | H | `/bind-controller-awaits-the-pre-unbind-hook` (sign-out, uid change and deletion: hand-off commit sequence number below the unbind), `/hook-times-out-at-5-s-the-unsealed-recording-stays-in-its-scope`, `/hook-fails-same-fallback`, `/sign-out-guard-path-uses-the-same-hook` | as stated (5 s is PROPOSED) | the scope unbinds before the hand-off, or a hung hook blocks sign-out |
| DT-30-11 | S04-R-019 (b); Y3 | I | 4 | H | `/appends-while-unbound-go-to-a-bounded-memory-buffer-and-flush-after-the-same-uid-rebinds`, `/buffer-bound-119-s-keeps-120-s-stops-with-reason-account` (stop event `stoppedAccount`, S4-4 reason `gpsReasonAccount`), `/different-uid-after-null-writes-nothing-to-the-new-uid`, `/buffer-is-memory-only` | as stated (120 s is PROPOSED) | a transient null loses samples, or the buffer lands in another scope |
| DT-30-12 | S04-R-014 (d); Y3 | I | 3 | H | `/durable-wiped-marker-survives-a-process-restart`, `/late-write-refused-after-the-restart`, `/marker-is-in-the-repository-layer-not-the-in-memory-wipedUid` | as stated | a late write after a wipe is accepted once the process restarted |
| DT-30-13 | S04-R-019 (d); Design 4.7 | I | 2 | M | `/ordinary-unfinished-recording-never-expires` (D-6 option A), `/expiry-sweep-runs-at-bind-time-and-only-for-failed-hand-off-and-quarantined` | as stated | an ordinary unfinished recording is deleted, or an expired leftover stays |

#### S04-31 Sanitising wrapper and global error handlers (R-052)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-31-1 | S04-R-052 (a); S04-31 AC-1 | I | 3 | H | a sentinel placed in an error raised at `/journal-decode`, `/worker-entry`, `/isolate-boundary` | the wrapper emits a content-free error type (a bare code plus allowed fields); the message, cause chain and `toString` carry no sentinel form | a raw error leaves the layer |
| DT-31-2 | S04-R-052 (b); S04-31 AC-2 | I | 5 | H | F-sentinel flows (record, kill-recover, finish, fail) with sinks `/zone-handler`, `/recordFlutterFatalError`, `/recordError`, `/debugPrint-telemetry-sink`, `/crashlytics-spy` | none of the five sees any sentinel form | a coordinate reaches a process-wide handler |
| DT-31-3 | S04-R-052; S04-31 AC-3 | K | 2 | H | `/no-raw-exception-reaches-a-global-handler` (call paths from recorder code), `/main-dart-splice-uses-the-wrapper` | zero raw paths | a raw exception object bypasses the wrapper |
| DT-31-4 | AC-D4-N-4, AC-D4-C-5; S04-R-052 | W | 2 | H | `/decode-worker-isolate-errors-show-only-gpsGenericError-or-the-panel-text` (no screen, announcement or notification contains the sentinel), `/no-raw-exception-path-or-message-on-any-screen` | only `gpsGenericError` or the specific panel text | a raw message is shown to the user |

#### S04-32 Lock-screen notification (R-053)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-32-1 | S04-R-053 (a); S04-32 AC-1; Y11 | U | 2 | H | notification builder `/owner-visible-version` (unlocked shade: sport, moving time and distance), `/lock-screen-public-version` (generic static text only) | the public version contains no sport, time, distance, coordinate or pace; neither version contains a coordinate digit pattern of the sentinel or a pace string; visibility private with the public version set explicitly | the lock screen leaks what or where |
| DT-32-2 | S04-R-053 (b); S04-32 AC-2 | U | 2 | H | `/public-has-zero-actions`, `/owner-visible-has-exactly-pause-resume-and-finish` | as stated (whether the plugin notification can carry actions is UNKNOWN, Design D-20: if not, this row reads that actions are not offered) | an action on the public version |
| DT-32-3 | S04-R-053 (c); AC-D4-T-5 | I | 2 | H | `/finish-leaves-the-recorder-in-its-prior-state-until-confirmed`, `/pause-resume-uses-the-same-controller-method` | recording still counting, no release, no write until the user confirms in the stop panel | one tap on a locked phone ends a recording |
| DT-32-4 | S04-R-053 (d); S04-32 AC-3; AC-D4-T-5 | W | 2 | M | `/plain-tap-opens-the-recording-screen-with-focus-on-the-headline`, `/finish-action-opens-the-stop-panel-with-focus-on-its-header` | focus as stated; zero `SemanticsService.announce` calls for either (read by focus) | focus lost or a double reading |
| DT-32-5 | S04-R-053 | K | 1 | M | notification configuration scan | visibility set explicitly; a public version exists | the OS default exposes the content |
| DT-32-6 | S04-R-053 (e); AC-D4-N-1; S04-32 AC-4 | D | 2 | H | DL-12: lock-screen photo or screen record with lock-screen notifications `/show-all` and `/hide-sensitive` | only the generic text shows; no sport, time, distance, coordinate or action on the public version | NOT_RUN until a phone |

#### S04-33 Consent withdrawal surface (R-054)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-33-1 | S04-R-054; AC-D4-Z-2; S04-33 AC-1 | W | 4 | H | Settings, Privacy row S4-11: `/row-shows-state-and-text-version`, `/withdraw-opens-an-inline-confirmation-no-dialog-route`, `/allow-again-records-a-new-version`, `/delete-link-opens-the-delete-flow-and-no-export-control-exists` | as stated; the strings are DRAFT | withdrawal is harder than granting |
| DT-33-2 | S04-R-054 (a); AC-D4-P-17; S04-33 AC-2 | W | 2 | H | `/start-blocked-by-consentWithdrawn-zero-requests-zero-service-starts`, `/allow-again-restores-start` | panel `consentWithdrawn` with Open privacy settings and Add manually | Start collects after withdrawal |
| DT-33-3 | S04-R-054 (b), S04-R-016 | I | 3 | H | an unfinished journal and consent withdrawn: `/resume-refused-or-disabled-with-a-reason`, `/save-as-finished-works`, `/discard-works` | as stated | a withdrawn user is resumed, or locked out of their own data |
| DT-33-4 | S04-R-054 (c); S04-33 AC-3 | I | 2 | H | `/withdraw-during-a-recording`, `/withdraw-while-paused` | subscription 0 within 2 s, the recording is sealed, handed off and kept (never deleted), the automatic-stop notification is posted (DT-35-1) and S4-4 shows `gpsReasonConsent` | a recording is lost or keeps collecting |
| DT-33-5 | S04-R-054 (d); S04-33 AC-4 | I | 2 | H | `/file-listing-identical-except-the-stopped-recording`, `/record-holds-new-state-and-timestamp-and-no-data-deleted` | as stated | withdrawal deletes data |
| DT-33-6 | S04-R-054; retro rule 6 | I | 1 | M | the switch flipped twice in a row, and withdrawn then granted | idempotent; one record per change | equal events double-write |
| DT-33-7 | AC-D4-Z-3, AC-D4-P-22; S04-R-054, S04-R-026 | W | 2 | M | `/never-consented-shows-gpsConsentNone-no-switch-and-the-links`, `/gpsConsentDeleteData-row-leads-to-the-deletion-path-behind-an-inline-confirmation` | as stated | a withdraw switch for a user who never consented |

#### S04-34 Start preconditions (R-055)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-34-1 | S04-R-055; AC-D4-P-15; S04-34 AC-1 | W | 3 | H | `/journal-opening-shows-preparing`, `/unfinished-check-pending-shows-preparing`, `/both-complete-start-works` | `preparing` (static `gpsPreparingBody`, Back only); no service, no request; subscription 0 | Start opens a second recording over an unrecovered one |
| DT-34-2 | S04-R-055; AC-D4-P-15, AC-D4-P-21; S04-34 AC-2 | W | 3 | H | `/journal-open-fails-shows-cannotStart-with-try-again-and-add-manually`, `/preparing-becomes-cannotStart-after-5-s-and-not-before` (4.9 s still `preparing`), `/try-again-retries-once-per-tap` (TP-S04-16 resolved: one 5 s timeout) | panel `cannotStart`; subscription 0 | a hang with no panel |
| DT-34-3 | S04-R-055; AC-D4-P-16; S04-34 AC-3 | W | 4 | H | `/button-reads-gpsStarting-and-is-disabled`, `/second-tap-starts-nothing`, `/startFailed-15-s-after-the-service-start-call-not-the-tap-and-no-service-left` (TP-S04-16 resolved), `/startFailed-focus-on-header-read-by-focus` | as stated | a double service start, or a silent hang |
| DT-34-4 | S04-R-055; Design 5.4 | I | 7 | H | refusal reason codes `/journal-not-open`, `/unfinished-check-running`, `/unfinished-recording-found-offers-recovery`, `/consent-withdrawn`, `/permission-missing`, `/own-gym-timer-running`, `/foreign-session` | the right reason code and panel; no `meta.json` written on refusal; phase back to `idle`; subscription 0 | a silent no-op or a wrong reason |
| DT-34-5 | S04-R-055; Design 5.4 | I | 3 | M | `/preparing-timeout-calls-releaseAll`, `/quarantined-recording-does-not-block-start`, `/pending-revoked-decision-does-not-block-start` | the service is released at the timeout; neither a quarantined recording nor a pending revoked decision blocks Start | Start blocked forever by a quarantined file |
| DT-34-6 | S04-R-055; retro rule 6 | I | 1 | M | the unfinished check completes AFTER the timeout (held completer) | the late completion is ignored; no late start | a start fires after the user saw an error |

#### S04-35 Automatic-stop notification (R-056)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-35-1 | S04-R-056; AC-D4-T-6; S04-35 AC-1 | I | 5 | H | `/battery-3-percent`, `/storage-failure-60s`, `/sample-cap`, `/consent-withdrawal-stop`, `/permission-loss-posts-gpsRevokedNotif-instead` (TP-S04-17 resolved, Y10) | for the first four: one non-ongoing `gpsAutoStopNotif` with the matching reason (`gpsReasonBattery`, `gpsReasonStorage`, `gpsReasonSampleCap`, `gpsReasonConsent`), saved time and distance, no coordinate, pace or sport; the persistent notification is gone; the stored session and S4-4 carry the same reason; no strip row remains. For the revoked stop: `gpsRevokedNotif`, not `gpsAutoStopNotif` | a stop with the screen off is invisible |
| DT-35-2 | S04-R-056 (content) | U | 2 | H | builder `/content-free-fixed-string-table`, `/private-version-with-generic-public-version` | no coordinate, pace or sport; own channel | the stop notification leaks |
| DT-35-3 | S04-R-056; AC-D4-T-6; S04-35 AC-2, AC-3 | W | 2 | M | `/screen-treated-as-off-it-is-the-only-signal` (app in background), `/tap-moves-focus-per-Y11-with-zero-announce-calls` | as stated | the user believes the recording is still running |
| DT-35-4 | S04-R-056; Design 5.5 | I | 2 | M | `/different-id-and-channel-from-the-persistent-notification`, `/recovery-cannot-start-notification-is-content-free` | as stated | the stop replaces or merges with the ongoing notification |
| DT-35-5 | S04-R-056 device; S04-35 AC-2 | D | 1 | H | DL-13: a screen-off run auto-finished at the battery threshold; look at the lock screen | the notification shows | NOT_RUN until a phone |

#### S04-36 Manual-pause interval and prompt (R-057)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-36-1 | S04-R-057; S04-36 AC-1 | I | 3 | H | `/interval-10s-during-manual-pause` (fake `LocationSource` records `setInterval`), `/interval-1s-after-resume`, `/no-sample-reaches-the-track-and-distance-and-moving-time-unchanged` | subscription count stays 1 at 10 s; 1 s restored; nothing journaled as track | a forgotten pause collects at full rate |
| DT-36-2 | S04-R-057; AC-D4-S-13; S04-36 AC-2 | I | 3 | H | `/prompt-at-30-minutes-exactly-once` (29:59 none, 30:00 one), `/state-is-still-pausedManual`, `/never-for-auto-pause` | one non-modal prompt; nothing stops or discards | the prompt ends the recording, or repeats |
| DT-36-3 | S04-R-057; AC-D4-S-13; S04-36 AC-3 | W | 3 | M | `/hint-says-location-stays-on`, `/gpsPausedLongBanner-with-one-polite-announcement`, `/prompt-offers-resume-or-finish-non-modal` | as stated | the user thinks location is off |
| DT-36-4 | S04-36 AC-4; S04-03 AC-4 | U | 1 | M | the transition-table test with the interval change event | subscription count 1 is consistent in both stories | the two stories contradict |
| DT-36-5 | S04-R-057, S04-R-030 | I | 1 | L | battery critical while manual-paused. DEPENDS-ON-DESIGN: which interval wins | per design | undefined interaction |

#### S04-37 Engine-detach behaviour (R-058) - CONDITIONAL on device test T2

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-37-1 | S04-R-058; AC-D4-N-3; S04-37 AC-1 | I | 3 | H | fake `engineDetached`: `/notification-changes-to-gpsNotifDetached`, `/never-says-Recording-while-no-fix-is-consumed`, `/nothing-journaled-while-detached` | as stated | a false "Recording" |
| DT-37-2 | S04-R-058; S04-37 AC-2; Design 5.6 | I | 2 | H | `/service-released-after-the-grace-period` (60 s, PROPOSED), `/restart-offers-recovery-with-a-marked-gap` | as stated | the service lingers or the gap is invisible |
| DT-37-3 | S04-R-058; S04-37 AC-3 | D | 1 | H | DL-16 (T2): start recording, swipe away, wait 60 s; record whether samples are still journaled and what the notification shows | PASS only if the notification claim equals the true recorder state | NOT_RUN until a phone |

#### S04-38 Release gate (privacy policy, data-safety form, foreground-service declaration, disclosure text)

| Id | Covers | Lvl | N | Sev | Fixture and steps | Expected | Fails when |
|---|---|---|---|---|---|---|---|
| DT-38-1 | S04-38 AC-1 | K | 4 | M | the release checklist document: `/privacy-policy`, `/data-safety-form`, `/foreground-service-declaration`, `/in-app-disclosure-text` | one row each with an owner and a status in DRAFT, READY or NOT_RUN | a release item has no owner or status |
| DT-38-2 | S04-38 AC-2 | K | 1 | M | the minors statement | says recordings are private only, no sharing, no upload | a wrong privacy claim |
| DT-38-3 | S04-R-052 entry condition | K | 1 | H | the checklist records the status of the server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 (UNKNOWN today) | a status field exists; the recorder is not enabled in a release build while it is not READY (the default of `GPS_RECORDER` is DT-28-1) | recorder code ships before the server rule |
| DT-38-4 | S04-38 AC-3 | K | 1 | M | the data-safety answers in the checklist versus the manifest and S04-28 | they match: no upload, no sharing, no heart rate | a false data-safety answer |
| DT-38-5 | S04-38 AC-4 | K | 1 | M | the checklist with any row not READY | the sprint can be accepted for code but the release is recorded as blocked, never as ready | a release marked ready with an open row |
| DT-38-6 | S04-38 AC-5 | K | 1 | M | the accepted risks (rooted or debuggable build, a second app with location permission, notification-listener apps, file sizes and mtimes, no AAD binding of frames) | each is written down in the design or the checklist | an accepted risk is undocumented |

## 4. Retro rules applied

### 4.1 Rule 1: compile smoke

Lanes (implementation agents) cannot build. After wave 1 (R1, R3, R4 interface commits) and after every later batch of agent edits, one test agent runs ONLY DT-00-1 and DT-00-2 before the commit (focused command, not an analyzer gate). The first real test run therefore starts after wave 1, not after the last lane. Known compile risk: new `ActiveSessionState` and `ActiveSessionKind` values break the exhaustive switches in `dock_widgets.dart` until lane R6 finishes (DT-00-1/exhaustive-switch, DT-24-7). The lead reads the diff of every risky edit.

### 4.2 Rule 2: every entry point of a capability has a row

| Capability | Entry point | Row |
|---|---|---|
| Start allowed (all go through `requestStart`) | Record sheet row `recordSheet.row.gpsStart` | DT-25-43, DT-24-12/record-sheet-opener |
| | rail Record slot | DT-24-12/rail-slot-compact |
| | Record pill | DT-24-12/record-pill, DT-24-8 |
| | keyboard shortcut | DT-24-12/record-shortcut |
| | Start button on S4-1 | DT-17-1 to DT-17-19 |
| | Resume from the recovery offer | DT-12-2/resume, DT-12-6 |
| | notification tap (opens the screen only) | DT-04-3, DT-24-12/notification-tap |
| | call sites of `requestStart` (static) | DT-00-3 |
| Recording visible | dock strip | DT-24-8, DT-24-12/dock-strip |
| | compact rail slot | DT-24-12/rail-slot-compact, DT-24-11 |
| | extended rail strip | DT-24-12/rail-strip-extended |
| | Home recovery card | DT-12-8, DT-24-12/home-recovery-card |
| | S4-1 block | DT-12-9 |
| Foreign account hidden | strip, Home card, start block, listing | DT-15-4, DT-15-5, DT-24-2, DT-24-12 |
| Stop and release (all call `releaseAll()`) | Stop button | DT-04-4/stop |
| | Discard | DT-04-4/discard, DT-25-20 |
| | permission loss | DT-04-4/permission-loss, DT-19-1 |
| | battery finish | DT-04-4/battery-finish, DT-22-1 |
| | sign-out | DT-04-4/sign-out, DT-30-2 |
| | account switch and deletion | DT-14-10, DT-30-2, DT-30-4 |
| | storage stop and 190 000 samples | DT-16-1, DT-14-9 |
| | notification Finish... action (opens the panel only) | DT-04-7, DT-25-21, DT-32-3 |
| Sign-out with a recording | settings sign-out, guard sheet, account-deletion flow, auth-stream event, notification action while signed out | DT-30-7 (five entries), DT-30-6 |
| Consent withdrawal | Settings row S4-11, Start blocked, Resume refused, withdraw during a recording | DT-33-1 to DT-33-6 |
| Recovery offer | app-start gate, strip in `restoring`, Home card, S4-1 block, Record sheet when an unfinished recording exists | DT-12-1, DT-12-8, DT-12-9, DT-25-43 |

Procedure for the test agents (a listing, not a test run): list all test names with the Grep tool, confirm each row above exists under the id shown; the listing is recorded in the findings file.

### 4.3 Rule 2: ordered-write fault injection points

Each point is a sequence in which an earlier durable write must precede a later action. The fault is injected after each step and the state after a restart is asserted.

| FP | Sequence | Faults | Rows |
|---|---|---|---|
| FP-1 | begin: `meta.json` temp write, fsync, rename, then the first sample | crash after each step; throw on write | DT-11-4 |
| FP-2 | frame append: write then fsync, ack only after fsync | crash after N bytes, before fsync, after fsync | DT-11-5, DT-11-6, DT-11-7, DT-11-13 |
| FP-3 | pause and resume events: event frame flushed before the state change is visible | crash after the event, before it | DT-11-5/event-forces-flush |
| FP-4 | stop: last flush, stop event, `SEALED` temp, fsync, rename | crash after each | DT-14-1, DT-14-2 |
| FP-5 | hand-off: worker, `put` commit, verify read, delete directory, revision bump | crash after each of the seven steps; `put` failure; verify failure | DT-14-2 to DT-14-5, DT-19-5 |
| FP-6 | resume after a kill: new segment, `restart` event, gap pair, subscription | crash after each | DT-12-2/resume |
| FP-7 | consent: stored consent written before the system request; older write cannot follow a newer | throw; reorder with completers | DT-21-3, DT-21-4 |
| FP-8 | wipe versus a late flush; deletion order recorder, recording journal, S02 wipe | wipe while a write is in flight; fault between the three steps | DT-15-1, DT-15-7, DT-30-4 |
| FP-9 | discard: `DISCARDING` marker, then segments, `SEALED`/`QUARANTINED`, `meta.json` last, directory | crash after each of the five steps | DT-12-2/discard, DT-12-13 |
| FP-10 | sign-out while recording: stop, seal, hand-off into the owner's store, then unbind | crash between steps | DT-30-2, DT-30-6 |
| FP-11 | account switch mid hand-off: scope captured at Start | switch during `stopping` | DT-14-10 |
| FP-12 | the state-field rule (retro action 7): for each new persisted field (recorder meta, consent record, `SEALED` marker) every function that reads or resets it has a row | per field | DT-11-4, DT-21-1, DT-14-2 |
| FP-13 | every recording step (append, seal, hand-off `put`, recovery, delete) re-checks the owner scope captured at `begin()` | scope unbound or wiped between steps | DT-30-5 |
| FP-14 | stop event then `SEALED` with a fixed `importedAt`; hand-off repeat after a crash | crash between the two | DT-14-12 |
| FP-15 | the bind controller awaits the recorder pre-unbind hook (5 s) before it unbinds | hook fails or times out | DT-30-10 |
| FP-16 | the durable wiped marker versus a late write after a restart | restart between wipe and write | DT-30-12 |
| FP-17 | `segmentBreak` as the first frame of every segment after an unclean close | crash, write error, resume | DT-11-18 |
| FP-18 | revocation: collection stops, partial recording SEALED as a pending decision, Keep hands off, Delete removes | fault or kill after each step | DT-19-12, DT-19-13 |
| FP-19 | lifecycle: hand-off then delete, failed hand-off leftover, sign-out, deletion, expiry, sign-in | state after each step | DT-15-9 |
| FP-20 | pending decision: durable `DECISION` marker written atomically before Keep or Delete acts; first marker wins; recovery reads it | crash or concurrent request before `put`, right after `put`, before journal cleanup | DT-19-14, DT-19-17 to DT-19-24 |

### 4.4 Rule 6: events of every source stream (all kinds, including repeated and equal values)

| Stream | Event kinds covered | Rows |
|---|---|---|
| Fixes | normal; identical repeat; same time different position; backwards; forward jump; NaN or out of range; error event; stream closed unexpectedly | DT-05-4, DT-05-8, DT-05-9, DT-19-2 |
| Permission | granted; denied once; denied forever; approximate; restricted; services off; repeated identical; granted to denied; denied to granted; precise to approximate | DT-17-4 to DT-17-18, DT-19-4 |
| Battery | falling through 10, 3; jump over thresholds; repeated equal; charging flips; oscillation; unavailable | DT-22-1, DT-22-2, DT-22-6 |
| Auth | null; loading; repeated same uid; confirmed different uid; signed out; account deletion in progress | DT-30-1, DT-30-2, DT-30-9, DT-30-10, DT-30-11, DT-24-2, DT-14-10 |
| Consent | granted; withdrawn; repeated withdrawn; withdrawn then granted | DT-33-6, DT-21-4 |
| Network | flapping; absent | DT-25-7, DT-01-4 |

### 4.5 Concurrency, retry and kill-recovery summary

Concurrency: DT-11-3 (writer versus writer), DT-11-11 (two writers), DT-14-4 (double Finish), DT-17-17 (double Start), DT-17-4 (double Try again), DT-19-5 (revocation during stop), DT-21-4 (ordered consent writes), DT-30-5 (scope change between steps), DT-34-6 (late completion of the unfinished check). Retry: DT-11-13 (append retry), DT-16-1 (retry each flush for 60 s), DT-14-3 (retry once per tap). Kill-recovery: DT-11-6 (50 points), DT-11-7, DT-11-8, DT-12-1 to DT-12-14, DT-13-1, DT-14-2, DT-11-17.

## 5. Device-lab and battery protocol

Nothing here has been run. No reference phone is named (Req A-2: UNKNOWN), so every item below is NOT_RUN. Repo comments mention a Samsung S23 Ultra and an S8; neither is confirmed as the reference. When a model is named, every PROPOSED number is re-set from one measured baseline run and the marks are removed one by one.

### 5.1 Device-lab items

| DL | What is measured | How | Duration | Pass criterion (PROPOSED) | Rows | Status |
|---|---|---|---|---|---|---|
| DL-1 | distance, pace, ascent tolerance on a walked known route | walk a route of known length (2 to 5 km, surveyed by map or measuring wheel; method written in the record), phone in a pocket and then in hand | about 45 min | distance within 2 percent; ascent per DT-10 tolerance; undefined shown where data is missing | DT-29-1 | NOT_RUN |
| DL-2 | same on a ridden known route | ride a known route, phone mounted | about 45 min | same | DT-29-2 | NOT_RUN |
| DL-3 | screen-off continuity, notification, location indicator, fix interval, battery drain (walk) | start from the visible app, switch the screen off, carry for 60 min, then Stop and read the indicator | 60 min plus setup | no gap over 10 s without a recorded cause; notification present; median fix interval 0.9 to 1.5 s; drain at most 8 percent per hour | DT-04-8 to DT-04-10, DT-29-3, DT-29-7 | NOT_RUN |
| DL-3b | battery drain (ride) | same on a ride | 60 min plus setup | same | DT-29-4 | NOT_RUN |
| DL-4 | kill survival | during recording: `adb shell am kill`, swipe from recents, `adb shell cmd activity stop-app <package>`, phone restart (the package name is read from the build; placeholder here) | 4 x about 10 min | everything flushed before the kill is offered; loss at most about 5 s | DT-11-16 | NOT_RUN |
| DL-5 | permission revocation mid-recording; precise to approximate | revoke location in system settings while recording; observe latency and whether the process restarts | about 15 min | latency recorded; no re-request | DT-19-8 | NOT_RUN |
| DL-6 | notification permission denied | deny on Android 13 or later; does the service keep running | about 15 min | outcome recorded in the Study | DT-20-6 | NOT_RUN |
| DL-7 | airplane mode | location on, network off, record 10 min, save | about 15 min | a saved track | DT-29-6 | NOT_RUN |
| DL-8 | 100 000-sample budget in profile mode | open, seal, finish, summarise the F-100k fixture on the phone | about 30 min | max frame build 16 ms; seal plus open 3 s; extra memory under 100 MB | DT-26-7 | NOT_RUN |
| DL-9 | OEM task killer | read the result of DL-3 and DL-4 on the phone's own battery manager; record yes or no and the settings used | within DL-3 | recorded per run | DT-29-5 | NOT_RUN |
| DL-10 | Doze during a stationary auto-pause | `adb shell dumpsys deviceidle force-idle`, `am set-inactive` while pausedAuto | about 20 min | cadence of fixes recorded | DT-29-8 | NOT_RUN |
| DL-11 | merged manifest of a built APK | build artifact inspected (needs a build; no agent of this plan builds) | about 10 min | equals the approved list | DT-04-11 | NOT_RUN |
| DL-12 | lock-screen content of the recording notification | lock-screen photo or screen record with lock-screen notifications set to show all and to hide sensitive | about 15 min | generic text only on the public version | DT-32-6 | NOT_RUN |
| DL-13 | automatic-stop notification with the screen off | a screen-off run auto-finished at the battery threshold; look at the lock screen | within a battery run | the notification shows reason, time and distance | DT-35-5 | NOT_RUN |
| DL-14 | TalkBack walk and numeral contrast | JP-1, JP-8, JP-9, JP-11, JP-12 with TalkBack; live numerals against 7:1 (PROPOSED) | about 30 min | every task completes | DT-25-52, DT-25-53 | NOT_RUN |
| DL-15 | approximate to precise downgrade | approximate only, then Precise in settings, return to S4-1 | about 10 min | continues without a new request; outcome recorded | DT-17-21 | NOT_RUN |
| DL-16 | engine detach (T2) | start recording, swipe the app away, wait 60 s; are samples still journaled and what does the notification say | about 10 min | the notification claim equals the true recorder state | DT-37-3 | NOT_RUN (conditional) |

### 5.2 Battery protocol (the content of `S04_BATTERY_PROTOCOL.md`, written by lane R11 from Req S04-R-028)

Each run record has ALL of these fields; a run missing a field is not accepted as evidence (DT-23-2):

1. Reference phone model and Android version (and build), app build id and git head.
2. Run type (walk or ride) and the routes; duration 60 min each (PROPOSED).
3. Screen off for the whole run, phone in a pocket or mounted; auto-brightness irrelevant with the screen off; no other app in the foreground; same system location mode.
4. Charger-free: no USB or charger during the run (a USB cable charges the phone and invalidates the number); start and end battery read from the system, not estimated. Because whole-percent resolution is coarse for a one-hour run, the record also stores the charge counter in microampere-hours before and after (PROPOSED, read through the platform battery property) and, when possible, the system battery statistics.
5. A control run with the app installed but not recording, same duration and conditions, to separate recording drain from background drain (PROPOSED).
6. Start level at least 80 percent and the unplugged time before the run.
7. Temperature if known; network state (airplane, Wi-Fi, cellular); weather note.
8. Recorder settings used (request interval, flush interval, auto-pause) and the sample, reject and gap counters of the run (counts only).
9. Result as percent per hour, the 8 percent target and the status PASS, FAIL or NOT_RUN. At least two runs per type (PROPOSED) with both values reported; a FAIL is recorded, not hidden, and the product owner decides accept, tune or defer (Req S04-R-029).
10. OEM background-kill entry: yes or no and the battery-manager settings used (Req S04-R-031).

### 5.3 Required field names (checked by DT-23-1 and DT-23-2)

`device_model`, `android_version`, `build_head`, `run_type`, `duration_min`, `screen_off`, `carry`, `no_charger`, `battery_start_percent`, `battery_end_percent`, `charge_counter_start`, `charge_counter_end`, `control_run`, `temperature`, `network_state`, `recorder_settings`, `counters`, `percent_per_hour`, `target`, `status`, `oem_kill_entry`.

## 6. Rows that cannot run without a device (or a build)

All are NOT_RUN until a reference phone is named (Req A-2); none may be reported PASS without an artifact:

DT-04-8, DT-04-9, DT-04-10 (notification, 60 min screen off, location indicator), DT-04-11 (merged manifest: needs a build), DT-11-16 (kill survival x3), DT-19-8 (revocation x2), DT-20-6 (notification denial), DT-26-7 (100k profile mode x3), DT-17-21 (approximate to precise), DT-25-52 and DT-25-53 (TalkBack walk and focus reading), DT-32-6 (lock screen x2), DT-35-5 (automatic-stop notification with the screen off), DT-37-3 (engine detach, conditional), DT-29-1 to DT-29-9 (tolerance, battery, OEM killer, airplane mode, Doze, second brand). Partly device-limited although runnable now, with the limit stated: DT-26-5 (JIT test timing is not a frame budget), DT-04-2 (plugin-declared service not visible in the source manifest), DT-01-1/boot-start and DT-12-8 (a simulated start, not a real boot), DT-11-6 (FI file system, not real fsync behaviour; real flash behaviour is NOT_RUN), DT-25-25/assertive (assertive announcement support in the pinned Flutter is UNGROUNDED, F12), DT-25-39 and DT-25-26 (Ahem test font: Russian widths are test widths, real device widths are NOT_RUN), all TalkBack reading order (NOT_RUN; goes to the independent accessibility review), outdoor-glare contrast (UNGROUNDED), and every iOS, iPad and MacBook family row of the Contract (design only, NOT_RUN).

## 7. Coverage matrices

### 7.1 Requirement to rows (every S04-R id)

| Req | Rows | Not run or limit |
|---|---|---|
| 001 | DT-04-2, DT-04-3, DT-04-6, DT-04-8, DT-04-9 | (a) screen-off 60 min and (b) notification on a phone: NOT_RUN |
| 002 | DT-04-4, DT-04-5, DT-04-10, DT-25-17 | location indicator: NOT_RUN |
| 003 | DT-01-1, DT-01-2, DT-01-5, DT-01-6 | |
| 004 | DT-03-1 to DT-03-13 | |
| 005 | DT-01-3, DT-01-4, DT-25-7, DT-29-6 | airplane mode on a phone: NOT_RUN |
| 006 | DT-05-1, DT-05-2, DT-22-7, DT-29-7 | median interval on a phone: NOT_RUN |
| 007 | DT-05-3, DT-05-8, DT-05-9, DT-05-10, DT-11-14, DT-11-15, DT-27-6 | |
| 008 | DT-05-4, DT-05-5, DT-05-11, DT-17-6, DT-17-7 | |
| 009 | DT-05-6, DT-05-7, DT-25-5 | |
| 010 | DT-06-1, DT-06-2, DT-06-8 | |
| 011 | DT-06-3 to DT-06-7 | |
| 012 | DT-07-1 to DT-07-8, DT-25-6 | |
| 013 | DT-03-6, DT-03-7, DT-12-4, DT-36-1 | |
| 014 | DT-11-1 to DT-11-4, DT-11-11, DT-11-12, DT-30-4, DT-30-5, DT-30-10, DT-30-12 | wording conflict resolved by the rewrite (sibling recording journal) |
| 015 | DT-11-5 to DT-11-9, DT-11-13, DT-11-16, DT-11-17, DT-11-18 | real kill and real fsync: NOT_RUN |
| 016 | DT-12-1 to DT-12-14, DT-33-3 | |
| 017 | DT-13-1 to DT-13-5, DT-13-7, DT-13-8, DT-11-17 | |
| 018 | DT-14-1 to DT-14-8 | |
| 019 | DT-15-1 to DT-15-3, DT-15-7, DT-15-9, DT-15-10, DT-30-1 to DT-30-13, DT-13-7 | real Auto Backup behaviour: NOT_RUN |
| 020 | DT-16-1 to DT-16-6, DT-35-1 | free-space early warning only if D-9 option B |
| 021 | DT-17-1, DT-17-2, DT-17-3, DT-01-6 | |
| 022 | DT-04-1, DT-04-11, DT-18-1, DT-18-2 | merged manifest: NOT_RUN; branch B only if chosen |
| 023 | DT-17-4 to DT-17-18, DT-12-6 | |
| 024 | DT-19-1 to DT-19-24, DT-24-18 | latency on a phone: NOT_RUN |
| 025 | DT-17-3, DT-20-1 to DT-20-6 | device outcome: NOT_RUN; conditional |
| 026 | DT-21-1 to DT-21-5, DT-21-7, DT-21-8, DT-21-10, DT-33-1, DT-33-5, DT-33-7 | |
| 027 | DT-21-6, DT-21-9 | |
| 028 | DT-23-1, DT-23-2 | the runs themselves: NOT_RUN |
| 029 | DT-29-3, DT-29-4 | NOT_RUN: no phone |
| 030 | DT-22-1 to DT-22-8, DT-17-12, DT-35-1 | |
| 031 | DT-29-5, DT-29-11 | NOT_RUN: no phone (the no-exemption scan runs now) |
| 032 | DT-08-1 to DT-08-4, DT-29-1, DT-29-2 | surveyed real route: NOT_RUN |
| 033 | DT-09-1 to DT-09-5 | |
| 034 | DT-10-1 to DT-10-5 | |
| 035 | DT-02-1 to DT-02-6 | |
| 036 | DT-08-5 to DT-08-9, DT-14-6, DT-14-9 | |
| 037 | DT-24-1 to DT-24-5, DT-24-8, DT-24-12 | |
| 038 | DT-24-4 | |
| 039 | DT-24-6, DT-12-7, DT-13-3, DT-13-4 | |
| 040 | DT-25-1, DT-25-2, DT-17-10, DT-25-43, DT-24-17 | |
| 041 | DT-26-1 to DT-26-4, DT-14-7 | |
| 042 | DT-26-5, DT-26-6, DT-26-7 | frame budget: NOT_RUN (profile mode on a phone) |
| 043 | DT-11-10, DT-16-3 | |
| 044 | DT-27-1 to DT-27-7, DT-04-6, DT-31-2 | |
| 045 | DT-15-4, DT-15-5, DT-15-8, DT-14-10 | |
| 046 | DT-28-1 to DT-28-4, DT-01-4 | |
| 047 | DT-28-5, DT-25-18 | |
| 048 | DT-28-6, DT-28-7, DT-28-9 | |
| 049 | DT-28-6, DT-28-7 | |
| 050 | DT-04-1, DT-28-8, DT-25-33 | iOS rows NOT_RUN by definition |
| 051 | DT-29-10 | the record itself: NOT_RUN until a phone |
| 052 | DT-31-1 to DT-31-4, DT-27-4, DT-38-3 | entry condition (server enforcement of GPS-PRIV-050 and 098) is UNKNOWN: recorded, not tested |
| 053 | DT-32-1 to DT-32-6, DT-04-7 | lock screen on a phone: NOT_RUN; plugin action support UNKNOWN (D-20) |
| 054 | DT-33-1 to DT-33-7, DT-21-2, DT-21-3, DT-21-10 | |
| 055 | DT-34-1 to DT-34-6, DT-17-11, DT-17-17, DT-17-22 | |
| 056 | DT-35-1 to DT-35-4, DT-16-2, DT-22-4 | lock screen with the screen off: NOT_RUN (DT-35-5); the revoked stop keeps its own notification (Y10) |
| 057 | DT-36-1 to DT-36-5, DT-25-46 | |
| 058 | DT-37-1 to DT-37-3 | conditional; the device test T2 is NOT_RUN |

All 58 requirements have at least one row; the parts that need a phone are explicitly NOT_RUN above and in section 6.

### 7.2 AC-D4 to rows (all 71)

| AC | Rows | AC | Rows |
|---|---|---|---|
| P-1 | DT-17-1 | Y-1 | DT-25-23 |
| P-2 | DT-17-2 | Y-2 | DT-25-24 |
| P-3 | DT-17-3 | Y-3 | DT-25-25, DT-24-14, DT-13-6, DT-19-9, DT-22-5 |
| P-4 | DT-17-4 | Y-4 | DT-25-26 |
| P-5 | DT-17-5 | Y-5 | DT-25-27 |
| P-6 | DT-17-6, DT-17-7 | Y-6 | DT-25-28 |
| P-7 | DT-17-8 | Y-7 | DT-25-29 |
| P-8 | DT-20-3, DT-20-4 | Y-8 | DT-25-30 |
| P-9 | DT-18-1, DT-18-2 | W-1 | DT-25-31 |
| P-10 | DT-17-9 | W-2 | DT-25-32 |
| P-11 | DT-17-10 | W-3 | DT-25-33 |
| P-12 | DT-12-9 | C-1 | DT-25-34 |
| P-13 | DT-17-12 | C-2 | DT-21-6 |
| P-14 | DT-17-13 | C-3 | DT-25-35 |
| S-1 | DT-03-3, DT-03-4 | H-1 | DT-24-8 |
| S-2 | DT-03-1, DT-03-2 | H-2 | DT-24-4, DT-25-42 |
| S-3 | DT-03-5, DT-25-9 | H-3 | DT-24-9 |
| S-4 | DT-25-3 | H-4 | DT-24-10 |
| S-5 | DT-25-4 | H-5 | DT-25-43 |
| S-6 | DT-05-6, DT-25-5 | H-6 | DT-24-11 |
| S-7 | DT-03-6 | Z-1 | DT-28-9 |
| S-8 | DT-07-1, DT-07-2, DT-07-4, DT-25-6 | N-1 | DT-04-8 (NOT_RUN) |
| S-9 | DT-25-7 | N-2 | DT-27-5, DT-27-1 |
| S-10 | DT-25-8 | V-1 | DT-19-1, DT-19-6 |
| G-1 | DT-25-10 | V-2 | DT-19-7 |
| G-2 | DT-25-11 | V-3 | DT-19-8 (NOT_RUN) |
| G-3 | DT-25-12, DT-22-3 | R-1 | DT-12-8 |
| G-4 | DT-25-13, DT-25-14 | R-2 | DT-12-1, DT-12-9 |
| G-5 | DT-25-15 | R-3 | DT-12-7 |
| B-1 | DT-22-1, DT-22-3 | R-4 | DT-12-2 |
| B-2 | DT-22-2 | R-5 | DT-13-1, DT-13-3, DT-13-4 |
| B-3 | DT-22-1, DT-22-4, DT-22-5 | R-6 | DT-12-6 |
| B-4 | DT-22-1 | R-7 | DT-15-5, DT-24-2 |
| T-1 | DT-25-16 | T-2 | DT-25-17, DT-25-18, DT-04-4 |
| T-3 | DT-25-19 | T-4 | DT-25-20 |
| T-5 | DT-25-21, DT-04-7 | | |

Contract revision 2 adds 27 ids and changes the wording of others; the table above keeps the revision 1 mapping and this supplement adds the rest. Family totals after Round 2: P 23, S 15, G 7, B 4, T 7, R 11, V 6, N 4, H 8, Z 3, Y 12, W 3, C 6 = 109. The Round 2 ids map as follows: P-21 DT-34-2; P-22 DT-21-10, DT-33-7; P-23 DT-17-22; H-8 DT-24-18; Z-3 DT-33-7; Y-12 DT-25-53 (NOT_RUN); C-6 DT-25-54, DT-25-55. Round 2 also changed the wording of G-1 (classes at most 8, at most 10 with the Details label and the gym-timer row) DT-25-10; T-5 (focus only, zero announce) DT-32-4, DT-25-21; T-6 (sample cap and consent reasons, `gpsRevokedNotif` for revoked) DT-35-1; V-1 and Y-3 (focus-only rule, offline once, suppressed state announced when the window ends) DT-19-1, DT-25-25; V-4 (pending item excluded from the precondition) DT-19-10; Z-2 (`gpsReasonConsent`) DT-33-4; P-16 (15 s from the service-start call) DT-34-3.

| New AC | Rows | New AC | Rows |
|---|---|---|---|
| P-15 | DT-34-1, DT-34-2 | N-3 | DT-37-1 |
| P-16 | DT-34-3 | N-4 | DT-31-4 |
| P-17 | DT-33-2 | H-7 | DT-24-17 |
| P-18 | DT-12-14 | Z-2 | DT-33-1 |
| P-19 | DT-17-21 (NOT_RUN) | Y-9 | DT-25-50 |
| P-20 | DT-17-16 | Y-10 | DT-25-52 (NOT_RUN) |
| S-11 | DT-25-45 | Y-11 | DT-25-51 |
| S-12 | DT-03-12 | C-4 | DT-25-36 |
| S-13 | DT-36-1, DT-36-2, DT-36-3 | C-5 | DT-31-4 |
| S-14 | DT-25-46 | R-8 | DT-13-5, DT-13-8 |
| S-15 | DT-03-13 | R-9 | DT-30-6, DT-30-8 |
| G-6 | DT-25-47 | V-4 | DT-19-10 |
| G-7 | DT-25-48 | T-6 | DT-35-1, DT-35-3 |
| T-7 | DT-25-49 | | |

Ids whose wording changed in revision 2 and the rows that now carry the changed part: P-2 (precise line and privacy line in one view) DT-17-2; S-4 (`gpsPauseDisabledHint`) DT-25-3; G-1 (per-class caps, at most 8 in total) DT-25-10; G-3 (observer scoped to the `/record/gps` route) DT-25-12; T-5 (Finish... action and tap, focus and one announcement) DT-32-3, DT-32-4, DT-25-21, DT-04-7; V-1 (Keep and Delete only, focus, assertive announcement) DT-19-1, DT-19-6; Y-3 (user kinds always announced, focus-moving transitions) DT-25-25, DT-25-49; Y-5 (S4-1 to S4-7, automatic swaps) DT-25-27; Y-7 (S4-1 to S4-7, strip, rail slot) DT-25-29; N-1 (public version set explicitly) DT-32-1, DT-32-6, DT-04-8; Z-1 DT-28-9; C-1 (withdrawn ids) DT-25-34; C-3 DT-25-35; R-5 DT-13-1. Set comparison (Z4): a grep of every `AC-D4-<family>-<n>` id in the Contract against the full ids in this plan found exactly one id missing, AC-D4-B-4 (it was written in the short form `B-3, B-4`); it is now written in full in DT-22-1, and DT-00-4 repeats the comparison mechanically. Late additions to the map: R-10 DT-12-4; R-11 DT-15-9; V-5 DT-19-12, DT-19-13; V-6 DT-19-14, DT-19-15, DT-19-16. Every one of the 109 ids has a row; the ids that need a phone (N-1, V-3, P-19, Y-10, Y-12 and the device half of T-2) are marked NOT_RUN in their rows.

### 7.3 Story to rows (every AC of every story)

| Story | Rows (an AC of the story maps to the listed row) | Conditional |
|---|---|---|
| S04-01 | AC-1 DT-01-1; AC-2 DT-01-2; AC-3 DT-01-4 (plus DT-01-3, DT-01-5 to DT-01-7) | |
| S04-02 | AC-1 DT-02-1; AC-2 DT-02-2; AC-3 DT-02-3 (plus DT-02-4 to DT-02-6) | |
| S04-03 | AC-1 DT-03-1, DT-03-2; AC-2 DT-03-3, DT-03-4; AC-3 DT-03-6; AC-4 DT-03-7 | |
| S04-04 | AC-1 DT-04-1, DT-04-2; AC-2 DT-04-8; AC-3 DT-04-3; AC-4 DT-04-4, DT-04-10; AC-5 DT-04-9 | |
| S04-05 | AC-1 DT-05-1; AC-2 DT-05-3; AC-3 DT-05-4; AC-4 DT-05-5; AC-5 DT-05-6; AC-6 DT-05-10 | |
| S04-06 | AC-1 DT-06-1; AC-2 DT-06-3, DT-06-4; AC-3 DT-06-2 | |
| S04-07 | AC-1 DT-07-1; AC-2 DT-07-2; AC-3 DT-07-3; AC-4 DT-07-4 | |
| S04-08 | AC-1 DT-08-1; AC-2 DT-08-2; AC-3 DT-08-3; AC-4 DT-08-5, DT-08-6 | |
| S04-09 | AC-1 DT-09-1; AC-2 DT-09-2; AC-3 DT-09-3 | |
| S04-10 | AC-1 DT-10-1; AC-2 DT-10-2; AC-3 DT-10-3 | |
| S04-11 | AC-1 DT-11-1; AC-2 DT-11-3; AC-3 DT-11-6; AC-4 DT-11-10; AC-5 DT-11-16 | |
| S04-12 | AC-1 DT-12-1; AC-2 DT-12-2; AC-3 DT-12-7, DT-24-6; AC-4 DT-25-45; AC-5 DT-33-3; AC-6 DT-12-4 | |
| S04-13 | AC-1 DT-13-1; AC-2 DT-13-2; AC-3 DT-13-3 | |
| S04-14 | AC-1 DT-14-1; AC-2 DT-14-2; AC-3 DT-14-3 | |
| S04-15 | AC-1 DT-15-1; AC-2 DT-15-2; AC-3 DT-15-4, DT-15-5, DT-15-8 (plus DT-15-9, DT-15-10) | |
| S04-16 | AC-1 DT-16-6; AC-2 DT-16-1, DT-16-2 | AC-1 only if D-9 option B |
| S04-17 | AC-1 DT-17-1; AC-2 DT-17-2, DT-17-3; AC-3 DT-17-4 to DT-17-9 | |
| S04-18 | AC-1 DT-18-1; AC-2 DT-18-2 | CONDITIONAL |
| S04-19 | AC-1 DT-19-1; AC-1b DT-19-12; AC-2 DT-19-6; AC-3 DT-19-8; AC-4 DT-19-12, DT-19-13; AC-5 DT-19-14, DT-19-17; AC-6 DT-19-14, DT-19-15, DT-19-16; AC-7 DT-19-17, DT-19-24; AC-8 DT-19-14; AC-9 DT-19-14, DT-19-19; AC-10 DT-19-18; AC-11 DT-19-20, DT-19-22, DT-19-23; AC-12 DT-19-21; AC-13 DT-19-22, DT-19-23 (plus DT-19-9 to DT-19-11) | |
| S04-20 | AC-1 DT-20-1; AC-2 DT-20-2; AC-3 DT-20-3, DT-20-4 | CONDITIONAL |
| S04-21 | AC-1 DT-21-1; AC-2 DT-21-2; AC-3 DT-21-6 | |
| S04-22 | AC-1 DT-22-1; AC-2 DT-22-2; AC-3 DT-22-3, DT-22-4 | |
| S04-23 | AC-1 DT-23-1; AC-2 DT-23-2 | |
| S04-24 | AC-1 DT-24-1; AC-2 DT-24-2; AC-3 DT-24-3; AC-4 DT-24-4; AC-5 DT-24-6; AC-6 DT-24-12 | |
| S04-25 | AC-1 DT-25-1; AC-2 DT-17-1 to DT-17-9, DT-25-16 to DT-25-20, DT-12-2; AC-3 DT-25-2; AC-4 DT-25-18, DT-28-5; AC-5 DT-25-47; AC-6 DT-25-49; AC-7 DT-13-8, DT-19-6, DT-25-48 | |
| S04-26 | AC-1 DT-26-1, DT-26-2; AC-2 DT-26-5, DT-26-7 | |
| S04-27 | AC-1 DT-27-1; AC-2 DT-27-2 | |
| S04-28 | AC-1 DT-28-1 to DT-28-4; AC-2 DT-28-5; AC-3 DT-28-6, DT-28-7; AC-4 DT-28-8 | |
| S04-29 | AC-1 DT-29-10 (template) with DL-1 to DL-9; AC-2 DT-29-10; AC-3 DT-29-10; AC-4 DT-29-11 | CONDITIONAL |
| S04-30 | AC-1 DT-30-1; AC-2 DT-30-2; AC-3 DT-30-3; AC-4 DT-30-4; AC-5 DT-30-5; AC-6 DT-30-6; AC-7 DT-30-7; AC-8 DT-15-9 (plus DT-30-8 to DT-30-13) | |
| S04-31 | AC-1 DT-31-1; AC-2 DT-31-2; AC-3 DT-31-3 (plus DT-31-4) | |
| S04-32 | AC-1 DT-32-1; AC-2 DT-32-2, DT-32-3; AC-3 DT-32-4; AC-4 DT-32-6 (plus DT-32-5) | |
| S04-33 | AC-1 DT-33-1; AC-2 DT-33-2, DT-33-3; AC-3 DT-33-4; AC-4 DT-33-5 (plus DT-33-6, DT-33-7) | |
| S04-34 | AC-1 DT-34-1; AC-2 DT-34-2; AC-3 DT-34-3 (plus DT-34-4 to DT-34-6) | |
| S04-35 | AC-1 DT-35-1; AC-2 DT-35-3, DT-35-5; AC-3 DT-35-3 (plus DT-35-2, DT-35-4) | |
| S04-36 | AC-1 DT-36-1; AC-2 DT-36-2; AC-3 DT-36-3; AC-4 DT-36-4 (plus DT-36-5) | |
| S04-37 | AC-1 DT-37-1; AC-2 DT-37-2; AC-3 DT-37-3 | CONDITIONAL |
| S04-38 | AC-1 DT-38-1; AC-2 DT-38-2; AC-3 DT-38-4; AC-4 DT-38-5; AC-5 DT-38-6 (plus DT-38-3) | outside code; documents |

### 7.4 Reverse check

1. A row id is unique in the file. An id `DT-xx-n` sits under story xx; the story column of section 7.3 and the id prefix never conflict. Rows with N above 1 repeat their id with a `/suffix`.
2. Cross-story timing is not cross-story ownership: DT-04-7 and DT-25-21 test the same notification behaviour from the service side and the UI side and are both listed; DT-17-11 (controller refuses) and DT-12-9 (the panel) are two different assertions of AC-D4-P-12.
3. The test agents list all test names starting with `DT-` with the Grep tool at the end, confirm every row id above is present, confirm every AC-D4 id and every S04-R id appears in sections 7.1 and 7.2, and record the listing in `S04_TEST_FINDINGS_FINAL.md`.

## 8. Counts and focused commands

### 8.1 Counts

N is the number of test entries. DT-15-R and DT-24-R (regression evidence, N=0) and the DL items (counted through their DT-xx rows) add no entries. Unconditional stories are listed first; conditional stories separately.

| Story | Epic | U | W | I | K | D | Total |
|---|---|---|---|---|---|---|---|
| S04-01 | A | 1 | 0 | 5 | 4 | 0 | 10 |
| S04-02 | A | 1 | 0 | 31 | 1 | 0 | 33 |
| S04-03 | A | 11 | 0 | 1 | 1 | 0 | 13 |
| S04-04 | A | 3 | 0 | 8 | 3 | 4 | 18 |
| S04-05 | B | 7 | 0 | 13 | 0 | 0 | 20 |
| S04-06 | B | 5 | 0 | 4 | 0 | 0 | 9 |
| S04-07 | B | 12 | 0 | 6 | 0 | 0 | 18 |
| S04-08 | C | 5 | 0 | 14 | 0 | 0 | 19 |
| S04-09 | C | 5 | 0 | 6 | 0 | 0 | 11 |
| S04-10 | C | 1 | 0 | 8 | 0 | 0 | 9 |
| S04-11 | D | 3 | 0 | 29 | 2 | 3 | 37 |
| S04-12 | D | 0 | 10 | 23 | 0 | 0 | 33 |
| S04-13 | D | 0 | 4 | 13 | 1 | 0 | 18 |
| S04-14 | D | 0 | 0 | 23 | 0 | 0 | 23 |
| S04-15 | D | 0 | 3 | 13 | 3 | 0 | 19 |
| S04-16 | D | 0 | 2 | 5 | 0 | 0 | 7 |
| S04-17 | E | 0 | 44 | 7 | 0 | 1 | 52 |
| S04-19 | E | 0 | 8 | 64 | 0 | 2 | 74 |
| S04-21 | E | 4 | 0 | 18 | 0 | 0 | 22 |
| S04-22 | F | 0 | 5 | 17 | 0 | 0 | 22 |
| S04-23 | F | 0 | 0 | 0 | 3 | 0 | 3 |
| S04-24 | G | 3 | 22 | 23 | 2 | 0 | 50 |
| S04-25 | G | 0 | 131 | 1 | 12 | 2 | 146 |
| S04-26 | H | 0 | 0 | 6 | 1 | 3 | 10 |
| S04-27 | H | 3 | 0 | 13 | 2 | 0 | 18 |
| S04-28 | H | 4 | 2 | 1 | 5 | 0 | 12 |
| S04-30 | J | 1 | 2 | 40 | 0 | 0 | 43 |
| S04-31 | J | 0 | 2 | 8 | 2 | 0 | 12 |
| S04-32 | J | 4 | 2 | 2 | 1 | 2 | 11 |
| S04-33 | J | 0 | 8 | 8 | 0 | 0 | 16 |
| S04-34 | J | 0 | 10 | 11 | 0 | 0 | 21 |
| S04-35 | J | 2 | 2 | 7 | 0 | 1 | 12 |
| S04-36 | J | 1 | 3 | 7 | 0 | 0 | 11 |
| S04-38 | J | 0 | 0 | 0 | 9 | 0 | 9 |
| DT-00 | cross | 0 | 0 | 0 | 7 | 0 | 7 |
| Unconditional total | | 76 | 260 | 435 | 59 | 18 | 848 |
| S04-16 DT-16-6 (D-9 option B) | D | 0 | 0 | 1 | 0 | 0 | 1 |
| S04-18 | E | 0 | 3 | 0 | 2 | 0 | 5 |
| S04-20 | E | 0 | 9 | 0 | 0 | 1 | 10 |
| S04-29 | I | 0 | 0 | 0 | 3 | 9 | 12 |
| S04-37 | J | 0 | 0 | 5 | 0 | 1 | 6 |
| Conditional total | | 0 | 12 | 6 | 5 | 11 | 34 |
| Grand total | | 76 | 272 | 441 | 64 | 29 | 882 |

Note on S04-16 in the unconditional rows: DT-16-6 is excluded from the S04-16 line (7 entries, rows DT-16-1 to DT-16-5) and counted as conditional. DT-15-6 (moved to S04-30), DT-15-R and DT-24-R (regression evidence) add no entries (N=0). S04-37 is conditional on the device test T2. Revision 1 totals were 568 unconditional and 596 with the conditional stories; revision 2 had 747 and 781; revision 3 had 783 and 817; the gate batch (revision 4) adds 21 unconditional entries: DT-15-9 and DT-15-10 +8, DT-19-12 and DT-19-13 +9, DT-22-1 +2 (the other side of each boundary), DT-00-4 +2. The Z5 and Z6 batch (revision 5) adds 17 unconditional entries: DT-19-14 to DT-19-17 +13, DT-38-4 to DT-38-6 +3, DT-00-4 +1; the grand total is 855. The Z7 and Z8 batch (revision 6) adds 17 unconditional entries: DT-19-14 +2, DT-19-17 +1, DT-19-18 to DT-19-21 +14; the Z9 to Z12 batch (revision 7) adds 6 unconditional entries: DT-19-21 +2 (six recovery states), DT-19-22 +2, DT-19-23 +2 (DT-19-17 and DT-19-20 keep their entry counts); the Z13 to Z15 batch (revision 8) adds 4 unconditional entries: DT-19-22 +1, DT-19-23 +1, DT-19-24 +2; the grand total is 882. Per epic (unconditional): A 74, B 47, C 39, D 137, E 148, F 25, G 196, H 40, J 135, cross-cutting 7 = 848. Level shares of the unconditional total: U 10, W 33, I 48, K 7, D 2 percent (rounded). Device-only entries: 18 unconditional plus 11 conditional = 29, all NOT_RUN until a phone exists.

### 8.2 Focused commands (per step; run from `mobile/`; PROPOSED file lists, final names set by the test agents)

All have the form `flutter test --timeout 60s <explicit files>`; the agent also records `flutter --version`, the resolved executable path, the git head and the result line verbatim. A directory argument is allowed only for a directory created for S04.

| Step | Command (relative to `mobile/`) |
|---|---|
| 0 compile smoke | `flutter test --timeout 60s test/s04_conformance/compile_smoke_test.dart test/s04_conformance/scan_set_test.dart` |
| 1 EP-A | `flutter test --timeout 60s test/features/recording/location test/features/recording/pipeline/replay_harness_test.dart test/features/recording/state/recorder_state_table_test.dart test/features/recording/state/service_release_test.dart test/android/manifest_location_test.dart test/core/architecture` |
| 2 EP-B and EP-C | `flutter test --timeout 60s test/features/recording/pipeline` (directory created for S04) |
| 3 EP-D | `flutter test --timeout 60s test/features/recording/journal test/android/backup_rules_test.dart test/android/backup_exclusion_test.dart test/features/account_deletion` plus the existing S02 journal test files unchanged (listed by exact path from Glob). Order inside the step: lifecycle and backup files first |
| 4 EP-E | `flutter test --timeout 60s test/features/recording/permissions test/features/recording/consent test/features/recording/pages/start_screen_test.dart test/features/recording/state/revocation_test.dart` |
| 5 EP-F | `flutter test --timeout 60s test/features/recording/state/battery_test.dart test/s04_conformance/battery_protocol_test.dart` |
| 6 EP-G | `flutter test --timeout 60s test/features/workouts/active_session_sources_test.dart test/shared/widgets test/features/recording/pages test/features/recording/widgets` plus the existing S03 strip and dock tests unchanged |
| 7 EP-H | `flutter test --timeout 60s test/features/recording/privacy test/features/recording/performance test/s04_conformance/static_scans_test.dart` (the measure-only test DT-26-5 is run once, numbers recorded) |
| 7b EP-J | `flutter test --timeout 60s test/features/recording/accounts test/features/recording/privacy/sanitiser_test.dart test/features/recording/pages/notification_test.dart test/features/recording/consent/withdrawal_test.dart test/features/recording/state/start_preconditions_test.dart test/s04_conformance/release_gate_test.dart` plus the existing sign-out guard and account-deletion tests unchanged |
| 8 EP-I | `flutter test --timeout 60s test/s04_conformance/device_lab_record_test.dart` (the template validators only) |
| 9 final | every file of steps 0 to 8 in one command line, once, on the exact head to be approved |

A defect fix that touches a file of an earlier step re-runs that whole step. A run one fix cycle behind the approved head does not count as final.

## 9. Findings about the inputs: status after the revised documents

Status of the revision 1 findings against the revised Design (section 16.1 Round 2 additions), Requirements and Contract. RESOLVED means the concrete expected value is now in the rows; the DEPENDS-ON-DESIGN tags of those rows were removed. CARRIED means still open.

| Id | Status | Where the rows follow it |
|---|---|---|
| TP-S04-1 | RESOLVED: re-anchor after 5 speed-only rejections or 30 s (PROPOSED), `gapStart`/`gapEnd`, wrong anchor stays in raw | DT-05-11 |
| TP-S04-2 | RESOLVED: Design uses the three Contract channels | DT-03-5, DT-25-9 |
| TP-S04-3 | RESOLVED: Design 5.2 mapping paragraph and Discard edges | DT-03-3, DT-03-11 |
| TP-S04-4 | RESOLVED: private version has Pause/Resume and `Finish...`, public version none | DT-04-7, DT-32-2, DT-32-3 |
| TP-S04-5 | RESOLVED: auto-pause default on for walk, run, ride; off for hike and every other value | DT-07-4 |
| TP-S04-6 | RESOLVED: 5-sample median plus a 10 m step limit | DT-10-5 |
| TP-S04-7, TP-S04-9 | RESOLVED: a torn tail only at the end of the last segment or announced by `segmentBreak`; all other damage is `recoveryFailed`, no partial offer | DT-11-9, DT-11-17, DT-13-1 |
| TP-S04-8 | RESOLVED: `DISCARDING` marker, ordered delete, `meta.json` last, deleted at the next start | DT-12-2, DT-12-13 |
| TP-S04-10 | RESOLVED by the Contract: panel `restricted`, Add manually only | DT-17-16 |
| TP-S04-11 | RESOLVED: the flag is `GPS_RECORDER` | DT-25-43, DT-28-1 |
| TP-S04-12 | RESOLVED by the rewrite of Req S04-R-014 (sibling recording journal) | DT-11-1 |
| TP-S04-13 | CARRIED: the 50 kill points come from a fixed LCG, not `Random` | DT-11-6 |
| TP-S04-14 | RESOLVED: `offline` is not shown by default; the chip rows use a fake connectivity signal | DT-25-7 |
| TP-S04-15 | CARRIED: the merged manifest needs a build (NOT_RUN) | DT-04-1, DT-04-11 |
| TP-S04-16 | RESOLVED (Y5): `preparing` becomes `cannotStart` after 5 s; `startFailed` 15 s counted from the service-start call, not the tap | DT-34-2, DT-34-3 |
| TP-S04-17 | RESOLVED (Y10): automatic stops with the non-ongoing notification are battery, storage, sample cap and consent withdrawal; a revoked stop keeps its own notification | DT-35-1 |
| TP-S04-18 | RESOLVED: S04-38 cites requirements section 12 (release gate); DT-38-x trace to it | DT-38-1 to DT-38-3 |
| TP-S04-19 | RESOLVED (Y5): the "cannot check" path keeps Sign out anyway with explicit text; Story AC-6 and Req S04-R-019 follow the design | DT-30-6 |
| TP-S04-20 | NEW: the Contract still lists assertive announcements (`gpsAnnRevoked`, `gpsAnnRecoveryFailed`) next to the focus-only rule C6 (no announce when focus moves to the new headline); the tests assert zero announce calls when focus moves and the announcement only where focus does not move | DT-13-6, DT-19-9, DT-25-25 |
| Z1 | RESOLVED: Resume after a kill enters `acquiring` for every origin; pause origin and values preserved; a `restart` gap pair adds nothing | DT-12-4 |
| Z2 | RESOLVED: on revocation the partial recording is durably SEALED as a pending decision; Keep hands off (ordered, idempotent, owner-checked); Delete uses the ordered delete; the stale name `stoppedRevoked` is replaced by `permissionRevoked` | DT-03-1, DT-19-1, DT-19-12, DT-19-13 |
| Z3 | RESOLVED as a PROPOSED clarification of GPS-PRIV-014 plus an operator question (alternative: strict deletion) | DT-15-9, DT-15-10 |
| Z4 | RESOLVED: AC-D4-B-4 written in full and covered on both sides of each boundary; mechanical set comparison | DT-22-1, DT-00-4 |
| Z5 | RESOLVED: first durable `DECISION` marker wins; Delete not offered after Keep is durable, Keep refused after Delete is durable, replays are no-ops; crash and concurrent injection before `put`, right after `put` and before journal cleanup give one deterministic result; new AC-D4-V-6 | DT-19-14 to DT-19-17 |
| Z6 | RESOLVED: story AC map completed (S04-12 AC-4 to AC-6, S04-19 AC-1b and AC-4 to AC-8, S04-25 AC-5 to AC-7, S04-30 AC-8, S04-38 AC-3 to AC-5); DT-00-4 repeats the story AC comparison | section 7.3, DT-00-4 |
| Z7 | RESOLVED: one exclusive-create `DECISION` file arbitrates (never a rename); the loser acts irreversibly never; `DISCARDING` is only the DELETE progress marker; DT-19-14 and DT-19-17 extended; forced two-writer interleaving in both orders, file arbitration with the mutex bypassed, empty or torn file, malformed combinations quarantined; story ACs AC-9 to AC-12 mapped | DT-19-14, DT-19-17 to DT-19-24 |
| Z8 | RESOLVED: DT-19-13 states that a Delete after a durable `KEEP` is a no-op refused with "already decided" and never removes the S02 activity, even when cleanup is unfinished | DT-19-13 |
| Z9 | RESOLVED: one recovery matrix of six states driven through `listUnfinished()` itself | DT-19-21 |
| Z10 | RESOLVED: the `DECISION` file is published whole (temp file, fsync, exclusive hard-link, directory fsync) and nothing ever unlinks it; an empty, truncated or unknown-token file at recovery is QUARANTINED, never removed (the earlier "removed and pending" expectation is withdrawn); regression row for a paused writer; publish-whole row | DT-19-20, DT-19-22, DT-19-23 |
| Z11 | RESOLVED: quarantine also applies to malformed decision-state recovery; ordinary revocation never quarantines | DT-19-20, DT-19-21 |
| Z12 | RESOLVED: DT-19-17 asserts only that no irreversible operation begins before both durability barriers complete | DT-19-17 |
| Z13 | RESOLVED: the rule is "a `DECISION` is never unlinked or replaced on its own; it disappears only with its whole directory after DELETE completion or verified KEEP cleanup"; rows for completed KEEP cleanup and for a crash or restart during it | DT-19-22, DT-19-24 |
| Z14 | RESOLVED: the journal lock is process-wide and exclusive; a second instance in another process or isolate fails closed; recovery cannot run concurrently with a live fallback writer because Keep and Delete are gated on `recoveryComplete`; "owner lock" wording replaced by the process-wide journal lock | DT-19-20, DT-19-22, DT-19-23 |
| Z15 | RESOLVED: S04-19 AC-13 mapped to DT-19-22 and DT-19-23, the KEEP cleanup row to AC-7; the story AC comparison is repeated by grep | section 7.3 |

Original wording of revision 1 (kept for traceability; where it says DEPENDS-ON-DESIGN for a RESOLVED item, the table above wins):


| Id | Finding | Rows affected |
|---|---|---|
| TP-S04-1 | The speed gate compares each fix with the previous KEPT fix and the design defines no recovery: one wrong first fix with a good accuracy can make every later fix fail the speed rule forever. | DT-05-11 |
| TP-S04-2 | Design 5.1 proposes ONE priority order that includes `batteryCritical`; the Contract 5.3 uses three channels (headline, banner, chips) and puts battery in the banner. The tests follow the Contract. | DT-03-5, DT-25-9 |
| TP-S04-3 | Design phases `preparing`, `stopping`, `stoppedRevoked` (old name, now `permissionRevoked`, Z2) have no name among the Contract's 13 states, and the diagrams differ (for example Contract: recording to idle on Discard; Design: via `stopping`). | DT-03-3, DT-03-11 |
| TP-S04-4 | Design 1.2 and 7.3 say no notification action buttons; Contract 17 and DN-7 define Pause/Resume and Stop actions. | DT-04-7, DT-25-21 |
| TP-S04-5 | Req S04-R-012 sets auto-pause on for walk, run and ride; the Contract offers Walk, Run, Hike, Ride; the default for hike is undefined. | DT-07-4 |
| TP-S04-6 | A single GPS altitude outlier would add its full height to ascent (hysteresis alone does not filter a one-sample spike). | DT-10-5 |
| TP-S04-7 | A missing middle segment or a bit flip in a middle frame is treated by the "torn tail" rule as the end of the log: everything after it is silently dropped and a short track could be shown as recovered. The design must separate a torn tail from mid-log corruption. | DT-11-9, DT-13-1/mid-log-bit-flip |
| TP-S04-8 | The delete order of a discarded recording is unspecified; a crash in the middle of a discard could resurrect a partial recording as a recovery offer. | DT-12-2/discard |
| TP-S04-9 | See TP-S04-7: the expected value for the mid-log case is not in any document; the test asserts only the invariant (no short track presented as complete). | DT-13-1 |
| TP-S04-10 | Permission status `restricted` exists in the service interface but the Contract has no panel for it. | DT-17-16 |
| TP-S04-11 | Two flag names for one switch: Design 9.1 `RECORDER_ENABLED`, Contract 14.2 `GPS_RECORDER`. Tests read the flag by the provider, not by the define name, until the names are merged. | DT-25-43, DT-28-1 |
| TP-S04-12 | Req S04-R-014 says samples go "through the S02 repository writer" while the design adds a sibling `RecordingJournal` (Design 15 already notes it); the K scan DT-11-1 uses the design reading. | DT-11-1 |
| TP-S04-13 | Req S04-R-015 asks for "random offsets, 50 runs"; this plan uses a fixed LCG so the 50 points are reproducible (no `Random` in tests). | DT-11-6 |
| TP-S04-14 | Offline detection has no source (no connectivity package, DN-16); offline rows exercise a fake. | DT-25-7 |
| TP-S04-15 | The merged manifest cannot be seen without a build; the source-manifest K rows can pass while a plugin adds a permission. | DT-04-1, DT-04-11 |

The rows that exist to catch the most likely silent failures, in order of risk: DT-11-6 and DT-11-13 (kill promise and failed-append recovery), DT-14-2 (hand-off window), DT-15-1 and DT-15-2 (location data surviving sign-out or leaving through backup), DT-24-12 (entry-point leaks of a foreign recording).
