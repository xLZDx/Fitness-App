# Change record: v1 design gate round 7 remediation (2026-10-22)

Commit: docs(v1): address design gate round 7. Head reviewed by the gate: 300bf9e7.

## What changed
Round 7 returned 0 BLOCKER and 3 MAJOR (protocol 1.4.2):
- 8.6 P5 (R7-M01): the clean scan is documented as a partition in time. It certifies only the documents that existed at its start; events after `backfillStartedAtMs` are handled by the trigger or by typed-command conversion, so no write is left outside typed state or quarantine whatever the lag. The compare-and-set also names the committed scan id, and the SERVER_ONLY cutover requires a quiet trigger backlog for 24 hours.
- 8.3 item 2 (R7-M02): idempotence no longer rests on the 7-day marker. Markers live 30 days; quarantine entry ids are permanent, the typed document keeps `convertedFromEventId`, the trigger retry window is a deployment invariant of at most 24 hours, and a legacy event older than 7 days at delivery raises an alert. The no-op rule runs before quarantine creation.
- 5.5 and 8.3 item 11 (R7-M03): the tombstone keeps `deletes[]` (generation and commit time per server deletion); a DELETE event whose commit time matches an entry is a server-originated no-op even if the before-image lost its server fields.
- FU-AC-100 protocol text: only a typed item that does not create a new logical session is refused after a legacy-era delete.
- FU-AC-119 scenarios 21, 22, 24 extended (protocol section 10 and reissued ACCEPTANCE.csv).

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). GPT-PM round 8 pending.
