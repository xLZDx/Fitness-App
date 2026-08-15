# Fitness-App Expert Team — Review v2.1 → v2.2

Date: 2026-08-15

## Verdict

v2.1 fixed the largest knowledge-density gap in v2 by adding clinical and prescription references plus a runtime safety prompt. Those changes are retained. v2.2 focuses on a different problem: separating evidence from product heuristics, making release gates executable, and assigning real human ownership for clinical and regulatory decisions.

## What v2.1 got right

- Kept the orchestrator/specialist architecture and shared Skills.
- Added explicit clinical red-flag categories instead of asking the model to "know" them implicitly.
- Added a prescription reference so training agents do not rely only on generic prose.
- Split medication normalization (`raw name -> verified class`) from downstream interpretation in principle.
- Added a runtime pre-generation / generation / post-generation safety pattern.
- Preserved all v2 specialist roles.

## Important correction about Claude Code nesting

Current Claude Code supports nested subagents. The default maximum spawn depth is three layers below main, and the depth can be controlled with `CLAUDE_CODE_MAX_SUBAGENT_SPAWN_DEPTH`. v2.2 therefore keeps the orchestrator → specialist design.

There is an important current Claude Code nuance: `Agent(agent-a, agent-b, ...)` is a true type allowlist when the agent runs as the main thread via `claude --agent`, but the parenthesized type list is ignored when the same definition runs as a nested subagent. v2.2 therefore uses two controls: the explicit type list for main-thread mode and a scoped `PreToolUse` command hook for nested mode. The hook checks `tool_input.subagent_type` against a versioned policy file and fails closed on unknown/missing types.

## Problems found in v2.1

### 0. One premise in the review was too strong

The statement that a custom subagent's own system prompt is the *only* place its expertise can live is not accurate in current Claude Code. A normal custom subagent also loads the CLAUDE.md hierarchy the main conversation loads, and any Skills named in `skills:` are injected in full at startup. It does not inherit the parent's conversation history or files already read. The practical safety conclusion still stands: critical domain rules should be explicit, versioned, and preloaded rather than left to model recall.

### 1. Some reference rules were too absolute

Examples included treating beta-blocker use as making all HR-based prescription invalid and treating pregnancy as a universal no-HR-zone state. The safer product rule is narrower: generic age-predicted HR targets can be unreliable or require modification, while individualized targets may still be usable when established appropriately; in pregnancy, RPE/talk-test methods are often preferable because HR response varies.

**v2.2 fix:** clinical reference now distinguishes generic formula limitations from individualized clinician/test-derived targets and uses RPE/talk-test fallbacks without claiming a universal HR ban.

### 2. Evidence and product policy were mixed together

The v2.1 prescription reference contained useful engineering defaults but presented several as though they were universal physiological truths: fixed progression increments, fixed e1RM expiry windows, a mandatory novice RIR correction, a single deload recipe, fixed volume landmarks, and ACWR/weekly-load ranges.

**v2.2 fix:** numeric rules are classified as:

- `EVIDENCE_ANCHOR` — directly grounded in a cited guideline or synthesis.
- `MODEL_ESTIMATE` — a calculation/estimate with uncertainty.
- `PRODUCT_HEURISTIC` — an app policy that must be configurable, testable, and labeled as such.

No product heuristic may be represented to the user or developer as a medical/scientific fact.

### 3. Medication handling still had a missing executable layer

A prompt can forbid guessing a drug class, but the product still needs deterministic semantics after a verified class/effect tag is available.

**v2.2 fix:** `runtime/medication_effects.v1.json` contains effect-tag → product-action mappings. It deliberately does **not** map raw drug names to classes. Raw-name normalization must come from a verified medication terminology/source. Medication dose/timing/injection-site changes remain out of scope.

### 4. Safety references were still prose-only

Prose is useful to agents but is not a deterministic runtime gate.

**v2.2 fix:** `runtime/safety_rules.v1.json` provides normalized machine-readable safety facts/actions, while `RUNTIME_SAFETY_PROMPT.md` defines how the LLM layer consumes already-normalized facts. The app should implement the actual pre-generation classifier/gate in code.

### 5. The eval set was not a release gate

A Markdown list of expected behavior is documentation, not an executable test.

**v2.2 fix:** `evals/cases.jsonl` contains structured safety/regression cases and `evals/run_safety_evals.py` runs them against a real application adapter. The suite must not report PASS without a real adapter. `evals/run_static_gates.py` separately validates the Claude configuration and policy regressions.

### 6. Regulatory ownership was implicit

A model reviewer cannot determine the legal classification of the product by itself. Intended use, claims, jurisdiction, UI, data, and actual functionality matter.

**v2.2 fix:** adds `regulatory-compliance-reviewer`, `fitness-regulatory-reference`, and `GOVERNANCE_OWNERSHIP.md`. Regulatory output is a risk flag / review packet, not a binding legal conclusion. A real regulatory/legal owner is required before release of medical-adjacent features.

### 7. Clinical-reference ownership was not enforceable

Saying “requires clinician review” without identifying ownership is easy to ignore.

**v2.2 fix:** `GOVERNANCE_OWNERSHIP.md` defines named human signoff slots and change-control responsibilities. The package intentionally does not invent clinician/legal names.

## Architecture retained

```text
main Claude session
  -> fitness-recommendation-orchestrator
       -> clinical-safety-gate (when needed)
       -> 1-4 scoped specialists
       -> regulatory-compliance-reviewer (claim/feature boundary when needed)
       -> recommendation-adversary (material/high-risk cases)
```

Production recommendation path remains:

```text
validated intake
  -> deterministic normalization / provenance
  -> deterministic safety gate
  -> deterministic eligibility & calculations
  -> LLM specialists for reasoning/explanation/choices
  -> deterministic output validator
  -> audit trace
```

## Release criteria introduced in v2.2

1. `python evals/run_static_gates.py` — must pass.
2. `python evals/run_safety_evals.py --adapter <module:function>` — 100% mandatory cases must pass against the real recommendation path.
3. Required human signoffs in `GOVERNANCE_OWNERSHIP.md` must be assigned for the feature/jurisdiction in scope.
4. Evidence/product-rule changes require provenance and regression tests.
5. No release claim may imply that an LLM reviewer substitutes for a clinician, dietitian, privacy professional, or regulatory counsel where those roles are required.

## Bottom line

v2.1 increased expert knowledge density. v2.2 makes that knowledge safer to operationalize by separating evidence from heuristics, constraining delegation, adding machine-readable runtime policy, creating executable release gates, and assigning human governance.
