# AI Coach Phase 9 remediation and operator handoff

Date: 2026-10-20. Documentation-only change.

## What changed

- `docs/ai-coach/24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md`: replaced open B-01–B-06 placeholders with a concrete documentary proposal for an in-document receipt ledger, process-recovery epoch, server-callable mutation path, legacy-client rule carve-out, UI lifecycle, AICR-074 mapping, and writer/reader/export outcomes.
- `docs/ai-coach/01_REQUIREMENTS.md`: made the AICR-074 offline exception operation-specific and distinguished pre-reservation unsent capture from submitted UNKNOWN/pending work.
- `docs/ai-coach/02_BACKLOG.md`: recorded AC-8–AC-11 for identity/receipts, old-client denial, epoch-fenced recovery and reader/export compatibility; updated AI-COACH-01 gate state.
- `docs/ai-coach/03_DESIGN.md`: reconciled current status with the selected documentary proposal and latest withheld authorization.
- `docs/ai-coach/acceptance.md` and `docs/ai-coach/23_PHASE9_ACCEPTANCE_RECONCILIATION_2026-10-20.md`: recorded exact correlated request/job/turn/reply identifiers, B — CODE NOT AUTHORIZED (3 BLOCKER, 3 MAJOR), and the limits of the proposed remediation without changing any story disposition.
- Added `docs/ai-coach/25_PHASE9_STATUS_AND_HANDOFF_2026-10-20.md`, a dated evidence-based timeline and per-criterion acceptance matrix, and `docs/ai-coach/26_AI_COACH_NEXT_AGENT_PROMPT_2026-10-20.md`, a detailed next-agent prompt.
- Included the pre-existing untracked `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md` unchanged at the operator's instruction to commit all current in-scope work. Its original author/provenance is not attributed to this turn.
- Regenerated `docs/DOCUMENT_REGISTRY.md` using the repository's document registry generator.

## Why

The exact-scope GPT-PM review `3e612e9f-1d41-4e78-8ee8-ff9a3886f431` was successfully sent and correlated but returned B — CODE NOT AUTHORIZED, with three blockers and three major findings. The operator requested a local commit, a detailed prompt for another agent, and an account of AI Coach work from October 16 through October 20. The durable records start on October 17; the handoff explicitly marks October 16 development work NOT_VERIFIED.

The proposed fixes address receipt identity/replay/retention, old-client full-document writes, process-death recovery, lifecycle, AICR-074 and repeated-set reader/export semantics. They remain proposals until a focused review accepts them and an exact authorization permits implementation.

## Evidence and decisions

- Product request `4b6238a0-1c80-4d69-87ba-45a214fc7e31`: job `4176bb29-d3f1-42a8-920c-e7f562f42ee0`, turn `313be192-99de-436e-bc12-0ddd545f0a16`, reply `5e446c22-bca5-464f-9fac-c167648855d4`; Option A accepted, implementation not authorized.
- Exact-scope review `3e612e9f-1d41-4e78-8ee8-ff9a3886f431`: job `e679c280-0658-453f-acb0-b8852eee3cf6`, turn `68be0956-a5f1-443c-b366-afd06461ff39`, reply `e1c0abe7-d91a-4337-b2dc-7fc617812ded`; `sendPhase=sent`, one attempt, correlated; verdict B, 3 BLOCKER and 3 MAJOR.
- `firestore.rules:84-126` grants broad owner collection reads/writes and does not exclude `workout_sessions`; Firestore's permissive matching means a nested deny cannot override the wildcard. Scope proposal therefore requires a wildcard carve-out and server-callable path.
- The natural October 20 ACS-100 query recorded in reconciliation F-07 returned HTTP 200 without a `timeSeries` field. This is OBSERVABILITY UNKNOWN, not a zero-traffic/health conclusion; no synthetic request was generated.
- Current source records cited in the scope document identify the whole-document `.set`, four-second timeout, both workout player callers, best-set projection, direct set consumers, projected mobile export and capped raw server export.
- All 13 story dispositions remain PENDING. OQ-07 has no qualified clinical signature or approved values. OQ-14/OQ-18 product inputs remain deferred. ACS-100 remains OBSERVABILITY UNKNOWN and alert delivery NOT_VERIFIED.

## Verification and limits

Documentation was reviewed against the cited source paths and PM Bridge response. `python scripts/dev/gen_document_registry.py` regenerated the document registry. No tests, checks, builds, CI, migrations, code changes, Firestore rules/schema changes, runtime operations, alerts, synthetic AI traffic, deployment, push or merge were performed. The proposed callable, epoch fence, capacity and rules carve-out are not runtime-proven and await focused GPT-PM review.

## Commit linkage

This detailed record is intended to be included in its own local commit with the files listed above. No push is authorized.
