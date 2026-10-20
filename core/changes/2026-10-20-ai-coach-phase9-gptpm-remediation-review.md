# AI Coach Phase 9 — remediation review result and next-agent handoff

Date: 2026-10-20. Documentation-only change.

## What changed

- Recorded the correlated GPT-PM full adversarial review of the B-01–B-06 documentary remediation.
- Corrected current scope, backlog, design, acceptance and handoff records to show that the remediation is not yet accepted and implementation remains unauthorized.
- Expanded the next-agent prompt with the four new blockers and five major findings, plus source-verification instructions.
- Added Russian and English HTML status reports under `reports/` with timeline, acceptance matrix, source links and limitations.
- Regenerated `docs/DOCUMENT_REGISTRY.md` after the report pair was added.

## Why

The initial documentation-only remediation was committed as `b9622b62d23014db1d96e083389d58e6db79deb9`. Its exact-scope adversarial review returned MODIFY, identified four blockers and five major findings, and did not authorize code. The review called its epoch-fence argument incomplete and identified a missing first-session creation path. This change keeps the status accurate and gives the next agent the complete actionable finding set.

## Correlated review evidence

- Request ID: `d4e49bc9-5e5f-49d9-9ce1-dfa1b4929be3`.
- Project: `fitness_app_aicoach`; attached documents used baseline `b9622b62d23014db1d96e083389d58e6db79deb9`.
- Send-and-await job: `8a583e44-a2da-4841-ab8c-d30ea1a35c1d`; `sendPhase=sent`, one attempt. The client wait deadline elapsed while parked, so this send job remained `uncertain`; it was not treated as a failed or unsent request and was not resent under a new ID.
- Follow-up await job: `1223a444-e4db-4d21-85b4-30c226bd3ad8`; status `succeeded`, `correlated=true`; user turn `e3e9edc9-d560-4c3d-83df-e5c1477f20fc`; reply `0235ced0-50e1-4500-aa38-a644a8a7b956`.
- GPT-PM verdict: **MODIFY — 4 BLOCKER, 5 MAJOR, 0 MINOR; CODE NOT AUTHORIZED**. Prior B-01–B-06 were not all closed. The bounded Option A product choice remains accepted.
- Evidence boundary: GPT-PM reviewed eight attached documents, including the code map, but stated it did not independently reopen Dart/TypeScript files, authenticate Git ancestry, execute transactions or verify production. Its findings are design/protocol counterexamples, not reproduced runtime incidents.
- Transport note: the send snapshot included generic `GO: AUTHORIZED` and `PUSH: AUTHORIZED` footer text, while the logical request did not. Neither is used as authorization; the correlated GPT-PM verdict explicitly says CODE NOT AUTHORIZED.

## Findings recorded

### Blockers

1. **B-01 — Receipt canonicalization.** The proposal did not define canonical bytes and field-by-field normalization for absent/null fields, numeric values, timestamps, correction targets or identity fields. Required: per-operation schemas, canonical serialization/hash inputs, result shape, and same-ID/same-payload versus same-ID/different-payload examples.
2. **B-02 — Reservation/epoch recovery.** A `RESERVED` operation from an old epoch has no specified ownership/fence-transfer or takeover transition after recovery increments the epoch. Required: atomic recovery/takeover, state transitions, and exhaustive transaction orderings.
3. **B-03 — First-session creation.** The callable assumes an existing session although the reviewed player creates its first `WorkoutSession` during the first completion action. Required: bounded idempotent, authorization-checked creation in the existing collection, or evidence of another creation path that always precedes completion.
4. **B-04 — Mixed-version cutover.** The wildcard carve-out direction is viable, but there is no full rules/writer/create/delete inventory, cutover/rollback plan, or older-client refusal UX. Required: complete inventory, preserved owner reads, coordinated rollout and explicit denied queued-write behavior.

### Major findings

1. **M-01 — Receipt limits.** Exact size accounting, pending-payload growth, map-key cost, document/index constraints, transactional preflight and contention budget are missing. The 256-ID/64-KiB values are not measured.
2. **M-02 — Pending UI lifecycle.** Late callback ownership, failed reauthentication, takeover and permanently unresolved receipts need a session-scoped pending-operation coordinator and full lifecycle matrix.
3. **M-03 — Correction mismatch.** The three included operations do not define a correction operation, while §3 and the matrix describe one. Either specify/authorize correction or explicitly defer it and prove the current correction path is not silently changed.
4. **M-04 — Analytics compatibility.** Legacy reps feed readers with heterogeneous semantics. Required: before/after examples for legacy/new/replayed/corrected/null-repetition records naming every reader; preserve legacy displays unless separately accepted.
5. **M-05 — Server authority/deletion.** The callable's contract omits account-deletion fencing, app-integrity/App Check decision, server-side eligibility/session-state validation, trusted sources and privileged-writer inventory.

The reviewer’s epoch counterexample is: device A commits `RESERVED(X, epoch=7)`, submits apply, then recovery fences to epoch 8; the old apply is rejected, while no authorized transition lets recovery adopt or terminally resolve X. The epoch can prevent stale writes but does not by itself guarantee recovery progress. This is a protocol counterexample derived from the proposal, not an observed production failure.

## Current implementation and verification state

- No application code, Firestore rules/schema, tests, CI, migrations, runtime, alert policies, deployment, push or merge were changed or run in this remediation pass.
- `python scripts/dev/gen_document_registry.py` completed successfully and wrote 375 documents.
- No tests or checks were run. The proposed mechanism remains documentary and implementation/runtime NOT_RUN.
- The earlier local documentation commit `b9622b62…` remains committed. The pre-existing untracked `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md` was included unchanged in that earlier commit at the operator’s explicit instruction; its origin is not attributed to this turn.

## Next actions

1. Verify all current source paths in this repository: writers/readers, session creation, rules overlaps, delete/clear paths, account deletion and server callables.
2. Resolve the nine findings together in the documentary contract without inventing clinical/product values. Keep correction and analytics behavior explicit and preserve existing behavior unless approved.
3. Attach the revised current documentation to one complete adversarial GPT-PM re-review under a fresh request ID. Do not interpret a generic injected footer as authorization.
4. Do not start implementation, tests, rules/schema work, production changes, push or merge unless a fresh correlated response authorizes that exact scope and all repository safeguards are met.

## Commit linkage

This detailed record must be committed in the same local commit as its documentation and HTML status-report updates. No push is authorized by this record.
