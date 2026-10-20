# S02 remediation D: rules mirror primarySourceId (A12 parity)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/support/firestore_rules_parser.dart`: the hand-written mirror of `actLabelsOk` now checks `primarySourceId` against `^[A-Za-z0-9._:-]{1,64}$` and denies coordinate-like values (a digit, a dot and two or more digits), the same as `firestore.rules` and the `sourceId` rule in `functions/src/activity_streams/schema.ts`. It was a type-and-length check only.
- `docs/phase2/s02/S02_REMEDIATION_D_TEST_NOTES.md`: assertion for the mirror.

## Why
Remediation A12 tightened the rules; the test-support mirror had to follow so the Dart parity tests cannot drift from the deployed rules.

## Affected contracts and paths
Test-support only; no production behaviour change.

## Verification state
Not run in this commit by design; the test agents run the parity tests.
