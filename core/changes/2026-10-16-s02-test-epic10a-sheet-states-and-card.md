# S02 test epic 10a: sheet states test and entry card fix (FL2)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/widgets/sync_conflict_sheet_states_test.dart` (new, 8 tests): spinner before first emission, empty text only after a loaded empty state, error and retry after a stream error, retry re-subscribes and the following emission shows the conflict, entry card visibility rules.
- `mobile/lib/features/activity/widgets/activity_sync_entry_card.dart`: the card is also shown when the load failed (defect D10a-1: it was hidden, so the retry action was unreachable).
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC10.md` (new): epic 10a section.

## Why
Remediation C item FL2 and the reachability of the retry action.

## Affected contracts and paths
Flag-off behaviour unchanged (the card still builds nothing and never reads the presenter). With the cloud flag on, a failed load now shows the entry card.

## Verification state
`flutter test test/features/activity/state test/features/activity/widgets test/features/activity/repository/activity_sync_test.dart test/features/activity/repository/activity_sync_corrupt_summary_test.dart` : `+47: All tests passed!`
