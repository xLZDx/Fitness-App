# Change record: v1 design gate round 5 remediation (2026-10-22)

Commit: docs(v1): address design gate round 5. Head reviewed by the gate: 3bb60dd7.

## What changed
Round 5 returned 2 BLOCKER and 2 MAJOR, all in the long-lived "legacy-only session" class that rounds 3 and 4 had added (ledger, deletion fence, reader exception). Instead of patching a fifth time, that class is removed.
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (version 1.4.0):
  - 8.3 item 10 rewritten: eager conversion. A server backfill converts every existing session at entry to DRAIN (new precondition P5 in 8.6); afterwards the trigger converts the event's own snapshot of any never-seen or overtaking event into a typed session, so every later or reordered legacy event is class A (quarantined, never overwritten). A legacy delete is never authoritative in DRAIN or later: it is recorded as a deletion intent and the document is recreated until the owner confirms through `deleteWorkoutSession`.
  - The legacy ledger, the `LEGACY_DELETE` tombstone source and `LEGACY_DIVERGENT` entries are removed (5.3, 5.5, 8.3 item 5, 8.7).
  - 8.3 item 11: every real session has a head after backfill, so existing legacy workouts stay visible with provenance `LEGACY_UNVERIFIED`; a projection that fails the head check is "verifying".
  - 8.4: the account export includes unresolved quarantine entries (also in the lifecycle document).
  - Section 10: FU-AC-119 scenarios 13, 18, 20, 21 rewritten.
- `docs/v1/package-amendments/reissued/ACCEPTANCE.csv`: FU-AC-082, FU-AC-119 aligned; note on FU-AC-049.
- `docs/v1/design/QUEUE_LIFECYCLE_DATA_PRIVACY.md`: server-side data in the export; deletion list.

## Product consequence (for the operator)
A workout deleted in an OLD app build reappears with a review prompt until the owner confirms the deletion in a current build. This follows from the operator decision of 2026-10-22 (no silent loss of legacy data).

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). GPT-PM round 6 pending.
