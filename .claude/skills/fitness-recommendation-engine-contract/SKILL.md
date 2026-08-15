---
name: fitness-recommendation-engine-contract
description: "Real-repository contract that binds Fitness-App expert agents to Recommendation Engine v1.1 ownership, veto precedence, gate reviews, and current xLZDx/Fitness-App files."
---

# Fitness Recommendation Engine Contract

## Repository binding

This contract is grounded in the private repository `xLZDx/Fitness-App`, branch
`master`, audited remote HEAD `5b7c9acc7acdd00db502e1934afd2c75983eaeb9` on 2026-08-15.

Remote inspection does **not** prove the operator's local shared checkout is clean or
at the same commit. Before any write gate, the main coding session must verify local
branch, HEAD, upstream, `git status`, unpushed commits, untracked files and concurrent
work. Expert agents must never recommend reset/stash/discard of another session's work.

## Expert agents are not the production runtime

The expert team:
- designs and reviews rules;
- classifies evidence vs heuristics;
- attacks unsafe edge cases;
- owns vetoes defined by policy.

The production app executes deterministic/versioned Recommendation Engine rules.
The LLM may explain approved output but must not be the sole source of safety,
exercise eligibility, exact load, progression, or numeric prescription.

The expert subagents are also not the default code-writing executor. The main Claude
Code session implements an approved gate after local repository verification and
project rules. Expert agents return review artifacts.

## Canonical production pipeline

```text
merged UserProfile + history + programme + health + scanner/form context
        ↓
RecommendationContext + provenance/freshness
        ↓
SafetyGate
        ↓
ExerciseEligibility
        ↓
goal/preference Ranking
        ↓
PrescriptionEngine
        ↓
LoadEngine
        ↓
ProgressionEngine
        ↓
SubstitutionEngine
        ↓
RecommendationValidator
        ↓
structured RecommendationResult
        ↓
UI + optional AI explanation
```

Hard restrictions are gates, never negative ranking points.

## Current real-repo decision owners that must converge

- injury/catalog boundary:
  `mobile/lib/features/equipment/data/exercise_filter.dart`
  and `mobile/lib/features/equipment/state/equipment_providers.dart`
- Home:
  `mobile/lib/features/home/state/suggestion_providers.dart`
  + `home/data/suggestion_builder.dart`
- personalisation:
  `personalisation/data/fitness_model.dart`
  + `personalisation/data/for_you_ranker.dart`
- AI Planner:
  `ai_planner/state/ai_planner_providers.dart`
  + `ai_planner/data/plan_builder.dart`
- programmes:
  `programmes/data/programme_fit.dart`,
  `programme_schedule.dart`,
  `programmes/state/programme_providers.dart`
- progression/load:
  `workouts/data/progression.dart`
- recovery:
  `recovery/data/deload_detector.dart`
- AI numeric-advice boundary:
  `ai_coach/ai_coach_context.dart`
- scanner:
  `visual_equipment/data/scan_outcome.dart`
- Form Check:
  `form_check/data/pose_gate.dart`

Read `.claude/policies/fitness-engine-real-repo-map.json` for the machine-readable map.

## Known blockers from G0

### RE-B01 — personalisation semantic inversion

Current subjective model lowers a muscle score after `tooHard`, while the ranker
prioritizes lower scores with `1 - score`. Do not inherit this formula. "Too hard"
must never increase exposure solely because the score fell.

### RE-B02 — AI numeric prescription authority

Current AI Coach asks the cloud model for beginner volume and a starting-load cue
without a deterministic prescription validator. Recommendation Engine must make
numeric prescription authoritative; AI explanation is subordinate.

### RE-B03 — incomplete general clinical safety gate

The profile collects conditions, medication strings, limitations, surgeries and blood
pressure in addition to injuries. Recommendation generation currently has a strong
injury boundary but no general deterministic clinical safety gate for all of these
inputs. Raw medication strings may not be classified by model memory.

## Conflict precedence

1. emergency/clinical safety;
2. explicit clinician restriction/clearance;
3. active MSK pain/rehab restriction;
4. special-population safety;
5. exercise/equipment ontology feasibility;
6. technique-data validity;
7. goal-specific programming;
8. recovery/readiness;
9. preference/adherence;
10. wording/presentation.

Do not majority-vote across levels.

Additional governance vetoes:
- evidence reviewer can block unsupported **evidence claims**;
- data scientist can block measured/calibration claims that exceed evidence;
- regulatory reviewer can require human legal/regulatory review before claim release;
- adversary can issue DO_NOT_SHIP for unresolved BLOCKER;
- architect can block duplicate-source-of-truth / LLM-only safety architecture.

## Agent ownership

The complete matrix is:
`.claude/policies/fitness-agent-engine-ownership.json`.

For every recommendation-engine task:
1. identify changed engine components and real repo paths;
2. select the minimum policy owners/reviewers from the matrix;
3. keep rule author and final adversarial reviewer independent where practical;
4. return structured artifacts, not a vote.

## Gate review matrix

Read:
`.claude/policies/fitness-recommendation-gates.json`.

G0 is complete as remote read-only audit.
G0.5 is this ownership contract.
G1 begins only after explicit implementation GO and local checkout verification.

## Required specialist review artifact

Each specialist returns:

```yaml
agent:
scope:
repo_paths_reviewed:
inputs_assumed:
policy_proposals:
rule_classification:
  - EVIDENCE_ANCHOR | MODEL_ESTIMATE | PRODUCT_HEURISTIC
hard_constraints:
uncertainties:
required_tests:
blocking_findings:
handoffs:
```

A goal coach does not issue the final safety verdict.

## Required orchestrator synthesis artifact

```yaml
gate:
routing:
policy_owner_findings:
conflicts:
precedence_resolution:
deterministic_rules_to_change:
llm_only_explanation:
required_tests:
open_blockers:
release_recommendation:
```

## Production invariants

- no exact kg from body mass, gender, tier, or LLM guess alone;
- no silent machine-to-machine exact load transfer without compatible load context;
- no restriction bypass through aliases/substitutions;
- no equipment/location bypass by Home/AI Planner/onboarding/programmes;
- no low-confidence scanner identity treated as fact;
- invalid Form Check input yields cannot-evaluate, not a confident fault;
- raw medication name is not a verified class;
- missing critical async profile data is not interpreted as no restrictions;
- all numeric prescriptions have basis/provenance/rule version;
- AI cannot override deterministic validator output.
