# S04 final test run

Head: ecd46403 plus uncommitted fix-pass changes (pipeline files, tests). Branch phase2/s04.

## Final command (run from mobile/)

`flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout --timeout 600s`

Result: 1096 passed, 0 failed, 0 skipped (exit 0). No repo-wide suite, no analyze, no build.

## Triage of the three failures reported in the wider run

| Test | Class | Evidence | Action |
|---|---|---|---|
| s04_15_16_lifecycle_test DT-15-10 | Test defect (stale docs text check) | Failed deterministically in two full runs. The contract line next to GPS-PRIV-014 now reads "S04 clarification, APPROVED by the operator on 2026-10-17"; the test required the old text "S04 proposed clarification". | Test now accepts either recorded state; the PROPOSED, 30 days and requirements-doc checks are kept. |
| s04_11_append_flush_test DT-11-6 | Not reproduced; not wall-time dependent | Uses fakeAsync and a seeded LCG, no DateTime.now or Stopwatch; passed in all three full runs. | None. |
| s04_26_31_journal_test DT-26-5 | Not reproduced; load-sensitive only through its 8 minute test timeout | Measure-only: timings are printed, not asserted. Alone: pass (write 7.9 s, seal 8.5 s, open 18.9 s). Passed in two of three full runs. In the first full run of this session it showed no error lines in the tail. | None. If it recurs under load, widen the Timeout in that test. |

## Fix applied

- mobile/test/features/recording/journal/s04_15_16_lifecycle_test.dart (DT-15-10): accepts the approved clarification wording.
- No production code changed in this pass.

## Per-group findings files

- docs/phase2/s04/S04_TEST_FINDINGS_EP_A_B_C.md
- docs/phase2/s04/S04_TEST_FINDINGS_EP_D.md
- docs/phase2/s04/S04_TEST_FINDINGS_EP_E_H.md
- docs/phase2/s04/S04_TEST_FINDINGS_EP_F_G_J.md

## NOT_RUN

| Item | Status | Reason |
|---|---|---|
| Device-lab rows (battery, lock screen, screen-off notification, engine detach, TalkBack) | NOT_RUN | no phone |
| Mutation runs | NOT_RUN | operator rule |
| flutter analyze, build, CI, repo-wide suite | NOT_RUN | outside the requested scope |
| Tests outside the three named folders | NOT_RUN | not part of this set |

## Round 2 after code review

Working tree: branch phase2/s04, HEAD 03143df3 plus uncommitted FIX-A and FIX-B. Leftover flutter_tester processes were killed first. Each folder was run separately from `mobile/` with `flutter test <folder> --timeout 120s` under a shell timeout.

Hang found: not a production deadlock. `test/features/recording/pages/fix_b_pages_test.dart` (U3 Back test) called `await w.ctl.stop()`, which never completes under the fake clock of `testWidgets`; the other two tests in the file were reported "did not complete" with it. Fixed in the test: Stop and Finish are tapped through the screen. A second test defect: `find.byType(PopScope)` matches no `PopScope<Object?>`; the test now uses a type predicate.

Other failures fixed:
- `recording/l10n` DT-27-3 and DT-28-7: FIX-A added `developer.log('expired')` (removed from `file_recording_journal.dart`) and expiry helper names; the DT-28-7 scan now whitelists the local quarantine-sweep identifiers only.
- `gps_strip/record_entry_points_test.dart` DT-24-18: with a pending revoked decision (U4) the record sheet correctly shows the enabled Open row, not Start; the stale expectation was updated.

New focused tests: U5 shell stays silent while the recording page is open (`gps_strip_widget_test.dart`, "U5 one announcer"). Existing FIX-B tests: U1/U2 `stream_location_source_test.dart` (4), U3/U5 `fix_b_pages_test.dart` (3), U6/U7 `fix_b_consent_gap_test.dart` (3), U4 `gps_sources_test.dart` and `record_entry_points_test.dart`.

Per-folder results (all green after fixes): location, pages 127, widgets 94, consent 58, permissions 56, safety 45, l10n 68, pipeline 204, battery 106, gps_strip 82, gps_signout 31.

Final complete set: `flutter test test/features/recording test/shared/widgets/gps_strip test/features/activity/gps_signout --timeout 300s` -> `+1119: All tests passed!`

Not covered: U6 real battery/services-off wiring (gap is stated on the Start panel only); no whole-repo suite, analyze or build was run.

## Known gaps at code gate

- Real battery monitor and services-off probe are not wired (the gap is stated on the Start panel only).
- The manual-entry page is missing; `/record/manual` redirects.
- The recorder has no public `releaseAll`.
- The native notification fallback text is not done.
- The offline chip is never set.
- `formulaVersion` is still `rec1.smooth-wma5-1`.
- NOT_RUN: device-lab rows, whole-repo analyze, build, CI, and manifest gate E8.
