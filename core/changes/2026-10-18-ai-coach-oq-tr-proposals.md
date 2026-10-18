# AI Coach Phase 9: limit-free OQ-07 and bounded OQ-14/OQ-18 TR proposals

Date: 2026-10-18. Documentation-only technical design update; no product implementation or runtime behavior changed.

## Why

The operator assigned GPT-PM as product decision owner/signatory and delegated the technical documentation to Codex. GPT-PM accepted bounded product directions for OQ-14/OQ-18, but the repository still lacked task-local technical proposals; OQ-07's product request failed before send. The project rules require separating Codex as executor from GPT-PM's product authority, qualified-human clinical authority, and any production service owner.

## Changes

- Added `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md` translating accepted OQ-14/OQ-18 product directions into bounded technical proposals. It records structured source-bound claims, deterministic templates and fail-closed handling, plus a pure local composer, immutable inputs, candidate/safety filtering, typed abort, explicit insufficient-recovery coverage, observed/projected separation, persistence-boundary idempotency, and OQ-14 constraints on factual explanations.
- Added `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md` specifying the separation between prescription assignment and performed facts. It deliberately supplies no load, repetition, rest, progression or symptom values and leaves qualified-human safety sign-off intact.
- Updated `docs/ai-coach/acceptance.md` to identify Codex as task-local technical author/executor, the `architect` profile as independent reviewer, GPT-PM as product decision owner/signatory, and the remaining GPT-PM detailed-proposal dispositions as open. OQ-07, OQ-14 and OQ-18 are not marked closed.
- Updated `docs/ai-coach/03_DESIGN.md`, `docs/ai-coach/20_PHASE9_EXECUTION_OWNERSHIP_AND_REVIEW_ROUTE.md`, the AI Coach README and `docs/sdlc/STATE.md` to retire contradictory unsigned defaults and the old arbitrary-prose OQ-14 validator text, preserve owner/executor/signatory/service boundaries, state unknown-recovery behavior, and prohibit factual-explanation bypass of OQ-14.
- Updated `docs/DOCUMENT_REGISTRY.md` from the resulting documentation tree.

## Evidence and decisions

GPT-PM's OQ-14/OQ-18 product dispositions are accepted and correlated under request `e5024ec8-f0ec-4a15-a3d3-68a8daa7a073`, user turn `fe4cd638-5f39-4f68-a10e-5482e7dae331`, reply `17ab61ae-fcfb-4bcf-b491-beac80ac9e21`, and durable decision IDs `AICOACH-OQ14-PRODUCT` / `AICOACH-OQ18-PRODUCT`. They permit bounded TR proposals but do not approve these detailed proposals. The OQ-07 request `8a1a6c41-4f21-4d0c-a44e-202610184201` failed before send with `ATTACHMENT_NOT_LANDED`; it has no correlated reply and cannot be reported as sign-off. Earlier architect recommendations inform the proposals but do not constitute exact-tree approval. No qualified clinical signer or runtime/on-call service owner is named in the scoped records.

## Follow-up evidence

- The `architect` reviewer approved the bounded OQ proposal on staged tree `6545ab3682e8079493f5f2a0e7b159c1d172f025`; `doc-updater` approved accuracy and traceability on the same tree. These are documentation-scope reviews and do not identify a canonical runtime service owner or constitute clinical sign-off.
- GPT-PM's earlier OQ-14/OQ-18 ACCEPT remains product-direction only. A later request for the detailed proposals, OQ-07 product gate, and ACS-100 routing used request `26649707-679f-4962-8d26-e3b2a2ff36b2` / job `37c54352-2436-4955-b217-65fdf141922c`, but failed before send with `ATTACHMENT_NOT_LANDED` (`acceptance.md` missing from the composer). It has no `userTurnId`, `replyId`, generation lease or send snapshot and its request lineage remains active. No GPT-PM disposition or signature resulted; do not alter or replace that request until the PM Bridge failure is safely resolved.
- Codex is explicitly assigned only as task-local TR documentation lead/executor. The future production service owner, ACS-100 on-call recipient and qualified clinical/safety signer remain unidentified.
- Follow-up review on staged tree `4f9817963551424ffde17e2dc50af4b0ca3e522a` closed two stale design statements: §17 no longer assigns the operator as alert owner, and §23 OQ-07 now matches §9.4's fail-closed rule. The `architect` review found no remaining in-scope BLOCKER/MAJOR/MINOR; `doc-updater` approved consistency and registry coverage (371 indexed documents, changed indexed-file byte counts matched). Neither review supplies the missing GPT-PM disposition, qualified clinical signer, or ACS-100 operational recipient. No tests, checks, or builds were run.

Any further review must name the exact tree and preserve the separation between recommendation, approval, product authority, clinical sign-off, and service ownership.

## Verification state

Manual document and link review only. The document registry generator was run as a local documentation-generation step. No tests, checks, builds, CI, migrations, runtime actions, alert configuration, push or merge were run or performed. Tests and runtime verification remain future work after implementation authorization and code completion.

## Remaining acceptance

1. The `architect` exact-tree review and `doc-updater` evidence review are complete for staged tree `6545ab3682e8079493f5f2a0e7b159c1d172f025`; re-review only if substantive proposal content changes.
2. Obtain GPT-PM's disposition for the detailed proposals after the active failed PM Bridge lineage is safely resolved; do not treat the earlier OQ-14/OQ-18 product-direction ACCEPT as TR contract approval.
3. Obtain authorized qualified-human signature for actual OQ-07 limits and symptom scope before use.
4. Identify the AI Coach runtime service and real on-call rotation for ACS-100, configure delivery, and capture delivery evidence.
5. Keep all 13 story dispositions PENDING until the operator explicitly reviews them on the then-current acceptance revision.
