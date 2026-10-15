# Phase 1 documents (production MVP line)

Branch family: `phase1/main`, fix branches `phase1/<topic>`. Starting point: tag `phase1-baseline` at `42d1b849` (the merge of PR #4, 2026-10-14). The tag is a historical split point, NOT a production-ready certificate.

Scope: everything planned before 2026-10-10. Allowed work: fixes, security, release readiness (store, legal, device acceptance, clinical and label gates). No new product features; post-2026-10-10 features present in this line are experiments, listed in the Phase 2 register `docs/EXPERIMENTS.md`. That register lives on the Phase 2 line (`phase2/main`, added by the S00 documentation PR) and does not exist on `phase1/main`; as of `phase1-baseline` no experiment code is in this line.

This directory is a navigation index only. The originals stay where they are (no moves without an operator-approved rename):

| Topic | Document |
|---|---|
| Plan of record for gates P0..P6, OBS-1, MVP1 | `core/MASTER_PLAN_2026-08-26.md` |
| Generated gate ledger (never hand-edited) | `core/CURRENT_STATE.md` |
| Original 75-item product vision (historical) | `FITNESS_APP_TASK_LIST.md` |
| Review and remediation status | `core/state/REVIEW_STATUS_2026-10-07.md`, `core/state/TAIL_CLOSURE_REGISTRY.json` |
| Canonical document index | `core/INDEX.md` |
| Phase 1 release plan (P1-S1..P1-S5) | Phase 2 line only: `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` section 4 (added by the S00 documentation PR; not present on `phase1/main` until that PR is merged and synced) |
| Stale, historical only | `core/plans/ROADMAP_2026_V2.md` (flagged STALE 2026-09-18) |
