# Change record: v1 design gate round 2 remediation (2026-10-22)

Commit: docs(v1): address design gate round 2. Base head reviewed by the gate: fcaa90a1.

## What changed
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (version 1.3.2):
  - 4.2 step 6a: the tombstone is evaluated before any create or legacy-conversion branch; conversion requires `g == 1` and `T == 0` (B-01).
  - 8.3 item 4: a legacy delete of a typed session is quarantined as a deletion intent and never applied without the owner's explicit confirmation; `deleteWorkoutSession` takes `expectedRevision` and returns `STALE_DELETE` for a stale one (B-02).
  - 8.3 item 2: server provenance of projection writes is proved by `projectionDigest` plus `projectionRevision`, not by the marker alone; rules obligation for server-owned fields (M-03).
  - 8.3 item 2: quarantine entry and `quarantineCount` increment are one transaction that first reads the entry, so the count equals the number of unresolved entries under any retry (M-04).
  - 8.3 item 9: a late legacy write after deletion is quarantined and the projection removed.
  - 3.6 and the `effective_set` description: the table is split into an identity marker (kept) and workout values (erased on discard or removal) (M-01).
  - T17: one rule for removing an `UNKNOWN_EFFECT` record without export (M-05).
  - Section 10: FU-AC-100 order test, FU-AC-119 scenarios 11, 13, 14, 15, FU-AC-125 additions.
- `docs/v1/design/QUEUE_LIFECYCLE_DATA_PRIVACY.md`: references T17 instead of proposing it, the 1.7 table uses the marker/values split, the removal warning for `UNKNOWN_EFFECT` no longer claims that nothing is saved on any server, U19 and U20 closed, FU-AC-128 text aligned.
- `docs/v1/package-amendments/reissued/`: ACCEPTANCE.csv rows FU-AC-014 and FU-AC-082 and BACKLOG.csv FU-014 rewritten in place (old wording preserved in the note); FU-AC-119, 125, 126, 128 aligned; additional required tests for FU-AC-100 and FU-AC-103 recorded in their notes so the approved amendment text stays byte-identical.

## Why
GPT-PM gate round 2 on head fcaa90a1 returned 2 BLOCKER and 5 MAJOR; all were verified against the documents and accepted.

## Affected contracts and paths
Protocol sections 3.2, 3.3, 3.6, 4.1, 4.2, 8.3, 8.5, 10; lifecycle 1.5, 1.7, 3.5, 12; registers FU-014, FU-AC-014, 082, 100, 103, 119, 125, 126, 128.

## Verification state
Documentation only. `validate_registers.py` reports OK (requirements 56, backlog 56, acceptance 139, traceability 139, new rows 48 all NOT_RUN). Nothing was executed against an application. GPT-PM round 3 is pending for the new head.
