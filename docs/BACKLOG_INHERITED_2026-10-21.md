# Inherited defects backlog (Fitness_App), 2026-10-21

Scope: defects and open items inherited by the 2026-10-20 manual branch integration. By operator decision the integration did NOT fix any of them on this base; each item below is "not fixed by integration by operator decision". Evidence source: `D:\Repo\Trash\_integrate\STATE_FitnessApp.md` and `docs/commits/2026-10-20-*.md`.

Severity values are guesses made at recording time, not reviewed ratings.

## FITNESS-INH-001: DT-0-10 journal_availability_test fails on cold start with a null uid

- Severity guess: MAJOR (a real defect in the activity journal cold-start path; 1 failing test in a 3237+ test run).
- Evidence: the `journal_availability_test` (DT-0-10) fails on this base; it was reproduced on the pristine source tip `5d5723fa` (`phase2/s04`), so it is a pre-existing defect of that branch and not an integration regression. Root cause: `UidScopedActivityJournal.bindUid(null)` on a signed-out cold start runs `_clearCompletedWipeMarkers`, which performs a path lookup before any bind has happened.
- Reference only (do NOT cherry-pick as part of this backlog commit): a reviewed fix exists on branch `integrate/2026-10-20` as commits `46abb3df` ("defer completed wipe-marker clearing so a signed-out cold start does no file I/O (DT-0-10)") and `912ab646` ("flush the deferred wipe-marker clear before a wipe and retry it on failure"), with the root-cause record `docs/commits/2026-10-21-dt-0-10-root-cause.md` and review record `docs/commits/2026-10-21-dt-0-10-review-fixes.md` on that branch.
- Origin: source branch `phase2/s04` (5d5723fa); integration origin: Merge 2 in `STATE_FitnessApp.md`.
- Suggested acceptance test: `flutter test` of the DT-0-10 journal availability test and the cold-start unbind test (`dt_0_10_cold_start_unbind_test.dart` on the fix branch) are green, and a signed-out cold start performs no file I/O before bind.
- Status: not fixed by integration by operator decision (fix exists on the integration branch; to be taken by a separate decision).

## FITNESS-INH-002: obsolete uncommitted-hardening patch for a separate sprint

- Severity guess: MINOR (stale parked artifact; risk is applying it by mistake).
- Evidence: `docs/wip-snapshots/2026-10-20-phase2-s01-uncommitted-hardening.patch` (5 lib files from the former worktree Phase2_s01). Applying it produced 210 new test failures versus 1 known failure on HEAD at the time, so it was stored instead of applied. A later check found it OBSOLETE (4 of 5 files produce identical output to main; `sign_out_guard` is a subset).
- Origin: former worktree `Phase2_s01` snapshot; integration origin: `docs/commits/2026-10-20-integrate-fitness-wip-snapshots.md`.
- Suggested acceptance test: the sprint owner either drops the patch or re-derives the one non-identical hunk against current HEAD; after that, recording, activity and android test groups show no new failures.
- Status: not fixed by integration by operator decision.

## FITNESS-INH-003: dart analyze baseline of 201 issues

- Severity guess: MINOR (static-analysis debt; 0 errors).
- Evidence: after the integration `dart analyze --no-fatal-warnings lib test` reports 0 errors and 201 issues (27 at the pre-integration baseline 14 warnings + 13 infos; 182 after the phase2 merges; 201 after the second phase2/main merge). The increase comes from merged branch code, not from integration edits.
- Origin: source branches `phase2/s04` and `origin/phase2/main`; integration origin: Merge 2 and Merge 6 in `STATE_FitnessApp.md`.
- Suggested acceptance test: `dart analyze lib test` issue count is classified (by rule and path) and reduced or explicitly waived; the count never rises above 201 in CI-free local checks.
- Status: not fixed by integration by operator decision.
