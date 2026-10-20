# S02 test epic 6b: retention, recompute, purge and index limits (S02-05b)

## What
New `retention_purge.test.ts` covering F14-F19, F63-F67, F88, F89 (and F71 row 9 missing-index signal). Shared fakes extended: the body_scan fake Firestore now maps orderBy("__name__") to the document id, refuses range filters on null or mismatched types (as Firestore does), and exposes `fx.checkQuery`; the activity FakeBucket gained `getFiles` listing and creation times; new `support/indexes.ts` enforces the parsed `firestore.indexes.json` (FAILED_PRECONDITION, code 9).

## Why
Retention, derived expiry, resumable recompute and the index contract of design 5.3 had no tests. Plan F18 says lengthening resurrects an expired row; design 5.3 says it does not, so the test follows the design.

## Affected paths
- `functions/src/__tests__/activity/retention_purge.test.ts`
- `functions/src/__tests__/activity/support/indexes.ts`
- `functions/src/__tests__/activity/support/fakes.ts`
- `functions/src/__tests__/body_scan/fakes.ts`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/retention_purge.test.ts`: 1 suite, 27 tests passed. Regression of the edited shared fakes: `npx jest src/__tests__/activity src/__tests__/body_scan`: 23 suites, 943 tests passed.
