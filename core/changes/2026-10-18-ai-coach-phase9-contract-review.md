# AI Coach Phase 9: OQ technical proposal review and remediation

Date: 2026-10-18

## Review scope and evidence

The `architect` reviewer completed a read-only exact-HEAD review at `862a864a6164920844115d6c9ac3edf45e0217cf` of:

- `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`
- the related requirements, design, test-plan references, acceptance record, and supplied product-decision evidence

The role launch used GPT-6 Luna / medium effort, consistent with the repository agent configuration. The reviewer returned one BLOCKER, seven MAJOR and three MINOR findings. Neither proposal was ready to adopt as a closed technical contract. The findings did not authorize clinical values, implementation, runtime use, story acceptance, or assignment of a technical/service owner.

## Changes

- Revised AICR-029 in `docs/ai-coach/01_REQUIREMENTS.md` to distinguish malformed performed facts, proposed assignments outside an approved policy, and structurally valid performed facts outside that policy. This resolves its direct wording conflict with AICR-082 while keeping numeric limits unavailable until signed.
- Expanded the OQ-07 proposal with policy approval/provenance and freshness fields, typed structural-versus-policy outcomes, exact performed-fact structural bounds, and a sourced path-to-enforcement inventory covering the plan provider/builder, `dispatch`/`SafetyGate.check` for `start_workout`, `start_set` targets and `replace_exercise`, progression suggestions, future composer/replacement, and performed-fact commands.
- Expanded the OQ-14 proposal with a closed user-visible factual-response envelope, deterministic rendering, typed source references, an explicit source/field allowlist, version/freshness/consistency semantics, typed evidence outcomes, and a falsifiable boundary against model-authored factual text.
- Expanded the OQ-18 proposal with per-source snapshot identity/version/timestamps and skew rules, a typed recovery-coverage shape and completeness predicate, an atomic/concurrent persistence contract, deterministic digest canonicalization, and future acceptance traceability responsibilities.
- Clarified that the separately correlated GPT-PM decision establishes the bounded OQ-14/OQ-18 product direction only. The additional OQ-07 and OQ-18 recovery `REFUSE`/`UNKNOWN` details remain sourced to the operator-supplied artifact labelled with the failed request ID, not to a correlated PM Bridge reply.
- Updated `docs/ai-coach/acceptance.md` and `docs/sdlc/STATE.md` with the exact review result and current proposal status. The acceptance record keeps the OQ contracts open, the 13 stories `PENDING`, and the technical/service-owner, clinical, on-call and PM Bridge dependencies explicit.

## Decisions and limits

- These are revised proposals, not adopted TR decisions. Exact-tree architect re-review and required GPT-PM disposition remain pending.
- OQ-07 has no clinical numeric limits or symptom scope. A qualified human signature remains required before application.
- OQ-14 source mappings and accepted freshness/consistency limits remain open; no absent mapping or threshold is guessed.
- OQ-18 freshness/skew values, recovery policy, actual persistence owner and backing transaction mechanism remain open. No production service owner is inferred.
- `functional-test-reviewer` and `e2e-runner` retain test authoring/execution ownership. The test plan was not edited; the proposal records future test-matrix needs only.
- Manual cross-document search found that test-plan table C7 still has the label “above-limit weight/reps rejected on record”, although its body separates structural validation, out-of-band confirmation and assignment caps. That label and the linked acceptance coverage remain assigned to the authorized test owner; they were not changed in this proposal pass.

## Verification

Manual source review and documentation reconciliation only. No tests, checks, builds, CI, migrations, runtime actions, alert changes, push, or merge were performed. The working tree was clean before this change; exact-tree re-review is required after the resulting commit.

## Affected paths

- `docs/ai-coach/01_REQUIREMENTS.md`
- `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/22_PHASE9_OQ07_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/acceptance.md`
- `docs/sdlc/STATE.md`
- `docs/DOCUMENT_REGISTRY.md` (generated after the edits)
