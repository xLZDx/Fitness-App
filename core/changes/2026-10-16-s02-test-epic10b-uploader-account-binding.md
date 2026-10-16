# S02 test epic 10b: uploader account binding and single-flight tests

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/repository/activity_stream_upload_account_binding_test.dart` (new): for a uid flip to another uid and to null at each of five points (before create, before PUT, before commit, before `markStreamUploaded`, before the `upload_failed` mark) the run ends `cancelled`, no later fake-server call is made and the journal is not marked; plus controls, `runPending` stopping before the next entry, and single-flight checks (concurrent `runPending` share one run; concurrent `uploadEntry` for one id share one upload; different ids and finished runs are not merged).
- `mobile/test/support/stream_upload_world.dart`: `makeUploader` takes an optional `currentUid` (additive).

## Why
Remediation C (FL5) added account binding and single-flight to the uploader; the oracle is `docs/phase2/s02/S02_REMEDIATION_C_TEST_NOTES.md`.

## Affected contracts and paths
Tests and test support only.

## Verification state
Run by the author: 20 tests, all passed (`flutter test` on this file from `mobile/`).
