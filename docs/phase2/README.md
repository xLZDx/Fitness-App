# Phase 2 documents (development line)

Branch family: `phase2/main`, work branches `phase2/<sprint-id>`. Phase 2 is cloned from Phase 1 (`phase1/main`, tag `phase1-baseline`) and is fed by Phase 1 fixes through the sync protocol. Index only: decisions stay in `core/DECISION_LOG.md`, the canonical document entry point stays `core/INDEX.md`.

## Plan package (approved by the operator on 2026-10-15, GPT-PM APPROVE on revision 3)

| File | Content |
|---|---|
| `plan/01_PROJECT_REASSESSMENT_2026-10-15.md` | Project review, phase definitions, per-folder provenance inventory |
| `plan/02_PHASE_SPLIT_AND_REPO_LAYOUT_2026-10-15.md` | Repository and folder split, migration protocol, sync protocol, backend separation gate |
| `plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` | Sprints S00..S28, epics, priorities, execution graph, decision register, lifecycle matrix |
| `plan/04_UI_UX_DIRECTION_2026-10-15.md` | UI direction from the concept film and the four-mode blueprint, UI sprint matrix |

## Records

- `split/SNAPSHOT_2026-10-15.md`: read-only record of refs, worktrees and dirty state before the split (recovery map).
- `../EXPERIMENTS.md`: experiments register.
- `../SYNC_LOG.md`: Phase 1 to Phase 2 synchronisation log.
- `../DOCUMENT_REGISTRY.md`: derived listing written by `scripts/dev/gen_document_registry.py`; never edit by hand.

## Operator decisions recorded for S00

D-1 phase rule as written (`training_context` stays in Phase 1, experiments flag-only); D-2 PR #5 retargeted to `phase2/main` and merged there; D-4 separate Firebase alias for Phase 2; D-5 Option A (one repository, two branch families, two worktrees).
