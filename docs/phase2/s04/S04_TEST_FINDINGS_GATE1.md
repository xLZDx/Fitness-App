# S04 gate 1: functional test findings for the seven external-review fixes

Repository: `D:\Repo\Trash\Fitness_App_Phase2_s01`, branch `phase2/s04`, HEAD `5d5723fa`
plus the UNCOMMITTED production fixes (five files under `mobile/lib`). Nothing was committed.
All commands run from `mobile/`. Every run used `--timeout 300s`. No whole-repo analyze or build.

## Result

| Run | Command | Result |
|---|---|---|
| Complete sprint set (plus the M-05/M-06 file) | `flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout test/features/activity/repository/s04_gate1_m05_m06_scoped_journal_test.dart --timeout 300s` | 1155 passed, 0 failed (baseline before the fixes: 1119; 36 new tests; 1119 + 36 = 1155) |
| First run of the same set (before test fixtures were adapted) | same | 1136 passed, 19 failed (all 19 explained below, all fixture or intended-behaviour changes) |
| Adjacent files that use `UidScopedActivityJournal` (regression check of the production change) | see "Adjacent regression run" | 91 passed, 2 skipped, 1 failed (`journal_availability_test.dart` DT-0-10, see below) |

Production defects found by the new tests: none. No production code was changed by this test pass.

## Per finding

### B-01 geolocator adapter does not compile
File: `mobile/test/features/recording/location/s04_gate1_b01_source_compiles_test.dart` (4 tests, passed).
- `B-01: the geolocator adapter imports and constructs (it compiles)`: the test file imports the adapter, so a compile error turns the whole file red.
- `B-01: the adapter file has no leftover text between its header comment and its first import`: first non-comment line must be the geolocator import.
- `B-01: no non-comment junk at column 0 anywhere in lib/features/recording`: static scan of every production file (allow-list: comments, `import`/`export`/`part` followed by a quote, `library`, `class`, `abstract`, `enum`, `typedef`, `mixin`, `extension`, `final`, `const`, `var`, `void`, `Future`, `@`, `}`, `)`, `]`, `(` for record return types, built-in type names, capitalised type identifiers).
- `B-01: the scan itself detects the original defect (self-check)`: the line `import a location package (S04-R-003). The` is flagged; plain prose is flagged; valid declarations are not.
Scan note: two legitimate record-return-type declarations start with `(` (`countValidFrames`, `sanitizeForGlobalHandler`); `(` is therefore allowed.

### M-01 withdraw races a grant write in flight
File: `mobile/test/features/recording/consent/s04_gate1_m01_consent_race_test.dart` (5 tests, passed).
- grant held in flight, then withdraw: state denied immediately, still denied after the grant completes, grant returns false, stored value is the withdrawal.
- a grant called after the withdraw succeeds and is stored.
- a stale recording grant does not block a grant of the other purpose (background).
- withdraw during an active collection (`RecorderPhase.recording`) with a grant in flight: in memory denied at once; after the write is released `stopAutomatically(consentWithdrawn)` is called exactly once.
- no-race control: grant then withdraw persists and stops a collecting recording.
Observation (not a defect of the fix): the stop of a running recording is queued behind the held grant write, so it happens only when that write completes; the in-memory denial is immediate.

### M-02 sign-out guard skipped the pre-unbind hook
File: `mobile/test/features/activity/gps_signout/s04_gate1_m02_signout_hook_test.dart` (6 tests, passed).
- zero activities and only a quarantined / pending-decision (permission revoked) / quarantined+pending (FALLBACK-held) recording: the hook runs once for uid `A` with reason `signOut`, no warning sheet, result true.
- empty recording journal: no hook, result true, the journal was consulted.
- hook that hangs: nothing for 1 s, after the 5 s bound the notice appears, tapping it signs out.
- listing that throws: cannot-check sheet, hook not run, "Sign out anyway" then signs out.
Mapping note: the `UnfinishedStatus` enum has no FALLBACK value; the test models FALLBACK-held as `quarantined` with `pendingDecision: true`.

### M-03 sweep of a foreign scope without its lock
File: `mobile/test/features/recording/journal/s04_gate1_m03_sweep_lock_test.dart` (7 tests, passed). Fake `LockOps` extends the existing `MemRecordingOps`.
- lock held elsewhere (acquire throws): expired recording kept, returns 0, no acquire recorded.
- lock held by a live holder through the same ops, then released: first sweep 0 and files kept, second sweep 1 and files deleted.
- free lock: recording deleted, exactly one acquire and one release, lock really free afterwards.
- release throws: sweep result unchanged (1, deleted).
- every acquire throws: returns 0, nothing deleted, no throw.
- owned scope (a recording begun by the sweeping instance): no second acquire, no release, the expired recording is deleted, the active recording is untouched.
- only the expired recording is removed; a fresh one of the same foreign scope stays.

### M-04 `_writePending` crossed a segment boundary inside one drain
File: `mobile/test/features/recording/journal/s04_gate1_m04_write_pending_test.dart` (3 tests, passed, about 2 min wall time because of 5000-frame AES).
- failing disk accumulates `kFramesPerSegment + 1` pending frames, the recovering drain writes them in one pass: no `storageFailing` fault, two segments (5000 + 1 frames), frame numbers contiguous 1..5001, sample order preserved, a second flush writes nothing again, recovery after kill reads 5001 samples, status readable.
- a drain queued behind a gated first segment open (5002 frames over two drains): same invariants, segments 5000 + 2.
- exactly `kFramesPerSegment` frames in one drain stays one segment.

### M-05 owner-checked put in flight vs unbind / wipe
File: `mobile/test/features/activity/repository/s04_gate1_m05_m06_scoped_journal_test.dart`, group M-05 (6 tests, passed).
- switch to B while a put is held: delegate A not closed until the put completes; the put succeeds; close strictly after `put.end`.
- `bindUid(null)` waits the same way.
- put that never finishes: under fake time, not closed at 4 s, closed after 6 s, bind completes.
- `wipeForUid(A)` waits for the put in flight (events show close after put end).
- `putForOwner` after `wipeForUid(A)` is CALLED (not yet awaited) and after it finished throws `JournalUnbound`; no put reaches any delegate.
- wrong expected uid still refused, right one still works.

### M-06 durable wipe marker fails closed
Same file, group M-06 (5 tests, passed). In-memory file system subclass whose marker create and marker read can fail.
- marker cannot be created: `wipeForUid` throws (the exception reaches `ActivityAwareLocalDataWipe`, which turns it into the `LocalWipeIncomplete` path), old binding dropped, delegate not wiped, `bindUid('B')` and `bindUid('A')` return false; after the fault clears a wipe succeeds and `bindUid('B')` binds.
- same failure when A is not bound (relaunch retry): throws, bound B stays bound, later wipe succeeds.
- marker cannot be read: `bindUid` false, stays unbound, the scope is never opened, retry still closed; readable again it binds.
- unreadable marker while bound to A: switching to B returns false and unbinds A (A closed once).
- completed wipe still refuses a rebind of the wiped uid.
Not covered: the `LocalWipeIncomplete` conversion itself is existing code in `activity_aware_local_data_wipe.dart`; the new test proves the throw that feeds it, not the conversion.

## Existing tests changed (and why; no assertion was weakened)

1. `mobile/test/features/recording/consent/location_consent_notifier_test.dart`, test `a slow older write cannot land after a newer one` (DT-21-4). It called `grant()` and `withdraw()` back to back and expected `grant` to return true. Under M-01 a grant called before a later withdrawal of the same purpose is stale and returns false by design. The test now lets the grant reach its (held) write first, then withdraws, and asserts `grant` is false, `withdraw` is true, both writes reach the disk in order, and the final stored value is the withdrawal. All other assertions are unchanged.
2. `mobile/test/support/scoped_journal_world.dart`: `ScopedJournalWorld` now passes `scopesRoot: () async => '$base/activity_journal'`. Reason: the fixture used the default `getApplicationSupportDirectory()`, which does not exist in a unit test; the old code silently read an unreadable marker location as "no marker", the M-06 fix fails closed ("wipe marker not readable"), so `bindUid` returned false. This fixed the failures in `account_events_test.dart` (14 tests) and `s04_15_16_lifecycle_test.dart` (5 tests); the consent test above was the remaining one (the runner counted 19 failed, the list of failing names has 20 entries, one of them is probably reported twice). The wipe markers of these tests now really live in the temp directory.
3. Adjacent files outside the mandated set got the same fixture fix (a real or in-memory `scopesRoot`, and `fileSystem: fs` where the journal uses a memory file system): `test/features/activity/e2e/s02_auth_flip_e2e_test.dart`, `s02_consent_switch_e2e_test.dart`, `s02_pass_account_switch_e2e_test.dart`, `test/features/activity/repository/uid_scoped_journal_wipe_rebind_test.dart` (3 constructors), `uid_scoped_activity_journal_test.dart` (1), `test/features/activity/widgets/sync_conflict_sheet_display_tie_test.dart` (2), `test/features/activity/journal_availability_test.dart` (`_SpyScoped` takes an optional `scopesRoot`; the DT-0-3b factory-failure test uses an absent but readable scopes root so the failure still comes from the factory).

## Adjacent regression run

```
flutter test test/features/activity/e2e/s02_auth_flip_e2e_test.dart test/features/activity/e2e/s02_consent_switch_e2e_test.dart test/features/activity/e2e/s02_pass_account_switch_e2e_test.dart test/features/activity/journal_availability_test.dart test/features/activity/repository/uid_scoped_activity_journal_test.dart test/features/activity/repository/uid_scoped_journal_wipe_rebind_test.dart test/features/activity/widgets/sync_conflict_sheet_display_tie_test.dart test/features/activity/sign_out_warning_test.dart --timeout 300s
```
Result: 91 passed, 2 skipped, 1 failed. Before the fixture fixes 17 of these failed.
Remaining failure: `journal_availability_test.dart` "DT-0-10 no file or directory I/O before the bind; availability is binding": `Expected: <0> Actual: <1>` "no path lookup before the bind". INFERENCE (not run on the baseline): this is not caused by the gate-1 fixes. `bindUid(null)` calls `_clearCompletedWipeMarkers()`, which resolves the scopes root through path_provider, and that code is identical at HEAD (`git show HEAD:...uid_scoped_activity_journal.dart` lines 192 and 324). It was not changed to pass. It needs a decision (the DT-0-10 contract "no path lookup before the first bind" versus the unbind-time marker cleanup) and an owner outside this pass.

## Not verified
- No mutation or red-before-fix runs (operator rule), so "the test fails without the fix" is argued from the assertions, not demonstrated. Strongest signal: M-04 asserts no `storageFailing` fault plus contiguous frame numbers across a segment boundary; M-01 asserts the stale `grant` returns false and the stored value is the withdrawal; M-03 asserts the file survives while the lock is held elsewhere.
- Real device and real file locks (`RecordingFileOps` is faked in memory); the real `getApplicationSupportDirectory` path; the full app test suite.

## Round 2: M-02-R2-01

Finding: a failed read of `recordingJournalPortProvider` or `recorderPhaseProvider` counted as "no recordings", so sign-out could skip the pre-unbind hook.
Rule under test (`mobile/lib/features/activity/state/sign_out_guard.dart`, uncommitted change): the port provider's default `UnimplementedError` (recorder not wired) means no recordings; any other exception reading the port, or any exception reading the phase provider after the port read worked, means "cannot check" (the cannot-check sheet with the explicit "Sign out anyway" choice, which still runs the leave path with the hook).

New file: `mobile/test/features/activity/gps_signout/s04_gate1_m02r2_provider_failure_test.dart` (9 tests):

Zero activities:
1. Port provider throws `StateError`: cannot-check sheet shown, result list empty, hook not run; after "Sign out anyway" the hook runs for uid A with reason signOut and the result is true.
2. Same, but Cancel: result false, hook never runs.
3. Working port, `recorderPhaseProvider` throws: same cannot-check outcome, the port was not listed, hook only after "Sign out anyway".
4. Nothing overridden (default `UnimplementedError`): result true at once, no sheet, no hook.
5. Not wired plus a throwing phase provider: still true, no sheet (phase never read).
6. Count listing succeeds, the second listing (any-files check) throws: cannot-check, hook only after "Sign out anyway".

Account with local activities (count path):
7. Port provider throws: cannot-check (not the warning sheet), hook only after "Sign out anyway".
8. Working port, phase provider throws: same.
9. Default `UnimplementedError`: normal warning sheet (activities only), "Sign out" returns true and offers the hand-off to the registered hook.

No production defect found; all new tests passed on the first run.

Commands (from `mobile/`, HEAD 63b03a7a plus the uncommitted guard change):
- `flutter test test/features/activity/gps_signout/s04_gate1_m02r2_provider_failure_test.dart --timeout 300s` -> +9, All tests passed.
- `flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout test/features/activity/repository/s04_gate1_m05_m06_scoped_journal_test.dart --timeout 300s` -> +1164, All tests passed (1155 before + 9 new).

Not covered: mutation runs (not performed by operator decision); a real recorder wiring on a device.

## Round 3: M-02-R3-01

Finding: "recorder not wired" was inferred from the exception type (`UnimplementedError`) thrown by `recordingJournalPortProvider`, which does not prove absence.
Rule under test (`mobile/lib/features/activity/state/sign_out_guard.dart`, `recorderWiredProvider` in `recorder_ports.dart`, override in `main.dart` under GPS_RECORDER; uncommitted): flag false (default) means 0 recordings / no files, silent fast path, no recorder provider read; flag true means ANY exception reading the port or phase provider, `UnimplementedError` included, is "cannot check" (sheet with explicit "Sign out anyway").

Changed existing tests (flag added only where the test expects a WIRED recorder; no assertion changed):
- `s04_gate1_m02_signout_hook_test.dart`: `recorderWiredProvider.overrideWithValue(true)` next to the port override (all tests there expect a wired recorder).
- `gps_signout_test.dart`: flag added under the same `if (!noPort)` condition; the `noPort` test ("recorder not wired at all counts as zero recordings") deliberately keeps the flag false.
- `s04_gate1_m02r2_provider_failure_test.dart`: flag true for the `throwing` and `working` modes; `unwired` stays flag false. Header comment updated.
- Checked and left unchanged: `recorder_world.dart`, `recorder_harness.dart`, `gps_sources_test.dart` and the other recording/gps_strip tests override the port but never run `confirmSignOutWithLocalData`; `sign_out_warning_test.dart` and the e2e wipe tests never override the port and correctly use the not-wired path.

New tests in `s04_gate1_m02r2_provider_failure_test.dart` (+7; new modes `wiredUnimplemented` and `unwiredSpy`, the latter counting every read of the port and phase providers):
Zero activities:
1. Flag true + port provider default `UnimplementedError`: cannot-check sheet (not a silent true), hook only after "Sign out anyway".
2. Same, Cancel: result false, hook never runs.
3. Flag true + working port, phase provider throws: cannot-check.
4. Flag false, spy overrides: result true, no sheet, no hook, zero reads of port and phase providers, zero listings.
Account with local activities (count path):
5. Flag true + `UnimplementedError`: cannot-check (not the warning sheet), hook only after "Sign out anyway".
6. Same, Cancel: result false, no hook.
7. Flag false: normal warning sheet, zero provider reads during the count, "Sign out" returns true.

No production defect found; all new tests passed on the first run.

Commands (from `mobile/`, HEAD ea5d1b8e plus uncommitted changes):
- `flutter test test/features/activity/gps_signout --timeout 300s` -> +53, All tests passed.
- `flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout test/features/activity/repository/s04_gate1_m05_m06_scoped_journal_test.dart --timeout 300s` -> +1171, All tests passed (1164 before + 7 new).
- `flutter test test/features/activity/sign_out_warning_test.dart test/features/activity/e2e --timeout 300s` -> +62 ~2 -1. The one failure is `e2e/s02_stale_view_e2e_test.dart` ("A to B with the same activity id"): `expect(await journal.bindUid('B'), isTrue)` at line 72 got false. That file imports none of the changed code (no sign_out_guard, recorder or main.dart) and fails alone with the same error; treated as pre-existing and outside this change (not confirmed on a clean HEAD run).

Not covered: mutation runs (not performed by operator decision); a real recorder wiring on a device; the `main.dart` override itself (no test builds the real app root).


## Round 4: whole activity directory

Working tree: HEAD ea5d1b8e plus uncommitted changes. Every run used `--timeout 300s`; no stash/checkout, no mutation runs.

Commands and results (cwd `mobile/`):

| Command | Result |
|---|---|
| `flutter test test/features/activity --timeout 300s` (first run) | 1575 passed, 2 skipped, 55 failed |
| `flutter test test/shared test/core --timeout 300s` | 760 passed, 1 failed |
| `flutter test <activity_sync_auth_tie, activity_sync_pass_identity, activity_wipe_export_account_bound>` after fixture fix | all passed |
| `flutter test test/features/activity --timeout 300s` (second run) | 1629 passed, 2 skipped, 1 failed |
| Sprint set: `test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout test/features/activity/repository/s04_gate1_m05_m06_scoped_journal_test.dart` | 1171 passed, 0 failed |

### Failures and classification

1. 54 failures, all `expect(await journal.bindUid(...), isTrue)` -> `Actual: <false>`, in three files:
   `repository/activity_sync_auth_tie_test.dart` (14), `repository/activity_sync_pass_identity_test.dart` (30), `repository/activity_wipe_export_account_bound_test.dart` (10).
   Classification: caused by M-06 (journal now fails closed when the wipe-marker location cannot be read: `_wipeMarkerExists` throws, bind returns false). These tests subclass `UidScopedActivityJournal` / `HookJournal` with only a `factory`, so they fell back to `getApplicationSupportDirectory`, which is unavailable in a unit test. Fixture-only defect; the shared `ScopedJournalWorld.journal` already passed a scopesRoot.
   Fix (assertions unchanged): `_CountingJournal` and `_SpyJournal` constructors take a scopesRoot and pass it to `super`; `_Rec` forwards the optional `scopesRoot` to `HookJournal`; all three call sites pass `() async => '${w.base}/activity_journal'`. All three files pass after the change.

2. `journal_availability_test.dart` DT-0-10 'no file or directory I/O before the bind; availability is binding': `Expected: <0> Actual: <1>` ("no path lookup before the bind").
   Classification: PRE-EXISTING, not caused by our changes. At 5d5723fa `bindUid(uid == null)` already ran `_clearCompletedWipeMarkers()`, which calls `_scopesRoot()` -> `getApplicationSupportDirectory()` (`git show 5d5723fa:mobile/lib/features/activity/repository/uid_scoped_activity_journal.dart`, lines 192 and 324-326). The test opens the journal through `openActivityJournal` (default scopesRoot), so the signed-out bind(null) performs one path lookup. Our uncommitted changes do not touch the journal file. Note for the owner: the test's invariant (no path lookup while signed out) is genuinely violated by the production code since the wipe-marker commit; not fixed here (no failing-test-proven regression from this round's change; the product decision is whether bind(null) may resolve the scopes root).

3. `shared/widgets/app_shortcuts_test.dart` 'AC-KB-1b/1c ... control: same-account session opens the owner destination, not the sheet': `Expected: '/workout/ex1' Actual: '/workouts'` (line 295). Deterministic (fails alone too).
   Classification: PRE-EXISTING / unrelated. Neither the test nor `lib/shared/widgets/app_shortcuts.dart` imports `sign_out_guard`, `recorder_ports` or `main.dart` (grep over lib and test/shared); `git diff 5d5723fa HEAD` shows no change in `lib/shared` or `lib/features/workouts`. Our uncommitted diff only touches `sign_out_guard.dart`, `recorder_ports.dart`, `main.dart`. The shortcut path (`_record` -> `openActiveSessionDestination(activeSessionDestinationProvider)`) does not read `recorderWiredProvider`. Root cause not investigated further (not confirmed on a clean HEAD run).

### Unresolved failures

- test/features/activity/journal_availability_test.dart: DT-0-10 (pre-existing, see 2)
- test/shared/widgets/app_shortcuts_test.dart: AC-KB-1b/1c control: same-account session opens the owner destination (pre-existing, see 3)

No production code was changed in this round. Not covered: mutation runs, device runs, the real app root.
