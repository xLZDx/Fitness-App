# Migration notes: v1 -> v2

## Keep conceptually

The v1 pack had several strong ideas worth preserving:
- safety gate before plan generation;
- deterministic validation after LLM output;
- RIR/RPE fallback when reliable 1RM is unavailable;
- explicit red-flag interruption rather than a disclaimer footer;
- trend-based interpretation of noisy wearable/body metrics;
- skepticism about injury-risk claims from consumer video;
- separate strength, hypertrophy, endurance, technique, mobility, nutrition, recovery and behavior expertise.

## Change

### 1. Shared contract delivery
Old: `_shared-intake-contract.md` beside agent files and an instruction to read it.
New: mandatory policy/intake are Skills preloaded with `skills:`.

### 2. Medication model
Old: raw string list plus prose rule. The sample even placed `lisinopril` beside a beta-blocker comment.
New: raw name + normalized name + class + exercise-effect tags + verified source/version. Agents may not infer medication effects from memory when the normalized layer is absent.

### 3. Special populations
Old: one agent handled older adults, youth, pregnancy/postpartum, menopause, obesity, chronic disease and disability.
New: separate specialists with narrower descriptions so Claude delegates correctly and each prompt can carry population-specific safeguards.

### 4. Production prompt drift
Old: every expert file included a copy-pastable in-app system prompt block.
New: do not maintain 25 independent runtime prompts. Keep product rules in versioned code/config and generate a smaller runtime policy layer from those rules. Expert agents review that implementation.

### 5. Consensus
Old: team composition existed, but conflict resolution was implicit.
New: explicit precedence: safety > clinician restrictions > rehab > population rules > technique/equipment > goal programming > preference/adherence.

### 6. Exercise knowledge graph
Old: exercise selection logic was spread across coaches.
New: `exercise-ontology-curator` owns canonical IDs, machine capabilities, movement properties, substitution semantics and restriction tags.

### 7. Recommendation evaluation
New: `recommendation-adversary` and `fitness-data-scientist` explicitly evaluate abstention, calibration, subgroup failures, null/conflicting inputs and unsafe engagement incentives.
