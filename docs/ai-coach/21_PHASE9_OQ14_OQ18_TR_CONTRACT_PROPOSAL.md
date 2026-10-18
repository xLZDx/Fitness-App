# OQ-14 and OQ-18 bounded TR contract proposal

Status: proposed; exact-tree independent architect review and GPT-PM decision-owner disposition are pending. Neither TR contract is closed. Date: 2026-10-18.

## Goal and constraints

Translate GPT-PM's accepted product directions into the smallest technical boundary consistent with current repository interfaces. This proposal is documentation only. It does not authorize implementation or runtime use. GPT-PM is product decision owner/signatory; Codex is technical author/executor; `architect` is independent reviewer. None of these assignments creates a production service owner.

## Non-goals

- Do not choose clinical limits, symptom policy, progression values, or other product-owned rules that depend on OQ-07 or a separate GPT-PM decision.
- Do not claim that current AI Coach interfaces implement these contracts or that input digests prove source freshness or cross-source consistency.
- Do not activate a feature, persist an active plan, assign an operational on-call recipient, accept the 13 pending stories, or replace qualified-human clinical/safety sign-off.
- Do not allow model-generated factual prose or model-selected numeric/schedule policy as a fallback when evidence or policy is missing.

Current interface evidence is recorded in [`01b_CODE_MAP.md`](01b_CODE_MAP.md#interface-facts-rechecked-2026-10-18-oq-18) and [`13_PHASE9_OQ_TECHNICAL_REVIEW.md`](13_PHASE9_OQ_TECHNICAL_REVIEW.md): `AiCoachContext` does not currently carry structured factual evidence and `AiCoachService.advise` returns free-form text; `PlanReason` is typed but has no source reference/version; Form Coach results are transient; `buildPlan` is a pure single-session builder, and no multi-week composer or persistence contract exists. Recovery evidence is a 14-day lookback, not a forward projection. Visual equipment matches are candidates, not confirmed access. The volume ledger's target/secondary-weight values are product heuristics, not approved weekly policy.

## Options and chosen bounded direction

| Area | Option A | Option B | Decisive criterion | Proposal |
|---|---|---|---|---|
| OQ-14 factual responses | Typed evidence-bound claims rendered by deterministic templates | Arbitrary model prose plus token/reason validator | Absolute factual grounding cannot be established by checking a finite set of number tokens or reason codes in arbitrary prose | A, matching GPT-PM's ACCEPT |
| OQ-18 composition | Pure application-owned composer reusing the existing single-day builder | Model chooses schedule, exercise selection, numeric prescriptions, or future recovery | Determinism, source traceability and approved safety policy must remain outside model generation | A, matching GPT-PM's ACCEPT |

## OQ-14 proposed contract

1. A factual response is composed from typed claims; each claim has a closed claim kind, canonical typed value/unit where applicable, and an explicit permitted evidence reference. Reason claims use closed typed reason codes. A technique claim requires a specific current Form Coach result and its typed cue/rep evidence; it is not generalized into clinical or safety evidence.
2. Claim-bearing factual text is rendered through deterministic localized templates. The model may not add factual numbers, measurements, reasons, diagnoses, technique conclusions, health conclusions, or prescriptions as free-form text.
3. Canonical values and units are validated and normalized before locale formatting. The eventual evidence schema must identify source kind and source reference/version and define capture-time/freshness semantics before a claim can be considered current. The current interfaces do not provide a common version or freshness token; this proposal does not assert one exists.
4. Missing, stale, ambiguous, contradictory, or unparsable evidence yields a typed unavailable/refusal/clarification outcome and no factual claim. A response containing a factual claim without its required evidence is refused rather than repaired with model inference.
5. This contract cannot claim runtime capability today: the current AI Coach context/service has no claim/evidence schema. OQ-14 stays open until the schema, permitted-source map, version/freshness rules, validation outcomes, and template coverage are specified and reviewed.

## OQ-18 proposed contract

1. A future composer is a pure local function over an immutable copied input, an explicit schema/policy version, and explicit ordered day slots. The output is a draft only; it is not active or persisted by this contract.
2. For each day, apply training-context candidate narrowing and its paired safety-context transformation before calling the existing pure single-day `buildPlan`. Preserve stable day order; every selected exercise must be present in the filtered candidate input. A model cannot choose the schedule, exercise set, weekly volume, sets/reps/rest, progression, or numeric prescriptions. Model-authored explanation may use non-factual phrasing only; any factual claim about a generated draft must follow the OQ-14 source-bound claim, evidence-reference, and deterministic-template contract.
3. Any missing required input/policy or any `PlanRefused` aborts the whole draft with a typed refusal; do not emit or persist a partial plan. The composer never writes planned sets into observed workout history or the volume ledger.
4. Keep observed deficit and projected planned volume distinct. No adaptive projection or feedback into later days/weeks is permitted until a separately versioned and approved formula defines how completed/scheduled/planned sessions interact.
5. Recovery may use only the currently evidenced window; do not extend a 14-day lookback verdict into unsupported future weeks. Recovery input must carry an explicit evidence-coverage state distinct from a negative deload verdict: empty, insufficient, stale or invalid evidence is never interpreted as recovered/no deload. The operator-provided response artifact labelled request `26649707-679f-4962-8d26-e3b2a2ff36b2` records the product decision to REFUSE when a recovery-dependent draft requires a judgment and coverage is insufficient; this artifact is not correlated to a PM Bridge turn/reply. `UNKNOWN` never implies `RECOVERED`. A recovery-independent draft may proceed only under a separately approved product policy that establishes no recovery judgment is needed; this decision does not create such a policy. The existing `DeloadVerdict`/`detectDeload` interface currently returns a boolean/factor and can return `shouldDeload: false` for empty evidence; it does not satisfy this proposed coverage contract. Visual matches remain candidate inputs until separately confirmed as available equipment.
6. A future persistence contract must bind a generation key to a canonical input/policy digest, make identical retries idempotent, reject conflicting content under the same key, and commit the draft atomically. Replay of a previously committed result belongs to that persistence/idempotency boundary; the stateless composer itself only derives a draft from its supplied snapshot. The digest identifies the inputs used; it does not prove freshness or a coherent cross-source snapshot. Persistence remains a separate implementation contract because no composer or plan persistence currently exists.
7. OQ-18 stays open until input/source versions and freshness semantics, day-slot acquisition, policy versioning, generation identity, atomic persistence/conflict behavior, and explicit refusal outcomes are reviewed. Weekly prescription/progression values remain unavailable until OQ-07's approved policy exists.

## Failure modes and recovery

| Failure | Required result |
|---|---|
| Missing, stale, ambiguous, contradictory, or invalid OQ-14 evidence | Return unavailable/refusal/clarification; emit no factual claim |
| OQ-14 rendered claim has no traceable source or violates its closed kind/value rules | Refuse the claim-bearing response; do not fall back to free-form prose |
| OQ-18 required input or versioned policy is missing | Refuse the entire draft; create no partial or active plan |
| A day builder returns `PlanRefused` | Refuse the entire draft and preserve the typed reason; do not continue with fewer days |
| Persistence retry uses the same generation key and canonical inputs | Persistence returns the prior identical result; the pure composer does not perform replay lookup |
| Same generation key is reused with different canonical input/policy digest | Refuse as a conflict; preserve the first result |
| Atomic persistence fails | Keep the draft uncommitted/inactive and allow a safe idempotent retry |

## Rollout, rollback, and verification plan

No rollout is authorized by this proposal. Keep the feature unavailable until GPT-PM signs the bounded technical direction, the architect approves the exact contract, OQ-07 policy dependencies are signed where needed, implementation is separately authorized, and required functional/E2E evidence is complete. If later implementation violates a boundary, disable the affected path and retain the last known-safe planner behavior; do not silently downgrade to free-form generation, partial plans, or heuristic weekly limits.

After implementation, `functional-test-reviewer` and `e2e-runner` should derive and run tests for claim provenance, normalization, invalid evidence, technique-source binding, deterministic multi-day output, context/safety ordering, builder refusal, idempotent replay, conflict refusal, atomic persistence failure, and separation of planned from observed volume. This design pass ran no tests, checks, builds, CI, migrations, or runtime actions.

## Open decisions and owners

| Open item | Owner / executor | Closure evidence |
|---|---|---|
| Approve or revise this detailed technical proposal | GPT-PM product decision owner/signatory; `architect` reviews technical correctness | Correlated exact-tree GPT-PM disposition plus architect review |
| OQ-14 evidence schema, permitted source map, versions and freshness | Codex technical executor; architect reviewer; GPT-PM decides product-impacting freshness/scope | Versioned schema and source-to-claim table, reviewed at exact tree |
| OQ-18 source snapshot/freshness, recovery evidence-coverage state, day-slot inputs, atomic persistence semantics | Codex technical executor; architect reviewer; GPT-PM decides whether a draft may proceed without a recovery adjustment when coverage is insufficient | Interface, versioning, explicit unknown-recovery behavior, and conflict contract reviewed at exact tree |
| OQ-07 numeric limits and symptom scope | Authorized qualified human clinical/safety signer; GPT-PM product signatory | Signed values and symptom scope; remain unavailable until then |
| Real ACS-100 alert receiver and delivery | GPT-PM accountable for routing; owning runtime service/on-call owner is not identified | Named rotation in canonical operations record and successful delivery evidence |

## Evidence and approval boundary

The accepted product direction is evidenced by the correlated PM Bridge reply and durable decisions listed in the [execution and route record](20_PHASE9_EXECUTION_OWNERSHIP_AND_REVIEW_ROUTE.md) and [product-disposition change record](../../core/changes/2026-10-18-ai-coach-oq14-oq18-product-dispositions.md). It authorizes recording a bounded technical proposal, not treating this proposal as already reviewed or approved. The `architect` profile must review the exact proposal tree; GPT-PM must then record its disposition on that same tree (or the exact resulting commit). A review role is not the assigned product decision owner. Codex is the delegated executor/author only. The owning runtime service remains unidentified.

The architect's earlier read-only finding supports the selected direction but is not approval of this document: OQ-14 needs a source/evidence schema and freshness map; OQ-18 needs snapshot/version, day-slot, policy, and persistence semantics. Until those definitions are completed and accepted, both technical OQs remain open. No clinical value is inferable from this proposal.
