# SDLC state: Phase 2 program (sprints S00, S01, S02)

Source of phase truth for the Phase 2 line. Updated 2026-10-16. Head confirmed with git when written: branch `phase2/s02-unified-activity`, base `phase2/main` at `5bb61f15` (S01 merged). The earlier Body Scan sprint state (PR #5, merged as `5137ccda`) is history; its acceptance and release phases (9, 10) remain open there and need the operator-owned gates it lists.

## S00: split and migration (merged)

Current phase: closed (all ten phases done or not applicable). PR #7 (`db01888f`) and PR #8 (`89927444`) are merged into `phase2/main`; Phase 1 PR #6 (`0eee9ca2`) is merged into `phase1/main`.

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
| 10 Report + retro | done | `docs/phase2/s00/S00_SPRINT_REPORT_AND_RETRO.md` |

Open items recorded in `docs/phase2/split/BACKEND_SEPARATION.md` (before the first Phase 2 cloud deploy): production project number hardcoded in the kill-switch secret path of `functions/src/abuse_guard.ts`; candidate dotenv content not verified by the guard; separate production deploy credentials or protected CI (operator-owned); Blaze billing for the Phase 2 project (operator-owned; billing account project quota exceeded).

## S01: contracts and UI baseline (documentation only, merged)

Current phase: closed. PR #9 merged into `phase2/main` as `5bb61f15` after GPT-PM APPROVE on the exact head `d16a5b65` (round 4; rounds 1 to 3 returned MODIFY: stale Storage baseline after PR #5, debug telemetry guarantee, stale Body Scan and account-deletion statements; the cause was fixed by a full citation re-verification against the PR #5 tree).

| # | Phase | Status | Artifacts |
|---|---|---|---|
| 1 Discovery | done | requirements drawn from the roadmap and the Phase 2 plan |
| 2 Backlog | done | S01 row of the roadmap |
| 3 Design | done | `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` (98 requirements, all PROPOSED), `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md` |
| 4 Docs + test plan | done | `docs/phase2/s01/RIGHTS_STUDY_TILES_ROUTES_POI.md`, `UI0_BASELINE_AUDIT.md`, `UI0_BASELINE_AUDIT_ADDENDUM.md`, `UI0_BASELINE_AUDIT_BODYSCAN_DELTA.md`; acceptance criteria are inside the contract |
| 5 Doc review | done | security review rounds 1 to 4 closed; product-ux and accessibility review of UI-0; GPT-PM four rounds, APPROVE on `d16a5b65` |
| 6 Build | n/a | no code in this sprint |
| 7 Verify | n/a | no tests in this sprint |
| 8 Gate | done | PR #9 merged (`5bb61f15`) |
| 9 Accept + release | partial | operator answered D-16, D-17, D-6, D-7 on 2026-10-16 (recorded in contract section 9); approval of the contract as a whole is not stated, requirement labels stay PROPOSED |
| 10 Report + retro | done | gate closure report pair `reports/2026-10-16-s01-gate-closure.ru.html` and `.html`; no separate retrospective (documentation sprint) |

Operator decisions recorded 2026-10-16: D-16 GPS in the cloud with a user-set expiry and heart rate on the phone only; D-17 friends by mutual accept allowed, public sharing not allowed for minors, age self-declared (adult-minor friend edges stay refused, default E1); D-6 open source tiles; D-7 open source tracks and maps. Still open: the first-release region (before S07), D-3, D-10.

Agents and models actually run in S01 (all Sonnet 5.5): technical-writer (contract, matrix, citation re-verification), general-purpose (rights study), code-explorer (UI-0 audit, addendum, Body Scan delta), security-reviewer (rounds 1 to 4), product-ux-reviewer (UI-0 review).
Agents and models actually run in S00: implementation-engineer, tdd-guide (Sonnet 5.5); security-reviewer, silent-failure-hunter (Sonnet 5.5, medium); reviews through GPT-PM (PM Bridge).

## S02: unified activity (E1)

Current phase: 8 Gate (build finished for all stories S02-01 to S02-11; test epics 1 to 10 written, run and committed green by the test agents and the final complete runs recorded in `docs/phase2/s02/S02_TEST_FINDINGS_FINAL_RUN.md`; six independent specialist reviews done and their findings remediated in batches A to D; GPT-PM round 11 on `f1646961` returned REJECT (three MAJOR, no BLOCKER: account switch wiped another account's journal, a lost owner marker let the next account adopt a journal, tombstone push capped at 8 per pass), all three verified and remediated (E1 account-scoped journals, E2 tombstone continuation and erasure quota 1000); a second independent review round (four specialists, then three verification reviews) found further defects in the remediation, fixed in batches F and G; test epics 11 to 13 written and run green by the test agents (`docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`, `EPIC12.md`, `EPIC13.md`); GPT-PM round 12 accepted the three findings as resolved and returned REJECT for one new MAJOR (the cloud-upload consent cache was shared by all accounts), verified and remediated together with its siblings found by a class sweep of the whole surface (remediation H and I; test epics 14 and 15 written and run green by the test agents, `docs/phase2/s02/S02_TEST_FINDINGS_EPIC14.md`, `EPIC15.md`); GPT-PM round 13 on `0096dd88` accepted all earlier findings as resolved and returned REJECT for one more MAJOR (consent calls checked only the locally bound account while the callable ran as the account signed in at that instant), verified and remediated as a class (remediation J, J3: the initiating account travels in every activity callable request and is verified on the server; three independent reviewers swept the whole surface with an inventory table; test epic 16 written and run by the test agents, `docs/phase2/s02/S02_TEST_FINDINGS_EPIC16.md`); resubmitted as round 14 on the exact head recorded in the review record, push and the single sprint PR only after APPROVE; documentation phase closed earlier with GPT-PM APPROVE on exact head `9c68cab8` in verification round 10, design and test plan revision 12; started 2026-10-16 on branch `phase2/s02-unified-activity` from `5bb61f15`). Entry decisions D-16 and D-17 are answered. Sprint scope is the S02 row of `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`; GPS-specific requirements stay with S04 onwards, S02 covers the activity model, persistence, retention, deletion, export and the debug telemetry server guarantee (GPS-PRIV-050 and 098) that must exist before any GPS code.

Artifacts: `docs/phase2/s02/S02_CODE_MAP.md` (done, code-explorer); `docs/phase2/s02/S02_DESIGN.md` revision 12 (technical-writer); `docs/phase2/s02/S02_TEST_PLAN.md` revision 12 (functional-test-reviewer, 239 planned tests); two internal review rounds and ten GPT-PM rounds done, the last one APPROVE.

Next role to launch: GPT-PM verification review, round 14 (fixes plus one broad sweep of the remediation code on the exact head), then remediation in one batch if needed, then push and ONE PR for the sprint. Lessons of the sprint are in `core/LESSONS_LOG.md` and `docs/phase2/s02/S02_SPRINT_REPORT_AND_RETRO.md` (living draft). After the merge: acceptance and release notes (phase 9), report and retro (phase 10). Next-sprint documentation (S03-D UI design contract draft, revision 2, reviewed by product-ux-reviewer and a11y-architect) is in `docs/phase2/s03/`. Reports: `reports/2026-10-16-s02-documentation-phase.ru.html`, `reports/2026-10-16-s02-code-gate.ru.html`. Operator-owned open items: privacy wording approval, retention answers, bucket/IAM/alerts/soft-delete window/service account, the release gate for off-UI-isolate work (design 17 item 20), and the S03 local-journal flag decision.
