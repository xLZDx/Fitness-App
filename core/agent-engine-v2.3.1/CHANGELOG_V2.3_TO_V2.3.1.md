# v2.3 -> v2.3.1

Fixes after independent review:

1. Hook portability: source default `python3`; recommended installer pins absolute `sys.executable`,
   so Windows/macOS do not depend on `python`/`python3` aliases.
2. Installation layout is explicit and enforced: agents/skills global, hooks/policies under the
   Fitness-App repo-root `.claude/`.
3. Added bundled deterministic `reference_policy_adapter.py` and `run_reference_policy_gate.py`;
   all 33 cases are executable. This is explicitly **not** an app release PASS.
4. Added `app_adapter_template.py` that fails loudly until the real Recommendation Engine bridge exists.
5. Removed all `__pycache__` and `.pyc` artifacts; final manifest/ZIP is produced after tests and cleanup.
6. Re-verified G0 at exact SHA `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`; progression rules and RE-B01 remain confirmed.
