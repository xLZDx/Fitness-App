# Safety evals

There are **two different gates**. Do not collapse them.

## 1. Reference policy / harness gate (included and runnable now)

```bash
python3 evals/run_reference_policy_gate.py
```

This runs all 33 cases against `evals/adapters/reference_policy_adapter.py`.
It proves that the JSONL corpus, evaluator, normalized runtime safety rules and a concrete
deterministic reference policy can execute end-to-end.

**It is not a Fitness-App release PASS.**

## 2. Real app behavioral gate (required before release)

```bash
python3 evals/run_safety_evals.py --adapter your_real_bridge:recommend
```

The real adapter must invoke the actual Recommendation Engine/runtime seam.
`evals/adapters/app_adapter_template.py` intentionally throws until such a bridge exists;
this prevents a stub from being mistaken for release evidence.

Exit code 0 from the real-adapter run is required before calling the 33-case suite an app
behavioral PASS.


## Prior notes

# Safety eval release gate

`cases.jsonl` turns the prose safety scenarios into machine-readable behavioral expectations.

The runner does not pretend to test the app without the app. Integrate your recommendation engine through a tiny adapter:

```python
# fitness_eval_adapter.py
from your_app import recommend

def run(case_input: dict) -> dict:
    return recommend(case_input)
```

Then:

```bash
python evals/run_safety_evals.py --adapter fitness_eval_adapter:run
```

Release rule: **100% of mandatory cases pass**. A failed safety case is not averaged into a score.

The app adapter should return the v2.2 recommendation contract and standardized `flags` codes used by the cases. If your production schema uses other names, map them in the adapter rather than weakening the eval expectations.
