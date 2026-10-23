# Slice V0 plan (2026-10-23)

Status: PLAN, NOT IMPLEMENTED. Source of scope: section 6 of `PRE_IMPLEMENTATION_CONDITIONS_2026-10-22.md` and protocol v1.5.10 (`OFFLINE_COMMAND_PROTOCOL.md`).

## Scope
One `CompleteSet` for one user, one session, one exercise, one logical set: local durable commit, canonical payload (hashVersion 2), stable operation id, minimal server fence and receipt, pending and synced display behind an interface, lost acknowledgement, identical replay.

## Excluded
Any feature activation, `DRAIN`, backfill, voice and ML work, account-deletion changes, route refactors, the watchdog and the audit inventory.

## Negative evidence required
Crash before and after the local commit; lost response; second identical submission; altered payload under the same id; uid mismatch; second APPEND to the same logical set; server mutation and receipt in one transaction.

## Exit
Deterministic Dart and server tests and emulator tests pass on the same revision, and no new collection is writable through the owner wildcard.

## Work packages (to be refined by the recon report)
1. Server: carve-outs and rules tests for the new collections first (protocol 5.3), then the apply transaction (4.2 steps 1 to 8 restricted to CompleteSet APPEND), behind a flag that keeps the callable undeployed or off.
2. Mobile: canonical payload and hash, durable local store with a unique index on the operation id, sender, status interface.
3. Shared fixture: golden canonical payloads iterated by Dart and server tests.
4. Tests written and run by the test-writing agents per epic; the coordinator runs none.
