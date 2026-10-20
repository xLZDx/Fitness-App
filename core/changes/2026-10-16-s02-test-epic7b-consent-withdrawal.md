# S02 test epic 7b: consent withdrawal tests (I28) and findings

## What
`activity_consent_withdrawal_test.dart` (12 tests): withdrawing stops queued and in-flight uploads (before PUT, before commit, during backoff), nothing is sent after a restart, the bulk-delete option is offered, `deleteExisting` is sent exactly once and only when chosen, not choosing leaves cloud streams, local data and summaries are untouched. Adds `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md` (epic 7b section: defects, plan wording issues, exact final command and result).

## Why
Plan row I28 and design 9.1.

## Affected paths
- `mobile/test/features/activity/repository/activity_consent_withdrawal_test.dart`
- `docs/phase2/s02/S02_TEST_FINDINGS_EPIC7.md`

## Verification state
Final run: `00:55 +198: All tests passed!` (command in the findings file).
