# Review of v2, and what v2.1 changes

## Verdict

The v2 **architecture** is a genuine improvement and should be kept. The v2 **content** is
a regression: the structural discipline was bought by deleting the domain knowledge, and
several agents are now instructed to have expertise they are not given.

v2.1 keeps every architectural decision and restores the missing substance as two new
shared skills plus one runtime layer. Nothing from v2 was removed.

## What v2 got right — verified, not assumed

| Claim | Status |
|---|---|
| `skills:` preloads full skill content into a subagent | **Correct.** Documented: "The full skill content is injected, not only the description" |
| `maxTurns`, `disallowedTools` are valid frontmatter | **Correct.** Both documented |
| Subagents can nest up to 3 layers by default | **Correct.** Configurable via `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH` |
| Orchestrator can actually spawn specialists | **Correct.** It is the only agent with `Agent` in `tools` — deliberate and right, since the docs state that omitting `Agent` is exactly how you stop a subagent from spawning others |
| Splitting `special-populations-coach` into 6 agents | **Right call.** One agent covering minors + pregnancy + 65+ + disability + chronic disease was too broad to be safe |
| `exercise-ontology-curator` with movement-property restriction | **Best single addition in v2.** Blocking substitution by property rather than by name closes a real hole |
| Model tiering (sonnet for coaches, opus for clinical) | Sensible, and cheaper than v1's blanket opus |
| `SAFETY_EVAL_CASES.md` | 25 well-specified cases. Keep as a release gate |
| Structured medication object with `verified_source` | Better than v1's flat string array |

## Finding 1 — the safety layer names no symptoms (critical)

Across all 28 agents and all 3 skills, these strings appear **zero times**:

```
"chest pain"      0        "cauda equina"   0
"saddle"          0        "calf"           0
"beta-block"      0        "syncope"        1  (youth agent only)
```

`clinical-safety-gate` is told to "distinguish emergency warning signs from non-emergency
clearance needs". It is never told what one is. `fitness-core-policy` defines
`S0_EMERGENCY` as "symptoms plausibly needing urgent evaluation" — which is circular.

A subagent's system prompt is the only place its expertise lives. An agent instructed to
recognise emergencies without a list will fall back on whatever it happens to recall,
which is precisely the non-determinism this architecture exists to eliminate. This is the
highest-consequence content in the product and it became implicit.

**v2.1**: `fitness-clinical-reference` — red flags by category with product response,
absolute contraindications, condition-specific restrictions, soft-tissue contraindications,
pain-triage thresholds, intensity-method validity rules.

## Finding 2 — the medication rule has no second half

v2's rule "never infer exercise effects from a raw medication string" is correct and is an
improvement on v1. But it creates a dependency on a verified medication layer that the pack
does not ship and does not specify. Today that yields one of two outcomes: no medication
logic at all, or the model inferring from memory anyway — the exact behaviour the rule
forbids.

The rule conflates two different lookups:

```
name_raw → drug_class      needs a real database (RxNorm/ATC). Correctly forbidden to the LLM.
drug_class → exercise_effect   deterministic, small, and belongs in the pack.
```

**v2.1**: ships the second table (`fitness-clinical-reference` §4) with an explicit note
that it must not be used to guess a class from a name. The rule becomes operable instead of
blocking.

## Finding 3 — quantitative content was deleted, not relocated

```
v1: 14 agents, 23,875 words  → 1,705 words/agent
v2: 28 agents,  8,094 words  →   289 words/agent
```

Every v2 agent is 54–66 lines and follows an identical template
(Role / Mission / You must / You must not / Decision method / Required output / Handoffs).
That uniformity is good for the contract and bad for expertise — the files are almost
interchangeable once you remove the title.

The shared skills do not compensate: `fitness-core-policy` (882 words) is entirely policy
and contains no domain numbers. So `strength-power-coach` is told to "prefer heavier
loading for strength when appropriate" with no %1RM table, no RIR calibration method, no
increment sizes, and no deload trigger. `hypertrophy-bodybuilding-coach` has no volume
landmarks. `endurance-conditioning-coach` has no zone model.

**v2.1**: `fitness-prescription-reference` — load/rep table, e1RM formulas and staleness
rules, RIR calibration, MEV/MAV/MRV, frequency and rest defaults, progression increments
with hard bounds, deload triggers, HR zone models and HRmax estimators, interval templates,
nutrition anchors, and the time-budget formula.

## Finding 4 — nothing ships into the product

`MIGRATION_FROM_V1.md` §4 drops v1's per-agent in-app prompt blocks with sound reasoning:
"do not maintain 25 independent runtime prompts. Keep product rules in versioned
code/config and generate a smaller runtime policy layer."

Correct — but that layer was not written. The pack now contains 28 agents that review an
implementation and nothing that can be deployed into one. The app runs with no safety
prompt, or with an unreviewed one.

**v2.1**: `RUNTIME_SAFETY_PROMPT.md` — one runtime policy in three layers (pre-generation
classifier, system prompt, post-generation validator with a rejection table). One layer,
not 28, which is what the migration note actually asked for.

## Finding 5 — the lisinopril claim is overstated

v2 reports finding "a real bug" in v1's `_shared-intake-contract.md`:

```jsonc
"medications": ["lisinopril"],   // beta-blockers invalidate HR-based zones — critical
```

The comment documents the *field*, not the value, and v1's `sports-physician-screener`
listed lisinopril correctly under ACE inhibitors → post-exercise hypotension. So the pack
was internally consistent; the example was badly chosen and invited exactly that
misreading. Fair criticism of the example, not a logic defect.

Worth noting because the fix that followed is right for a different reason — provenance,
not correction — and the reasoning should match the change. (v2's own contract still uses
`lisinopril` as the example, now harmlessly, since `drug_class` is null.)

## Finding 6 — routing matrix gaps (minor)

Six agents are never referenced in `ROUTING_MATRIX.md`:
`fitness-recommendation-orchestrator`, `recommendation-adversary`,
`evidence-guideline-reviewer`, `fitness-data-scientist`, `sports-nutrition-dietitian`,
`mobility-flexibility-coach`.

The first three are control-plane and arguably belong in the matrix as explicit escalation
targets, since `fitness-core-policy` §3 routes conflicts to two of them by name. The last
three look like omissions. Not shipped as a fix — decide the intent first.

## What v2.1 adds

```
.claude/skills/fitness-clinical-reference/SKILL.md       new  (~1,500 words)
.claude/skills/fitness-prescription-reference/SKILL.md   new  (~1,400 words)
RUNTIME_SAFETY_PROMPT.md                                 new
REVIEW_V2_TO_V2.1.md                                     this file
manifest.json                                            version 2.1, skill_count 5
```

All 28 agent files patched: new skills added to `skills:` by role. No agent body text was
changed, no agent removed, no architectural decision reversed.

Skill assignment: clinical reference → 19 agents (safety, clinical, special-population,
control-plane); prescription reference → 22 agents (all programming coaches plus
control-plane and engineering).

## Still open — decisions, not defects

1. **Regulatory classification.** Mentioned in `README.md` and `recommendation-adversary`,
   but no agent owns the wellness-vs-medical-device boundary. Features like injury-risk
   prediction and symptom triage push toward device regulation (FDA / EU MDR), and
   discovering that late forces a rebuild. This needs regulatory counsel, and the pack
   should say who holds it.
2. **28 agents is a lot to route across.** Descriptions are well differentiated — better
   than expected — but `general-fitness-coach` vs `strength-power-coach` vs
   `functional-mixed-modal-coach` will still overlap on ordinary requests. Measure
   orchestrator routing accuracy against the eval cases before adding a 29th.
3. **The eval suite has no expected-output assertions**, only expected behaviours. To be a
   release gate it needs a runner and pass/fail criteria per case.
4. **Named clinical advisor.** `fitness-clinical-reference` is an engineering reference and
   is explicitly marked as requiring clinical ownership before release. That person does
   not exist in the pack.
