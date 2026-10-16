# S02 test findings, epic 6a: functions stream upload, settings, tombstone and delete

Stories: S02-04a, S02-04b, S02-05a, S02-06a (plus F94 of S02-00). Jest unit tests with fakes, `functions/src/__tests__/activity/`.

## Final run

Command (cwd `functions`):
`npx jest src/__tests__/activity/ src/__tests__/abuse_guard.test.ts src/__tests__/scaling.test.ts src/monitoring/__tests__/app_check_metric_parity.test.ts`
Summary line: `Tests:       669 passed, 669 total` (`Test Suites: 17 passed, 17 total`).

## Files

Support: `support/fakes.ts` (fake bucket with generation pinning, promotion, 404, signed URL, failure injection, hooks; fake Auth; Date-only fake clock; deadlock-guarded Gate; builders; the body_scan in-memory Firestore with conflict-retrying transactions is reused unchanged), `support/flow.ts`, `support/seven.ts` (table of the SEVEN callables).
Tests: `fake_firestore_conflict` (F94), `stream_validator` (F01-F06), `closed_schema` (F51, F53), `closed_schema_strings` (F91), `canonical_reserialisation` (F52, hash helpers), `decompression_limits` (F50), `bucket_paths`, `upload` (F07-F12), `upload_fence` (F44, F87, F45), `commit_state` (F46-F49), `commit_overlap` (F84-F86), `callable_hardening` (F41, F60, F61, F62), `settings_consent` (F13, F75, F68, F82), `delete_fence` (F20-F23, F59, F76, F79, fence.ts). Edited in place: `abuse_guard.test.ts` (F83, exact set with the eight S02 names, values pinned, snake_case absent, refusal-log loop extended), `scaling.test.ts` (ten new exports registered, three scheduled jobs listed as single-flight). S01-S03 are the Storage rules tests of epic 5; U08, U09, U32, U37 and I28 are Dart tests of earlier epics.

## Production fixes (each the smallest change)

1. `upload_validate.ts`: invalid UTF-8 was reported as `bad_json` under jest because the TextDecoder `TypeError` comes from another realm; the check now also compares the error `name`.
2. `commit_stream.ts` `writeIntendedHash`: two concurrent commits of the SAME upload id: the second failed with `superseded` after the first had stored the row. It now returns `already_stored` (F47).

## Contradictions (design followed)

- F03: plan says exactly +/-90 and +/-180 are rejected; design 5.1 and the code say inclusive. Tests assert accepted.
- F50: plan says ratio exactly 20 rejected; code and design: 20 accepted, 20 + 1 byte rejected.
- F13: plan says 90/365/730 refused; design 5.3 offers exactly these. Tests assert accepted.
- F45: plan says a create over a stored row writes a `pending` row; design 5.2 (and F86) keeps `state = stored` and adds the pending marker.
- F61: plan says the over-limit log line contains the uid; design 5.4 redacts the uid. Tests assert no uid.
- F91: plan lists a geohash as rejected; design 5.1a states it cannot be detected. A test pins the honest limit.
- Design 17.3 effect: `importedAt` with two or more fractional digits is rejected as coordinate-like although the fixture regex allows six; the Dart builder cuts to whole seconds. Pinned by a test.

## Not modelled or not covered

- Firestore rules gate (stale `rev`, F94 clause): emulator tests of epic 5.
- Gate hook `betweenFirestoreDeleteAndSweep` and the account deletion order: epic 6b (F56, F77, F78, F95).
- F63-F67, F69-F74, F80, F81 (beyond the quota/continuation facts in F82), F88-F90, F92, F93, F95, F96: other epics.
- The fake Firestore replaces a nested map on `set(..., {merge: true})`; real Firestore merges nested maps. Assertions avoid depending on `acceptedAt` surviving a withdrawal.
- A second concurrent same-id commit arriving after the first deleted the quarantine object gets `upload_missing` (client retry gets `already_stored`); not changed.
- Jest reports one worker that "failed to exit gracefully" (open handle, not diagnosed); all suites pass.
