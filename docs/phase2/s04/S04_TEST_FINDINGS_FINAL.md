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
