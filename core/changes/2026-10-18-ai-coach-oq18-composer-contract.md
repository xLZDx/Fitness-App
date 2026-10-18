# AI Coach: propose deterministic multi-week composer contract

Date: 2026-10-18. Documentation-only technical design for the open TR portion of OQ-18.

## Goal and non-goals

Define a deterministic boundary for composing a multi-week plan from the existing single-session planner while keeping exercises and numeric prescriptions outside model authority. This does not approve training values, clinical rules, a default schedule, cross-device sync or implementation.

## Design and alternatives

`docs/ai-coach/03_DESIGN.md` §13.1 compares three options and proposes a pure application-owned composer that calls `buildPlan` for each planned day, then applies an immutable versioned `PlanningPolicySnapshot`. A model-generated full plan and model-filled prescription fields are rejected because they break reproducibility and the candidate/safety boundary. The proposed input is explicit plan intent, an immutable safety/context/candidate snapshot, and the approved policy. Missing or unsigned policy, stale safety input, any refused day, candidate mismatch or invalid prescription refuses the entire draft; no partial plan is active or persisted. The draft records policy version and stable digest. The model may explain only.

## Ownership, failure and compatibility

The composer is pure and owns no mutable workout Runtime state. The caller owns snapshot freshness and draft persistence. TR must still define persistence idempotency and version conflicts. The proposal is additive for AI-COACH-03; it changes neither existing `buildPlan` nor workout history and requires no migration. Missing policy or a disabled feature means no composition; existing manual flows continue. OP/TR must approve actual weekly schedule/progression and all load/rep/rest values under OQ-07. The operator/product owner decides how plan intent and day slots are collected. No named TR owner is present in project records.

## Paths

- `docs/ai-coach/03_DESIGN.md`: proposed §13.1 contract and corrected OQ-18 cross-reference.
- `docs/ai-coach/01_REQUIREMENTS.md`: A-06 and OQ-18 current status.
- `docs/ai-coach/02_BACKLOG.md`: OQ-18 and AI-COACH-03 blocker wording.
- `docs/ai-coach/acceptance.md`: OQ-18 proposed status and remaining TR review.
- `docs/sdlc/STATE.md`: Phase 9 status notes that the proposal remains unapproved.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after edits.

## Verification plan and state

In the implementation phase, `functional-test-reviewer` should derive coverage for deterministic repeat output, stable ordering, candidate subset, policy version, fail-closed missing/invalid inputs, whole-draft refusal and no partial persistence. This is a future plan only; no tests were authored or run. Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents. Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN. Push and merge: not performed.

## Unknowns and remaining acceptance

TR review is required for policy schema/version, snapshot freshness, candidate ordering, persistence/idempotency and conflict handling. OP/TR decisions are required for actual weekly values under OQ-07. OQ-18 remains open; this proposal is not approval or implementation authorization.
