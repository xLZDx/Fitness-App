# S02 test epic 12b (4): wipe and rebind end to end, complete runs, findings

## What changed
- New `mobile/test/features/activity/e2e/s02_wipe_and_rebind_e2e_test.dart` (3 tests) over the real `FileActivityJournal`, the real binding provider and `ActivityAwareLocalDataWipe`: delete A, the auth stream re-emits A (also around a sign-out), no scope, file or key for A reappears; B signs in and records, B intact, A gone; journal guard alone (no deleting-uid marker); failed key deletion leaves the deletion incomplete and the retry erases everything.
- Section "Epic 12b" in `docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md` with defects, exact commands and summary lines.
- The throwing-close wipe test failure was a test defect (key is created lazily); classified with evidence in the findings, assertion not weakened.

## Verification state
`flutter test test/features/activity` -> `+1264: All tests passed!`; guards plus account_deletion -> `+116: All tests passed!`.
