# S04 test findings, group EP_F_G_J (epics EP-F, EP-G, EP-J)

Status: COMPLETE for the code-testable parts. Device rows, mutation runs and CI were not run (see gaps).

Branch phase2/s04, HEAD 1d76b05e (working tree, nothing committed). Author: test-author agent for group EP_F_G_J.

## Stories covered

- EP-F: S04-22 (battery critical behaviour), S04-23 (battery protocol document).
- EP-G: S04-24 (strip, independent sources), S04-25 (record sheet, shortcut, GPS recording page, 13 display states, layout contract).
- EP-J: S04-30 (sign-out guard, account events, pre-unbind hook), S04-33 (consent surface, withdrawal), S04-34 (start preconditions), S04-35 (automatic-stop state), S04-36 (manual pause), S04-37 (engine detach), S04-38 (release checklist document).
- Only the code-reachable parts of S04-31 (sanitising) and S04-32 (notification content) are NOT covered here (see gaps).

## Files (all under mobile/test)

Shared harness (not test files): features/recording/pages/recorder_harness.dart, features/recording/pages/page_harness.dart.

- features/recording/battery/battery_critical_test.dart, battery_protocol_doc_test.dart (S04-22, S04-23)
- shared/widgets/gps_strip/gps_sources_test.dart, gps_strip_widget_test.dart, record_entry_points_test.dart (S04-24, S04-25 sheet and shortcut)
- features/recording/pages/gps_page_states_test.dart (S04-25 page, 13 states, layout), ep_j_flow_test.dart (S04-34/35/36/37 on the real controller), start_panels_test.dart (Start screen panels, S04-33/34)
- features/recording/widgets/consent_row_test.dart (S04-33), gps_scans_test.dart (DT-25-1, 25-2, 25-14 scans and gps_format), release_gate_doc_test.dart (S04-38), start_pause_detach_test.dart (S04-34..37, controller level, overlaps ep_j_flow_test and adds the battery-critical-while-paused row)
- features/activity/gps_signout/gps_signout_test.dart (S04-30 guard and notice), account_events_test.dart (S04-30 bind controller and hook)

## Commands

Complete set, run once at the end (working directory mobile):

`flutter test --no-pub test/features/recording/pages test/features/recording/widgets test/features/recording/battery test/shared/widgets/gps_strip test/features/activity/gps_signout`

Per-file runs were used while fixing. No whole-suite run, no analyze, no build.

## Results

Final complete run: 432 passed, 0 failed, 0 skipped.

Per area at the last separate runs: battery 106, gps_strip 80, gps_page_states 47, ep_j_flow 53, start_panels 24, consent_row 16, gps_scans 25, release_gate_doc 15, start_pause_detach 35, gps_signout 17 (guard) plus account_events.

Test defects found and fixed (not production): fake-async hangs on awaited stream cancels (fixed with runAsync and unawaited calls plus flush), pending zero-duration timers, wrong semantics helpers, shared sheet flag leaking across tests, a start-count assertion in a restart test.

## Production bugs found and fixed (every production change)

1. mobile/lib/features/recording/state/recorder_controller.dart: `battery.readings.listen(_onBattery, onError: (Object _) {})`. A battery stream error was an uncaught async error (S04-22: a failing battery source must never affect the recording).
2. mobile/lib/features/recording/pages/gps_recording_page.dart:
   - the 30 s weak-signal hint and the announcement gate used `DateTime.now()`; they now use the recorder environment clock (`_poorSinceMs`, `_nowMs`, `_nowForGate`), so they follow the recording clock.
   - the battery announcement is sent after the frame and names the current reading (it used a stale or fallback value).
   - added the assertive `gpsAnnBatteryFinish` announcement when a battery stop begins (the string existed and was never used).
   - acquiring now shows the recovered moving time (0:00 for a fresh run) instead of the running total.
   - at text scale above 1.3 the GPS signal indicator moves under the headline; at scale 2.0 on 360x640 the header row overflowed by 157 px (en) and 210 px (ru) (DT-25-15).

## Remaining gaps (NOT_RUN or not covered, stated honestly)

- All device-lab rows (battery runs DT-22 device, lock screen, screen-off notification DT-32-6/35-5, DL-16 engine detach, TalkBack) are NOT_RUN: no phone.
- Mutation runs, CI and analyze were not run (operator rule).
- DT-23-2 record validator is test-local: no production validator exists, the document is the only artifact.
- The sample-cap automatic stop (190000 samples) is covered only by the notice-set table, not by driving the cap.
- S04-31 sanitising sinks and S04-32 notification builder content are not tested here (the notification builder is outside the five folders).
- The acquiring-time jump in the pipeline and several unused announcement strings were seen and not changed.
- No status exists for a pending-revoked decision in the strip projection beyond what gps_sources_test covers.
- A GpsRecordingOwner `''` capture is a hypothesis, not tested.
- The 5 s hook bound test waits in real time (about 5 s).
