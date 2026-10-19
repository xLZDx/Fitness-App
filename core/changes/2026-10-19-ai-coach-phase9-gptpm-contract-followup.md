# Phase 9 GPT-PM technical-contract follow-up

Date: 2026-10-19  
Scope: document-only incorporation of GPT-PM's targeted OQ-07 and OQ-18 amendments; OQ-14 decision provenance; no implementation authorization.

## Baseline and provenance

- Local baseline commit: `aa49017d9b947e917720e8138a39a92260e1e4c9` on the active AI Coach documentation branch.
- Exact local proposal attachments sent: `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md` (SHA-256 `7b697a4ccf3617ed1859f356f14f52357bd79b300eff13472529442ffb32a78d`) and `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md` (SHA-256 `9b942f703c5e1655dc057e4f8d77c20cc0aebaf9f2c1401de5d34a207313aa4c`).
- PM Bridge request: `6f1c2a4e-8b73-4d95-a2c6-1e0f7b34d8a9`.
- Durable send-and-await job: `c8bed96e-ed05-4483-bed3-3bb53b8e3980`, status `succeeded`, `sendPhase=sent`, one attempt, no send uncertainty.
- Correlation: project `fitness_app_aicoach`, conversation `6ad656cf-7c4c-83ed-89f0-fd349f19ba1a`, user turn `9581e461-83de-419c-9504-ada1061bdd27`, reply `4143be11-e4c2-4341-9c4c-ce26eb7ac37d`, `correlated=true`.
- GPT-PM treated the commit as operator-supplied and did not authenticate its Git ancestry. The local baseline is observable from this checkout; no remote ancestry claim is made.

## Decision

GPT-PM returned `MODIFY` overall, with these bounded decisions:

| OQ | Decision | Required work / remaining boundary |
|---|---|---|
| OQ-07 | `MODIFY` | A structurally valid performed fact is stored unchanged when the applicable signed policy cannot be verified. Classification is `POLICY_CLASSIFICATION_UNAVAILABLE`, never `WITHIN_POLICY`, `RECORDED_OUT_OF_POLICY`, or clinically safe. Fact, provenance and classification are associated atomically, or the record has an explicit pending/unavailable classification. Reclassification against the applicable versioned policy is deterministic and independently auditable and never changes the fact. Actual policy values, symptom scope and qualified-human signature remain unapproved and open. |
| OQ-14 | `ACCEPT` | The limit-free typed source-bound claim, versioned allowlist, deterministic rendering and fail-closed refusal boundary is sufficient. Populated product-approved source/claim mappings, source versions, measured freshness/clock/skew, templates and formatting remain open. |
| OQ-18 | `MODIFY` | Each generation has a deterministic user-scoped identity. The programme header and all generated scheduled-session documents become atomically visible under that identity. IDs, expected document counts, digest metadata and replay results are deterministic or transactionally persisted. No reader treats partial materialization as accepted/active. Conflicts, authorization failures, transaction-size limits, or unprovable atomic visibility fail closed without partial writes. Conformance includes existing programme/schedule readers and security rules. Product inputs and runtime persistence evidence remain open. |

GPT-PM explicitly did **not** grant implementation/code GO. It did not approve clinical values, qualify a signer, authorize tests, migrations, Firestore/security-rule changes, alert changes, deployments, or production activation. The response reviewed attached documentation only and did not independently verify repository contents or runtime behavior.

## Changes made in this follow-up

- Added OQ-07 unavailable-classification semantics and separate deterministic/auditable reclassification without mutating performed facts to `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md`.
- Added OQ-18 generation identity, atomic visibility, no-partial acceptance, and reader/security-rule conformance clauses to `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`.
- Updated the six-item acceptance matrix and project overview to distinguish GPT-PM ACCEPT/MODIFY decisions from remaining product, clinical, implementation and operations gates.
- Recorded that focused verification of the two incorporated amendments is pending; neither is marked closed before that review.

## Verification and remaining work

- Manually compared the incorporated text with the exact GPT-PM reply and the attached contract files.
- No source code, test, check, build, CI, migration, runtime, alert, production, push, or merge action was performed.
- Next: send only the amended OQ-07 and OQ-18 clauses for focused GPT-PM verification, using a new request ID and these exact files. If accepted, close only their document-level contract statuses. If modified, incorporate the exact requested wording and ask for one focused confirmation.
- Independent remaining gates: qualified-human OQ-07 signature and actual signed values/symptom scope; OQ-14 approved source mappings and measured freshness/templates; OQ-18 approved product inputs and implementation/persistence conformance under a separate code GO; ACS-100 fresh natural metrics and real delivery/acknowledgement; 13 story dispositions remain PENDING by operator direction.
