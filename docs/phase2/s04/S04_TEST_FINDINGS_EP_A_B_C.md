# S04 test findings, group EP_A_B_C (EP-A, EP-B, EP-C)

Author: test agent for stories S04-01 to S04-10. Date: 2026-10-17. Branch `phase2/s04`, HEAD `1d76b05e` plus the uncommitted work of other agents (nothing committed by this agent).
Flutter: `/d/flutter/bin/flutter`, Flutter 3.27.1 stable (the bare `flutter` resolved to this one).

## Result

Complete set of the files written by this agent, one run: **273 passed, 0 failed, 4 skipped** (skips are the four KNOWN_DEFECT tests below, each skipped with an explicit reason).

Command (from `mobile/`, run once on the final state, about 17 s):

```
flutter test --timeout 60s \
  test/features/recording/location/location_seam_test.dart \
  test/features/recording/pipeline/auto_pause_test.dart \
  test/features/recording/pipeline/calculators_test.dart \
  test/features/recording/pipeline/gate_and_gaps_test.dart \
  test/features/recording/pipeline/replay_harness_test.dart \
  test/features/recording/pipeline/smoothing_test.dart \
  test/features/recording/state/recorder_service_test.dart \
  test/features/recording/state/recorder_state_machine_test.dart
```

Expected-result recording (done once, never to make a failing test pass):
`flutter test --dart-define=S04_RECORD=true test/features/recording/pipeline/replay_harness_test.dart` writes `mobile/test/support/recording/replay_expected.json`.
Important: the stored results for F-noise-line, F-walk-real and F-flat-alt-noise freeze the CURRENT (defective, see below) outputs. If the smoothing or elevation algorithm is replaced, re-record with the reason written here.

## Files

| File | Stories / rows |
|---|---|
| `mobile/test/features/recording/location/location_seam_test.dart` | S04-01: DT-01-1 (4 entries plus refused-start), 01-2, 01-3, 01-4, 01-5, 01-6, 01-7 |
| `mobile/test/features/recording/pipeline/replay_harness_test.dart` | S04-02: DT-02-1 (21 fixtures plus list check), 02-2, 02-3 (all 8 constants), 02-4, 02-5, 02-6 (static plus behavioural live-vs-replay proof) |
| `mobile/test/features/recording/state/recorder_state_machine_test.dart` | S04-03: DT-03-1, 03-2, 03-3, 03-4, 03-5, 03-6, 03-7, 03-8, 03-9, 03-10, 03-11, 03-12, 03-13 |
| `mobile/test/features/recording/state/recorder_service_test.dart` | S04-04: DT-04-1 (adapted), 04-2, 04-3, 04-4 (5 entries plus 2), 04-5 (2 entries plus 2), 04-6 and 04-7 (partial). S04-05 controller half: DT-05-1, 05-2, 05-3 (structural) |
| `mobile/test/features/recording/pipeline/gate_and_gaps_test.dart` | S04-05: DT-05-4, 05-5, 05-6, 05-7, 05-8, 05-9, 05-11 |
| `mobile/test/features/recording/pipeline/smoothing_test.dart` | S04-06: DT-06-1 to DT-06-8 |
| `mobile/test/features/recording/pipeline/auto_pause_test.dart` | S04-07: DT-07-1 to DT-07-8 plus auto/manual bookkeeping |
| `mobile/test/features/recording/pipeline/calculators_test.dart` | S04-08: DT-08-1 to 08-9; S04-09: DT-09-1 to 09-5; S04-10: DT-10-1 to 10-5 |
| `mobile/test/support/recording/replay_fixtures.dart` | LCG generator for the 21 fixtures, CSV writer, replay driver (same `RecorderPipeline` class), serialiser |
| `mobile/test/support/recording/recorder_world.dart` | real `RecorderController` over `FakeLocationSource`, `FakePermissionService`, `FakeBatteryMonitor`, in-memory journal port, manual `FakeAsync` |
| `mobile/test/support/recording/scan_support.dart` | K-scan helper with size and anchor sanity checks |
| `mobile/test/support/recording/replay_expected.json` | recorded expected results of the 21 fixtures |

Every story S04-01 to S04-10 has tests; the AC mapping of plan section 7.3 is covered row by row except the items under "Remaining gaps".

## Production changes (all of them)

1. `mobile/lib/features/recording/pipeline/accuracy_gate.dart`, one line: `acc < 0` is now rejected like a missing or non-finite accuracy (counted in the accuracy counter). Before, a negative accuracy passed the `acc > max` test and the fix was KEPT. Found by DT-05-4 (negative accuracy row). No other production file was edited.

## Defects found and NOT fixed (need a decision; each has a skipped test carrying the assertion)

D1. Smoothing cannot meet S04-R-011 / S04-R-032 on the plan's noise (FACT, measured):
- F-noise-line with LCG noise up to 8 m per axis: final length 1543.4 m for a 999.6 m truth (+54 percent; limit 3 percent). With 2 m noise: +2.8 percent (passes, and is asserted).
- F-walk-real (correlated AR(1) noise, sigma 2.5 m): +8.7 percent (limit 2 percent). With sigma 1.0 m: +1.1 percent (passes, asserted).
- Cause (INFERENCE from the measurements): the 5-fix weighted average cannot remove lateral noise at walking speed. Probe with a wider window (radius 12, 25 fixes) gives +0.4 percent on the 8 m fixture, but that contradicts the documented 5-fix window and the id `smooth-wma5-1`. Design 3.5 names a constant-velocity Kalman filter as the fallback ("the replay fixtures decide"); this is that decision point. Skipped tests: `smoothing_test.dart` (8 m noise), `calculators_test.dart` (F-noise-line 8 m, F-walk-real 2.5 m).
- The 15 m displacement limit holds in every case (asserted at 2 m and 8 m noise).

D2. Elevation cannot meet S04-R-034 on F-flat-alt-noise (plus or minus 4 m): ascent 61.0 m and descent 59.0 m against the limit of 5 m (FACT, measured). A 15-sample median with 4 m hysteresis would give 0 and still count the 100 m staircase as 99 m (probe). With plus or minus 1.5 m noise the current code passes (asserted). The 5-sample median and 3 m hysteresis are documented constants (TP-S04-6). Skipped test: `calculators_test.dart` DT-10-1 plan fixture.

D3 (MINOR, FACT measured). Every segment end loses about two steps of distance (smoothing windows shrink at the ends and pull the end points inwards): F-tunnel, 60 s each side, ride: 949.6 m against 983 m; a recording of two fixes 10 m apart reports 0 m; the ride-real fixture is at -1.6 percent even without noise because of five auto-pauses. Within the tolerances of the plan for long tracks, but it grows with the number of pauses and gaps. No test fails; the behaviour is pinned (DT-08-9 `/two-fixes` accepts 0 to 10 m).

D4 (HYPOTHESIS, needs the plugin source, not verified). Auto-pause uses the provider speed whenever it is present, including 0.0 (Design 3.6, asserted as PINNED in `auto_pause_test.dart`). The plan row DT-07-5 expects "provider speed 0 with a moving position does not pause". If the platform reports 0.0 for a fix without speed, walking would auto-pause after 8 s. The adapter maps `speed < 0` to null only. Decision needed: keep Design 3.6, or fall back to the implied speed when the provider speed is exactly 0.0.

D5 (observation). `RecorderFlags.offline` and the `offline` chip are never set by any production code (the recorder has no connectivity input by design, S04-R-005); the chip cannot appear. The adapter also passes `p.altitude` unconditionally (a missing altitude may arrive as 0.0; UNKNOWN, not verified).

## Plan rows that conflict with the design or cannot hold (recorded, not hidden)

- DT-04-1 as written expects the SOURCE manifest to declare the four new permissions. The design (2.3) deliberately declares none there and strips or requires them in a Gradle manifest transform. The test was adapted: the source manifest declares none of them, none of the three forbidden ones, and `build.gradle` lists exactly the approved four and always strips `ACCESS_BACKGROUND_LOCATION`. The merged-manifest check stays NOT_RUN (needs a build).
- DT-08-1 `/F-noise-line` says 0.5 percent; DT-06-3 says 3 percent for the same fixture. Only 3 percent is achievable for any noisy fixture, so the test uses the 3 percent limit at 2 m noise (and the skipped 8 m test).
- DT-05-4 says accuracy 0, negative, NaN, infinite, missing are "rejected as invalid, counted". Today NaN, infinite, missing and (after the fix) negative are counted in the ACCURACY counter, not the `invalid` counter (which is for coordinates). Accuracy 0 is KEPT (design text "present, finite, at most 30 m"; the plan marks it DEPENDS-ON-DESIGN); pinned by a test so a change is visible.
- DT-02-3 `/hysteresis-3m`: the altitude constants have no seam in `PipelineConfig`; the probe runs on `ElevationAccumulator` directly over F-climb and F-flat-alt-noise (both directions mismatch).
- DT-03-3: the code enum has 13 names in the contract order; the headline function itself returns 10 of them, the other three (offline, background, batteryCritical) are chip and banner conditions (consistent with DT-03-5). Asserted as such.

## Remaining gaps (NOT_RUN honestly)

- DT-04-6 (notification content builder and throttle) and DT-04-7 (`FakeNotificationHost`, Finish action): no production symbol exists. A test asserts the symbols are absent and fails when they appear (so the rows get written then); the foreground-notification text passed on the start request is tested (no coordinate).
- DT-04-8 to DT-04-11 (device rows) and the merged-manifest half of DT-04-2: NOT_RUN, need a phone or a build.
- DT-05-3 `/reject-extra-field` (journal schema validator) and DT-05-10 (journal to `ActivitySession` mapper): belong to the journal epic (EP-D); only the structural half of DT-05-3 (the `Fix` fields and the adapter mapping) is covered here.
- DT-01-5: the "FakeJournal file system drops unsynced bytes" half belongs to EP-D; the location and permission fake halves are covered.
- DT-01-7: the existing guards `pure_data_layer_guard_test.dart` and `import_graph_guard_test.dart` do NOT list `recording`; this group added its own pure-layer scan of `pipeline/` (in `location_seam_test.dart`); extending the old guard files is outside the folders of this group.
- DT-01-4: no `FakeNetwork` exists; the recorder has no network port, so the test runs the full flow and the import scan (DT-01-3) proves the absence of any network or upload import.
- DT-03-11 and DT-03-4 read the contract markdown by heading and by mermaid arrows; a rewording of those sections breaks them on purpose.
- No mutation run, no kill table, no analyzer, no build, no whole-suite run (operator rules).
- Test harness note: `Stream.cancel()` futures complete through the root zone, so a `fakeAsync` body cannot await them; `RecorderWorld` drives a manual `FakeAsync` and yields to the real event loop between flushes. Tests that use the world are therefore `async` and call the controller through `world.run`.
