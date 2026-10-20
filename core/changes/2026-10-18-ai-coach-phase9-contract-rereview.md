# AI Coach Phase 9: exact-tree contract re-review and timestamp clarification

Date: 2026-10-18. Kind: documentation-only Phase 9 contract follow-up.

## Scope and evidence

An actual `architect` reviewer re-read the OQ-07 and OQ-14/OQ-18 proposals, related requirements, acceptance and linked change records at exact HEAD `ea5b997ca4df8ba3e5712d5ca7bb180bf9152317`. The role was `architect`; the project instruction resolves this profile to GPT-6 Luna, medium effort. The review was read-only and found no new BLOCKER/MAJOR. It confirmed the prior OQ-07 AICR-029/AICR-082 conflict and assignment-path/policy-provenance gaps were corrected at proposal level; the OQ-14 output/source boundary, OQ-18 snapshot/recovery/persistence interface, digest and future acceptance traceability were sufficiently specified for continued owner review.

One MINOR clarification remained: `capturedAt` freshness and skew rules did not explicitly define timezone parsing, clock authority/tolerance, or rejection of implausible future timestamps. The reviewer recommended adding those semantics before implementation. This finding does not approve either proposal or close either TR contract.

## Changes

- Added explicit UTC-instant parsing requirements for OQ-14 evidence and OQ-18 snapshots; offset-less local timestamps are invalid.
- Added a versioned authoritative assembly-clock and non-negative source-clock tolerance requirement. Capture times beyond assembly time plus tolerance fail with `INVALID_TIMESTAMP`; implementations must not clamp them.
- Added `INVALID_TIMESTAMP` to OQ-14 typed evidence outcomes and the OQ-18 source/snapshot failure mapping.
- Kept numeric freshness, cross-source skew and clock-tolerance values open for GPT-PM and the responsible technical/service owner; no defaults or product thresholds were invented.
- Recorded the exact-tree re-review outcome and retained both technical proposals as proposals, not adopted/closed contracts.
- The authorized `functional-test-reviewer` revised only `docs/ai-coach/04a_FUNCTIONAL_TEST_PLAN.md`: C7 and linked FT rows now distinguish structurally invalid facts, unchanged recording/classification of valid performed facts, and assignment ceilings requiring a signed/versioned OQ-07 policy. Existing IDs were retained; result-code names remain contract-neutral. This is planned coverage only and does not claim test execution.
- Updated the acceptance and SDLC records to reflect the re-review and C7 correction without changing product decisions, owner assignments, or the 13 story dispositions.
- Re-read the original PM Bridge durable job during this follow-up: job `37c54352-2436-4955-b217-65fdf141922c`, request `26649707-679f-4962-8d26-e3b2a2ff36b2`, remains `failed` / `sendPhase=not-started` / `ATTACHMENT_NOT_LANDED`, stored payload hash `ae7bf4ff2bc39b20a9680ce2012e8298e3b1facc7ff6b8e96acee31ae5e02ecb`, no send snapshot, user turn or reply. No resend, changed payload, or duplicate request was made.

## Decisions and limits

- OQ-07/14/18 technical contracts remain open pending exact-tree GPT-PM disposition, named canonical technical/service ownership where required, and the specific product/policy decisions identified in the proposals.
- No numeric clinical limit, symptom scope, freshness threshold, cross-source skew, or clock tolerance was selected.
- No service/on-call owner was assigned; ACS-100 remains open pending actual service identity, accountable owner, recipient and delivery evidence.
- OQ-07 actual clinical values remain unavailable until a qualified human signs the values and symptom scope.
- All 13 story dispositions remain `PENDING` per operator instruction.
- No application code or runtime behavior changed. No tests, checks, builds, CI, migrations, runtime/alert actions, push or merge were performed.

## Affected paths

- `docs/ai-coach/04a_FUNCTIONAL_TEST_PLAN.md`
- `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/acceptance.md`
- `docs/ai-coach/00_README.md`
- `docs/sdlc/STATE.md`
- `docs/DOCUMENT_REGISTRY.md` (generated after the edits)
