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

## Current S00 state (2026-10-15)

Done: snapshot, tag `phase1-baseline` (42d1b849), branches `phase1/main` and `phase2/main`, PR #5 retargeted and merged into `phase2/main` (5137ccda), worktrees `D:\Repo\Fitness_App_Phase1` and `D:\Repo\Fitness_App_Phase2`, the separate Firebase project `fitness-app-phase2-korostelev` (Spark plan, created 2026-10-15), retirement of merged sprint branches and helper worktrees with recovery tags `retired/2026-10-15/*`.
In review: S00 documentation PR and the deploy-line guard (GPT-PM round 1 returned MODIFY; fixes in progress). Until the guard is approved and the `phase2` alias is committed to `.firebaserc`, no Phase 2 deploy is allowed.
Open and operator-owned: Blaze billing for the Phase 2 project (linking to the existing billing account failed with a Cloud billing quota error on 2026-10-15), deleting remote branches (blocked by the shell policy hook).
The plan documents under `plan/` keep their original wording; the banner at the top of each states which parts are historical.

## Operator decisions recorded for S00

D-1 phase rule as written (`training_context` stays in Phase 1, experiments flag-only); D-2 PR #5 retargeted to `phase2/main` and merged there; D-4 separate Firebase alias for Phase 2; D-5 Option A (one repository, two branch families, two worktrees).
