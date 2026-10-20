# S02 test epic 10b: primarySourceId parity table

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `mobile/test/features/activity/data/primary_source_id_parity_test.dart` (new, 27 tests): one value table checked against the Dart mirror (`rulesViolations`), the TypeScript `sourceId` pattern and `COORDINATE_LIKE` copied literally from `functions/src/activity_streams/schema.ts` (lines 128 and 168), and the `actLabelsOk` literals parsed from `firestore.rules`. Non-strings, empty, over 64, characters outside `[A-Za-z0-9._:-]`, and coordinate-like values (`51.5007`, `x-0.1276`) are rejected; `health.connect:abc-1_2` is accepted. Guard tests fail if either source file changes its literal.

## Why
Remediation D tightened the Dart mirror; it must not drift from the deployed rules.

## Affected contracts and paths
Tests only.

## Verification state
Run by the author: 27 tests, all passed.
