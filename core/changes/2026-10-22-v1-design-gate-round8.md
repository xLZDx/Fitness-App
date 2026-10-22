# Change record: v1 design gate round 8 remediation (2026-10-22)

Commit: docs(v1): address design gate round 8. Head reviewed by the gate: e1bd259b.

## What changed
Round 8 returned 0 BLOCKER and 2 MAJOR (protocol 1.4.3):
- 8.3 item 2 (R8-M01): the trigger transaction checks, in a fixed order, the processed-event marker, then the permanent quarantine entry of the same event in any status, then `convertedFromEventId`, and only then continues; the entry is created with a create that fails if it exists. A resolved entry is therefore never recreated or recounted after its marker expires.
- 5.5, 8.3 item 11, 8.5 (R8-M02): a server deletion is identified by the exact `createTime` of the projection incarnation that the deletion transaction itself deleted (stored in the tombstone `deletes[]`), compared for equality with the `createTime` of the DELETE event's before-image. No time proximity, window or heuristic is used; if the trigger SDK does not expose it, the outcome is a visible deletion intent, never a silent no-op.
- FU-AC-119 scenarios 21 and 24 extended (reordered events with near timestamps, createTime unavailable, resolved-entry redelivery).

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). GPT-PM round 9 pending.
