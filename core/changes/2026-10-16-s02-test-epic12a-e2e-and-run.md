# S02 test epic 12a (2): account-switch pass e2e, complete run, findings

Date: 2026-10-16.

## What changed

- New `mobile/test/features/activity/e2e/s02_pass_account_switch_e2e_test.dart` (3 tests): the promise
  "a sync of account A that is still running never touches account B's data" over the real
  `FileActivityJournal` on a temp directory, with a per-account recording cloud fake.
- `activity_sync_corrupt_summary_test.dart`: the SF9 oracle now expects `lastTombstonePushError` to be
  null after a clean pass (F1 contract, design 17 item 23).
- New `docs/phase2/s02/S02_TEST_FINDINGS_EPIC12.md` with the section "Epic 12a".

## Verification state

Complete run of repository, state, widgets and e2e directories: `03:14 +659: All tests passed!`
(first run had one stale-oracle failure, fixed here). No production file changed.
