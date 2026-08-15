# Specialist artifact contracts

## Policy specialist output

```yaml
agent:
gate:
scope:
repo_paths_reviewed:
inputs_assumed:
policy_proposals:
rule_classification:
  - rule:
    class: EVIDENCE_ANCHOR | MODEL_ESTIMATE | PRODUCT_HEURISTIC
    evidence_refs: []
hard_constraints:
uncertainties:
required_tests:
blocking_findings:
handoffs:
```

## Evidence reviewer output

```yaml
claims_reviewed:
supported:
downgraded_to_heuristic:
unsupported:
sources_required:
blocking_claims:
```

## Data-science reviewer output

```yaml
signal:
target:
validation_split:
calibration:
abstention:
subgroups:
freshness:
failure_modes:
release_metrics:
```

## Adversary output

```yaml
findings:
  - severity: BLOCKER | HIGH | MEDIUM | LOW
    rule_or_file:
    attack_case:
    expected:
    observed:
verdict: SHIP | SHIP_WITH_FIXES | DO_NOT_SHIP
```

## Orchestrator synthesis output

```yaml
gate:
routing:
specialist_findings:
conflicts:
precedence_resolution:
deterministic_rules_to_change:
llm_only_explanation:
required_tests:
open_blockers:
release_recommendation:
```
