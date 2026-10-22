# Change record: v1 design gate round 3 remediation (2026-10-22)

Commit: docs(v1): address design gate round 3. Head reviewed by the gate: 3d166137.

## What changed
- `docs/v1/design/OFFLINE_COMMAND_PROTOCOL.md` (version 1.3.3):
  - `deleteWorkoutSession` takes `expectedSessionGeneration` and `expectedRevision`; both are compared in one transaction, a mismatch of either returns `STALE_DELETE` and changes nothing (revision numbers restart with a generation).
  - 8.3 item 2: server provenance is a keyed seal (`projectionSeal`, HMAC) on every server-written projection instead of a comparison with the latest digest, so delayed and repeated events of older server revisions verify; the digest field is removed from the typed document. Repair, quarantine entry and counters run in one transaction that reads the typed document and current projection, so a repair cannot overwrite a newer typed state.
  - 8.3 item 10 and 8.4: three session classes (typed, deleted, never-seen) with one outcome each; an account-level quarantine summary and `getLegacyQuarantine()` without a session id make post-delete data discoverable; readers hide an unverified restored projection during the repair window.
  - 3.3: `appendExists = false` branch (new APPEND allowed), while a marker with `appendExists = true` never allows an APPEND.
  - 3.1 and 3.2: `serverStateUnknown` is a field of the canonical record; `SIGNOUT_REMOVE` also covers the confirmed no-file removal (`exportedAt = null`).
  - Section 10: FU-AC-119 scenarios 11 (ABA), 14, 15 extended, 16, 17, 18; FU-AC-125 additions.
- `docs/v1/design/QUEUE_LIFECYCLE_DATA_PRIVACY.md`: S6 text aligned with the schema field and discard source.
- `docs/v1/package-amendments/reissued/ACCEPTANCE.csv`: FU-AC-082 (per session class), FU-AC-119, FU-AC-125 aligned; cross-references in the notes of FU-AC-100 and FU-AC-103 corrected.

## Why
GPT-PM gate round 3 on head 3d166137 returned 1 BLOCKER and 6 MAJOR, all consequences of the round 2 rewrite; each was checked against the text and accepted.

## Verification state
Documentation only. `validate_registers.py` OK (56/56/139/139, 48 new rows NOT_RUN). Nothing was executed against an application. GPT-PM round 4 pending.
