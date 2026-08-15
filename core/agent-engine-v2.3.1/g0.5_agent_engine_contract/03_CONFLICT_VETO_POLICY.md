# Conflict and veto policy

## Safety precedence

1. S0 emergency/urgent action
2. explicit clinician restrictions/clearance
3. active pain/rehab constraints
4. special-population safety
5. movement/equipment feasibility
6. technique input validity
7. performance programming
8. recovery/readiness
9. adherence/preference
10. wording

No average, no majority vote.

## Veto classes

### SAFETY_VETO
Clinical or MSK/special-population owner can block recommendation execution when the
product cannot establish a safe path.

### EVIDENCE_CLAIM_VETO
Evidence reviewer can block calling a rule "evidence-backed". The rule may only remain
as an explicitly labelled PRODUCT_HEURISTIC if other gates permit it.

### ONTOLOGY_UNKNOWN_BLOCKS_EXACT_MATCH
Unknown/conflicting exercise/equipment mapping blocks exact match/substitution claims.
Use REVIEW_REQUIRED/ask-confirm/fallback.

### MEASUREMENT_VALIDITY_VETO
Data scientist can block confidence/calibration/performance claims that were not
measured adequately.

### CLAIM_RELEASE_VETO_PENDING_HUMAN_REVIEW
Regulatory reviewer can require a human regulatory/legal owner before a risky claim is
released. The agent itself does not declare regulatory clearance/classification.

### RELEASE_VETO_ON_UNRESOLVED_BLOCKER
Recommendation adversary can issue DO_NOT_SHIP when mandatory safety/eval findings
remain BLOCKER.

### ARCHITECTURE_GATE_VETO
Engine architect can block:
- second source of truth;
- LLM-only safety;
- LLM-originated exact load;
- unversioned deterministic policy;
- missing audit/provenance on numeric output.
