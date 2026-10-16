# Stale presenter test fix and findings 16c (epic 16c, 2/2)

Date: 2026-10-16. Kind: test fix and test findings.

## What changed
- mobile/test/features/activity/state/sync_conflict_presenter_test.dart: containers now override syncConflictUidProvider (J3 B4 makes a tap without a uid a no-op).
- docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md: section 16c.

## Why
The first complete activity run failed seven presenter tests and one hung past the timeout; cause was the missing uid, not a product defect.

## Affected contracts and paths
Test code and documentation only.

## Verification state
Activity directory: 1485 passed. Account deletion, architecture, backup, parity and n07 set: 120 passed.
