# Multi-agent workflow for Recommendation Engine changes

## Never run the whole team by default

The orchestrator selects the minimum relevant specialists. A routine change normally
uses 2–5 expert agents plus an independent adversary.

## Standard workflow

```text
1. Main session verifies local repo state
2. Identify gate + changed engine component
3. Orchestrator selects required/conditional experts
4. Policy owner(s) produce structured findings
5. Evidence/Data/Regulatory review where applicable
6. Architect converts accepted policy into deterministic contract
7. Main session implements code + tests
8. Independent adversary reviews diff/results
9. Required host/device/eval gates run
10. Local commit
11. STOP; push needs separate explicit authorization
```

## Independence rule

The same agent may help shape a rule and explain it, but the final adversarial
release verdict should be performed by `recommendation-adversary` after the rule and
implementation exist.

## No majority vote

Examples:

- Strength coach says progress, physiotherapist says active restriction -> restriction wins.
- Behavior coach says user prefers X, ontology says X requires unavailable equipment -> X cannot win.
- Goal coach proposes precise progression, evidence reviewer says it is not evidence-backed -> it may
  remain a clearly labelled PRODUCT_HEURISTIC only if safety/validation owners accept it.
- Regulatory reviewer says claim requires human review -> do not ship the claim as ordinary wellness copy.

## Code ownership boundary

Expert agents return policy/review artifacts. The main coding session writes Dart/config
only under the currently approved gate.

This avoids a 29-agent runtime architecture and avoids independent subagents making
concurrent edits to the shared local checkout.
