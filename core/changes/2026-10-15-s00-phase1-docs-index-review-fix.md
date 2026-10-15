# S00: Phase 1 documentation index, review fix

Date: 2026-10-15. Branch: `phase1/s00-docs-index`.

## What changed
- `docs/phase1/README.md`: the reference to `docs/EXPERIMENTS.md` now says that the register lives on the Phase 2 line (`phase2/main`, added by the S00 documentation PR) and does not exist on `phase1/main`. The Phase 1 release plan row now says that the plan file is Phase 2 only and is absent from `phase1/main` until the Phase 2 documentation PR is merged and synced.
- `core/DECISION_LOG.md`: one entry for this fix.

## Why
GPT-PM review round 1 (verdict MODIFY, MAJOR-01): every path in the index must exist on the Phase 1 line at `42d1b849` or be explicitly labelled as living on the Phase 2 line. `docs/EXPERIMENTS.md` was not labelled.

## Affected contracts and paths
Documentation only. No code, rules, flags or tests.

## Verification state
No tests or checks were run (documentation change). The seven Phase 1 paths named in the index were verified by the reviewer against `42d1b849`.
