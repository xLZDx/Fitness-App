# S02 design revision 3 (closing check of architect, reliability and security)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`. Reviewed head: `dd7f84e6`.

## What changed
`docs/phase2/s02/S02_DESIGN.md` revised in place for the three closing reviews (section 15 lists every finding): account-level delete fence and late job in a top-level server-only collection written at the first deletion step; "permission denied" no longer means "deleted" (tombstone read first, `sync_conflict` otherwise, read-then-write with the next `rev`); summary batches of at most 10; seventh callable `deleteAllActivityStreams` (resumable, own quota); commit state machine with uploadId-specific object path, intended `storedSha256` recorded before promotion, stored state kept during re-upload; indexed `recomputePending` flag for the expiry recompute; journal changes (no directory fsync claim, `streamHash` and `seq`, orphan recovery, sign-out warning whenever the journal is non-empty, no client re-download); telemetry counters capped at 255 and identity as an enumeration; regex per string field in closed schemas; operations via structured log metrics and a runbook; tombstone TTL policy as an operator-owned external prerequisite; stories with a dependency graph, split upload and deletion stories, a test-id column and a step-0 prerequisite.

## Why
All three closing reviews returned NEEDS CHANGES with MAJOR findings caused or left open by revision 2; this is the remediation batch before the GPT-PM review. The test plan is aligned in the next commit.

## Affected contracts and paths
Documentation only: `docs/phase2/s02/S02_DESIGN.md`.

## Verification state
No tests or checks were run. Open assumptions listed in section 12.3: a deleted uid is never reused, the Firestore batched-write access-call limit (10 chosen, 20 reported), top-level default deny for the new server-only collection, contents of `firestore.indexes.json`. Test ids in the stories table were taken from the reviewers' lists and are checked against the test plan by the next pass.
