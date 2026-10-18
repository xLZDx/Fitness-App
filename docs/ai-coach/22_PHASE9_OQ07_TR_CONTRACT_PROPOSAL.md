# OQ-07 limit-free technical contract proposal

Status: proposed; the initial exact-tree architect review at `862a864a6164920844115d6c9ac3edf45e0217cf` rejected adoption pending the findings recorded in `core/changes/2026-10-18-ai-coach-phase9-contract-review.md`. The revisions were re-reviewed at `ea5b997ca4df8ba3e5712d5ca7bb180bf9152317`; no BLOCKER/MAJOR findings remain, while the reviewer confirms that the contract, owner assignments, and clinical sign-off remain open. GPT-PM disposition of the detailed proposal is pending. This proposal assigns no clinical values and closes neither the product decision nor the safety sign-off. Date: 2026-10-18.

## Goal and constraints

Specify the technical boundary between assigning a proposed prescription and recording a performed workout fact, while keeping the system fail-closed when approved policy is missing. This is documentation only: it does not authorize implementation, runtime use, or numeric limits. The operator is accountable for the delegated task; Codex is the task-local technical author/executor; GPT-PM is the product decision owner/signatory; `architect` is the independent technical reviewer. No implementation service owner or qualified clinical signer is identified by those assignments.

## Non-goals

- Do not choose load, repetition, rest, age, progression, or symptom thresholds.
- Do not reject or rewrite a structurally valid fact that the user actually performed merely because it is outside a prescription ceiling; classify and route it without falsifying the fact.
- Do not treat an existing heuristic, age policy, progression helper, or model output as signed safety policy.
- Do not enable symptom-stop behavior until the symptom scope and actual numeric values have an authorized qualified-human signature.

## Options and proposed direction

| Option | Behavior | Assessment |
|---|---|---|
| A — prescription-only policy gate | Validate proposed prescriptions against a versioned authoritative policy; separately record valid performed facts and attach a typed policy/safety outcome where relevant. | Recommended: preserves factual workout history while keeping policy-controlled assignments fail-closed. |
| B — one shared cap for assignments and performed facts | Apply the prescription ceiling as a universal validator and reject every out-of-range input. | Rejected: conflates a policy recommendation with an observed event and can corrupt the record of what happened. |

## Proposed technical boundary

1. **Policy envelope.** A policy is usable only through an explicit, versioned record containing a stable policy ID and version, content digest, scope, approval-record reference, qualified-signer reference, approval/effective timestamps, expiry or supersession state, and the policy-schema version. This proposal defines no numeric limit, symptom value, or credential standard. A missing/unverifiable approval reference, signer qualification, scope match, version, or active state makes the policy unavailable; an unsigned heuristic is never promoted to policy.
2. **Freshness and invalidation.** Before assignment, resolve the policy against the current user/context identity and its authoritative record. Reject a policy that is not yet effective, is expired, revoked or superseded, has a mismatched scope/version, or cannot be checked against its authoritative source. The maximum age for mutable supporting inputs must be an explicit versioned policy field; if that value or a required source timestamp is absent, the input is not current and the assignment fails closed. No hidden client default or elapsed-time guess may supply freshness.
3. **Assignment gate.** Every value that can become an actionable recommendation must pass one policy gate before it is exposed as an assignment. The sourced paths are: `generatedPlanProvider` -> `buildPlan` -> `PlanReady`; `SafetyGate.check` inside `dispatch` step 4 for `start_workout`, `start_set` targets and `replace_exercise`; progression suggestions from `suggestNextWeight`; model-proposed loads; any future multi-week composer; and any plan loaded by `start_workout`. The gate validates load/repetition/rest against the applicable approved policy and emits a typed refusal/unavailable result when policy or required inputs are absent, invalid, stale, contradictory, or out of policy. Existing `evaluateExercise`, age-band policy and progression values are eligibility/intensity heuristics, not signed maxima; the current gate does not prove an approved OQ-07 policy is enforced. The current closed command set has no separate load-assignment command; `record_set` and `correct_set` are performed-fact operations and must not be converted into prescription checks. This path map describes the required future enforcement boundary and does not claim the current interfaces enforce it.
4. **Structural validity versus policy outcome.** The performed-set structural schema is separate from prescription policy: canonical non-empty exercise ID; integer repetitions `0..1000` (the existing design bound); finite IEEE-754 binary64 `weight_kg >= 0`, or `null` only for a bodyweight set; closed source enum `manual|voice|form_coach|wearable`; and a valid command ID/provenance envelope. The finite representation is the structural bound for weight; no policy/clinical ceiling is applied to a performed fact. A malformed event returns `INVALID_PERFORMED_FACT` and stores nothing. A structurally valid performed fact is stored unchanged even when it exceeds an assignment ceiling; its result is `RECORDED_OUT_OF_POLICY` with a separate `SAFETY_REVIEW_REQUIRED` marker when the applicable signed policy says that review is needed. Those names are proposed result codes, not claims about current implementation. They never imply that the fact or activity was safe, do not silently clamp/rewrite the report, and do not block `record_set`, `correct_set` or `void_set` solely because of an assignment ceiling. A missing signed policy cannot invent a ceiling or turn the fact into a refusal.
5. **Requirements reconciliation.** AICR-029 now separates structural rejection, proposed-assignment policy refusal, and recording an out-of-policy performed fact. AICR-082's performed-fact allowance remains in force. The corresponding acceptance oracle must independently assert all three cases; the existing test-plan rows are not silently treated as updated by this proposal. The current C7 test-plan label still says “above-limit weight/reps rejected on record” even though its body distinguishes structural checks, out-of-band confirmation and assignment caps; the authorized test owner must correct that label and reconcile its linked rows. `FT-1053` remains blocked for assignment behavior until the assignment path and signed policy exist; test authors must add/adjust coverage through the authorized `functional-test-reviewer`/`e2e-runner` route.
6. **Symptoms and explanations.** Symptom handling uses only a separately defined and signed scope. If policy, scope, or qualified signature is unavailable, no symptom threshold or list is inferred, and no clinical-safety claim is made. Any user-visible statement that a value is safe, clinically appropriate, or approved must be a deterministic rendering of a traceable result from the applicable signed policy; model prose cannot create that conclusion.

## Failure modes and recovery

| Failure | Required behavior |
|---|---|
| No approved policy/version for a proposed assignment | Typed refusal/unavailable; create no actionable assignment |
| Policy or required context is stale, contradictory, or invalid | Typed fail-closed result; request clarification or policy correction |
| Proposed assignment exceeds a current signed policy | `REFUSED_POLICY`; create no actionable assignment |
| Performed fact is structurally invalid (for example, NaN or invalid representation) | `INVALID_PERFORMED_FACT`; store nothing |
| Performed fact is structurally valid but outside an assignment ceiling | Preserve the exact fact; return `RECORDED_OUT_OF_POLICY` and the policy-defined review marker; never clamp it or claim safety |
| Symptom scope or qualified signer is missing | Keep symptom limits unavailable; do not infer values or claim approval |
| Policy result cannot be traced to its version/source | Refuse the claim-bearing result and retain no unsupported safety assertion |

## Path-to-enforcement inventory (proposal)

This inventory is based on the current code map; it separates existing paths from proposed enforcement and is not evidence that the gate is implemented.

| Current or proposed path | Current evidence | Required OQ-07 enforcement |
|---|---|---|
| `generatedPlanProvider` -> `buildPlan` -> `PlanReady` | Current deterministic single-session builder consumes a safety context; no approved OQ-07 assignment policy is evidenced. | Validate every actionable load/repetition/rest before `PlanReady` is exposed or persisted; absence of policy refuses the prescription. |
| `dispatch` step 4 -> `SafetyGate.check` for `start_workout`, `start_set` targets, and `replace_exercise` | Design §9.1 names these paths; existing `evaluateExercise`/`intensityCeiling` values are heuristics, not signed OQ-07 limits. | Add the authoritative signed-policy result to the existing typed gate for every target/replacement; an unsigned heuristic cannot satisfy the policy condition. |
| `suggestNextWeight` progression suggestion | Existing progression helper is heuristic and is not a hard safety cap. | Treat as an untrusted candidate; pass through the same assignment gate before the UI or another caller can present it as actionable. |
| Future multi-week composer and model/replacement suggestions | No multi-week composer exists; model output is not an authoritative policy source. | Composer and replacement boundaries call the same gate; they cannot mint policy or bypass a refusal. |
| `start_workout` loading a saved plan | Existing command starts a selected plan; it is not itself the policy source. | Revalidate policy identity/version and assignment before a saved plan becomes active; refuse stale or unsigned prescriptions. |
| `record_set`, `correct_set`, `void_set` | These are performed-fact journal operations; AICR-082 says performed facts are not gated by safety checks. | Apply structural validation and provenance only; preserve valid reports and attach the out-of-policy result separately. |

The policy authority, approval proof format, user/context scope, source lookup interface, and exact mappings from legacy `evaluateExercise` results to typed refusal codes remain technical interface decisions for review. No reviewer role or task-local author is represented as the future service owner.

## Rollout, rollback, and verification

No rollout is authorized. Keep prescription behavior unavailable until GPT-PM records the product-level disposition, an authorized qualified human signs actual values and symptom scope, the exact TR contract is reviewed, and implementation receives separate authorization. If an implementation later violates this boundary, disable the assignment path while preserving recorded performed facts; do not silently substitute heuristics. After implementation, `functional-test-reviewer` and `e2e-runner` should derive/run coverage for missing or stale policy, boundaries, typed refusal, performed facts beyond caps, symptom routing and provenance. This design pass ran no tests, checks, builds, CI, migrations, or runtime actions.

## Open decisions and owners

| Open item | Owner / executor | Closure evidence |
|---|---|---|
| Product-level fail-closed assignment boundary | GPT-PM, assigned product decision owner/signatory | Correlated disposition on the exact proposal/commit; original product request `26649707-679f-4962-8d26-e3b2a2ff36b2` remains failed before send and is not represented as a correlated reply |
| Technical contract review | `architect` reviewer; Codex executes revisions | Exact-tree review with BLOCKER/MAJOR findings resolved or explicitly carried; review at `862a864a6164920844115d6c9ac3edf45e0217cf` rejected adoption pending the recorded corrections |
| Actual numeric limits and symptom scope | Authorized qualified human clinical/safety signer; no named signer identified | Signed limits, scope and policy provenance before use |
| Implementation/runtime ownership | Owning service is not identified | Canonical service assignment and separately reviewed implementation evidence |
