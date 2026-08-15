# G0.5 — Agent ↔ Recommendation Engine Contract

Repository binding: `xLZDx/Fitness-App` / `master` / audited remote HEAD `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`.

This document makes the agent team and Recommendation Engine one engineering system.

## Core model

```text
Expert agents -> versioned rules/policies/evals -> deterministic Recommendation Engine -> UI
                                                -> AI explanation only
```

Agents do **not** become 29 runtime API calls. They own policy design/review and release gates.

## Ownership matrix

| Agent | Role | Engine ownership | Primary gates | Veto |
|---|---|---|---|---|
| `fitness-recommendation-orchestrator` | workflow_coordinator | cross-cutting orchestration | G0.5, G2, G3, G4, G6, G7, G8, G9, G10, G11 | `none_by_itself` |
| `clinical-safety-gate` | safety_policy_owner | SafetyGate, clinical stop/clearance/restriction policy | G2, G6, G7, G9, G10, G11 | `SAFETY_VETO` |
| `evidence-guideline-reviewer` | evidence_governance | evidence registry, EVIDENCE_ANCHOR vs MODEL_ESTIMATE vs PRODUCT_HEURISTIC classification | G2, G4, G6, G8, G11 | `EVIDENCE_CLAIM_VETO` |
| `recommendation-adversary` | independent_release_adversary | RecommendationValidator eval strategy, adversarial release review | G2, G3, G4, G5, G6, G7, G8, G9, G10, G11 | `RELEASE_VETO_ON_UNRESOLVED_BLOCKER` |
| `general-fitness-coach` | goal_policy_specialist | generic prescription fallback, general-fitness goal policy | G6, G7 | `none` |
| `strength-power-coach` | goal_policy_specialist | strength/power prescription, load progression | G5, G6, G7 | `none` |
| `hypertrophy-bodybuilding-coach` | goal_policy_specialist | hypertrophy prescription, volume/progression policy | G6, G7 | `none` |
| `endurance-conditioning-coach` | goal_policy_specialist | conditioning prescription, intensity method selection | G6, G7, G8 | `none` |
| `running-coach` | goal_policy_specialist | running dose/progression, multi-stressor progression | G6, G7, G8 | `none` |
| `calisthenics-bodyweight-coach` | goal_policy_specialist | bodyweight progression, non-external-load prescription | G6, G7 | `none` |
| `mobility-flexibility-coach` | goal_policy_specialist | mobility/flexibility dose, mobility substitutions | G6, G7 | `none` |
| `sport-performance-coach` | goal_policy_specialist | power/plyometric/speed/COD prescription | G6, G7 | `none` |
| `functional-mixed-modal-coach` | goal_policy_specialist | mixed-modal/HIIT/circuit prescription | G6, G7 | `none` |
| `biomechanics-technique-analyst` | cv_technique_boundary_owner | FormContext, observable technique interpretation, technique-aware modification | G6, G10, G11 | `TECHNIQUE_DATA_VALIDITY_VETO` |
| `exercise-ontology-curator` | ontology_owner | exercise metadata, equipment resolution, aliases, movement properties, substitution families | G2, G3, G6, G7, G10, G11 | `ONTOLOGY_UNKNOWN_BLOCKS_EXACT_MATCH` |
| `musculoskeletal-physiotherapist` | pain_rehab_specialist | pain/rehab restrictions, MSK substitutions, return-to-training constraints | G2, G6, G7, G10, G11 | `MSK_SAFETY_VETO` |
| `older-adult-functional-coach` | special_population_specialist | older/frail/fall-risk modifications | G2, G6, G7 | `SPECIAL_POPULATION_SAFETY_VETO` |
| `youth-adolescent-coach` | special_population_specialist | youth supervision/dose/progression constraints | G2, G6, G7 | `SPECIAL_POPULATION_SAFETY_VETO` |
| `pregnancy-postpartum-coach` | special_population_specialist | pregnancy/postpartum exercise modifications | G2, G6, G7, G8 | `SPECIAL_POPULATION_SAFETY_VETO` |
| `chronic-condition-exercise-specialist` | special_population_specialist | condition-aware exercise constraints | G2, G6, G7, G8 | `SPECIAL_POPULATION_SAFETY_VETO` |
| `adaptive-training-coach` | special_population_specialist | function-based accessibility/adaptive alternatives | G2, G6, G7 | `FUNCTIONAL_FEASIBILITY_VETO` |
| `body-recomposition-coach` | goal_policy_specialist | recomposition training-goal policy, REDs/LEA escalation triggers | G2, G6, G7, G8 | `BODYCOMP_SAFETY_ESCALATION` |
| `sports-nutrition-dietitian` | nutrition_boundary_specialist | nutrition context, fueling/recovery boundaries | G8, G11 | `NUTRITION_SAFETY_VETO_WHEN_APPLICABLE` |
| `recovery-sleep-coach` | recovery_policy_owner | readiness/recovery adaptation | G4, G6, G8, G11 | `RECOVERY_DATA_VALIDITY_VETO` |
| `massage-soft-tissue-specialist` | recovery_specialist | massage/soft-tissue contraindication reference | G2, G8 | `MASSAGE_SAFETY_VETO_WHEN_APPLICABLE` |
| `behavior-adherence-coach` | preference_adherence_owner | preference ranking, adherence/schedule-fit signals | G3, G4, G7, G8 | `none` |
| `recommendation-engine-architect` | engine_architecture_owner | RecommendationContext, RecommendationResult, SafetyGate interfaces, EligibilityEngine, PrescriptionEngine, LoadEngine, ProgressionEngine, SubstitutionEngine, RecommendationValidator, versioning/audit trace | G1, G2, G3, G4, G5, G6, G7, G8, G9, G10, G11 | `ARCHITECTURE_GATE_VETO` |
| `fitness-data-scientist` | measurement_validation_owner | calibration, confidence, offline eval, subgroup/safety monitoring | G1, G4, G5, G6, G8, G10, G11 | `MEASUREMENT_VALIDITY_VETO` |
| `regulatory-compliance-reviewer` | regulatory_claims_reviewer | claim boundary, wellness vs medical-purpose escalation, regulatory review packet | G2, G9, G10, G11 | `CLAIM_RELEASE_VETO_PENDING_HUMAN_REVIEW` |

## Non-voting precedence

1. emergency/clinical safety
2. clinician restriction/clearance
3. MSK pain/rehab
4. special populations
5. ontology/equipment feasibility
6. technique-data validity
7. goal programming
8. recovery/readiness
9. preference/adherence
10. wording/presentation

A lower level cannot outvote a higher one.

## Implementation executor

The expert agents in this pack are deliberately read/review oriented. The **main Claude Code session** is the code-writing executor for an approved gate after checking the local shared checkout and the repo's `CLAUDE.md` / `AGENTS.md` rules. For Dart changes, the repo-specific `fitness-flutter-reviewer` remains the project review surface defined by the repository itself.

## Machine-readable source

`agent_engine_ownership.json` is authoritative for automation.