# SDLC state: Phase 2 program (sprints S00, S01)

Source of phase truth for the Phase 2 line. Updated 2026-10-16. Head confirmed with git when written: branch `phase2/s01-contracts`, base `phase2/main` at `89927444`. The earlier Body Scan sprint state (PR #5, merged as `5137ccda`) is history; its acceptance and release phases (9, 10) remain open there and need the operator-owned gates it lists.

## S00: split and migration (merged)

Current phase: 10 Report + retro (partial). PR #7 (`db01888f`) and PR #8 (`89927444`) are merged into `phase2/main`; Phase 1 PR #6 (`0eee9ca2`) is merged into `phase1/main`.

| # | Phase | Status | Artifacts |
|---|---|---|---|
| 1 Discovery | done | `docs/phase2/plan/01_PROJECT_REASSESSMENT_2026-10-15.md` |
| 2 Backlog | done | `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md` (sprints, epics, decision register) |
| 3 Design | done | `docs/phase2/plan/02_PHASE_SPLIT_AND_REPO_LAYOUT_2026-10-15.md`, `docs/phase2/split/BACKEND_SEPARATION.md` |
| 4 Docs + test plan | done | `docs/phase2/README.md`, change records in `core/changes/`; tests written by `tdd-guide` |
| 5 Doc review | done | internal security and silent-failure reviews; GPT-PM four rounds (APPROVE `48ad73a7`) |
| 6 Build | done | deploy-line guard, wrapper, generator `--check`, registry |
| 7 Verify | done | 742 focused jest tests passed (`release_guard.test.ts` 505, `guard_scripts.test.ts` 112, `scaling.test.ts` 125) |
| 8 Gate | done | GPT-PM APPROVE for PR #7 head `48ad73a7`, for PR #8 head `b5a6f752`, for Phase 1 PR #6 head `e309e5ba` |
| 9 Accept + release | n/a | documentation and tooling sprint; no release |
| 10 Report + retro | partial | sprint report and retrospective missing |

Open items recorded in `docs/phase2/split/BACKEND_SEPARATION.md` (before the first Phase 2 cloud deploy): production project number hardcoded in the kill-switch secret path of `functions/src/abuse_guard.ts`; candidate dotenv content not verified by the guard; separate production deploy credentials or protected CI (operator-owned); Blaze billing for the Phase 2 project (operator-owned; billing account project quota exceeded).

## S01: contracts and UI baseline (documentation only)

Current phase: 5 Doc review. Entry criteria of the next phase (8 Gate): internal consensus closed, GPT-PM review of the document set, then the operator decisions listed below.

| # | Phase | Status | Artifacts |
|---|---|---|---|
| 1 Discovery | done | requirements drawn from the roadmap and the Phase 2 plan |
| 2 Backlog | done | S01 row of the roadmap |
| 3 Design | done | `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (98 requirements, all PROPOSED), `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md` |
| 4 Docs + test plan | done | `docs/phase2/s01/RIGHTS_STUDY_TILES_ROUTES_POI.md`, `docs/phase2/s01/UI0_BASELINE_AUDIT.md` and `UI0_BASELINE_AUDIT_ADDENDUM.md`; acceptance criteria are inside the contract (rules and sweep tests for later sprints) |
| 5 Doc review | in progress | security review rounds 1 to 3 (round 3 found one MAJOR, fix in progress); product-ux and accessibility review of UI-0 done; GPT-PM review not started |
| 6 Build | n/a | no code in this sprint |
| 7 Verify | n/a | no tests in this sprint |
| 8 Gate | not started | GPT-PM APPROVE on the exact head, then one push and one PR |
| 9 Accept + release | not started | operator approval of the contract and decisions |
| 10 Report + retro | not started | |

Operator decisions required at acceptance (each stays open until answered): retention of GPS and heart-rate streams (D-16); minors, sharing and public routes (D-17); map tiles source (D-6); route data source and launch region (D-7).

Agents and models actually run in S01 (all Sonnet 5.5): technical-writer (contract and matrix), general-purpose (rights study), code-explorer (UI-0 audit, addendum, Body Scan delta), security-reviewer (rounds 1 to 3), product-ux-reviewer (UI-0 review).
Agents and models actually run in S00: implementation-engineer, tdd-guide (Sonnet 5.5); security-reviewer, silent-failure-hunter (Sonnet 5.5, medium); reviews through GPT-PM (PM Bridge).

Next role to launch: technical-writer (finish round 3 fixes), then security-reviewer for a closing check, then GPT-PM.
