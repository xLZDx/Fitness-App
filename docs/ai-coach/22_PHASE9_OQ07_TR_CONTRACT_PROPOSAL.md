# OQ-07 limit-free technical contract proposal

Status: proposed for exact-tree `architect` review and GPT-PM product disposition. This proposal assigns no clinical values and closes neither the product decision nor the safety sign-off. Date: 2026-10-18.

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

1. Prescription assignment requires an explicit, versioned authoritative policy. If policy, required user/context inputs, or policy version is absent, stale, contradictory, or invalid, return a typed refusal/unavailable outcome and issue no prescription.
2. Validate proposed load/repetition/rest assignments against that policy before making them actionable. Preserve the source policy/version and typed reason for any rejection or clarification. No value is supplied by this proposal.
3. A user-reported performed set is a distinct event from a proposed assignment. Validate its structural parse and provenance; preserve a structurally valid performed fact even if it exceeds a prescription ceiling. Attach a typed out-of-policy/safety-review outcome and use the separately approved symptom response, if one exists. Do not silently clamp, discard, or rewrite the performed values.
4. Symptom detection uses only a separately defined and signed symptom scope. If that signed policy is unavailable, do not invent a symptom list or claim clinical safety; return the defined safe unavailable/escalation behavior only after GPT-PM and the qualified human signer establish it.
5. No AI-generated explanation may assert that a value is safe, clinically appropriate, or approved unless that conclusion is a deterministic rendering of a traceable policy result.

## Failure modes and recovery

| Failure | Required behavior |
|---|---|
| No approved policy/version for a proposed assignment | Typed refusal/unavailable; create no actionable assignment |
| Policy or required context is stale, contradictory, or invalid | Typed fail-closed result; request clarification or policy correction |
| Performed fact is valid but outside prescription policy | Preserve the performed fact; attach the typed out-of-policy/safety route; never clamp it into a different fact |
| Symptom scope or qualified signer is missing | Keep symptom limits unavailable; do not infer values or claim approval |
| Policy result cannot be traced to its version/source | Refuse the claim-bearing result and retain no unsupported safety assertion |

## Rollout, rollback, and verification

No rollout is authorized. Keep prescription behavior unavailable until GPT-PM records the product-level disposition, an authorized qualified human signs actual values and symptom scope, the exact TR contract is reviewed, and implementation receives separate authorization. If an implementation later violates this boundary, disable the assignment path while preserving recorded performed facts; do not silently substitute heuristics. After implementation, `functional-test-reviewer` and `e2e-runner` should derive/run coverage for missing or stale policy, boundaries, typed refusal, performed facts beyond caps, symptom routing and provenance. This design pass ran no tests, checks, builds, CI, migrations, or runtime actions.

## Open decisions and owners

| Open item | Owner / executor | Closure evidence |
|---|---|---|
| Product-level fail-closed assignment boundary | GPT-PM, assigned product decision owner/signatory | Correlated disposition on the exact proposal/commit; existing request `8a1a6c41-4f21-4d0c-a44e-202610184201` failed before send and cannot be represented as a reply |
| Technical contract review | `architect` reviewer; Codex executes revisions | Exact-tree review with accepted findings resolved or explicitly carried |
| Actual numeric limits and symptom scope | Authorized qualified human clinical/safety signer; no named signer identified | Signed limits, scope and policy provenance before use |
| Implementation/runtime ownership | Owning service is not identified | Canonical service assignment and separately reviewed implementation evidence |
