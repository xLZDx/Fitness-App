# Change record: v1 design gate round 4 remediation (2026-10-22)

Commit: docs(v1): address design gate round 4. Head reviewed by the gate: ae119f26.

## What changed
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (version 1.3.4):
  - 8.3 item 10: class C (never-converted legacy session) writes are accepted AND appended to a server-only legacy ledger (idempotent by event id, deduplicated by content hash); conversion (item 5) turns every divergent ledger entry into a `LEGACY_DIVERGENT` quarantine entry, so conversion is never the first moment of preservation (B-01).
  - 8.3 item 10 and 5.5: a legacy delete of a class C session writes a deletion fence (tombstone with `source = LEGACY_DELETE` and `deleteEventTime`); classification uses Firestore commit times, not trigger order; the delete trigger re-reads the current projection so a stale write that landed first is still quarantined as `POST_DELETE_WRITE` (B-02).
  - 5.3: the summary and head documents are carved out of the wildcard with owner read and no client write (M-01).
  - 8.3 item 11: a server-only head document (revision, content hash) lets readers verify a class A projection without any secret; unverified projections are excluded from history, progress, coach context and export (M-02).
  - 8.3 item 11: DELETE events are classified by the typed document, the tombstone `source` and `before`, never by an `after` seal (M-03).
  - 8.4: "restore as a new workout" choice for post-delete entries; 8.7 and lifecycle deletion lists include the new collections.
  - Section 10: FU-AC-119 scenarios 13 and 18 extended, 19, 20, 21 added.
- `docs/v1/package-amendments/reissued/ACCEPTANCE.csv`: FU-AC-082, FU-AC-119 aligned; note on FU-AC-063.
- `docs/v1/design/QUEUE_LIFECYCLE_DATA_PRIVACY.md`: deletion list.

## Why
GPT-PM gate round 4 on head ae119f26 returned 2 BLOCKER and 3 MAJOR, all in the class handling added in round 3; each was checked against the text and accepted.

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). Nothing was executed against an application. GPT-PM round 5 pending.
