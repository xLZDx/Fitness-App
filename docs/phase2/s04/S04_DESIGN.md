# S04 Technical Design: GPS recorder without a map

Status: DRAFT, revised once after review round 1 (finding-by-finding log in section 16). Written 2026-10-17 on branch `phase2/s04-docs`. Documentation only: no code is changed, no command was run, no device was used.

Reader: the architect, the implementation lanes and the test agents of S04. Inputs: `docs/phase2/s04/S04_REQUIREMENTS.md` (called "Req"; ids `S04-R-nnn`), `docs/phase2/s04/S04_ANDROID_PLATFORM_STUDY.md` ("Study"; rows cited as `Study 3.8`), `docs/phase2/s04/S04_DOC_READINESS.md` ("Readiness"; gaps G1..G12), `docs/phase2/s04/S04_STORIES.md` (lane table only, section 9, cited as "Stories 9"), `docs/phase2/s02/S02_DESIGN.md`, `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (ids `GPS-PRIV-nnn`), and the code in this worktree.

Tags: FACT (path, line or section read in this worktree), INFERENCE (drawn from facts), PROPOSED (a choice made here, not measured), DECISION NEEDED (needs an owner's answer; options in words), UNKNOWN (not verified), NOT_RUN (needs a device or console).

Plain-words glossary of ids: `S04-R-nnn` = a requirement of this sprint. `GPS-PRIV-nnn` = a privacy rule of the S01 contract. `G1..G12` = gaps listed in Readiness. `Lk` / `Rk` = an implementation lane (a group of files one agent owns); this file uses the lane names R1..R12 of Stories 9. "Fix" = one location reading from the phone. "Seam" = an interface that a test replaces with a fake. "Seal" = close the recording journal and mark it complete. "Hand-off" = turn the sealed recording into one finished activity in the S02 store. "S04-D" = the UI contract `docs/phase2/s04/S04D_UI_DESIGN_CONTRACT.md` (sections cited as `S04-D 5.3`). "Owner scope" = the per-account directory scope (hash of the uid) that was bound when the recording began. "Quarantine" = a recording kept on disk, untouched and no longer blocking Start, with an expiry. Ids `X1..X10`, `ARCH1..14` and `SEC1..9` = the decisions and findings of `docs/phase2/s04/S04_REVIEW_FINDINGS_ROUND1.md`; each is mapped in section 16. `S04-R-052..058` = the seven requirements added after round 1 (sanitising wrapper, lock-screen notification, consent withdrawal surface, Start preconditions, automatic-stop notification, manual-pause interval, engine-detach behaviour).

## 1. Scope, non-goals, entry conditions, definition of done

### 1.1 Scope

Roadmap row S04 (FACT, Req section 1): foreground-service recorder, journaled samples with crash-safe resume, auto-pause, smoothing and accuracy gate, calculators with replay tests, permission flow, battery protocol, recording that works with no map service. Platform: Android only (Req A-1; Study section 1). Upload stays off (Req A-6). The recording screens are those of the S04-D contract, which is a separate document (Req A-8); this design fixes behaviour and seams, not screens or copy.

Assumed operator defaults used throughout (from Req section 3; each is open until answered): A-1 Android only; A-2 reference phone UNKNOWN, all device numbers are PROPOSED; A-3 only two consent rows are built; A-4 default privacy-zone radius 200 m as a constant; A-5 default GPS expiry 24 months as a constant; A-6 no upload; A-7 pre-prompt text is DRAFT; A-8 S04-D is a separate approved contract.

### 1.2 Non-goals

No map, tile or route display; no EXPLORE or RIDE screens; no sharing; no privacy-zone editor; no heart-rate or BLE sensor; no FIT/GPX import or export; no cloud upload of streams; no consent centre; no iOS (Req section 1, S04-R-050). No `ApplicationExitInfo` reading, no battery-optimisation exemption request and no Export of an unfinished, revoked or unreadable recording (X3: Keep or Delete only; export of FINISHED activities is the existing S02 export, unchanged). Notification action buttons exist only as far as 5.5 allows (D-20).

### 1.3 Entry conditions

| # | Condition | State |
|---|---|---|
| E1 | S03 merged and accepted (strip, dock, `activeSessionStatusProvider` exist) | FACT: code present in this worktree (`active_session_status.dart`, `dock_widgets.dart`, `main_shell.dart`) |
| E2 | S02 journal and `ActivitySession` exist and the default build opens the journal | FACT: `activity_flags.dart` line 39 (`defaultValue: true`); `activity_wiring.dart` header |
| E3 | Backup exclusion covers `activity_journal` | FACT: `journal_layout.dart` lines 18, 41-46 (`kScopedJournalRootDirName` is in the excluded list) |
| E4 | S04-D UI contract approved | FACT: the contract is WRITTEN (`S04D_UI_DESIGN_CONTRACT.md`, 23 sections: states 5.1, priority 5.3, strip words 14.1, flag `GPS_RECORDER` 14.2) and is in its own round-1 fix pass; APPROVAL is pending. This design adopts its state names, priority channels, strip words and flag name (5.1, 7.2, 9.1). Lane R7 (screens) still waits for approval; lanes that need only states and words may start on the contract text |
| E5 | Reference phone named | UNKNOWN (Req A-2). Blocks acceptance, not coding |
| E6 | Device decisions of section 2.4 taken | NOT_RUN: needs a device |
| E7 | Server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 exists or is scheduled (SEC4) | UNKNOWN: contract text not re-read for this revision. Without it, client log hygiene alone does not meet those rules. Y6: it is a PRECONDITION to start building the recorder lanes (R3 onwards) unless the operator records a dated exception, and it is also a release gate (9.2 item 3) |
| E8 | Plugin dependency resolved and its MERGED manifest read (2.3 step 1-2) | NOT_RUN. Gates the shape of the flag-gated manifest of 2.4 (ARCH11) |

### 1.4 Definition of done (sprint level)

1. Every requirement in section 1.6 is implemented and has the tests of section 12, written and run by the test agents (coordinator runs none).
2. Recording continues with the screen off for the session length of the device-lab record, or the record states FAIL (S04-R-001, S04-R-051).
3. After a process kill or an orderly phone restart, everything flushed before it is recovered or the user is told recovery failed; no copy claims more than the promise in 4.6, and the notification never claims Recording while the Dart side is gone (S04-R-015..017, S04-R-058).
4. No coordinate appears in any log, error string or telemetry event (S04-R-044).
5. Upload flag stays false and no network call exists in the recorder (S04-R-005, S04-R-046).
6. The 100 000-sample frame-budget test passes or is recorded NOT_RUN with the reason (S04-R-042).
7. Missing device evidence is NOT_RUN, never PASS (S04-R-051). The DoD of the roadmap ("tolerance and battery recorded on the operator's phone") cannot close without the phone.
8. Each commit carries its change record and lessons entry (operator workflow rules).

### 1.5 Design in one paragraph

A Dart `RecorderController` (main isolate) owns the whole recording lifecycle. It talks to the phone only through three seams: `LocationSource`, `PermissionService` and `BatteryMonitor`. Each fix goes through a pure pipeline (gate, gap detection, auto-pause, incremental metrics) in O(1) work, and is appended in batches to a new crash-safe recording journal that sits beside the S02 journal and is written only by the repository layer. At stop the journal is sealed; a worker isolate computes smoothing, calculators and the sealed streams; the main isolate then submits one `ActivitySession` to the S02 journal through `ActivityJournal.put`, and only afterwards deletes the recording journal. After a kill the next start finds an unsealed recording and offers Resume, Save as finished or Discard. The shell strip reads a prioritised list of session sources instead of one gym-only derivation.

### 1.6 Requirement trace: every design section to S04-R ids

| Requirement | Design section | Lane (Stories 9) |
|---|---|---|
| S04-R-001, -002 | 2.3 platform host, 2.4 manifest, 5.3 stop path | R1, R2, R4 |
| S04-R-003 | 2.2 seams, 11 static checks | R1 |
| S04-R-004 | 5 state machine | R4 |
| S04-R-005, -046 | 2.2, 9 flags, 10 | R1, R4, R5 |
| S04-R-006, -007 | 3.1 sampling, 3.2 fields, 4.2 frame format | R3, R5 |
| S04-R-008, -009 | 3.3 gate, 3.4 gaps | R3 |
| S04-R-010, -011 | 3.5 smoothing | R3 |
| S04-R-012, -013 | 3.6 auto-pause, 5 state machine | R3, R4 |
| S04-R-014 | 4.1 relation to S02, 4.2 format | R5 |
| S04-R-015 | 4.4 flush, 4.6 promise | R5 |
| S04-R-016, -017 | 4.5 recovery | R5, R7 |
| S04-R-018, -019 | 4.3 seal and hand-off, 4.7 lifecycle | R5 |
| S04-R-020 | 4.8 storage full | R5 |
| S04-R-021..025 | 6.1 permission flow | R1, R7, R10 |
| S04-R-026, -027 | 6.2 consent | R8 |
| S04-R-028..031 | 8 battery hooks | R4, R11 |
| S04-R-032..036 | 3.7 calculators, 3.8 summary | R3 |
| S04-R-035 | 12.2 replay seams | R3 and test agents |
| S04-R-037..039 | 7 shell integration | R6 |
| S04-R-040 | 7.4 screens | R7, R9 |
| S04-R-041..043 | 2.5 isolate boundary | R3, R5 |
| S04-R-044 | 10 logging | R8 |
| S04-R-045 | 4.7, 6.3 | R5 |
| S04-R-047..049 | 9.3 constants | R8 |
| S04-R-050 | 1.2, 2.4, 11 | R2 |
| S04-R-051 | 12.4 evidence | R11 |
| S04-R-052 | 10 sanitising wrapper and global handlers, 11.2 checks (6), (9) | R8, R5 (decode), R9 (`main.dart` splice) |
| S04-R-053 | 5.5 lock-screen notification | R4, R2, R8 (strings) |
| S04-R-054 | 6.2 consent withdrawal surface | R8, R7 (widget), R9 (Settings splice) |
| S04-R-055 | 5.4 Start preconditions | R4, R9 |
| S04-R-056 | 5.5 automatic-stop notification, 4.8 | R4, R2, R8 |
| S04-R-057 | 3.6 manual-pause interval and prompt | R3, R4 |
| S04-R-058 | 5.6 engine-detach behaviour, 4.6, 2.3 D-1 | R1, R2, R4 |

## 2. Architecture

### 2.0 Existing code S04 attaches to (FACT)

| Attach point | Fact | Used by |
|---|---|---|
| Session model | `ActivitySession` (id, sport, startUtc, endUtc, `movingTimeS`, `summary`, `streams`, `provenance`, `formulaVersion`, `metricDefinitionVersion`) `activity_session.dart` lines 65-134; summary fields `distanceM`, `ascentM`, `descentM`, `avgSpeedMps` `activity_summary.dart` lines 7-43; sports `running, walking, hiking, cycling, ...` `sport_type.dart` lines 5-17 | 3.8, 4.3 |
| Streams | `StreamKind.gps/altitude/speed`; offsets strictly increasing; gps has parallel `lats`, `lons`, `accuracies`; `SampleStream.checked` throws on invalid data `sample_stream.dart` lines 8-124 | 3.2, 4.3 |
| Native id | `nativeActivityId(recordingUuid)` and `nativeSourceRecord(...)` with source id `app`, kind `companionApp`; "recording uuid generated ONCE at recording start" `native_session_id.dart` lines 18-57 | 4.3 |
| Journal interface | `ActivityJournal.put(session)` creates or replaces an activity as ONE new generation; identical re-put is a no-op; throws `JournalWriteFailure` subclasses incl. storage full `activity_journal.dart` lines 13-30; `read`, `list`, `delete`, `wipe`, `assessSignOut` | 4.3, 6.3 |
| put cost | `FileActivityJournal.put` runs `jsonEncode`, `gzip.encode`, `sha256` and AES-GCM seal on the calling isolate, whole streams every time `file_activity_journal.dart` lines 194-235 | 2.5, 4.1 |
| Mutex | `JournalMutex` is an in-isolate Future queue `journal_models.dart` lines 284-295; one per journal object | 2.5 |
| Layout | scope root `<support>/activity_journal/<scopeId>` (`uid_scoped_activity_journal.dart` lines 52-66); children `journal`, `sources`, `quarantine`; `FileActivityJournal.wipe()` deletes ONLY those three and forgets the key `file_activity_journal.dart` lines 651-666 | 4.7 |
| File seam | `JournalFileSystem` (createDir, readBytes, list, `openWrite(append)`, rename, deleteFile, deleteDir, no truncate, no directory fsync) `journal_file_system.dart` lines 37-64; `isDiskFull` lines 154-166 | 4.2 |
| Cipher and key | `AesGcmJournalCipher.seal/open`, `SecureStorageJournalKeyProvider(scopeId)` `journal_cipher.dart`; `JournalDecryptFailure` | 4.2 |
| Recovery types | `JournalRecoveryReport`, `RecoveryReportSource`, bind status `recoveredAbsentCount`, `streamLostCount` `journal_models.dart` lines 245-265; `activity_wiring.dart` lines 152-209 | 4.5 |
| Refresh seam | `activityJournalRevisionProvider` "every future writer (recorder ...) increments to request a reload" `activity_dashboard_providers.dart` lines 79-82 | 4.3 |
| Status provider | `ActiveSessionKind { gymWorkout }`, `ActiveSessionState { running, paused, resting, restFinished }`, `_activeSessionCoreProvider` reads set and rest timers only, `deriveActiveSessionStatus` hard-codes "set timer wins", one `activeSessionOwnerProvider` `active_session_status.dart` lines 65-80, 236-358 | 7 |
| Shell | `MainShell` reads `activeSessionStatusProvider` and `activeSessionForeignOwnerProvider` in `_frame` and at the Record entry `_openRecord` `main_shell.dart` lines 152-243; `shellRecordSheetOpenerProvider` overridden in `main.dart` line 624; `_kPillPaths` `main_shell.dart` line 56 and `_kShellTabPaths` `dock_widgets.dart` lines 38-44 are duplicates | 7 |
| Dock widgets | `RecordPill`, `RecordingStrip`, `RailRecordSlot`; `_stateWord`, `_railWord`, `_stateIcon` are exhaustive switches over `ActiveSessionState` `dock_widgets.dart` lines 57-76 | 7 |
| Manifest | permissions CAMERA, POST_NOTIFICATIONS, RECEIVE_BOOT_COMPLETED, WAKE_LOCK, VIBRATE, Health Connect; NO location, NO `FOREGROUND_SERVICE*`, no own `<service>`; comment "Re-add a permission only together with the feature, the privacy text and the Play declaration" `AndroidManifest.xml` lines 3-35 | 2.4 |
| Dependencies | `permission_handler ^11.3.1`, `flutter_local_notifications ^17.2.4`, `path_provider`, `flutter_secure_storage`, `crypto`, `encrypt` `pubspec.yaml`; NO location, battery or connectivity package; toolchain comment Flutter 3.27.1 / Dart 3.6.0 `pubspec.yaml` lines 61-62 (current state UNKNOWN, Study 6) | 2.3, 8 |
| Flags | `ActivityFlags.cloudSync` (default false) and `localJournal` (default true) `activity_flags.dart` lines 19-40 | 9 |
| Wipe prefix | per-uid keys with prefix `activity.` are erased by the device wipe (`local_data_wipe.dart` line 218, FACT from grep) | 6.2 |

### 2.1 Folders and layers (PROPOSED, aligned with Stories 9)

All new code is under `mobile/lib/features/recording/` unless a path says otherwise:

| Folder | Content | Layer rule |
|---|---|---|
| `location/` | `LocationSource` interface, `Fix` value, fake, the ONE adapter file for the chosen package | only this folder may import a location package |
| `permissions/` | `PermissionService` interface, adapter over `permission_handler`, fake | only this folder requests location or notification permission |
| `pipeline/` | gate, gap detector, smoothing, auto-pause, distance, pace, elevation, summary builder, live-metrics accumulator | pure Dart: no Flutter, no `dart:io`, no Riverpod (same guard as `activity/data`) |
| `journal/` | `RecordingJournal` interface, frame codec (pure part), file implementation, recovery, hand-off | repository layer; the ONLY place with file I/O for recordings |
| `state/` | `RecorderController`, state machine, battery monitor port, orchestration providers | Riverpod |
| `consent/` | location consent store and notifier | Riverpod |
| `pages/`, `widgets/` | only screens of the approved S04-D | Flutter |
| `l10n/` | log-safe error-code mapper; strings live in the ARB files | |
| `safety/` | `RecorderSafeError` (code plus original runtime type, no message) and `sanitizeRecorderError(Object)`; the one function every `catch` in `recording/**`, the journal decoder, the worker entry and the global handlers call (S04-R-052) | pure Dart, no Flutter |

Architecture guards: `mobile/test/core/architecture/pure_data_layer_guard_test.dart` and `import_graph_guard_test.dart` list known features (`_features` includes `activity`, not `recording`: FACT, grep of the test). Adding the folder needs an entry or a rule; the first step of lane R1 is to read both tests and extend them (the test agents own the files). Whether `pipeline/` is covered by the pure-layer guard without an edit is UNKNOWN.

### 2.2 Seams (what the recorder may touch)

| Seam | Interface in words | Real adapter | Fake |
|---|---|---|---|
| `LocationSource` | `start(request)` returns a stream of `Fix` (time UTC ms, lat, lon, accuracy m, optional altitude m, optional speed m/s) and errors; `stop()` ends the subscription; `setInterval(seconds)` changes the request rate without a new subscription (manual pause 10 s, battery critical 5 s); an `engineDetached` signal where the adapter can observe it (5.6); `activeSubscriptions` count for tests | one file over the chosen package (2.3) | scripted fixes with a fake clock; can throw an error event; counts subscriptions |
| `PermissionService` | `locationStatus()` (granted precise, granted approximate, denied, permanentlyDenied, restricted), `requestLocation()`, `notificationStatus()`, `requestNotification()`, `openSettings()`; request counter | adapter over `permission_handler` | scripted answers, request counter |
| `BatteryMonitor` | stream of (percent, charging) and a current read | see 8.1 (package undecided) | scripted levels |
| `RecordingJournal` | in 4.2 | file implementation over `JournalFileSystem` | in-memory plus the existing fault-injecting file system style (S02 design 10) |
| `HeavyWorkRunner` | `run(function, input)` returns output | `Isolate.run` | inline synchronous runner that records the call (test asserts it was used) |
| `Clock` | `nowUtcMs()` and monotonic `elapsedMs()` | system | fake |

Rule (S04-R-003): no location package or `Geolocator`-style type is imported outside `location/`; no permission-request API for location or notification outside `permissions/`. Enforced by a source-scan test (section 11). No subscription exists in the states idle, finished, after sign-out and after boot: the controller creates the subscription only inside `startRecording` and always releases it in one `finally` path (5.3).

### 2.3 Platform host, package recommendation and fallback

Facts from the Study that bind the choice: a `location` foreground service started while the app is visible keeps location with the screen off without background permission (Study 2.8, 2.9, 3.6, 3.7; 3.7 is high-confidence INFERENCE and NOT_RUN); a restart after a kill cannot create the service from the background without background permission (Study 3.8); swipe-away, force-stop and low-memory behaviour of the service is UNKNOWN (Study 5.9, 5.12); the package pages were read, not built (Study 6 notes).

Recommendation (PROPOSED, DECISION NEEDED after the device test T1..T3 of 2.6): use `geolocator` as the single location source, wrapped in one adapter file, with its optional foreground-notification configuration providing the foreground service; use the existing `permission_handler` for permissions.

Evidence for: maintained and recent (14.1.1, "19 days ago", Flutter Favorite, MIT, Study 6 table); uses the fused provider with a platform fallback; foreground notification config with title, text and wake lock; plugin merges the Android 14 foreground-location permission; needs compileSdk 35 and the repo has 36 (Study 1). The service lives in the app process and delivers fixes to the main isolate, so the journal has ONE writer in ONE isolate, which is what S02 design line 452 requires; no second Flutter engine is needed. Why not the others:

| Candidate | Reason not chosen as primary (Study 6) |
|---|---|
| `location` 10.0.2 | its manifest needs `ACCESS_BACKGROUND_LOCATION`, which forces the Play background-location form, video and disclosure (Study 4.3-4.6) for a design that does not need it |
| `flutter_foreground_task` | not a location source; runs a Dart handler in a separate isolate, which breaks the single Dart writer unless samples are sent to the main isolate (which may be dead); needs Kotlin 2.2.20+ and Gradle 8.11.1+ (toolchain UNKNOWN); battery-exemption helper is a Play policy risk (Study 5.7) |
| `flutter_background_service` | last update "22 months ago"; no verified type list |
| `flutter_background_geolocation` | commercial licence for release builds; paid dependency is an operator decision |

Fallback (PROPOSED): an own thin Kotlin foreground service plus `FusedLocationProviderClient` behind the same `LocationSource` interface (lane R2 owns the native files, path UNKNOWN), chosen if any of these holds: the plugin does not resolve against the pinned toolchain; the merged manifest does not show `foregroundServiceType="location"` on the service; test T1 or T2 fails. Cost: Kotlin code, a native reviewer and a native test strategy (Study 6 table). Because the interface is the same, the pipeline, journal and state machine do not change.

First steps of lane R1/R2 before any code (retro rule: verify design statements against files): (1) run dependency resolution for the candidate against Flutter 3.27.1 / Dart 3.6.0 and pin the newest line that resolves (the same trap hit `mobile_scanner`, `pubspec.yaml` lines 60-65); (2) read the plugin's own manifest and source for the service type, notification channel and what happens when the Activity is destroyed; (3) read the `permission_handler` page for the separate background step (Study 6 notes: UNKNOWN); (4) re-confirm every package claim of this section (version, "19 days ago", Flutter Favorite, compileSdk 35, wake-lock and notification options) against the version that actually resolves, because they were read from package pages for another version (ARCH14); (5) record what the plugin does when the Activity is destroyed and whether its notification supports actions (feeds 5.5, 5.6 and D-20).

DECISION NEEDED (D-1): primary package. Option A (recommended): `geolocator`, accepting that Dart lives in the UI engine, so a destroyed Activity may stop delivery. Option B: own Kotlin service from the start (more control, more cost). Option C: paid package (no). What changes: A is cheapest and keeps one writer; B is the answer if T2 (swipe-away) shows the service surviving while Dart does not and the product wants continued recording. The honest promise of 4.6 holds for A and B. Option A is acceptable ONLY IF T2 shows one of two outcomes: the service stops with the engine, or the notification stops saying Recording when the engine detaches (5.6, S04-R-058); a service that keeps a "Recording" notification while nothing is journaled is a user-visible false claim, and then option B (or a service that stops itself) is required. T2 gates option A.

### 2.4 Manifest and Play surface (design for lane R2; Study section 2)

Added entries (INFERENCE checklist from Study 2.1-2.4): `FOREGROUND_SERVICE`, `FOREGROUND_SERVICE_LOCATION`, `ACCESS_FINE_LOCATION`, `ACCESS_COARSE_LOCATION`; one `<service android:foregroundServiceType="location" android:exported="false">` if the plugin does not declare it (UNKNOWN until step 2 above). `POST_NOTIFICATIONS` already exists (FACT, manifest line 7), so notification permission is a runtime request only. NOT added: `ACCESS_BACKGROUND_LOCATION` (option A of Q1, default), `ACTIVITY_RECOGNITION`, battery-optimisation exemption. The comment block at manifest lines 30-35 is updated to list the new permissions together with the privacy text and the Play declarations, in the same commit. A test compares declared location permissions with the approved list (S04-R-022, S04-R-050).

DECISION NEEDED (D-2): background location. Option A (default, Study Q1 option A): not used; service is started only from a visible screen at a Start tap; no unattended restart after a kill; smaller Play declaration (one foreground-service declaration, no background form). Option B: request `ACCESS_BACKGROUND_LOCATION` at the first recording; restart after kill becomes possible (Study 3.8) but the Play background form, a 30 s video, the prominent disclosure dialog and the reminder notification apply (Study 4.3-4.6), lane R10 is built, and the second consent row is written. Waits for device test T1 and Play support answer for Study 4.11 (UNKNOWN).

Flag gating (X8, decision D-17 now option B, ARCH11, SEC9): the location and foreground-service entries are declared only in a build with `GPS_RECORDER=true`, through a flag-specific source set or manifest overlay (exact Gradle mechanism UNKNOWN, first step of lane R2). A plugin normally merges its own permissions into EVERY build; the main manifest therefore needs explicit removal markers (`tools:node="remove"`) for any location or foreground-service entry the plugin injects, re-added by the flag overlay. Hence the order: resolve the dependency and read the MERGED manifest of a flag-off and a flag-on build first (E8); only then write the overlay. The manifest-equality test (S04-R-022, S04-R-050) runs on both merged manifests: flag off declares NO location and NO foreground-service entry; flag on declares exactly the approved list (GPS-PRIV-011 "declared set equals used set").

### 2.5 Isolate boundary and the single writer

Rule: the main isolate is the only isolate that touches the recording or activity directories (S02 design line 452; `JournalMutex` is per object in one isolate, FACT `journal_models.dart` 284-295, so cross-isolate writers would not be serialised: UNKNOWN whether it could be made to be, and not needed here). Worker isolates run pure functions on bytes and return bytes.

| Work | Where | Why |
|---|---|---|
| Receive a fix, gate, gap, auto-pause, incremental distance and pace, append to the batch buffer, update live state | main isolate, O(1) per fix | per-fix cost is a few arithmetic operations; no full-session pass (S04-R-041) |
| Append a batch: encode, seal one frame, `openWrite(append)`, write, fsync | main isolate, async I/O, serialised by the journal's own lock | batch is at most 10 fixes (about 0.5 KB); the encode is tiny |
| Seal, full-session smoothing, calculators, build streams, JSON encode, gzip, SHA-256, AES-GCM seal of the final streams | worker via `HeavyWorkRunner` (`Isolate.run`) | 100 000 samples (about 28 h at 1 Hz) must not drop a frame (S04-R-041, S04-R-042, Readiness G10) |
| Read all segments of an unsealed journal for recovery | bytes read on main (async), decode and verify in the worker | same |
| `ActivityJournal.put` file steps (generation directory, rename, COMMIT) | main isolate under the S02 mutex | single writer |

Change to S02 code (lane R5, "isolate move" story): the CPU part of `FileActivityJournal.put` (lines 194-235: `jsonEncode`, `gzip`, `sha256`, `seal`) moves into one pure top-level function that runs through `HeavyWorkRunner`; file steps and mutex stay where they are. Gated and content-preserving (ARCH7): the PLAINTEXT stream bytes and `streamsPlainHash` (a hash of the plain bytes, FACT `file_activity_journal.dart` lines 201-208, 217) are identical to today's; the SEALED bytes are not identical, because every AES-GCM seal uses a fresh IV, so tests compare decrypted plaintext and the stored hash, never ciphertext (the earlier "bytes are identical" claim is withdrawn). The worker path is used only when `GPS_RECORDER` is on AND the session is above a size threshold (PROPOSED 2 000 samples); with the flag off, or below the threshold, the code path is exactly today's inline path, so S02 behaviour is unchanged for every user of S02 alone. A worker failure maps to the same typed failure as the inline path. The existing S02 journal tests must pass unchanged with the flag off, plus one equality test (inline versus worker: same plaintext, same hash) with the flag on. The AES key is read on the main isolate and passed to the worker as bytes; it is never logged. Data crossing the boundary is `TransferableTypedData` or plain lists; no object with a closure crosses it. Memory: the finalizer holds the decoded session once; PROPOSED ceiling 100 MB extra (S04-R-042), UNMEASURED.

### 2.6 Device tests that decide open points (NOT_RUN, lane R11 records results)

| Id | Test | Decides |
|---|---|---|
| T1 | 60 min walk, screen off, service started from the visible app, no background permission; fixes continue | D-2 option A, S04-R-001 |
| T2 | during recording: swipe away from recents; `adb shell cmd activity stop-app PACKAGE` (Study 5.8); `adb shell am kill` (Req S04-R-015); observe notification, process, journal | D-1, the promise in 4.6 |
| T3 | revoke location in system settings while recording; observe whether the app learns, how fast, whether the process restarts (Study 3.9, GPS-PRIV-008) | 6.1 revocation watchdog |
| T4 | notification permission denied: does the service keep running (Study 3.12) | D-5 |
| T5 | `dumpsys deviceidle force-idle` and `am set-inactive` during auto-pause (Study section 7 item 9) | sampling during stationary pause |
| T6 | 100k-sample seal and open on the phone | S04-R-042 |

## 3. Sample pipeline (lane R3, pure Dart)

All constants live in one file `pipeline/recording_constants.dart` (PROPOSED names), each marked PROPOSED, each overridable only in tests. Every number below is a Req PROPOSED number unless stated; none is measured.

### 3.1 Sampling (S04-R-006)

Request one fix per second while recording or auto-paused; 5 s at battery critical (S04-R-030). Higher rates are not allowed for diagnostics (GPS-PRIV-003). Priority is high accuracy; min-distance and batching are NOT set (Study 6.5: no official recommendation; UNKNOWN, measured in T-battery). The adapter, not the pipeline, applies the interval.

### 3.2 Fields (S04-R-007)

A journaled fix holds: offset ms from recording start, lat, lon, accuracy m, altitude m (optional), provider speed m/s (optional). Bearing, provider name, satellite count and device ids are dropped in the adapter, before the pipeline sees the fix. Offset = fix time minus start time; a fix whose offset is not strictly greater than the last kept offset is dropped and counted (clock jumps; matches `SampleStream.validate`, FACT `sample_stream.dart` lines 73-77). Mapping to `ActivitySession`: lats, lons, accuracies into the gps stream; altitude into an altitude stream; provider speed into a speed stream; each with `sourceId = kNativeSourceId` (`'app'`). Streams omit a kind that has no value at all.

### 3.3 Accuracy gate (S04-R-008)

Keep a fix only if: lat in -90..90 and lon in -180..180 and both finite; accuracy present, finite and at most 30.0 m (30.0 kept, 30.1 rejected); implied speed from the previous kept fix at most 30 m/s. Rejected fixes are not journaled; four counters are kept (accuracy, speed, invalid, non-monotonic) and appear only as integers in a batch frame and in logs. The first fix after start has no previous fix and passes the speed rule. Bad-anchor recovery (TP-S04-1): if one wrong fix passes the gate (for example a jump with a good reported accuracy), every later good fix would fail the speed rule against it. So after 5 consecutive fixes rejected ONLY by the speed rule, or 30 s of such speed-only rejections (both PROPOSED), the gate drops the anchor, re-anchors on the best-accuracy fix among the rejected ones that have accuracy of 30 m or better (Y9; none qualifies: no re-anchor yet), journals that anchor fix, and writes ONE `gapStart`/`gapEnd` pair around the break, or reuses the gap that 3.4 already opened (no distance across it) and counts the event in the speed counter. The wrong anchor fix that was already journaled stays (raw data is never edited, S04-R-010); smoothing and distance treat it as inside the segment that the gap closes. Replay fixture F-jump gets a variant with a bad anchor.

### 3.4 Acquiring, poor accuracy and gaps (S04-R-009)

`acquiring` lasts from Start to the first kept fix. If no fix is kept for 10 consecutive seconds during recording, the flag `poorAccuracy` is set and a `gapStart` event with the last kept offset is journaled; the flag clears on the next kept fix, which journals `gapEnd`. Distance is never interpolated across a gap. Gap time counts as moving time (PROPOSED; DECISION NEEDED D-8 below).

### 3.5 Smoothing (S04-R-010, S04-R-011)

Raw gate-passed fixes are journaled; smoothing is derived (S04-R-010). PROPOSED algorithm id `smooth-wma5-1`: a centred weighted moving average over 5 kept fixes inside one continuous segment (weights 1/accuracy squared), each smoothed point clamped to at most 15 m from its raw position; segment ends use a shorter window; segments are split at gaps and pauses. Live metrics use the same strategy with a lag of 2 fixes; the FINAL values are computed once by the worker over the whole session and are the stored ones (the live number may differ slightly from the final: stated in the UI contract, not hidden). Interface: `SmoothingStrategy.smooth(List<Fix>) -> List<Fix>`; the algorithm id is written into `formulaVersion` of the session. Fallback if fixtures F-noise-line and F-turns fail the 3 % and 15 m limits: a constant-velocity Kalman filter in a local plane. The replay fixtures decide, not opinion.

### 3.6 Auto-pause (S04-R-012, S04-R-013)

State machine `AutoPause` fed with kept fixes (speed = provider speed if present, else implied from the two last fixes): enter `pausedAuto` when speed stays below 0.5 m/s for 8 s; leave when at least 1.0 m/s for 3 s. Auto-pause default on for walk, run and ride; user can switch it off (the setting is copied into the journal meta at start). While `pausedAuto` the location subscription stays (needed to detect resume) and fixes are journaled; pause and resume are journaled as events with offsets, and the finalizer uses the events as truth rather than recomputing them. Manual pause (S04-R-013, S04-R-057, X5): the subscription stays (needed to detect nothing else than liveness and to resume fast) but at a REDUCED interval of 10 s (PROPOSED, `setInterval`, 2.2); fixes are NOT journaled (least data; PROPOSED), offsets keep running, a `pause` and a `resume` event are journaled. After 30 minutes of manual pause (PROPOSED) the recorder raises a prompt (a non-ongoing notification and the banner text of S04-D) asking to resume or finish; the pause hint says that location stays on while paused. The interval returns to normal at resume. A manual pause suppresses auto rules; resume returns to the prior moving state. The 10 s interval and the 30 min prompt are constants in `recording_constants.dart` with replay-test rows (12.1).

### 3.7 Calculators (S04-R-032..034)

| Metric | Rule |
|---|---|
| Distance | sum of great-circle (haversine, mean Earth radius 6 371 008.8 m) segments between consecutive smoothed kept fixes inside one moving segment; no distance across a gap, a manual pause or an auto-pause interval. Sphere versus ellipsoid difference is up to about 0.5 percent (INFERENCE, general geodesy, not from the sources); the 2 percent surveyed-route tolerance absorbs it and synthetic fixtures define "true length" with the same model |
| Moving time | elapsed minus manual and auto pause time (within 1 s) |
| Current pace | trailing 10 s of moving time; undefined (`null`) when moving distance under 10 m |
| Average pace and speed | distance over moving time; undefined when moving time is 0 |
| Ascent, descent | altitude outlier rule first (TP-S04-6): a 5-sample running median over kept altitudes, then any step above 10 m between consecutive medians in 1 s is treated as an outlier and ignored (both PROPOSED, fixture F-climb gets a spike variant); then altitude hysteresis 3 m from the last counted extreme; no barometer in S04 (Req Q2); absent altitude gives undefined, not 0. GPS altitude datum offset cancels in differences (INFERENCE) |

### 3.8 Summary (S04-R-036)

At finish the worker fills `ActivitySummary` (`distanceM`, `ascentM`, `descentM`, `avgSpeedMps`), `movingTimeS`, `startUtc`, `endUtc`, `formulaVersion` (the smoothing/calculator id, at most 32 characters, FACT `kMaxVersionStringLength` in `activity_versions.dart` line 17) and keeps `metricDefinitionVersion` from the S02 constant. A value outside the S02 bounds is rejected and the session is flagged, not written clamped (Req S04-R-036). Note: `SummaryProjection.derive` reads these same summary fields (FACT `summary_projection.dart` lines 60-80), so the recorder values become the "raw derivation" the S02 sync layer compares against; changing the formula id later is therefore a version change that S02 reconciliation understands (INFERENCE, S02 design 3.2 rule 2; the exact reconcile behaviour for a recorder-written record was not tested here, UNKNOWN).

## 4. Recording journal, seal, hand-off and recovery (lane R5)

### 4.1 Why a second journal, and how it relates to S02 (Readiness G3)

FACT: `ActivityJournal.put` writes the whole session as one new generation (gzip plus AES of all streams, new directory, COMMIT rename) and an identical re-put is a no-op (`file_activity_journal.dart` lines 173-250). Appending one second of data through `put` would re-encode the entire track every flush: for a 1 h run flushed every 5 s that is 720 full rewrites of up to 3 600 samples, and for 100 000 samples each rewrite is megabytes (INFERENCE from the code, not measured). So the permanent store cannot be the crash-safe append path. This matches GPS-PRIV-014 and S02 DQ-11: the recording journal is distinct from the permanent store.

Decision (PROPOSED, DECISION NEEDED D-3 for the architect): add a sibling append-only `RecordingJournal` in the repository layer (lane R5), under the same account scope, using the same `JournalFileSystem`, `AesGcmJournalCipher` and key provider. It is "the S02 repository writer" in the sense of S04-R-014: the recorder state and pipeline never call file APIs (a source-scan test enforces this); the journal object is the only writer of its directory, serialised by its own lock (the same `JournalMutex` class). Options in words: A (chosen) a separate `RecordingJournal` interface next to `ActivityJournal`, no change to the S02 interface or its fakes; B add `appendSamples` to `ActivityJournal` (every fake and `UidScopedActivityJournal` change; ties S04 to an S02 interface break); C append through `put` (rejected, cost above). Option A needs small, listed S02 touches: the account wipe and its ordering (4.7), the isolate move (2.5, gated) and the sign-out guard (7.3); all are in the lane table 13.1.

### 4.2 Layout and frame format (S04-R-007, S04-R-014, S04-R-015)

Location: `<support>/activity_journal/<scopeId>/recording/<recordingUuid>/` (PROPOSED). It sits under the scope root that the backup rules already exclude (FACT `journal_layout.dart` 18, 41-46; XML files list `activity_journal`), so no XML change is required; a test walks the real tree (retro rule 9). Contents:

| File | Content | Write rule |
|---|---|---|
| `meta.json` | schema version, recordingUuid, startUtc, utcOffsetMinutes, sport, auto-pause setting, constants snapshot (gate, gap, smoothing ids), app build id, `ownerScopeId` and `ownerUid` captured at `begin()` (X2) | temp file, fsync, rename; written BEFORE the first sample; sealed with the cipher |
| `seg-0001.log`, `seg-0002.log`, ... | append-only frames | `openWrite(append: true)`; a new segment is opened at start, at every resume after a restart, and every 5 000 frames |
| `SEALED` | cipher-sealed (authenticated, not a bare marker; ARCH5) payload: sample count, frame count, last offset, stop reason, `importedAt` (UTC, fixed once here), last segment number | temp file, fsync, rename; written last. Recovery decrypts it and checks the counts against the log; a mismatch is `recoveryFailed`, never a silent hand-off |
| `QUARANTINED` | cipher-sealed marker with the quarantine date (X3, 4.5) | temp file, fsync, rename; written only on the user's Keep choice for a `recoveryFailed` recording (Y1: Keep on a revoked recording hands off instead) |

Frame (PROPOSED): 4-byte length, 4-byte CRC-32 of the sealed payload, sealed payload (one `AesGcmJournalCipher.seal` of the plain payload; overhead is the cipher's magic, IV and tag, constants in `journal_cipher.dart`). Plain payload: UTF-8 JSON with `type` in {`samples`, `event`} and a frame counter; `samples` holds columns `t, la, lo, ac, al, sp` (al and sp may be null per sample) plus the four integer reject counters; `event` holds kind in {`pause`, `resume`, `autoPause`, `autoResume`, `gapStart`, `gapEnd`, `permissionRevoked`, `batteryCritical`, `stoppedBattery`, `stoppedStorage`, `stoppedAccount`, `stoppedConsent`, `stoppedCap`, `restart`, `segmentBreak`} and an offset. No frame holds a place name, device id or heart rate. A schema test rejects any extra field (S04-R-007). Compact JSON keeps the frame equal to the `SampleStream` shape; if the 100k seal budget fails (T6) a binary column format replaces it behind the same codec interface (PROPOSED).

Reading: a frame with short length, bad CRC or failed decrypt ends the readable log; everything before it is valid, the torn tail is dropped, never half-read (S04-R-015). The journal never appends to a segment it did not close cleanly: after a restart it opens the next segment (the file seam has no truncate: FACT). The same holds after ANY write or fsync error inside a run (ARCH4): a short write that is followed by a successful retry would otherwise leave a torn frame in the MIDDLE of a segment, and every later frame would be unreadable. So the first error closes the segment as suspect, the retry (and the in-memory fixes of 4.8) goes to a NEW segment, and a torn frame can only be the last frame of its segment. Torn-tail rule per segment: the reader applies it to each segment on its own. Choice made (TP-S04-7, TP-S04-9): a shortened track is NEVER presented as complete and there is no "partial" offer. Only ONE damage is tolerated silently, a torn tail: an incomplete last frame at the end of the LAST segment (a kill during a write). A torn end of an earlier segment is legitimate only when the first frame of the next segment is a `segmentBreak` event (in the event list above; Y7: it is the FIRST frame of every segment after an unclean close, that is after a resume, a seal-after-kill and a write-error rotation; a duplicate frame counter keeps the first occurrence) that names the previous segment and the number of valid frames it held, so the reader can check the count; an unannounced torn end is damage. Segments must be numbered without gaps from 1 to the last number (the last number is also in `SEALED` for sealed recordings), and frame counters must be consecutive. Any other damage (a bad frame followed by more bytes in the same segment, a missing or unreadable middle segment, a counter gap, a break whose count does not match) sends the recording to `recoveryFailed`: files untouched, Keep (quarantine) or Delete only, no track shown (4.5). Mutations through the journal: `begin(meta)`, `appendSamples(batch)`, `appendEvent(event)`, `seal(summaryInfo)`, `readAll()`, `listUnfinished()`, `delete(recordingUuid)`. Failures map to the existing typed errors (`JournalStorageFullException`, `JournalKeyUnavailable`, `JournalIoException`, FACT `journal_errors.dart`).

### 4.3 Seal and hand-off at stop (S04-R-018)

Ordered steps (retro rule 2: ordered writes; each step is a fault-injection point and a test row):

1. Stop: release the subscription, flush the open batch (frame fsync), cancel timers.
2. Append event `stop` (or the stop reason) and write `SEALED` (authenticated payload of 4.2, carrying the stop reason and `importedAt`, both fixed here and read back later, never recomputed). After this point the recording is complete and immutable. Crash gap between the stop event and `SEALED`: recovery sees a log whose last frame is a stop event and no `SEALED`; it re-seals using that event's reason and a fresh `importedAt` written once into `SEALED`, so every later repeat reuses it.
3. Read all segments (main isolate), send bytes to the worker. Worker decodes, verifies frames, runs smoothing and calculators, builds `ActivitySession` (id `nativeActivityId(recordingUuid)`, provenance `nativeSourceRecord(recordingUuid, importedAt)` with the `importedAt` from `SEALED`, so a repeat after a crash builds an identical record and the put stays a no-op, sport, streams gps/altitude/speed, summary, `movingTimeS`, versions) and the sealed stream bytes.
4. Owner check (X2, ARCH1, SEC1): immediately before the put, the hand-off confirms that the bound S02 scope equals the `ownerScopeId` in `meta.json`, that the scope is still bound and that it is not wiped (the `_wipedUid` marker of `UidScopedActivityJournal`, FACT `uid_scoped_activity_journal.dart` lines 83-86, 150-155). On any mismatch it writes NOTHING, keeps the recording and reports `handOffDeferred`. Then the main isolate calls `ActivityJournal.put(session)`. It completes only after the COMMIT rename (FACT, `activity_journal.dart` lines 18-21). Because the id is derived from the recording uuid, a repeat after a crash is an idempotent upsert (FACT `native_session_id.dart` lines 1-11).
5. Verify with `ActivityJournal.read(id)` (entry exists, not `streamLost`). Tombstone outcome: if the user deleted that activity from the S02 store after step 4 (a tombstone for the id exists, `listTombstones`, FACT `uid_scoped_activity_journal.dart` line 188), the outcome is `tombstoned`: step 6 still runs and the activity is NOT re-created by a later retry.
6. Clean up the recording after a verified hand-off with the same file order as Discard (Y8, K8) but WITHOUT a `DISCARDING` marker, because `DISCARDING` belongs only to the DELETE path and the recovery table below quarantines `DISCARDING` next to `KEEP` or next to no decision: segments, then `SEALED`, then `meta.json` LAST, then `DECISION` (if any) with the directory. A crash inside this step leaves a directory whose derived activity id already exists in the S02 store; the next start finishes the cleanup silently and never offers it (the deterministic id makes this check exact). Z13: this is the second of exactly TWO cases in which a `DECISION` disappears, always together with its WHOLE recording directory; it runs only AFTER the hand-off is verified (the S02 repository holds the activity with the deterministic id for the pinned owner, step 5), so the recording is no longer actionable and the cleanup can neither authorize an opposite decision nor invalidate a live writer (the writer has already returned). Crash during KEEP cleanup: recovery sees `DECISION=KEEP` without `DISCARDING` (a partially removed directory included), repeats the idempotent hand-off check and finishes the cleanup. Tests: completed KEEP cleanup, and crash and restart during it.
7. Bump `activityJournalRevisionProvider` (FACT seam, `activity_dashboard_providers.dart` 79-82) so dashboards reload.

Crash analysis: before step 4 completes only the recording journal exists; after step 4 and before step 6 both exist; never neither (S04-R-018 AC). On the next start a recording with `SEALED` whose activity id already exists in the S02 journal is silently finished by deleting the recording directory after step 5 passes; one without a stored activity is re-run from step 3. A `put` failure (storage full, key unavailable) leaves the recording journal in place and the user sees "could not save, your recording is kept" with retry (the recorder never claims saved). The session is never written clamped; a value outside bounds yields a flagged session or a save failure shown to the user (Req S04-R-036). Every step from 2 to 6 carries the owner check of step 4 (a lost scope makes the step a no-op that keeps the recording).

Revocation sequence (Z2, canonical for S04-R-024, S04-19 AC-2, 5.1, 5.2, F2 and the contract): (a) on revocation collection stops (`releaseAll()`); (b) steps 1 and 2 above run: the partial recording is durably SEALED in the recording journal with stop reason `revoked`; this is the pending-decision state, it is listed by `listUnfinished()` as pending, it does not block Start (5.4) and it survives a kill; (c) Keep first writes the durable `DECISION=KEEP` marker (below), then runs steps 3 to 7 (ordered, idempotent, owner-checked S02 hand-off), so the S02 hand-off happens on Keep and not at revocation; (d) Delete first publishes `DECISION=DELETE` (the plain `DISCARDING` marker of 4.5 is NOT this decision; it is written only after `DECISION=DELETE` is durable), then runs the ordered delete and the recording is never resurrected.

Decision rule for a pending-decision recording (Z5): Keep and Delete are mutually exclusive and the FIRST durable decision wins. Arbitration (Z7, replaces the temp-file-and-rename wording of Z5, because a rename may replace an existing target and two callers that both saw "absent" could both publish): there is ONE authoritative file per recording, named `DECISION`, created ONLY by an EXCLUSIVE create-if-absent (Dart `File.create(exclusive: true)`, native `O_CREAT|O_EXCL` / `Files.createFile`; never rename-over). Keep and Delete use the SAME operation. Publication rule (Z10, the single rule): `DECISION` is published WHOLE, never visible empty. The winner writes the token `KEEP` or `DELETE` into a temp file, fsyncs it, publishes it with an EXCLUSIVE HARD-LINK create (native `Files.createLink` or the equivalent create-if-absent link; it fails if `DECISION` exists), then fsyncs the PARENT directory and deletes the temp file. If the platform cannot hard-link, the fallback is an exclusive create followed by the write, permitted ONLY because the journal directory lock is a PROCESS-WIDE EXCLUSIVE file lock taken when the journal opens and held for the process lifetime (Z14): a second process or independent runtime instance cannot open the journal (it fails closed with a visible error and records nothing), which makes the recording single-process by construction, so recovery and the writer are always the same process; recovery runs before Keep and Delete are enabled (the actions are gated on `recoveryComplete`) and is never concurrent with a live fallback writer; a startup probe selects hard-link publication as the primary path. A same-process reader that sees an empty file waits (bounded, at most 2 s) instead of acting, then reports "decision in progress, try again" with no irreversible action. A `DECISION` is never unlinked or replaced on its own while the recording is actionable (Z13): it disappears only together with its WHOLE recording directory, in exactly two cases, (a) the completed DELETE execution and (b) KEEP cleanup after the hand-off is verified (step 6 of this section). A removed directory means the recording is no longer actionable, so neither case can authorize an opposite decision or invalidate a live writer. A regression test proves recovery and retrying callers never remove or replace a `DECISION` while its writer can still commit. An empty, truncated or unknown-token `DECISION` found by `listUnfinished()` at recovery (no writer is alive: the journal lock is process-wide and recovery runs before Keep and Delete are enabled) is malformed: the recording is `QUARANTINED` with the user notice, with no deletion and no hand-off; there is no "remove the empty file" variant. The durability boundary is "file fsynced AND parent directory fsynced"; no irreversible action (the S02 `put`, the ordered delete or the `DISCARDING` marker) may start before both have completed (Z12). A per-recording in-process mutex also serializes the two actions, as defence in depth only, not as the arbiter. `DISCARDING` is NOT a second decision: it is the in-progress marker of the DELETE execution and is written only after `DECISION=DELETE` is durable. Malformed or conflicting states (`DISCARDING` without `DECISION=DELETE`; `DECISION=KEEP` together with `DISCARDING`; an empty, truncated or unknown-token `DECISION` found at recovery) cause NO deletion and NO hand-off: the recording is marked `QUARANTINED` with a visible notice. DECISION is the sole authority; `DISCARDING` is never a decision. Every recovery and deletion instruction in this document (4.3, 4.5, 5.2, F2, 12.1) follows the ONE recovery table below, executed by `listUnfinished()` itself (Z9); no sentence deletes a directory because it has `DISCARDING` without first validating `DECISION`. Quarantine applies to `recoveryFailed` (S04-R-017) AND to the invalid decision-state rows of the table; ordinary permission revocation never quarantines (Z11). Test invariant (Z12): no irreversible operation (hand-off `put`, deletion, `DISCARDING`) begins before both durability barriers (file fsync and parent-directory fsync) have completed; a malformed result is handled at recovery by the table, and no test claims what a crash between the two fsyncs leaves behind.

| Durable state | Recovery by `listUnfinished()` |
|---|---|
| no `DECISION`, no `DISCARDING` | pending decision (nothing irreversible happened) |
| `DECISION=KEEP`, no `DISCARDING` | complete the idempotent S02 hand-off (upsert on the deterministic id), then cleanup |
| `DECISION=DELETE`, no `DISCARDING` | resume the ordered delete (write `DISCARDING`, then steps 2-5 of 4.5) |
| `DECISION=DELETE` + `DISCARDING` | complete the ordered delete |
| `DECISION=KEEP` + `DISCARDING` | `QUARANTINED`, no delete, no hand-off, user notice |
| `DISCARDING` without `DECISION=DELETE` | `QUARANTINED`, no delete, no hand-off, user notice |
| `DECISION` empty, truncated or with an unknown token | `QUARANTINED`, no delete, no hand-off, user notice; the file is left in place (Z10, Z13 above) |

A second or replayed action is a no-op that reports "already decided". Once `KEEP` is durable, Delete is not offered for that recording and NEVER removes the S02 activity that the hand-off created (the user may later delete the finished activity through the normal S02 delete flow, a separate action); once `DELETE` is durable, Keep is refused and the delete completes on recovery. Recovery obeys only the `DECISION` winner (Z7): `KEEP` completes the hand-off idempotently (upsert on the deterministic id, a no-op if the activity already exists) and then cleans up with the ordered delete of step 6, which removes only recording-journal files; `DELETE` completes the ordered delete; no marker means pending decision. A kill at any step recovers to the pending-decision state or to the finished activity, never both and never twice (the id is derived from the recording uuid, so a repeat is a no-op).

### 4.4 Flush policy (S04-R-015)

A batch is flushed (encode, seal, append, fsync) when it holds 10 fixes or 5 s have passed since the last flush, whichever is first; at 1 Hz the 5 s rule dominates. At battery critical the interval is 1 s (S04-R-030). Pause, resume, gap and stop events force an immediate flush. An in-memory buffer of at most 600 fixes serves live display (S04-R-043); the full list is never held after a flush.

### 4.5 Recovery after a kill (S04-R-016, S04-R-017, S04-R-039, S04-R-045)

Detection at app start, after the journal for the signed-in uid is bound (availability `open`, FACT `journal_availability.dart`): `RecordingJournal.listUnfinished()` returns recordings without `SEALED`. Journals of another uid are in another scope directory and are never listed (S04-R-045). State `restoring` shows while the worker reads. Outcomes:

| Result | What the user sees |
|---|---|
| Readable, non-empty | offer Resume, Save as finished, Discard, before any other recording can start (the Start action refuses while an unfinished, non-quarantined recording exists). Resume is also refused while the location consent is withdrawn (S04-R-054) |
| Readable but empty (no kept fix) | silent delete, no offer |
| Unreadable (truncated meta, wrong schema, key loss, decrypt failure, `SEALED` that disagrees with the log) | state `recoveryFailed`: files untouched until the user chooses Keep or Delete (X3: no Export in S04). Keep = quarantine: a `QUARANTINED` marker is written, the strip and the Start block clear, the files stay untouched and expire after 30 days (PROPOSED, ordinary scope cleanup; deletion at expiry is the existing owner-only recording deletion). No track shown; copy never claims recovery succeeded |
| Owner scope not bound or wiped (X2) | nothing is read, written or offered; the recording stays in its own scope directory and appears only when that same account is bound again |

Resume: open a new segment, append event `restart` with the offset of resume, continue the same recording uuid; the interval between the last journaled offset and the restart is a PAUSE interval (ARCH13): no distance, no moving time, no interpolation, journaled as a `gapStart`/`gapEnd` pair that the finalizer treats exactly like a pause. If the last event before the kill was a manual `pause`, that pause simply extends to the restart. Resume enters phase `acquiring` (S04-D 5.2 `restoring --> acquiring`), never straight into `recording` or the earlier paused phase, for EVERY origin (recording, manual pause, auto pause; Z1). The pause origin is kept as metadata in the journal (the last `pause`/`autoPause` event and its offset), so the recovered values are preserved, and the interrupted interval adds neither moving time nor distance (the `restart` gap pair). A test recovers from both paused states and asserts phase `acquiring`, the preserved values and the gap pair; because recovered data already exists, a Stop in this recovery-origin `acquiring` goes to `stopping` and seals the recovered data (shown as kept time, S04-D Finish or Discard), never to "nothing recorded" (UX1). Resume needs location permission and a visible screen (Study 2.8); if permission is not granted the Resume choice is disabled with a reason. Save as finished: seal and hand off as in 4.3. Discard (TP-S04-8): ordered delete so a crash never leaves an offerable fragment: (0) obtain the `DELETE` decision by the exclusive create of `DECISION` (4.3, Z7); if the create fails because `KEEP` (or `DELETE`) is already committed, report "already decided" and do nothing (Delete is not offered after Keep, Z5); (1) only after `DECISION=DELETE` is durable (file and parent directory fsynced), write the PLAIN, content-free `DISCARDING` progress marker, which is NOT a second decision (4.3) (no key and no cipher, so Delete still works when the failure was key loss; Y8) (temp file, fsync, rename), (2) delete the segment files, (3) delete `SEALED`/`QUARANTINED` if present, (4) delete `meta.json` LAST, (5) remove the directory. On every start `listUnfinished()` applies the recovery table of 4.3 (Z9) and nothing else: it completes the deletion (steps 2-5) ONLY for `DECISION=DELETE` (with or without `DISCARDING`) and never offers such a directory; a `DISCARDING` without a valid `DECISION=DELETE` is quarantined, not deleted. A file-listing test after a crash injected after each step proves no sample remains and nothing is offered (S04-R-016 AC). The word "recovered" appears only on the success path of a readable journal (S04-R-039); gym timers keep S03D R-S5.

DECISION NEEDED (D-6): how long an unfinished recording is offered (Req question 6). Option A (assumed): until the user chooses; storage grows. Option B: expire after N days (PROPOSED 30) with a notice. And (D-7) a long gap (Req question 7): Option A resume whatever the gap; Option B above 30 min only Save as finished. Defaults A.

### 4.6 The honest promise (S04-R-015)

The only promise (ARCH12): after the app process is killed, or the phone is shut down or restarted in an orderly way after the last fsync, everything recorded up to about 5 s before that moment is kept and offered. Not promised and listed as excluded: a sudden power loss or battery pull (the file system may lose or corrupt unsynced data), continued recording after a kill (Study 5.8, 5.9, 5.12, 3.8 give no basis), storage full, force-stop during the final flush, and the distance travelled while no process ran. Engine-detach rule (S04-R-058): while the Dart side is detached nothing is journaled, so the notification must not say Recording then (5.6). "Survives screen off" may be claimed only after T1. The roadmap DoD "survives app kill and screen off" is read as: journal recovery after kill, and continuity with the screen off; this reading needs the operator to confirm (Study Q2, DECISION NEEDED D-4).

### 4.7 Lifecycle (S04-R-019, S04-R-045)

Account events (X1, ARCH2, SEC2; replaces the old "deleted on sign-out" wording of S04-R-019): only a CONFIRMED DIFFERENT non-null uid, an explicit sign-out or an account-deletion event ends a recording. A transient auth null or a loading state stops nothing and unbinds nothing in the recorder; the owner check of 4.3 refuses writes while the owner scope is not bound, and the 120 s in-memory buffer below absorbs them. Pre-unbind hook (Y2, K2): the hand-off before unbind needs a mechanism, so the bind controller in `activity_wiring.dart` (the single splice of lane R5, Stories 9) awaits ONE registered hook before it unbinds on a sign-out, a uid change or an account deletion, bounded by 5 s (PROPOSED). The hook type is an injected interface `PreUnbindHook { Future<void> run(String ownerUid, UnbindReason reason) }` defined in the repository layer, which therefore never imports the recorder (layering); the recorder registers its implementation at wiring time. The hook runs `releaseAll()`, then stop, seal and hand-off with the owner check of 4.3. The sign-out guard calls the same hook. GPS-PRIV-014 reconciliation (Z3; FACT: the S01 contract line 101 says the recording journal is deleted on sign-out and account deletion; the S01 clarification is PROPOSED text, not an approved obligation): STRICT PATH, the default and the rule kept: an ordinary sign-out hands off first and then deletes the recording journal. FALLBACK, only if the hand-off cannot complete (hook timeout or failure): the unsealed recording stays ENCRYPTED in its own account scope for at most 30 days (PROPOSED) and is deleted on expiry, on account deletion or after recovery; the user is told at sign-out with explicit text, and another account never reads it. Amending the S01 note and the operator question (alternative: strict deletion, accepting silent loss when the hand-off fails) are carried to the privacy contract and `S04_REQUIREMENTS.md`, which this document does not edit. The relaunch path `finishInterruptedWipe` (FACT `account_deletion/data/local_data_wipe.dart` line 117, used with `ActivityAwareLocalDataWipe`) runs WITHOUT a recorder: it must delete `recording/` through the repository-layer wipe alone, which is why the durable marker below lives in the repository layer. Transient null (Y3, K3): the recorder keeps running; appends refused while the scope is unbound go to a bounded in-memory buffer (120 s, PROPOSED) and flush after the SAME uid rebinds; past the bound, or on a different uid, the recording stops with the stop reason `account` (automatic-stop set of 5.5 is unchanged; this stop is visible on screen). The recording journal keeps its OWN durable wiped-uid marker (a content-free file beside the scope root, outside the directories the wipe deletes, written before the S02 wipe step, removed only when a completed wipe is followed by a fresh explicit sign-in); it does not rely on the in-memory `_wipedUid`. Expiry (reconciles D-6): the 30-day expiry applies only to recordings that could not be handed off (this fallback) and to quarantined ones; a readable unfinished recording in the bound scope is offered until the user chooses (D-6 option A); the sweep is run by lane R5's `listUnfinished()` at bind time, not by a scheduler. Account deletion wipes `recording/` AFTER the recorder is shut down (ordering below). The recording directory is deleted after confirmed hand-off, on discard, on Delete in the revoked or recovery-failed flow, on expiry and on account deletion; on an ordinary sign-out it is handed off FIRST and then deleted (strict path, below). Ordering with the S02 wipe (X2, ARCH3): (1) recorder shutdown through `releaseAll()`, (2) the recording journal closes after its in-flight append drains and then refuses every write for that uid (the same wiped-uid refusal as `UidScopedActivityJournal._wipedUid`, FACT lines 83-86), (3) only then the S02 wipe, which also deletes `recording/` and forgets the key. Without step 2 a late append or hand-off `put` after the key was forgotten could resurrect the key and write under a wiped scope. Hazard found in the code: `FileActivityJournal.wipe()` deletes only `journal`, `sources` and `quarantine` and forgets the key (FACT lines 651-666), so a `recording/` directory under the scope root would survive a wipe as undecryptable but present files. Fix (lane R5, story "journal lifecycle"): `JournalPaths` (FACT: it lives in `journal_generation_writer.dart` line 29, which resolves the earlier UNKNOWN) gets a fourth directory `recording`, `wipe()` deletes it, `UidScopedActivityJournal.wipeForUid` runs the ordering above, and a test walks the real tree after wipe (retro rule 9). The S02 files touched are `file_activity_journal.dart`, `journal_layout.dart`, `journal_generation_writer.dart`, `uid_scoped_activity_journal.dart` and `activity_aware_local_data_wipe.dart` (FACT: `ActivityAwareLocalDataWipe.wipe(uid)` line 32); file ownership is the lane table of `S04_STORIES.md` section 9 (Y4, 13.1), not repeated here: R5 owns `file_activity_journal.dart`, `journal_layout.dart`, `journal_generation_writer.dart` and `uid_scoped_activity_journal.dart`; R13 owns `activity_aware_local_data_wipe.dart`, `sign_out_guard.dart` and `sign_out_warning_sheet.dart`. Backup: covered by the existing `activity_journal` exclusion; the test of S03 DT-0-6 style is extended to create a recording and list top-level entries (S04-R-019 AC). The consent keys use prefix `activity.` so the device wipe erases them (6.2).

### 4.8 Storage full (S04-R-020, SHOULD)

Free space is not read through a package (none declared; UNKNOWN whether `path_provider` or `dart:io` gives it): the 20 MB warning (PROPOSED) needs a source; DECISION NEEDED (D-9): option A use only write failures (`isDiskFull`, FACT `journal_file_system.dart` 154-166) and skip the early warning; option B add a free-space read through a small native call. On a failed append the recorder keeps fixes in memory for up to 60 s (PROPOSED), retrying each flush; if still failing it stops, writes the stop reason `stoppedStorage` if it can, and shows a visible reason on screen AND posts the separate automatic-stop notification of 5.5 (S04-R-056). The retry after a failed append goes to a new segment (4.2). Memory cap during this window: 600 fixes plus the batch (PROPOSED).

## 5. State machine (lane R4)

### 5.1 Phases and condition flags

Req S04-R-004 lists 13 states that overlap (for example background plus poor accuracy). To keep the transition table finite and testable, the model has ONE phase and independent flags (PROPOSED):

| Phase (exactly one) | Meaning |
|---|---|
| `idle` | no recording, no subscription |
| `preparing` | permission and consent checks, service start in progress |
| `acquiring` | subscription open, no kept fix yet |
| `recording` | moving, fixes kept |
| `pausedManual` | user paused; subscription stays |
| `pausedAuto` | auto-pause; subscription stays |
| `stopping` | flush, seal, hand-off running |
| `restoring` | reading an unfinished recording after a kill |
| `recoveryFailed` | unreadable journal, waiting for user choice |
| `finished` | hand-off done (terminal until the screen is left) |
| `permissionRevoked` | permission revoked; collection stopped; Keep (seal and hand off as a finished partial activity, Y1) or Delete offered, no Export (X3) |

Flags (independent booleans): `poorAccuracy`, `offline`, `background` (app not visible), `batteryCritical`. The 13 state names of S04-D 5.1 (`idle, acquiring, recording, poorAccuracy, offline, pausedManual, pausedAuto, background, restoring, recoveryFailed, batteryCritical, permissionRevoked, finished`) are a projection `displayState(phase, flags)` that returns three channels, as S04-D 5.3 defines them (ARCH9; D-10 is closed by adopting that order): HEADLINE (highest first) `permissionRevoked, recoveryFailed, restoring, pausedManual, pausedAuto, acquiring, poorAccuracy, recording`; BANNER (at most one) storage write failing, `batteryCritical`, notification off (variant only); CHIPS (at most two) `offline`, `background`. Consequences for the flags: `poorAccuracy` can be true only while the phase is `recording` (S04-D 5.1; the 10 s no-fix rule of 3.4 runs only in `recording`, is cleared on entering any pause phase and is not evaluated in `acquiring`, which has its own headline); `batteryCritical` may be true in `acquiring`, `recording` and both pause phases, with exit at charging or 12 percent (S04-D 5.2, hysteresis PROPOSED); `offline` and `background` never change the headline. Source of `offline` (TP-S04-14): FACT, no connectivity package is declared (2.0 Dependencies) and recording needs no network, so there is NO grounded source; the chip is UNGROUNDED in S04. Options: A (default) the flag is never set and the chip is not shown; B add a maintained connectivity package or platform read behind a seam like `BatteryMonitor` (needs the Study's minimum-evidence check first). `background` comes from the app lifecycle observer, which is grounded. Tests for `offline` use a fake source only if B is chosen. The two internal phases `preparing` and `stopping` have no S04-D name: `preparing` projects to `idle` with a busy label and, after the timeout of 5.4, to the `startFailed` panel of S04-D; `stopping` projects to the previous headline with a busy label. If S04-D changes any order in its own fix pass, the projection is one pure function in one file and the table test of S04-R-004 changes with it.

### 5.2 Legal phase transitions (S04-R-004 AC: table test over every pair)

| From | To (legal) | Event |
|---|---|---|
| idle | preparing | Start tap |
| idle | restoring | app start finds unfinished recording |
| preparing | acquiring; idle | checks pass and service started; refused or cancelled |
| acquiring | recording; stopping; idle; permissionRevoked | first kept fix; Stop (with recovered data or a kept fix: `stopping`, never discards, UX1); Stop with nothing recorded (`idle`, nothing saved, S04-D 5.2); permission lost |
| recording | pausedManual; pausedAuto; stopping; idle; permissionRevoked | Pause; auto rule; Stop or battery auto-finish; Discard (confirmed, 4.5 ordered delete); permission lost |
| pausedManual | recording; stopping; idle; permissionRevoked | Resume; Stop; Discard; permission lost |
| pausedAuto | recording; pausedManual; stopping; idle; permissionRevoked | auto resume; Pause; Stop; Discard; permission lost |
| stopping | finished; idle (hand-off failed, recording kept, offered again) | hand-off result |
| restoring | acquiring (Resume, after the Start preconditions of 5.4 including consent not withdrawn); stopping (Save as finished); idle (Discard); recoveryFailed | user choice or read result |
| recoveryFailed | idle | Keep (quarantine) or Delete chosen (X3, no Export) |
| permissionRevoked | stopping (Keep: durable `KEEP` decision, then S02 hand-off of the already sealed recording, then finished); idle (Delete: durable `DELETE` decision, then ordered delete); the exclusive create of `DECISION` arbitrates, the first creator wins and a later opposite choice is refused with "already decided" (Z5, Z7, 4.3) | user choice (Y1, Z2; the recording is already durably SEALED, 4.3; quarantine applies to `recoveryFailed` and to invalid decision states only, never to plain revocation, Z11) |
| finished | idle | screen left |

Mapping of design phases to the 13 display names of S04-D 5.1 (TP-S04-3): `idle`, `acquiring`, `recording`, `pausedManual`, `pausedAuto`, `restoring`, `recoveryFailed`, `permissionRevoked`, `finished` map to themselves; `poorAccuracy` = flag on phase `recording`; `offline`, `background`, `batteryCritical` = flags; `preparing` = display `idle` plus a busy label (then `cannotStart`/`startFailed` panels, 5.4); `stopping` = the display name of the phase it came from plus a busy label (`finished` follows on success). The phase and the display state are both named `permissionRevoked`; no other name for it is used (the older internal name is retired, Z2). Diagram alignment: S04-D 5.2 draws Discard as `recording/pausedManual/pausedAuto -> idle`; this table now has the same edges, and the Finish edge `-> finished` passes through `stopping` here. A test compares the display list with the S04-D list (S04-R-004).

Every other pair is undefined and the test fails on any transition not in this table. Manual pause suppresses auto rules (S04-R-013).

### 5.3 Start and stop paths (S04-R-001, S04-R-002, S04-R-003)

Start (only from a user tap while the app is visible; no code path starts from boot, launch, push or a notification, tested by a source scan of call sites): consent check, permission flow (6.1), notification permission, write `meta.json`, start the foreground service through the adapter, open the subscription, phase `acquiring`. Stop: one function `releaseAll()` in a `finally`: cancel subscription, stop the service and notification, cancel timers, flush; subscription count must be 0 within 2 s (fake time) of the action. Stop, discard, permission loss, battery auto-finish and sign-out all call it. Account switch while recording: see 4.7 and 7.3.

### 5.4 Start preconditions (S04-R-055, X7, ARCH8)

`requestStart()` (the one entry of 7.3) begins phase `preparing` and proceeds only when ALL hold; any failure keeps phase `idle` and sets a visible reason code (no silent no-op):
1. The activity journal availability is `open` for the signed-in uid (FACT `journal_availability.dart`: `JournalOpen.ownerUid`); `binding`, `gaveUp`, `failedToOpen` and `notEnabled` give the visible "cannot start" panel.
2. The unfinished-recording check (`RecordingJournal.listUnfinished()` for that scope) has COMPLETED; while it runs the panel says "preparing". A recording found makes Start refuse with the recovery offer (4.5). Quarantined recordings and a recording in phase `permissionRevoked` that waits for the user's Keep or Delete choice do not block (Y1, C1).
3. Location consent granted and not withdrawn (6.2); system permission granted precise (6.1); notification permission per D-5.
4. No gym timer of the same account is running (S04-D SH-4: the Record pill hides while a gym strip shows; the controller enforces the same rule so the keyboard shortcut and any other opener cannot bypass it; reason code `gymTimerRunning`).
5. No foreign-account session (`activeSessionForeignOwnerProvider`).
6. `meta.json` written and `begin()` succeeded (the key is available, F6).
One timeout set (Y5, K5), all PROPOSED and all constants in `recording_constants.dart`: `preparing` becomes the `cannotStart` panel after 5 s; after the service-start call the `startFailed` panel (Try again) appears after 15 s counted FROM THAT CALL, and `releaseAll()` cancels the attempt; the tap never hangs. Other timers in this design: pre-unbind hook 5 s (4.7), transient-null buffer 120 s (4.7), storage retry 60 s (4.8), engine-detach grace 60 s (5.6), manual-pause prompt 30 min (3.6), expiry 30 days (4.7). The "cannot check" sign-out path keeps "Sign out anyway" with explicit text (the user can always leave, 7.3).

### 5.5 Notification (S04-R-053, S04-R-056, X6, SEC6)

Ongoing recording notification: lock-screen visibility PRIVATE, with a generic PUBLIC version (Y11, S04-R-053). Owner-visible version (unlocked shade): sport, moving time and distance, plus the actions below. Lock-screen public version: generic static text only, with no sport, time, distance, coordinates, pace or account name, and NO action. No version ever contains a coordinate or a pace. A plain tap opens the recording screen with focus on the headline; the Finish... action opens the stop panel and moves focus to its header (one reading, no duplicate announcement; S04-D owns the copy). The `acquiring` phase has its own title text. Actions (private version only): Pause/Resume, and "Finish..." which opens the stop panel and never stops by itself; the actions are exactly these two (TP-S04-4). Whether the plugin's own foreground notification can carry actions is UNKNOWN (2.3 step 5): if not, actions need the Kotlin fallback or are not offered (D-20); the notification text is a log-safe fixed string table, never built from a fix.
The automatic-stop set (Y10, K10; the same set in S04-R-056 and S04-35) is: battery 3 percent, storage, the 190 000-sample cap and consent withdrawal (the account-rebind stop `account` of 4.7 is shown on screen). Each posts a SEPARATE, non-ongoing notification on its own channel with the reason, the saved moving time and distance (owner-visible version; the lock-screen public version is generic). Permission revoked is NOT in this set: it keeps its own normal notification of the same family with existing copy, because a stopped recording must be visible with the screen off (UX2). The same notification is posted when the recovery after a kill cannot start and needs the user (text content-free).

### 5.6 Engine-detach behaviour (S04-R-058, ARCH6)

The main isolate is the only writer (2.5), so when the Flutter engine is detached (Activity destroyed, swipe-away) nothing is journaled even if a foreground service survives. Rule: the notification must never say Recording while no fix is being journaled. Implementation by outcome of device test T2: (a) the service stops with the engine (acceptable; the kill-recovery path of 4.5 applies on the next start); (b) the service survives: the adapter reports `engineDetached`, the notification switches to a fixed "Recording stopped, open the app to continue" text without a time, and the service stops itself after a short grace period (PROPOSED 60 s); (c) own Kotlin service (D-1 option B) may journal natively only after a separate design that keeps one writer. Until T2 runs, option (a) or (b) is assumed and the promise of 4.6 holds.

## 6. Permission and consent state ownership (lanes R1, R8, R7)

### 6.1 Permission flow (S04-R-021..025)

Owner of system permission state: the operating system; the app never caches it across a resume. `PermissionService` is read on demand: at a Start tap, at app resume, at every Nth fix while recording (PROPOSED N = 1, so a revoked permission is seen within 2 s; the call is a cheap method-channel read, cost UNMEASURED) and on any location stream error. The Study found no documented revocation callback (Study 3 closing paragraph: UNKNOWN), so polling is the portable mechanism; test T3 shows whether the process is simply restarted instead (Study 3.9), in which case recovery (4.5) handles it and copy says "interrupted", not "revoked", unless revocation was observed.

Sequence at the first Start (Study 3 suggested order, INFERENCE): pre-prompt (one line: what is recorded, where it is stored, who sees it; text version, DRAFT) -> consent row written (6.2) -> request fine and coarse together (Study 3.2) -> notification permission before the service starts (Study 3.11) -> start service. Outcomes: granted precise; denied once -> screen with Try again and Add manually; permanently denied -> Open settings and Add manually, never re-requested; approximate only -> recording refused with an explanation (accuracy would fail the gate); request count at most 1 per tap, never in a loop. Launch, onboarding and tab switches request nothing (counter test). Notification denied: DECISION NEEDED (D-5, Req question 3): option A refuse recording with a reason; option B record with the persistent notification only in the Task Manager (Study 3.11) if T4 shows the service runs. Default A until T4.

### 6.2 Two consent rows (S04-R-026, S04-R-027)

Owner: `LocationConsentNotifier` in `consent/` (lane R8), storing in SharedPreferences under `activity.locationConsent.v1.<uid>` (PROPOSED key; prefix `activity.` is erased by the existing wipe, FACT `local_data_wipe.dart` line 218). Not the same thing as the cloud-streams consent (`AccountScopedConsentStore` in `activity_wiring.dart`, FACT lines 491-559): names and keys must not collide. Record per purpose `location_while_recording` and `background_location`: purpose, grantedAt (UTC), textVersion, state (granted, withdrawn, none). The second row exists in the schema and is written only if D-2 chooses option B. Ordered writes (retro rule 2): the notifier queues writes so an older write cannot land after a newer one, and it refuses a write if the signed-in uid differs from the remembered uid (the pattern of `TrainingContextNotifier`, S03 design 2.2). Fail closed: if the consent write fails, the system request is not made. Withdrawal surface (S04-R-054, X4, SEC5, UX11): a Settings, Privacy row with ONE withdraw switch (state granted or withdrawn, grant date) and links to the existing export and delete of finished activities. Effects: a withdrawn consent blocks the next Start (5.4) and refuses Resume (4.5); withdrawing DURING a recording stops it, seals and hands it off with the owner check of 4.3 and keeps the data (nothing is deleted by the switch). Re-granting goes through the pre-prompt again (new `grantedAt`). The widget belongs to lane R7, the strings to R8 and the Settings splice to R9 (the Settings page file is UNKNOWN to this design; first step of R9). The text version is read from the string file and compared with the stored one in a test. Start requires BOTH a granted consent row and a granted system permission.

### 6.3 Account ownership (S04-R-045)

Recording journal directories are per scope (hash of uid), so another account's recording is never listed. The recorder captures `ownerUid` and `ownerScopeId` at `begin()` (stored in `meta.json`, 4.2) and pins every step to them (X2): append, seal, hand-off `put`, recovery and delete each re-check that this scope is still bound and not wiped, and otherwise write nothing and keep the recording. Auth transitions follow X1 (4.7): a transient null or loading state changes nothing; a confirmed different non-null uid, an explicit sign-out or an account deletion triggers the sequence of 4.7. The strip and Record entries follow 7.3. Reading note (FACT `activity_wiring.dart` lines 98, 452): the S02 binding already unbinds WITHOUT deleting on a sign-out and returns null for the uid of an account being deleted; the recorder relies on that and adds its own owner check rather than trusting the binding alone.

## 7. Shell integration: prioritised session sources (lanes R6, R9; Readiness G9 and addendum)

### 7.1 Problem (FACT)

`activeSessionStatusProvider` derives from `_activeSessionCoreProvider`, which reads only the set timer and rest timer; `deriveActiveSessionStatus` hard-codes that the set timer wins; there is one `activeSessionOwnerProvider`, written only by the workout page; `ActiveSessionKind` has one value (`active_session_status.dart` lines 65-80, 236-358). The comment "a future source adds an enum value and a producer without changing the strip" does not hold (Readiness addendum). A GPS recording must be visible on every tab, must survive process death through recovery, and must coexist with a gym timer (S04-R-037, S04-R-038).

### 7.2 Design: a prioritised list of sources (PROPOSED; the alternative is a rewrite of the provider, DECISION NEEDED D-11 for the architect, default = list)

- Strip words are those of S04-D 14.1 (ARCH9). New value type `ActiveSessionSource`: `id`, `priority` (higher wins), `statusProvider` (a `Provider<ActiveSessionStatus?>`), and its OWN owner rule (`ownerUid` read from its own provider). Registered in `activeSessionSourcesProvider` (a plain list provider; tests override it with fakes).
- Two registered sources: `gymTimers` (priority 10; today's `_activeSessionCoreProvider` plus owner gating moved behind this entry with behaviour unchanged) and `gpsRecording` (priority 20, PROPOSED per S04-R-038). The owner of `gpsRecording` is intrinsic: the recorder's remembered owner uid.
- `activeSessionStatusProvider` = the status of the highest-priority source whose own owner matches the signed-in uid and whose status is non-null. A source of another account is skipped, not cleared: ending one source never clears another source's owner (S04-R-037 (c)); an account switch hides the foreign source (b); a fake second source is shown (a).
- `activeSessionForeignOwnerProvider` becomes "some source is running for another account AND no source of this account is visible", so the Record pill and rail slot stay hidden exactly as today (S03 F-11) and are not hidden merely because a foreign timer exists beside the own recording.
- Carrier for the S04-D strip words (ARCH9; replaces the earlier "both pauses map to `paused`", which cannot give S04-D's different words and rail words for manual and auto pause): `ActiveSessionKind` gains `gpsRecording`; `ActiveSessionState` gains `acquiring` (Looking for GPS), `recording` (Recording), `weakSignal` (Weak GPS signal), `autoPaused` (Auto-paused), `unfinished` (Unfinished recording) and `notRestored` (Recording not restored); manual pause reuses the existing `paused` (Paused). The optional `note` field carries only the banner short label of the third line. `permissionRevoked`, `finished` and `idle` produce a null status (no strip, S04-D 14.1). Time shown: moving time for `recording` and `weakSignal`, frozen time for both pauses, none for the rest. Adding enum values makes the exhaustive switches `_stateWord`, `_railWord`, `_stateIcon` (`dock_widgets.dart` 57-76) fail to compile until updated; that is the intended safety net and the reason for the compile smoke (13.2).
- Destination: GPS source has its own route (the recording page, owned by S04-D); `activeSessionDestinationProvider` reads the winning source's destination instead of the gym owner only (FACT today: `active_session_status.dart` lines 370-375).
- Announcements: the live-region logic in `main_shell.dart` lines 154-199 keys on `restOnly` and state words; for the GPS source it announces start, pause, resume and end once each, never per second (S03 AC-ST-4 rule).
- The gym timer stays reachable from the workout page when the strip shows GPS (S04-R-038).
- Recovery claim: the word "recovered" is reachable only from the recovery-success path of 4.5 (S04-R-039); a copy test greps for it.

DECISION NEEDED (D-12, operator with product-owner, Req question 1): strip priority when both run. Option A (assumed): GPS wins because location is being collected and must stay visible. Option B: gym timer stays on top (a person could forget an active recording). Option C: show both (taller dock, changes S03 layout). The list design supports all three by changing one priority number or a second slot.

### 7.3 Every entry point of the capability (retro rule 2: enumerate, one test row each)

| Capability | Entry points to enumerate and test | Rule |
|---|---|---|
| Start a recording | Record sheet row (`shellRecordSheetOpenerProvider`, `main_shell.dart` `_openRecord`); rail Record slot; Record pill; the keyboard shortcut that calls the same opener (`app_shortcuts.dart` line 128, FACT from grep); any recording screen Start button | all pass through one `RecorderController.requestStart()` with the preconditions of 5.4 (journal open and unfinished check complete, consent plus permission, no own gym timer running per S04-D SH-4, no foreign session, no unfinished recording). The Record sheet stays openable during a recording: the GPS row then reads Open recording (S04-D UX8 fix) |
| See / open the running recording | strip in the dock; compact running rail slot; extended rail strip; pill (idle only) | same `activeSessionStatusProvider`; hidden for a foreign owner in dock AND rail AND shortcut (S03 gate failure of this class is the reason for this row) |
| Pause / resume / stop | recording page controls; notification actions Pause/Resume and Finish... only if 5.5 and D-20 allow (Finish... opens the stop panel, it never stops) | one controller method each; the same method for page and notification |
| Recovery offer | app start gate, Record sheet when an unfinished recording exists, strip in phase `restoring` | one gate in lane R9 at start, not a copy in each screen |
| Sign-out while recording | sign-out sheet path (`confirmSignOutWithLocalData` in `sign_out_guard.dart`, awaited by every user-initiated sign-out, FACT file header) | D-13 option A with the guard changes below |
| Account switch / deletion while recording | confirmed different non-null uid; explicit sign-out or deletion event (`accountBeingDeletedUidProvider`); a transient null or loading state is NOT an event (X1) | on an event: `releaseAll()`, then stop, seal and hand off into the OWNER's store before the scope unbinds, owner-checked; if impossible the recording stays in its own scope (30-day expiry); never shown to the new account |
| Wipe | `DeviceLocalDataWipe`, `ActivityAwareLocalDataWipe`, account deletion | order of 4.7 (recorder, recording journal refuses, S02 wipe); `recording/` directory deleted |

Sign-out guard changes (X1, ARCH2; FACT from reading `sign_out_guard.dart`): (1) the guard counts only `assessSignOut().entryCount` of finished activities, so it must first ask the controller to stop, seal and hand off a running recording and then add the count of unfinished and quarantined recordings of that scope, otherwise a sign-out with only an unfinished recording takes the `entryCount == 0 -> true` path silently; (2) the "cannot check" sheet offers "Sign out anyway" and returns true without a wipe, so when a recording is active or unfinished the sheet text must say the recording stays on the device in this account's scope (copy by lane R8); (3) "Sign out and delete" calls `ActivityWipeCoordinator.onSignOut`, which must also remove `recording/` through the ordering of 4.7; (4) `sign_out_warning_sheet.dart` shows the recording count. The guard and the sheet are lane R13 files (Stories 9); the strings are lane R8; the hook is registered by R5 (4.7).

D-13 (sign-out during a recording; the old wording "deleted on sign-out" of S04-R-019 is replaced by X1): Option A (recommended, now with X1 detail): stop, seal and hand off into that account's local store first, then the existing sign-out warning counts it like any local activity (the user decides export of FINISHED activities or wipe; nothing is silently lost). Option B: block sign-out until the user stops. Option C: discard silently (rejected: silent data loss). Default A.

### 7.4 Screens (S04-R-040)

S04 builds only what the approved S04-D contract names, without a map: start with permission pre-prompt and denial screens, the recording screen (pause, resume, stop), the recovery offer, the finish screen with the saved-on-device notice (S04-R-047). The screen list is S04-D 4.1 (S4-1 .. S4-7 and the notification, S4-10); the copy and layouts are its own; lane R7 starts after its approval (E4). This design adds no screen: the revoked and recovery-failed screens offer Keep and Delete only (X3), and the Settings, Privacy consent row is the only surface added for S04-R-054. No new top-level shell path and no new sheet flag is copied: the Back rule, the one-sheet-at-a-time flags and the tab path lists are already duplicated (`main_shell.dart` line 56 and `dock_widgets.dart` lines 38-44; Readiness addendum) and S04 reads `kShellDestinations` instead of adding a copy. Routes are registered in one splice in `core/router` (lane R9).

## 8. Battery protocol hooks (S04-R-028..031; lanes R4, R11)

### 8.1 Hooks

`BatteryMonitor` (seam, 2.2) emits (percent, charging). No battery package is declared (FACT, `pubspec.yaml`), and none was evaluated in the Study: UNKNOWN. DECISION NEEDED (D-14): Option A a maintained package, evaluated with the Study's minimum-evidence method first (version, publisher, toolchain minimums, maintenance); Option B a small own platform channel on the same native side as the fallback of 2.3. The interface does not change.

Behaviour (S04-R-030, PROPOSED numbers): at or below 10 percent and not charging: flag `batteryCritical`, non-modal banner, interval 5 s, flush 1 s. At or below 3 percent: stop, seal, hand off, stop reason `stoppedBattery` visible to the user. Charging at 8 percent does not enter the state. The recorder never stops silently and never shows a blocking dialog while recording. DECISION NEEDED (D-15, Req question 5): option A as above; option B warn only, never stop (track may be lost if the phone dies).

### 8.2 Measurement hooks

A debug-only `RecordingRunLog` (counts, durations, battery start and end percent, sample counts, reject counters, state names; no coordinates) feeds the protocol record of Req S04-R-028: reference phone and Android version, 60 min walk and 60 min ride, screen off, start and end percent read from the system, percent per hour, temperature if known, network state. The protocol document is lane R11 (`S04_BATTERY_PROTOCOL.md`); a run missing a field is not evidence. Target 8 percent per hour is PROPOSED (S04-R-029): a result above is recorded as FAIL. Battery optimisation exemption is not requested (D-16 below; Study 5.7); the device-lab record states whether a vendor killer ended a screen-off run and the settings used (S04-R-031).

## 9. Flags, rollout and rollback

### 9.1 Flags

New compile-time flag `GPS_RECORDER` (the name of S04-D 14.2; the earlier name `RECORDER_ENABLED` is withdrawn), default OFF in the first build, read through a provider like `activityFlagsProvider` (FACT pattern, `activity_flags.dart`). OFF means: no recorder provider builds, no Record sheet row for GPS, no location or foreground-service manifest entry in the build (flag-gated overlay of 2.4), no subscription ever, and the gated S02 worker path of 2.5 stays off. `ACTIVITY_CLOUD_STREAMS` stays false and a test asserts the constant (S04-R-046). DECIDED (X8, ARCH11, SEC9): the manifest permissions ARE gated by the flag, so a flag-off build does not declare location (GPS-PRIV-011 "declared set equals used set"); only the exact Gradle mechanism is UNKNOWN (2.4). Options as first stated (D-17): option A one manifest, permissions always declared once the code exists (simple; a flag-off build still declares location, which the Play form must cover); option B a source set or manifest placeholder that adds the entries only for builds with the flag (extra build work, honest declaration).

### 9.2 Rollout order

0. Before any code lands (ARCH11): pin the plugin line that resolves, read the MERGED manifests of a flag-off and a flag-on build (E8), and write the flag-gated overlay with removal markers (2.4). The manifest change itself still lands late (below), but its shape is known first.
1. Land in this order, one commit per step, each with its change record: seams and fakes (R1) -> pipeline and fixtures (R3) -> recording journal and wipe/backup tests (R5) -> state machine (R4) -> consent and constants (R8) -> shell sources list (R6) -> screens (R7) -> manifest and service (R2) -> wiring (R9). Reason: the manifest and the service are the first piece with a Play and privacy surface, so they land after the code that gates them. The backup and wipe tests for `recording/` land before any code that writes a sample (S03 lesson: data protection before data on).
2. Flag ON for the operator's debug build only; device tests T1..T6.
3. Release with the flag ON only after ALL of the release-gate rows (SEC9) are closed, each with a named owner (the operator unless a role is named): device-lab record (lane R11); approved S04-D copy; privacy text decision (D-18); privacy policy updated for location collection (owner: operator); Play data-safety form answered for location (owner: operator); Play foreground-service-type declaration and prominent-disclosure text (owner: operator, text drafted by lane R8); server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 (E7); the minors statement of 10.1. A row without an owner and a date is an open blocker, not a pass.

### 9.3 Constants without enforcement (S04-R-047..049)

`lib/core/config/recording_defaults.dart` (lane R8) holds the default privacy-zone radius 200 m and its setting key, the default GPS expiry 24 months from the activity date, and the saved-on-device string key. Nothing applies them in S04; tests assert they exist and that no scheduler or deletion rule is added. Privacy-zone application point (SEC8): the 200 m default is applied when an activity is SHARED or exported outside the device by a later sprint, never at storage; S04 stores the raw coordinates on the device, and the privacy-zone copy of S04-D must say that the default applies when sharing and is not applied in this version.

### 9.4 Rollback

Kill switch: build with `GPS_RECORDER=false`; recording disappears from the UI, no subscription is created, the foreground service is never started. Data already recorded stays in the S02 store (a finished activity is ordinary data); an unfinished recording directory stays on disk and is offered for recovery again when the flag is turned on, or is removed by sign-out/wipe. The kill switch is build-time only (same accepted model as S03, `S03_DESIGN.md` 2.1 item 6). Manifest entries cannot be rolled back by a flag; removing a declared permission needs a new release and, for background location, removal from all tracks (Study 4.6). Forward-only risk: a recording journal schema change needs a version field (present in `meta.json`) and a reader that treats a newer schema as "recoveryFailed, files untouched" (never overwritten).

## 10. Telemetry and logging rules (S04-R-044; GPS-PRIV-048, -049, -068)

- Allowed: counts, durations, sample counts, byte sizes, recording and activity ids, permission state, state names, error codes, battery percent buckets. Forbidden: coordinates, geohashes, geometry, place names, heart-rate, free text from exceptions.
- Pattern to follow (FACT): fixed message plus `e.runtimeType` only, as in `activity_wiring.dart` line 360 and `active_session_status.dart` line 323. Every `catch` in lane code maps to a bare code first (`recording_error_codes.dart`, lane R8) and never interpolates a fix, a path or a uid; `toString` of value classes is content-free (pattern: `ActiveSessionStatus.toString`, FACT line 175).
- Journal errors: the typed exceptions carry `pending` sessions and causes (FACT `JournalKeyUnavailable(... cause, pending)`); they are never logged with `toString`, only by type.
- `debugPrint` is the only logger in the recorder; no analytics call is added. Crash reporting (`firebase_crashlytics` is declared, FACT `pubspec.yaml`) receives only the bare codes; the recorder never calls `recordError` with a raw exception (PROPOSED).
- Test (S04-R-044 AC): record, pause, kill-recover, finish and fail flows run with sentinel coordinates (for example 12.3456789) while a log capture, an exception-message capture and a telemetry spy collect output; no captured text may contain the sentinel digits.

Sanitising wrapper and global handlers (S04-R-052, SEC4). The rules above cover only recorder code, but errors also leave through paths that the recorder does not control. FACT, read in `main.dart`: `FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError` (line 247), `PlatformDispatcher.instance.onError` calls `recordError(error, stack, fatal: true)` (lines 248-254) and another `recordError(e, st, fatal: false)` sits at line 327; each takes the raw error object. A `FormatException` raised while decoding a frame can carry a snippet of the input, and an error crossing `Isolate.run` is re-thrown with its message and stack text. Therefore:
1. `sanitizeRecorderError(Object)` (folder `safety/`, 2.1) returns a `RecorderSafeError` that holds a bare code and the original `runtimeType` only; its `toString` is content-free.
2. It is applied at three places in recorder code: the journal frame decoder (lane R5), the worker entry function and its caller around `HeavyWorkRunner` (lane R5), and every `catch` in `recording/**` (lane R8 provides it). No raw exception from these places is rethrown, logged or passed to a handler.
3. The global handlers get one splice (lane R9, `main.dart`): an error whose type is `RecorderSafeError`, or whose stack contains a `features/recording/` frame, is reported through the sanitiser. The debug telemetry sink named in SEC4 (its file is UNKNOWN to this design) goes through the same sanitiser; locating it is the first step of lane R8.
4. Sentinel test: sentinel coordinates are injected into a frame, a worker input and a thrown error; the test captures the output of the zone/global handler (`FlutterError.onError` and `PlatformDispatcher.onError`), a Crashlytics spy and the log capture, and no captured text contains the sentinel digits.
5. Entry condition E7: server-side enforcement of GPS-PRIV-050 and GPS-PRIV-098 must exist before release, because client hygiene alone cannot meet them.

### 10.1 Accepted risks and the minors statement (SEC9; accepted-risk list of round 1)

Accepted risks (written down, not mitigated in S04): (1) a rooted phone or a debuggable build can read the journal key and process memory; (2) another installed app that holds location permission sees the same fixes from the system; (3) apps with notification-listener access can read the notification, which is why 5.5 keeps coordinates and pace off every version and makes the lock-screen version fully generic; (4) file sizes and modification times of the recording journal reveal the recording's duration; (5) frames are not bound to their position by additional authenticated data, so the cipher gives integrity per frame but not ordering (a frame swap inside one file is not detected; the per-frame counter and CRC detect gaps and reorder only by consistency checks in recovery).
Minors statement (PROPOSED text for the privacy documents): in this version location recordings are private to the account on the device; they are not shared and not uploaded (upload stays off, S04-R-046). The age gate and any rule for users under the minimum age stay with the product owner (UNKNOWN: not in the sources read).

## 11. Failure modes and static checks

### 11.1 Failure table

| # | Failure | Detection | Behaviour | Req |
|---|---|---|---|---|
| F1 | Permission denied once / permanently / approximate only | status read at Start | neutral screen; Try again or Open settings; Add manually; no loop; approximate refused | -023 |
| F2 | Permission revoked during recording | poll per fix, stream error, resume | `releaseAll()` within 2 s, durably SEAL the partial recording (pending decision, listed by `listUnfinished`, survives a kill; Z2), phase `permissionRevoked`, offer Keep (durable `KEEP` decision, S02 hand-off of the sealed recording happens on Keep) or Delete (durable `DELETE` decision, ordered delete); the exclusive create of `DECISION` decides (first creator wins, the loser does nothing irreversible, Z7) and Delete is not offered after Keep (Z5) (no Export, X3), no re-request; its own normal notification (5.5, Y10) | -024, -056 |
| F3 | Process killed (swipe, memory, stop-app) | no `SEALED`, next start | recovery offer; loss at most about 5 s plus the gap | -015, -016 |
| F4 | Torn last frame, or a short write followed by a successful retry | length/CRC/decrypt; any write or fsync error | per-segment tail dropped, earlier frames kept; the retry always goes to a NEW segment so a torn frame is never mid-segment (4.2, ARCH4) | -015 |
| F5 | Journal unreadable | read result | `recoveryFailed`, bytes untouched until user acts | -017 |
| F6 | Key unavailable at begin | `JournalKeyUnavailable` | recording refused with reason; nothing started | -014 |
| F7 | Storage full on append | `isDiskFull` / typed exception | keep in memory up to 60 s, retry each flush, then stop with reason | -020 |
| F8 | `put` fails at hand-off | typed exception | recording journal kept, "recording kept, retry", no claim of saved | -018 |
| F9 | Crash between `put` and delete; or between the stop event and `SEALED` | `SEALED` plus stored id; stop event without `SEALED` | next start verifies and deletes silently (a tombstoned id is not re-created); a missing `SEALED` is re-written once with its `importedAt`; never neither copy | -018 |
| F10 | No kept fix for 10 s | timer | `poorAccuracy`, gap events, no interpolated distance | -009 |
| F11 | Fix clock goes backwards | offset not increasing | fix dropped and counted | -007 |
| F12 | Battery low | monitor | critical mode at 10 percent, finish at 3 percent, visible reason | -030 |
| F13 | Location services off | stream error / status | same as F2 path without revocation wording; screen asks the user to turn location on | -023 (UNKNOWN: exact platform signal) |
| F14 | Notification permission denied | status | refuse (D-5 default) with a reason | -025 |
| F15 | Sign-out, account switch, deletion mid-recording; transient auth null | auth/deleting listeners; owner check | 4.7 and 7.3: only a confirmed different uid, explicit sign-out or deletion acts; a transient null stops nothing; every step owner-checked | -019, -045 |
| F16 | Worker isolate throws | `Isolate.run` error | recording journal kept; error code; retry offered; UI isolate unaffected | -041 |
| F17 | Two writers to the recording directory | per-instance lock, open-root guard like `_openRoots` in `file_activity_journal.dart` | second open throws `JournalAlreadyOpenException`-style error | -014 |
| F18 | Manual pause then kill | last event `pause` | recovery offer as usual; Resume enters `acquiring` for every origin, never the paused phase (4.5, Z1); pause origin is kept as metadata and the time from the pause to the restart is one `restart` gap pair (pause interval), not moving time | -013 |
| F19 | Session exceeds 200 000 samples | S02 bound | recording stops with reason at 190 000 (PROPOSED margin) and hands off; automatic-stop notification | -036, -056 |
| F20 | Wipe or account deletion races a flush or a hand-off `put` | owner check; wiped-uid refusal | recorder shutdown, recording journal drains and refuses, then the S02 wipe (4.7); the key is not resurrected; nothing is written under a wiped scope | -019, -045 |
| F21 | Uid changes while phase is `stopping` | owner check at every step | hand-off writes nothing for the new uid; the recording stays in the OLD scope and is finished when that account is bound again | -045 |
| F22 | Engine detached while the service lives | adapter `engineDetached` | notification stops saying Recording; service stops after the grace period (5.6) | -058 |
| F23 | Start while the journal is not open or the unfinished check has not finished | preconditions of 5.4 | visible preparing / cannot-start panel; no `meta.json` is written | -055 |
| F24 | A raw exception reaches a global handler | sanitiser; sentinel test | only a content-free `RecorderSafeError` is reported (10) | -052 |
| F25 | Consent withdrawn during a recording, or before Resume | consent notifier | stop, seal, hand off and keep; Resume refused (6.2) | -054 |

### 11.2 Static checks (test agents write them as Dart tests that read source, as in S03 8.1)

(1) no import of a location package outside `recording/location/`; (2) no location/notification permission request outside `recording/permissions/` (permission_handler is already used by camera code, FACT, so the scan targets the location and notification permission symbols only); (3) no `dart:io` import and no `File`/`Directory` use in `recording/pipeline`, `recording/state`, `recording/pages` and `recording/widgets`; (4) no map package and no network/Dio import in `recording/**` (S04-R-005); (5) no call site of `requestStart` outside the enumerated entry points of 7.3 and none from boot or launch code; (6) no `print` or `debugPrint` of an interpolated fix or exception message in `recording/**`; (7) declared manifest location permissions equal the approved list, checked on the MERGED manifests of a flag-off build (none declared) and a flag-on build (S04-R-022, S04-R-050); (8) no iOS pass claim in release notes (S04-R-050); (9) no `catch` in `recording/**` that logs, rethrows or reports a raw exception without `sanitizeRecorderError` (S04-R-052); (10) no notification string is built from a fix or a pace, and the lock-screen public version is a static string with no sport, time or distance (S04-R-053, Y11).

## 12. Test hooks and the requirement-to-test map

Test files are written and run by the test agents (`functional-test-reviewer`, `e2e-runner`; `tdd-guide` for unit seams); the coordinator runs none; focused commands only, in the form of S03 8.5 (`flutter test --timeout 60s <paths>` in `mobile/`; the project-pinned Flutter path is UNKNOWN here). Ids are owned by the S04 test plan (not written yet); this table names WHAT must be guarded.

### 12.1 Map: requirement to guarded behaviour to level

| Requirement | Guarded behaviour (assertion that fails if broken) | Level |
|---|---|---|
| -001, -002 | subscription count 0 within 2 s of Stop/discard; no start path except a user tap; 60 min screen-off continuity | unit + static; device T1 |
| -003 | zero subscriptions in idle, after stop, after sign-out, after simulated boot | unit |
| -004 | transition table over every phase pair; display projection list equals the S04-D list | unit |
| -005, -046 | full run with all network adapters throwing succeeds; flag constant false; no map import | integration + static |
| -006, -007 | 3 600 requests for a 3 600 s replay; extra field rejected; mapped session passes `SampleStream.validate` | unit |
| -008, -009 | boundary 30.0 kept / 30.1 rejected; 50 m and 2 km jump fixtures yield zero kept from injected; tunnel adds 0 m and one gap | replay |
| -010, -011 | changed algorithm id changes derived values, raw bytes identical; length within 3 percent, displacement at most 15 m, apex within 15 m | replay |
| -012, -013 | exact pause/resume count on F-stop-go; no flapping at 0.6-0.9 m/s; manual pause blocks auto | replay + unit |
| -014 | no file API in recorder packages; concurrent append and unrelated `put` both land | static + integration |
| -015 | fault injection at random offsets of a 600 s replay, 50 runs, recovered end at most 6 s before the kill; torn record dropped. FAULT ROW 1, short write then retry: the fake file system writes half a frame and fails, the retry succeeds; the reader returns every frame before the tear AND every frame written after the retry (the retry went to a new segment); a variant where the retry would append to the same segment must fail the test | fault-injection |
| -016, -017 | each recovery choice yields its stored result; truncated, bit-flipped, wrong-schema fixtures give `recoveryFailed` with bytes unchanged | integration |
| -018, -019 | crash injected after every step of 4.3 including between the stop event and `SEALED`: only journal, or both, never neither; repeat after crash reuses the stored `importedAt` and the put stays a no-op; tombstoned id is not re-created; a forged or mismatching `SEALED` gives `recoveryFailed`; sign-out and wipe leave no `recording/` file; backup test over the real tree. FAULT ROW 2, wipe racing flush and put: a wipe of the uid is started while an append and a hand-off `put` are in flight (all interleavings of the fake scheduler); afterwards no file under the scope, no key re-created, no write after the wiped-uid refusal. FAULT ROW 3, uid change during `stopping`: the bound uid changes between steps 3, 4 and 6; nothing is written for the new uid, the recording stays in the old scope and is finished when the old uid is bound again. Also: a transient auth null mid-recording stops nothing | fault-injection + file walk |
| -020 | disk-full fake gives warning path, then stop with all samples | integration |
| -021..025 | request counters: launch, onboarding, tabs = 0; each outcome; at most 1 per tap; revocation mid-run | widget + unit |
| -026, -027 | consent record with four fields; withdrawal gates the next Start; ordered writes; text version equal in store and string file | unit |
| -028..031 | fake battery at 10, 9, 3, 2 percent; charging at 8 percent; protocol fields complete | unit; device lab |
| -032..036 | synthetic length error limits; pace undefined cases; hysteresis fixtures; summary passes S02 validator | replay |
| -037..039 | fake second source shown; account switch hides; ending one source keeps the other's owner; recovery string reachable from one path | provider + widget |
| -041, -042, -043 | `HeavyWorkRunner` spy shows seal/gzip/SHA/smoothing off the main isolate; max frame time for a 100k fixture; live buffer never over 600 | integration; profile mode NOT_RUN without a phone |
| -044 | sentinel coordinate test (section 10) | integration |
| -045 | account-switch test hides journal and offer | integration |
| -047..050 | strings and constants exist; no application of the constants; manifest list equality | unit + static |
| -051 | evidence record complete, each item PASS, FAIL or NOT_RUN, head named | document |
| -052 | sentinel digits injected into a frame, a worker input and an exception never appear in zone-handler output, Crashlytics spy or log capture (10); the static check (9) of 11.2 | integration + static |
| -053, -056 | notification builder: owner-visible version with sport, time and distance but no coordinates or pace; public lock-screen version generic, without sport, time, distance or actions; every automatic stop of the Y10 set (battery 3 percent, storage, 190 000 cap, consent withdrawal) posts a separate non-ongoing notification with reason, time and distance; a tap or action requests focus on the stop-panel header once | unit + widget; device NOT_RUN |
| -054 | withdrawal blocks Start and Resume; withdrawing mid-recording stops, seals, hands off and keeps; re-grant writes a new `grantedAt` | unit + widget |
| -055 | Start refused with the right reason for: journal not open, unfinished check running, unfinished recording found, consent, permission, own gym timer, foreign session; no `meta.json` written on refusal; `preparing` times out to `startFailed` | unit |
| -057 | manual pause lowers the request interval to 10 s (fake `LocationSource` records `setInterval`), restores at resume, prompt raised after 30 min of fake time, no fix journaled while paused | replay + unit |
| -058 | fake `engineDetached`: notification text no longer says Recording; service released after the grace period; nothing journaled while detached | unit; device T2 |
| 2.5 isolate move | inline versus worker path give identical plaintext and `streamsPlainHash`; S02 journal suite unchanged with `GPS_RECORDER` off | integration |
| 4.7 ordering | recorder shutdown, recording journal refusal, S02 wipe happen in that order (spy log); `recording/` removed | integration |
| 4.7 lifecycle (Z3) | successful hand-off then delete; failed hand-off keeps the encrypted recording with the notice; explicit sign-out; account deletion removes it; expiry at 30 days removes it; a later sign-in of the same account offers it, another account never sees it | fault-injection + file walk |
| Keep/Delete race (Z5, Z7) | FORCED INTERLEAVING: a barrier between the "absent" check and the create makes both callers observe absence before either commits, once with Keep first and once with Delete first, with the in-process mutex bypassed so the file arbitration is proven alone: exactly one exclusive create succeeds and the loser reads the winner and does nothing irreversible; recovery-vs-live-writer: publication: `DECISION` is published whole (temp file, fsync, exclusive hard-link create, parent fsync, temp delete); in the no-hard-link fallback a paused live writer holds an EMPTY `DECISION` (barrier after the create, before the write) and a second same-process caller or reader waits at most 2 s, reports "decision in progress" and acts on nothing; a regression test shows no code path removes or replaces a `DECISION` on its own while the recording is actionable (it goes only with its whole directory: completed DELETE, or KEEP cleanup after the verified hand-off); tests for completed KEEP cleanup and for crash and restart during it (recovery sees KEEP without `DISCARDING`, repeats the hand-off check and the cleanup); a second journal instance in another process or isolate fails to open while the first holds the process-wide lock and records nothing; recovery cannot run concurrently with a live fallback writer because Keep and Delete are gated on `recoveryComplete`; at recovery an empty, truncated or unknown-token `DECISION` and every conflicting combination go to `QUARANTINED` with no delete, no hand-off and the file not unlinked; EVERY row of the recovery table of 4.3, including the valid DELETE rows, is driven through the real `listUnfinished()` path; durability invariant: no put, delete or `DISCARDING` before both fsyncs complete (no claim about a crash between them). Also: crash and concurrent Keep and Delete injected before `put`, immediately after a successful `put`, and before journal cleanup: exactly one deterministic result per the first-durable-decision rule (`KEEP`: one activity, cleanup completes on recovery; `DELETE`: nothing in S02, recording gone); Delete after `KEEP` is refused and never removes the S02 activity; Keep after `DELETE` is refused; a replayed action is a no-op reporting "already decided"; recovery by marker; no duplicate and no resurrected data | fault-injection |
| Revocation (Z2) | fault injection at revocation, seal, process death, Keep, hand-off and Delete: one consistent durable state each time, either pending decision or finished activity, no duplicated activity, Delete never resurrects | fault-injection |
| Resume origin (Z1) | recover from recording, manual pause and auto pause: phase `acquiring`, preserved values, one `restart` gap pair | integration |

### 12.2 Replay seams (S04-R-035)

Fixtures F-noise-line, F-turns, F-stop-go, F-tunnel, F-urban-canyon, F-jump, F-climb, F-ride-30kmh, F-walk, F-kill-mid-run are stored files with a stored expected-result file each (test agents write them in the first story of lane R3, Stories 9: S04-02). The replay driver feeds the SAME `RecorderPipeline` class the live recorder uses, through the fake `LocationSource` and the fake clock; no second code path. Output for a fixed input is bit-identical across runs: no `DateTime.now`, no `Random`, no map iteration order dependence in `pipeline/`. A fixture test must fail if a threshold is changed (assertion design only; no mutation run, operator rule).

### 12.3 What would make a green run misleading

A fake that never throws would pass the revocation test: the fake must support flipping status mid-run. A "no file API" check that only greps imports misses a helper in another folder: scan the whole `recording/` tree minus `journal/`. A recovery test that reads the journal from the same object that wrote it proves nothing: it must open a NEW journal object over the same fake file system after the injected crash. Mixed-account tests must use two real scope directories.

### 12.4 Evidence record (S04-R-051)

`S04_DEVICE_LAB_RECORD.md` (lane R11): device and OS, build id/head, kill survival (T2), screen-off continuity (T1), tolerance on a walked and a ridden known route, battery runs, OEM-killer entry; each PASS, FAIL or NOT_RUN. iOS rows read NOT_RUN.

## 13. Build lanes, file ownership and retro rules

### 13.1 Lanes: the lane table of `S04_STORIES.md` section 9 is the SINGLE source of file ownership (Y4, K4)

This table no longer owns paths. A path appears in one lane only, as in Stories 9; the middle column is a summary and the right column adds design detail. Where the two ever differ, Stories 9 wins. Ownership facts used by this design: R2 owns `pubspec.yaml`, `pubspec.lock` and the Gradle files; R5 owns `file_activity_journal.dart`, `journal_layout.dart`, `journal_generation_writer.dart`, `uid_scoped_activity_journal.dart` and the single hook splice in `activity_wiring.dart`; R6 owns the strip provider, `dock_widgets.dart`, `record_sheet.dart` and `app_shortcuts.dart`; R8 owns the ARB files, `recording/safety/**` and consent; R9 owns `main.dart`, the router, `main_shell.dart` and the Settings page splice; R13 owns `activity_aware_local_data_wipe.dart`, `sign_out_guard.dart` and `sign_out_warning_sheet.dart`. Wait edges: R13 after the R5 stop/seal/hand-off interface commit; R9 after the R13 guard API; R6 after the R5 recovery-pending API; R2 after the R8 notification keys; the hook splice in `activity_wiring.dart` is registered by R5 and used by R13 and R9 through its public interface.

| Lane | Owns (summary of Stories 9) | Additions made by this design (the lead adds them to the Stories 9 table before any edit) |
|---|---|---|
| R1 | `recording/location/**`, `recording/permissions/**`, guard-test support | the `LocationSource` interface commit comes first |
| R2 | `AndroidManifest.xml`, native files if D-1 picks B, backup/data-extraction XML | manifest comment block update (2.4) |
| R3 | `recording/pipeline/**` | constants file; `RecorderPipeline` class used by live and replay |
| R4 | `recording/state/**` | phase/flags model, projection function, battery monitor port |
| R5 | `recording/journal/**`, single splice in `activity_wiring.dart` | design detail: wipe list and gated CPU part of `put` (`file_activity_journal.dart`), recording dir constant (`journal_layout.dart`), `JournalPaths` (FACT `journal_generation_writer.dart` line 29), `wipeForUid` ordering and wiped-uid refusal (`uid_scoped_activity_journal.dart`), the pre-unbind hook splice (4.7); S02 regression tests unchanged with the flag off |
| R2 (see Stories 9) | | design detail: dependency pin and flag-gated manifest overlay with removal markers (2.4, X8); R2 step 0 before the R1 adapter |
| R8 (see Stories 9) | | design detail: every string key; other lanes request keys; sanitiser `recording/safety/**` (10) |
| R9 (see Stories 9) | | design detail: `main.dart` global-handler splice (10), Settings Privacy row splice (6.2), recovery gate |
| R6, R13 (see Stories 9) | | design detail: `record_sheet.dart` and `app_shortcuts.dart` use the one `requestStart()` (7.3); R13 sign-out guard changes (7.3) and wipe ordering (4.7) |
| R6 | `active_session_status.dart`, `dock_widgets.dart`, `shell_dock.dart` | sources list; `main_shell.dart` listener edits are lane R9's splice |
| R7 | `recording/pages/**`, `recording/widgets/**` | starts after S04-D approval |
| R8 | ARB files, `recording/l10n/**`, `recording/consent/**`, `core/config/recording_defaults.dart` | error-code mapper; flag file `core/config/recording_flags.dart` |
| R9 | `main.dart`, `core/router/**`, `main_shell.dart` | one splice each; sign-out guard call sites if D-13 is A (file names read in the story's first step) |
| R10 | conditional background-permission and notification-denied branches | built only if D-2 option B or D-5 option B |
| R11 | battery protocol and device-lab record | |
| R12 | fixes forced by tests and reviews | each fix listed by file first; starts after the other lanes close |

Order and waits follow Stories 9 (R3 needs the fixtures; R4 needs the R3 interface commit; R5 needs R3 and R4 interface commits; R7 needs S04-D approval and the R1, R4, R6 interface commits; R9 waits for page files). Interface commits first: R1 `LocationSource`/`PermissionService`; R3 pipeline events; R4 controller state API; R6 source list types.

### 13.2 Retro rules applied (S03 sprint report, retro actions 1, 2, 6, 8, 9, 10)

1. Compile smoke: lanes cannot build; after every batch of agent edits one test agent runs a compile-only smoke before the commit, and the first test run starts after wave 1 (R1, R3, R4 interfaces), not after the last lane. Special risk here: new enum values in `ActiveSessionState` break three exhaustive switches in `dock_widgets.dart` until lane R6 finishes. The lead reads the diff of every risky edit.
2. Every entry point enumerated: table 7.3 is the list; each row has a test row. Any notifier that persists state (consent, recorder meta) has an ordered write path and a uid guard.
3. State machines: for each stream a machine listens to (fixes, permission status, battery, auth) the test list names every event kind and repeated or equal values (a repeated identical fix, a repeated permission status, a repeated auth value for the same uid; S03 retro action 6).
4. Verify design statements against files: this document marks UNKNOWN where it did not read a file (package manifest, `JournalPaths` location, `permission_handler` background step, guard-test allow-lists); each is a "first step" of its lane.
5. Data protection before data on, and tests against real paths: the `recording/` backup and wipe tests walk the directory the real factory creates.
6. Test infrastructure: private output file name per test agent; final complete run on the exact approved head, recorded with head and results.
7. One fix round on a secondary mechanism, then stop (operator rule).

## 14. Open decisions (DECISION NEEDED), in words

| Id | Question | Options and consequence | Default used here | Owner |
|---|---|---|---|---|
| D-1 | Location host package | A `geolocator` (cheapest, one writer, Dart dies with the engine); B own Kotlin service (control, cost); C paid package | A, after dependency resolution and T1/T2 | architect, operator |
| D-2 | Background location | A none (smaller Play surface, no unattended restart); B request it (restart possible, Play form, video, disclosure, second consent row, lane R10) | A | architect, operator |
| D-3 | Recording journal placement | A sibling `RecordingJournal`; B extend `ActivityJournal`; C use `put` (rejected) | A | architect |
| D-4 | Meaning of "survives app kill" | journal recovery after kill (supported by the Study) or continued recording (no platform basis) | recovery | operator, product-owner |
| D-5 | Notification permission denied | A refuse recording; B record, notification only in Task Manager | A until T4 | operator |
| D-6 | How long an unfinished recording is offered | A until chosen; B expire after N days | A | operator |
| D-7 | Resume after a long gap | A always; B above 30 min only Save as finished | A | product-owner |
| D-8 | Gap time in moving time | A counts (average speed lower after tunnels); B excluded | A | product-owner |
| D-9 | Free-space warning source | A write failures only; B native free-space read | A | architect |
| D-10 | Priority order of overlapping display states | CLOSED in this revision: S04-D 5.3 three channels adopted (5.1); reopened only if S04-D changes it | S04-D 5.3 | ui-designer |
| D-11 | Strip derivation | list of sources or rewrite of the provider | list | architect |
| D-12 | Strip priority with a gym timer | A GPS wins; B gym wins; C both | A | operator |
| D-13 | Sign-out during a recording | A stop, hand off, then normal warning; B block; C discard (rejected) | A | operator |
| D-14 | Battery source | A evaluated package; B own channel | undecided; evidence first | architect |
| D-15 | Battery critical | A slow down at 10, finish at 3 percent; B warn only | A | operator |
| D-16 | Battery-optimisation exemption | A never ask; B in-app request (Play policy risk, Study 5.7) | A | operator |
| D-17 | Manifest gating by flag | CLOSED by X8: B flag-gated entries (2.4) | B | architect |
| D-19 | Meaning of Keep on a revoked recording | A quarantine (X3, used here); B seal and hand off into the store (S04-D 5.2 draws `-> finished`). B gives the user a usable activity; A leaves the data unreachable in S04 | CLOSED by Y1: hand off for a revoked recording (matches S04-D 5.2); quarantine for `recoveryFailed` and invalid decision states only, never plain revocation (operator may override) | operator |
| D-20 | Notification actions | A Pause/Resume and Finish... only if the plugin notification supports them; B none; C Kotlin fallback adds them | A if supported, else B | architect |
| D-18 | Pre-prompt wording approval before release | owner-only release with DRAFT marker, or approval first (Req A-7) | DRAFT | operator |

Reconciliation with S04-D revision 2 (panels `preparing`, `cannotStart`, `startFailed`, `consentWithdrawn`; Keep and Delete only; no Export): mapping to this design is `preparing` and `cannotStart` = failures 1-2 and 6 of 5.4, `startFailed` = the 10 s timeout of 5.4, `consentWithdrawn` = precondition 3 of 5.4 and 6.2. FLAG NAME: `GPS_RECORDER` is chosen (S04-D 14.2); `RECORDER_ENABLED` is withdrawn everywhere in this design, and requirements and stories must use `GPS_RECORDER` too.

Blocking UNKNOWNs for the next phase: S04-D approval (screens, copy; states, priority and words are already adopted); reference phone; device tests T1..T6; package resolution result; content of backlog item P2-009 (not found, Readiness section 6).

## 15. Stale or inconsistent documents found, not changed

- S04-R-019 wording ("journal deleted on sign-out") is replaced by X1 (4.7); owned by the requirements author.

- `docs/phase2/s04/S04_REQUIREMENTS.md` S04-R-014 says samples are "appended through the S02 repository writer"; the S02 interface has no append and `put` rewrites the whole generation (FACT, 4.1). This design resolves it with a sibling journal (D-3); the requirement wording should be reconciled after D-3.
- `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` line 334 ("future sources implement the same status without changing the strip") does not hold (Readiness addendum; 7.1). Settled S03 document; left unchanged.
- Comment in `active_session_status.dart` line 63-65 repeats the same claim; fixed by lane R6, not by this document.
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` lines 100 and 210 still describe the retention decision as open (Readiness section 6); needs a doc-updater pass.
- `docs/DOCUMENT_REGISTRY.md` exists (FACT, glob); it is generated and was not regenerated here; it should be regenerated with the S04 documents.

## 16. Round 1 remediation log

Source: `docs/phase2/s04/S04_REVIEW_FINDINGS_ROUND1.md`. Each id maps to the section changed or `carried: reason`. Status of every change: documentation only, nothing built or run.

| Id | Where handled |
|---|---|
| X1 | 4.7, 6.3, 7.3 (events, sign-out guard changes), F15, D-13 |
| X2 | 4.2 (`meta.json` owner), 4.3 steps 4 and last paragraph, 4.5, 4.7 ordering, 6.3, F20, F21 |
| X3 | 1.2, 4.2 (`QUARANTINED`), 4.5, 5.1, 5.2, F2; D-19 records the S04-D conflict |
| X4 | 6.2 withdrawal surface, 5.4, 4.5, F25 |
| X5 | 3.6, 2.2 (`setInterval`), 12.1 row -057 |
| X6 | 5.5, 4.8, F19, 12.1 row -053/-056; D-20 |
| X7 | 5.4, F23 |
| X8 | 2.4 flag gating, 9.1, 9.2 step 0, D-17 closed, 11.2 (7) |
| X9, X10 | carried: S04-D only (UI text rules), not a design topic |
| ARCH1, SEC1 | 4.3 step 4 owner check, 4.2, 6.3 |
| ARCH2, SEC2 | 4.7, 7.3, F15 (S04-R-019 wording flagged in 15) |
| ARCH3 | 4.7 ordering, F20, fault row 2 in 12.1 |
| ARCH4 | 4.2 new segment after any write error and per-segment torn-tail rule, F4, fault row 1 |
| ARCH5 | 4.2 (`SEALED` authenticated), 4.3 steps 2, 3, 5 (`importedAt`, tombstone), F9 |
| ARCH6 | 2.3 D-1 (T2 gates option A), 4.6, 5.6, F22 |
| ARCH7 | 2.5 (plaintext and hash identical, ciphertext not, gated, threshold), 12.1 |
| ARCH8 | 5.4, F23 |
| ARCH9 | 1.3 E4, 5.1 (S04-D channels, D-10 closed), 7.2 (status carrier and words), 7.3 (SH-4), 9.1 and the reconciliation note in 14 (flag name `GPS_RECORDER`) |
| ARCH10 | 13.1 (added rows), 4.7 file list |
| ARCH11 | 2.4, 9.2 step 0, E8 |
| SEC3 | 1.2, 4.5, X3 rows; no Export of unfinished data |
| SEC4 | 10 (sanitiser, global handlers, sentinel test), 2.1 `safety/`, 11.2 (9), E7, F24 |
| SEC5 | 6.2, 12.1 row -054 |
| ARCH12 | 4.6 |
| ARCH13 | 4.5, F18 |
| ARCH14 | 2.3 step 4 |
| SEC6 | 5.5 |
| SEC7 | 3.6 |
| SEC8 | 9.3 |
| SEC9 | 9.2 item 3 release-gate rows, 10.1 minors statement |
| Accepted risks | 10.1 |
| Requirements S04-R-052..058 | trace rows in 1.6, sections 10, 5.5, 6.2, 5.4, 5.5, 3.6, 5.6 |
| UX and A11Y findings | carried: they belong to `S04D_UI_DESIGN_CONTRACT.md`, fixed by its own author |
| Requirements and stories findings (S04-R-014, -019, new requirements, lane table) | carried: other authors; this design lists the lane additions in 13.1 and the wording conflict in 15 |

Verified against code while editing (FACT): `sign_out_guard.dart` counts only `assessSignOut().entryCount` and its "Sign out anyway" path returns true without a wipe; `uid_scoped_activity_journal.dart` has the `_wipedUid` refusal (lines 83-86, 150-155); `JournalPaths` is in `journal_generation_writer.dart` line 29; `main.dart` lines 247-254 and 327 pass raw errors to Crashlytics; `file_activity_journal.dart` lines 201-217 hash the plaintext. Not re-verified: the plugin behaviours, the Settings page path, the debug telemetry sink location (all UNKNOWN, first steps of their lanes).

### 16.1 Round 2 additions (test-plan gaps, `S04_TEST_PLAN.md` section 9)

| Id | Where handled |
|---|---|
| TP-S04-1 | 3.3 bad-anchor recovery (5 speed rejections or 30 s, re-anchor, gap pair) |
| TP-S04-2 | 5.1 already uses the three S04-D channels (headline, banner, chips); no single order remains |
| TP-S04-3 | 5.2 mapping paragraph and Discard edges |
| TP-S04-4 | 5.5 wording; 1.2 and 7.3 no longer contradict |
| TP-S04-6 | 3.7 altitude median and 10 m step rule |
| TP-S04-7, TP-S04-9 | 4.2: torn tail only at the end of the last segment (or announced by `segmentBreak`); everything else is `recoveryFailed`, no partial offer |
| TP-S04-8 | 4.5 ordered Discard with `DISCARDING` marker |
| TP-S04-14 | 5.1 `offline` is UNGROUNDED, default not shown |
| TP-S04-5, 10, 11, 12, 13, 15 | carried: not in the batch received; owners re-send them if still open |

### 16.2 Round 2 remediation log (decisions Y1..Y11, findings K1..K10)

| Id | Where handled |
|---|---|
| Y1, K1 | 4.2 (`QUARANTINED` only for `recoveryFailed`), 5.1, 5.2, 5.4 (revoked item does not block Start), F2, D-19 closed; carried: requirements R-024, S04-19 and the contract are other authors' files |
| Y2, K2 | 4.7 pre-unbind hook (interface, 5 s bound, timeout fallback, guard uses it, `finishInterruptedWipe` runs without a recorder), 13.1 wait edge |
| Y3, K3 | 4.7 transient-null buffer (120 s, `account` stop) and durable repository-layer wiped marker |
| Y4, K4 | 13.1 and 4.7 now cite the Stories 9 lane table; 7.3 guard owner R13; the layering minor (injected hook interface) in 4.7 |
| Y5, K5 | 5.4 one timeout set (5 s, 15 s from the service-start call, plus the other timers); cannot-check path keeps Sign out anyway (7.3) |
| Y6, K6 | E7: precondition to start R3 onwards unless a dated operator exception; also release gate |
| Y7, K7 | 4.2 event list and the `segmentBreak` rule (first frame after an unclean close; duplicate counter keeps the first) |
| Y8, K8 | 4.3 step 6 and 4.5 Discard: same ordered delete, plain content-free `DISCARDING` marker without the key |
| Y9, K9 | 3.3 re-anchor only after speed-only rejections, only among fixes with accuracy of 30 m or better, anchor fix journaled, one gap pair or the gap already opened |
| Y10, K10 | 5.5 automatic-stop set (battery, storage, cap, consent withdrawal), revoked keeps its own notification; 12.1 row -053/-056; event kinds `stoppedAccount`, `stoppedConsent`, `stoppedCap` |
| Y11 | 5.5 owner-visible and public contents, tap and Finish focus; 10.1 risk 3; 11.2 check (10); 12.1 row -053 |
| Minor: layering, expiry runner, D-6 | 4.7 (hook interface; sweep at bind time by R5; 30-day expiry only for the hand-off fallback and quarantine, D-6 option A otherwise) |
| Minor: repeated sentence in 5.5 | removed |
| C1..C8 and contract minors; stale wording in R-004, R-014, S04-11 AC-1 and the stories lines | carried: contract, requirements and stories belong to other authors, edited at the same time |

### 16.3 GPT-PM gate round 1 remediation log (Z1..Z4)

| Id | Where handled |
|---|---|
| Z1 | 4.5 (Resume enters `acquiring` for every origin, pause-origin metadata, `restart` gap pair), 5.2 (restoring row), F18, 12.1 row "Resume origin"; carried: DT-12-4, S04-R-013 and the contract are other files |
| Z2 | 4.3 revocation sequence (seal at revocation, hand-off on Keep, ordered delete), 5.2 row, F2, 12.1 row "Revocation"; `stoppedRevoked` no longer appears (5.2 note, F2, tables use `permissionRevoked`); carried: S04-R-024, S04-19, DT-03-1, DT-19-1 and the contract |
| Z3 | 4.7 strict path (hand-off then delete) and 30-day fallback with user notice, 12.1 row "4.7 lifecycle"; carried: the S01 PROPOSED note and the operator question in the requirements |
| Z4 | carried: test plan trace (AC-D4-B-4), not a design item |
| Z5 | 4.3 durable `DECISION` marker (KEEP or DELETE, first wins, recovery by marker (the interim "`DISCARDING` = DELETE" wording is withdrawn by Z9), replay a no-op, Delete never removes the S02 activity), 4.5 Discard step (0), 5.2 row, F2, 12.1 row "Keep/Delete race"; carried: R-024, S04-19 AC-4, contract 13, DT-19-12/13 are other files |
| Z6 | carried: test plan section 7.3 mapping, not a design item |
| Z7 | 4.3 arbitration (single `DECISION` file, exclusive create never rename, durability = file plus parent directory fsync, loser acts irreversibly never, bounded retry on empty, `DISCARDING` only a progress marker valid with DELETE, malformed combinations to `QUARANTINED`), 4.5 Discard steps (0)-(1), 5.2 row, F2, 12.1 race row with the forced two-writer interleaving; carried: R-024 and AC, S04-19 AC-5..8 and the new interleaving AC, DT-19-14..17 (other files, see the note in the hand-over) |
| Z9, Z10, Z11, Z12 (section 7 of the findings, head 27df5697) | 4.3: ONE recovery table embedded once (8 rows), `DISCARDING` is never a decision, single publication rule (temp + fsync + exclusive hard-link create, fallback exclusive create only under the process-wide journal lock (Z14), a `DECISION` removed only with its whole directory by completed DELETE or by KEEP cleanup after the verified hand-off (Z13); an empty, truncated or unknown-token `DECISION` found at recovery is `QUARANTINED`), quarantine scope (recoveryFailed plus invalid decision states, never plain revocation), Z12 durability invariant; 4.5: Discard recovery follows the table, no unconditional delete of a `DISCARDING` directory; 12.1 race row (never-unlink regression test, empty/malformed to quarantine, every table row through `listUnfinished()`); any earlier wording that removes an empty `DECISION` is gone; S04-R-024 and S04-19 AC-5, AC-11, AC-12, AC-13 carry the same rule (edited in this pass); carried: DT-19-17/20/21 and the contract (other files) |
| Z8 | carried: DT-19-13 wording is a test-plan item |
| Z13, Z14, Z15 (section 8 of the findings) | 4.3 publication rule: two-case whole-directory removal (completed DELETE, KEEP cleanup after verified owner-checked hand-off), step 6 with KEEP cleanup tests and crash/restart; fallback paragraph: process-wide exclusive journal lock held for the process lifetime, second instance fails closed, recovery gated before Keep/Delete, startup probe picks hard-link; 12.1 race row with the new tests; carried: requirements and stories wording (edited in the same pass), DT-19-22/23 and the Z15 plan map are test-plan items |
