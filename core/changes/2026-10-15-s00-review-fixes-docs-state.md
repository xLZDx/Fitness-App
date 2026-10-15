# S00: review fixes for documentation state and registry freshness

Date: 2026-10-15. Branch: `phase2/s00-split-docs`.

## What changed
- `docs/phase2/plan/01..04_*.md`: a "CURRENT STATE" banner under each title states that the plan is the approved baseline, lists what was executed, names the recorded decisions D-1, D-2, D-4, D-5 and says that the decision log and `docs/phase2/README.md` win where wording disagrees. The original text is untouched.
- `docs/phase2/README.md`: new section "Current S00 state" (executed steps, separate Firebase project `fitness-app-phase2-korostelev` on the Spark plan, retired branches and recovery tags `retired/2026-10-15/*`, open operator items).
- `scripts/dev/gen_document_registry.py`: new `--check` flag that exits 1 when `docs/DOCUMENT_REGISTRY.md` differs from a fresh render (deterministic stale-registry check).
- `docs/DOCUMENT_REGISTRY.md`: regenerated.
- `core/DECISION_LOG.md`: one entry.

## Why
GPT-PM review round 1 on `phase2/s00-split-docs` (verdict MODIFY): MAJOR-01 contradictory operational status between the committed plan documents and the decision log; MINOR-01 stale derived registry and no stale check; MINOR-02 the earlier change record says no tests were run while a later record reports 115 passing tests (chronological records, both correct; the later records are the current verification evidence, linked from the decision log).

## Affected contracts and paths
Documentation and one stdlib-only generator script. No product code, rules or flags.

## Verification state
`python scripts/dev/gen_document_registry.py --check` was run after regeneration (narrow explicitly relevant check of the generator, no product test). No tests were run for the documentation text.
