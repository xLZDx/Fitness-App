# Change record: v1 design gate round 6 remediation (2026-10-22)

Commit: docs(v1): address design gate round 6. Head reviewed by the gate: 7d619cb7.

## What changed
Round 6 returned 1 BLOCKER and 5 MAJOR against the eager-conversion design (protocol 1.4.0); the removal of the legacy-only class was accepted. Fixes inside the new design (protocol 1.4.1):
- 8.3 item 10(c): the no-op rule compares the full normalized legacy model (all `WorkoutSession` fields and every set, with no missing set or exercise); any difference, including a removal, becomes a quarantine entry (R6-B01).
- 8.2 and 8.6 P5: DRAIN entry has two phases. In phase `BACKFILL` the trigger already works in DRAIN mode and typed commands are held; the account moves to phase `OPEN` only after a clean scan started after `backfillStartedAtMs`; the 30-day clock starts at phase `OPEN` (R6-M01).
- 8.3 item 5 and 4.2 step 6b: sessions created by the backfill or the trigger are writerless (`writerTokenHash = null`, `writerEpoch = 0`); the first authenticated typed item claims atomically, takeover also works on a writerless session (R6-M02).
- 8.3 item 2 and 10(b): a processed-event marker `workout_legacy_events/{sessionId}~{eventId}` is written by every trigger run and checked first, so redelivery of any event, including the one that converted a session, changes nothing (R6-M03).
- 8.3 item 11: DELETE events are classified using the generation of the `before` image against the typed generation and the tombstone, so a delayed server deletion of generation 1 never becomes an intent for generation 2 (R6-M04).
- Section 10 FU-AC-100 text corrected to the non-authoritative legacy delete (R6-M05); the validator now rejects the withdrawn wording in the protocol document.
- FU-AC-119 scenarios 18b, 21 extended, 22, 23, 24 (protocol section 10 and reissued ACCEPTANCE.csv).

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). GPT-PM round 7 pending.
