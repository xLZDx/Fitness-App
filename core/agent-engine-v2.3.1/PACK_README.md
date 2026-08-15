# Fitness-App Expert Team v2.2

Claude Code expert system for designing, reviewing, and validating personalized fitness recommendations.

## What v2.2 changes from v2.1

v2.1 restored missing clinical and quantitative substance. v2.2 keeps that improvement but fixes overconfident rules and closes the remaining operational gaps:

1. **29 agents**: adds `regulatory-compliance-reviewer` for US/EU wellness-vs-medical-device boundary review.
2. **6 shared skills**: adds `fitness-regulatory-reference`.
3. Orchestrator uses an explicit `Agent(type, ...)` allowlist instead of unrestricted bare `Agent`.
4. Claude Code nesting compatibility is documented; recommended depth is 2 for `main -> orchestrator -> specialist`.
5. Clinical reference now separates normalized safety facts from diagnosis and removes unsupported universal numeric thresholds.
6. Medication logic is executable: raw-name normalization stays external/verified; verified effect tags map through `runtime/medication_effects.v1.json`.
7. Prescription reference distinguishes `EVIDENCE_ANCHOR`, `MODEL_ESTIMATE`, and `PRODUCT_HEURISTIC`.
8. Removed/softened brittle v2.1 rules: universal beta-blocker HR invalidity, fixed novice RIR +2 correction, mandatory deload recipe, prescriptive ACWR 0.8–1.3 target, universal sex-specific calorie floors, universal numeric pain tolerance.
9. Runtime safety config and recommendation JSON schema are included.
10. Safety evals are machine-readable and have an adapter-based release runner.
11. Human clinical/regulatory ownership is explicit in `GOVERNANCE_OWNERSHIP.md`.

## Team

### Governance / control
- `fitness-recommendation-orchestrator`
- `clinical-safety-gate`
- `evidence-guideline-reviewer`
- `recommendation-adversary`
- `regulatory-compliance-reviewer`

### Training
- `general-fitness-coach`
- `strength-power-coach`
- `hypertrophy-bodybuilding-coach`
- `endurance-conditioning-coach`
- `running-coach`
- `calisthenics-bodyweight-coach`
- `mobility-flexibility-coach`
- `sport-performance-coach`
- `functional-mixed-modal-coach`

### Technique / ontology
- `biomechanics-technique-analyst`
- `exercise-ontology-curator`

### Clinical / special populations
- `musculoskeletal-physiotherapist`
- `older-adult-functional-coach`
- `youth-adolescent-coach`
- `pregnancy-postpartum-coach`
- `chronic-condition-exercise-specialist`
- `adaptive-training-coach`
- `body-recomposition-coach`

### Support
- `sports-nutrition-dietitian`
- `recovery-sleep-coach`
- `massage-soft-tissue-specialist`
- `behavior-adherence-coach`

### Engineering / evaluation
- `recommendation-engine-architect`
- `fitness-data-scientist`

## Shared skills

- `fitness-core-policy`
- `fitness-intake-contract`
- `fitness-evidence-rules`
- `fitness-clinical-reference`
- `fitness-prescription-reference`
- `fitness-regulatory-reference`

Agents preload only what they need. Shared skills contain policy/reference knowledge; they do not replace deterministic runtime rules.

## Claude Code compatibility

Use Claude Code **>= 2.1.219** for the current default nested-subagent behavior. See `CLAUDE_CODE_COMPATIBILITY.md`.

Recommended depth:

```json
{
  "env": {
    "CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH": "2"
  }
}
```

This is enough for:

```text
main
  -> fitness-recommendation-orchestrator
       -> selected specialist(s)
```

Only the orchestrator has an `Agent(...)` tool, and it is restricted to the package's named specialists.

## Production architecture

```text
raw intake / logs / sensors / vision
        ↓
normalization + provenance
        ↓
deterministic clinical/product safety gate
        ↓
deterministic eligibility / movement restriction filter
        ↓
goal-specific prescription calculation
        ↓
LLM explanation / preference-aware coaching
        ↓
deterministic validator
        ↓
audit trace
        ↓
user response
```

Runtime artifacts:
- `runtime/safety_rules.v1.json`
- `runtime/medication_effects.v1.json`
- `runtime/recommendation_contract.schema.json`
- `RUNTIME_SAFETY_PROMPT.md`

## Release gates

Static package/config validation:

```bash
python evals/run_static_gates.py
```

Behavioral safety validation against the real app:

```bash
python evals/run_safety_evals.py --adapter your_adapter:recommend
```

Mandatory safety cases must pass **100%**. This pack does not fake a behavioral PASS without a connected recommendation engine.

## Regulatory/clinical ownership

AI agents are reviewers, not accountable owners. Before enabling medical-adjacent, pregnancy, youth, nutrition, CV safety, symptom-triage or injury-risk features, fill the applicable named human sign-offs in `GOVERNANCE_OWNERSHIP.md`.

In the US, current FDA guidance distinguishes low-risk general wellness software from software functions that meet device criteria. In the EU, intended medical purpose can bring software under MDR and Rule 11. Exact classification must be reviewed for the actual feature and claims.

## Installation

Merge `.claude/` into the repository root. Do not overwrite an existing project `CLAUDE.md`.

Then run:

```text
/agents
/skills
```

and execute the static gate above.


# v2.3 — Recommendation Engine integration

v2.3 adds `fitness-recommendation-engine-contract` and machine-readable ownership/gate policies. Key governance agents preload this contract so Recommendation Engine work is routed against the actual `xLZDx/Fitness-App` audit at `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`. See `CHANGELOG_V2.2_TO_V2.3.md`.
