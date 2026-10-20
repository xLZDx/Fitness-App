# Phase 9 correlated GPT-PM ownership and source-policy decision

Date: 2026-10-19. Documentation-only record of a fresh PM Bridge chat and correlated GPT-PM product decision for supplied HEAD `afc8507dee3d21b3b2cfe71c5cd822d42f174b80`.

## Request and correlation

- Project: `fitness_app_aicoach`; branch supplied: `docs/ai-coach-tdd-001`.
- Fresh conversation: `6ad55dbf-82f0-83eb-9180-9b441149ddf3`; the previous conversation was preserved.
- Request: `d4ec1090-fc55-40d5-bf39-2b87ad98852a`.
- Send job: `0fa7be7a-6900-45bc-b45d-f9fee733c988`; confirmed `sendPhase=sent`, user turn `b6de683a-ec75-4b15-a85f-5f6ce24f4e70`.
- The original send-and-await call reached its parked wait deadline. No replacement ID or duplicate send was created. Same-ID await harvested the response; the await job `df1d36fc-9401-4fd0-8898-32f2f0ad09ec` recorded reply `3fc1b7aa-1a34-423e-ba42-9aef96579a7b` with `correlated=true`.
- Ten text/code attachments were sent: `21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`, `ai_coach_context.dart`, `ai_coach_service.dart`, `ai_coach_advice.ts`, `workout_session.dart`, `scheduled_session.dart`, `deload_detector.dart`, `training_context.dart`, `visual_equipment_match.dart`, and `app_settings.dart`. GPT-PM's response treated them as candidate-interface evidence; it did not authenticate Git ancestry, live data, runtime behavior, or deployment.
- PM Bridge appended its generic execution-authority envelope, including a `PUSH: AUTHORIZED` statement, to the submitted request. GPT-PM's correlated reply explicitly states that this decision authorizes no tests, deployment, push, or merge. No push/merge action was taken.
- Earlier request `5f75bd8c-e546-4f23-a44d-c22f538ab031` remains a separate uncertain lineage. A prior chat peek showed text without durable turn/reply correlation. That text is not used as a binding disposition and the old request was not resent or mutated.

## GPT-PM disposition

Overall: `PARTIAL ACCEPT — TR OPEN`.

### Ownership

| Responsibility | Decision | Boundary |
|---|---|---|
| Project accountability | Operator | Accountable project owner |
| Product policy and non-clinical decisions | GPT-PM | Approves claim permissions, classifications, and policy values |
| OQ-07/OQ-14/OQ-18 technical contracts | Codex | Technical owner, author, executor, and task-local self-reviewer under operator delegation |
| Clinical/safety sign-off | Qualified human signer | Clinical values remain unsigned |
| ACS-100 owning component | Fitness_App AI Coach | Accepted project-local component, not a deployed service identity |
| ACS-100 technical investigation | Codex | Organizational responsibility only |
| Interim human escalation role | Operator | Not a configured alert recipient |

ACS-100 operational fields remain: deployed service ID `NOT_IDENTIFIED`; recipient endpoint and transport `NOT_CONFIGURED`; delivery and acknowledgement `NOT_VERIFIED`; disposition `CARRIED / OPEN`. Closure requires deployed service identity, alert-emission configuration, a reachable recipient endpoint, ownership/rotation record, and successful delivery plus acknowledgement evidence.

### OQ-14 factual claims

- Accept the closed typed-claim architecture; deny factual claims from the current unverified AI Coach input path.
- Request/catalog identity is denied for current factual use; later catalog-backed use is deferred until server-validated canonical identity, record version, and field mapping exist.
- Workout and scheduled-session claims are deferred. Candidate retrospective/scheduled fields do not establish immutable revisions, capture times, freshness, or a coherent snapshot; a scheduled session is not a completed workout.
- Sensitive questionnaire data is not to be disclosed to the cloud model. Non-sensitive training-context claims remain deferred and cannot imply medical eligibility or clinical conclusions.
- Recovery claims are deferred. `shouldDeload == false` is not proof of recovery, and no future recovery projection is authorized.
- Visual matches are denied as confirmed identity/access; only explicitly tentative matching claims may be considered later.
- `ru` and `en` are accepted as UI-language capabilities, not complete factual-rendering locales. Missing claim/template/translation/number/unit mappings suppress the factual envelope. No quantity rounding, unit conversion, numeric precision, or locale fallback is approved.
- Future claims require product-approved claim/source/field/type/unit mappings, stable identity/version, authoritative capture time, integrity/availability state, measured and approved freshness/clock/skew rules, complete non-contradictory evidence, and deterministic versioned rendering. Missing any required condition suppresses the factual response; no default threshold is inferred.

### OQ-18 composition and recovery

- Accept the pure application-owned composer and target snapshot schema, while populated source-to-snapshot mappings remain deferred.
- Accept fail-closed freshness semantics, complete evidence-backed coverage when recovery is required, and strict separation of `UNKNOWN` from `RECOVERED`.
- Defer numeric freshness/skew, recovery-required classes, recovery horizon/interval, and calendar/day-slot policy. Existing historical lookback and detector heuristics do not establish future policy values.
- Accept canonical digest plus linearizable create-if-absent as target requirements; actual storage technology, persistence owner, and conformance remain unresolved.
- Reaffirm `observed_projected_combination = DISABLED`, explicit UTC/offset timestamp semantics, refusal for incomplete required recovery coverage, and no heuristic fallback.

## Decisions still open

- OQ-14 populated claim allowlist, source identity/version, freshness measurements, clock authority/tolerance/skew, complete factual templates/locales, and numeric/unit normalization.
- OQ-18 populated snapshot mappings, measured freshness/skew, recovery-required classifications/horizon, calendar/day-slot policy, and persistence implementation/conformance.
- OQ-07 clinical values and symptom boundaries require a qualified human signature.
- ACS-100 remains open until deployed service identity, endpoint/transport, rotation, delivery, and acknowledgement are evidenced.
- All 13 story dispositions remain `PENDING`.
- No TR contract closure, implementation/production approval, test/deployment authorization, push, or merge was granted.

## Affected paths and verification

- Updated `core/DECISION_LOG.md`, `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`, `docs/ai-coach/acceptance.md`, `docs/ai-coach/00_README.md`, and `docs/sdlc/STATE.md` with the correlated decision and boundaries.
- Added this decision record and regenerated `docs/DOCUMENT_REGISTRY.md`.
- No tests, checks, builds, CI, migrations, production/runtime changes, alert configuration, push, or merge were performed.
