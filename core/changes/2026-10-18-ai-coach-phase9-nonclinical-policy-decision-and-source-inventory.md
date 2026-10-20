# Phase 9 non-clinical policy decision and source inventory

Date: 2026-10-18  
Status: GPT-PM decision correlated; repository inventory documented; detailed TR contracts remain open.  
Project: Fitness_App AI Coach  
Current pre-change HEAD: `35dc21db55d2c57b756a10815981b8f0b3f03c25`

## What changed

- Recorded GPT-PM's correlated non-clinical OQ-14/OQ-18 decisions in the proposal, acceptance queue, execution route, project README, and SDLC state.
- Added a bounded candidate-source inventory to `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md` §2. The inventory documents currently visible data paths and their separation from AI Coach input; it is not a product allowlist and was not included in the GPT-PM request.
- Kept concrete source mappings, freshness limits, clock authority/tolerance/skew, locale/template precision, recovery classes/horizon, day-slot policy, persistence service/owner, and exact TR closure open where the decision deferred them.

## Correlated PM Bridge evidence

- Request: `bafbb0e5-4c6a-47a4-85fa-bd389e685a9e`
- Job: `8fb63443-f4e0-4ffa-9b0a-316dbc7358ab`
- User turn: `9e635e00-feb0-4b9c-b2b6-c84abffe6303`
- Reply: `c083cd37-64e5-411f-92e3-f90a09d80be3`
- Status: succeeded, sent, correlated.
- The two attached proposal-file SHA-256 values were `73cedc9e464a6875a279a16636a6708f62cbc918ab7f48a841b730495ad166c8` and `2ae1d41c8ef1c8452cbf4995f155f6974cf85e5fa7034916d9b5286200498336`; local-file hashes and Git blobs matched supplied HEAD `35dc21db55d2c57b756a10815981b8f0b3f03c25`. GPT-PM did not independently authenticate Git ancestry.

GPT-PM decisions recorded from the correlated reply:

1. Accept source-independent fail-closed behavior when a required source, mapping, clock policy, timestamp or other required value is missing.
2. Accept absolute UTC/offset timestamps; an offset-free timestamp is invalid. A capture time beyond the approved tolerance is `INVALID_TIMESTAMP`; absent clock authority/tolerance fails closed.
3. Accept `observed_projected_combination = DISABLED` for the initial scope. No combination or adaptive feedback is permitted; any future formula requires separate versioning and approval.
4. For recovery-required drafts, refuse when coverage is incomplete; `UNKNOWN` is not `RECOVERED`. The classes that require recovery, intervals, freshness and horizon remain deferred. Existing 14-day lookback is not a future horizon.
5. Accept canonical digest and linearizable create-if-absent as target TR design requirements, subject to technical conformance review by the eventual persistence owner. This does not select a storage engine or establish implementation capability/owner.
6. Defer populated OQ-14 source mappings, freshness ages, clock tolerance/cross-source skew, approved locale/template precision; OQ-18 per-source freshness/skew, recovery classes/horizon and day-slot policy until source/update/clock/scheduling evidence is supplied.
7. Do not infer clinical values/signature, runtime ownership/on-call routing, story acceptance, implementation, testing or deployment from these decisions.

## Repository evidence inspected

- AI Coach request shape: `mobile/lib/features/ai_coach/ai_coach_context.dart`; client payload: `mobile/lib/features/ai_coach/ai_coach_service.dart`; server parsing/prompt: `functions/src/ai_coach_advice.ts`.
- Workout and schedule candidates: `mobile/lib/features/workouts/data/workout_log.dart`, `workout_session.dart`, and `scheduled_session.dart`.
- Recovery implementation and lookback: `mobile/lib/features/recovery/data/deload_detector.dart` and `mobile/lib/features/recovery/state/recovery_providers.dart`.
- Training-context candidates: `mobile/lib/features/training_context/data/training_context.dart` and `state/training_context_providers.dart`.
- Equipment match candidates: `mobile/lib/features/visual_equipment/data/visual_equipment_match.dart`.
- Locale behavior: `mobile/lib/core/settings/app_settings.dart` and `functions/src/ai_coach_advice.ts`.

These paths show candidate data and current wiring only. Their existence does not make a source approved, current, authoritative, consistent with another source, or permissible for a factual cloud claim. Existing workout timestamps do not alone establish freshness/version or a cross-source snapshot. `ru`/`en` are app locales, not an approved factual-template catalog. Recovery's 14-day history does not establish a future recovery horizon. The inventory therefore assigns no mappings or numeric policy values and preserves fail-closed behavior.

## Why

GPT-PM's deferrals were evidence-dependent. Recording the current repository source/data-flow inventory resolves the part Codex can establish from code and lets future policy decisions ask about concrete sources. It does not convert candidate paths into product-approved claims or answer the missing measurement/product-policy questions.

## Affected contracts and paths

- `docs/ai-coach/21_PHASE9_OQ14_OQ18_TR_CONTRACT_PROPOSAL.md`
- `docs/ai-coach/acceptance.md`
- `docs/ai-coach/20_PHASE9_EXECUTION_OWNERSHIP_AND_REVIEW_ROUTE.md`
- `docs/ai-coach/00_README.md`
- `docs/sdlc/STATE.md`
- `docs/DOCUMENT_REGISTRY.md` (regenerated after edits)

## Verification and limits

- Read the referenced source modules and compared the proposal's inventory claims to the current AI Coach request path. This is manual source inspection, not runtime evidence.
- Verified the correlated request/job/turn/reply identifiers and proposal-file SHA-256/Git-blob comparison from the recorded PM Bridge response evidence.
- No tests, checks, builds, CI, migrations, runtime actions, alert changes, push or merge were performed.
- The 13 story dispositions remain PENDING. OQ-14/OQ-18 TR contracts remain open; the GPT-PM response did not review the subsequently added repository inventory.
