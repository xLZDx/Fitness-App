# S03 carried items, deviations and accepted risks

Date: 2026-10-17. Status: living record for the S03 acceptance. Evidence pointers are files in this repository; nothing here is an operator decision unless it says so.

## 1. Deviations from the approved design or contract

| Item | What differs | Reason | Where recorded |
|---|---|---|---|
| AC-PR-2 | No Try again button in the unreachable `failedToOpen` state (Progress, Sources). | The state cannot be left by a retry of the same operation. | S03_DESIGN.md (disclosed), S03_TEST_FINDINGS_EPIC3_4.md |
| R14 | Loading can last up to 11 min 20 s while a bind keeps failing (retry delays 5 s, 15 s, 60 s, 5 min, 5 min). | Accepted risk of the retry schedule, delays unchanged from S02. | S03_DESIGN.md |
| One popup route | All surface placements (sheet, popover, dialog) use one PopupRoute instead of three route types. | Live re-placement when the window class changes. Judged sound by the architecture review. | review of 2026-10-17, adaptive_surface.dart |
| Home one column | Home uses one column above text scale 1.3. | The contract says one column at large text without a number; 1.3 is the coordinator's value. | S03_TEST_FINDINGS_EPIC3_4.md |
| Compact dock | The compact dock is also used above text scale 1.5. | Pill was 230x70 instead of 48x48 at scale 2.0; 1.5 is the coordinator's value. | S03_TEST_FINDINGS_EPIC5A.md |
| Sign-out sheet | Extra keep-data action. | Needed so keep is an explicit choice. | S03_TEST_FINDINGS_EPIC3_4.md |
| Health row label | The code says "Health platform", the plan said "Apple Health". | Region and build targets are undecided (no Apple targets in S03). | S03_TEST_FINDINGS_EPIC3_4.md |
| Session owner | The owner of the running session is not cleared on account switch; a foreign-owner flag hides the strip and the Record pill. | Clearing it while a timer runs would show account A's session to account B. | core/changes/2026-10-17-s03-l12-fix-batch-4-5.md |
| Pause announcements | A rest pause and a set pause cannot be told apart, so both announce pause and resume. | Single status value. | main_shell.dart, core/changes/2026-10-17-s03-l12-fix-batch-8-9.md |
| Record rows | While the mode loads the Record sheet shows the neutral Train rows. | No empty state defined in the contract. | S03_TEST_FINDINGS_EPIC2.md |

## 2. Findings not fixed in S03 (minor, carried)

- Record row flag inputs: `recordRowsFor` has no inputs for the food flags; tests DT-11-1 and the flags-off row of AC-RC-3 stay weak, and DT-11-1b pins the current behaviour and must be replaced when the inputs are added.
- Reliability review: no timeout on a hung journal open; the controller does not notice an external unbind of the journal; a second uncoordinated bind path exists in the cloud sync wiring.
- Security review: a guest who signs out and keeps data cannot reach it again (the next guest gets a new uid); the unbound-scope wipe has no fallback when the journal cannot start; a crash during export can leave a plaintext GPX in the cache directory.
- Silent-failure review: unknown mode entries are dropped on read and erased on the next write by an older build (rule: adding a mode requires a format version bump).
- Architecture review: duplicated one-at-a-time sheet flags, back rule and shell path lists; the TRAIN answer has two owners (mode store and training context) with two non-atomic writes; the mode change bus has no production consumer; `modeWarmUpProvider` and the migration import each other.
- Flutter review: Progress and Home rebuild whole pages on provider changes (performance, not correctness).
- Accessibility review: contrast of text on the photograph was not measured.
- Test rows NOT_RUN: Home and End keys in the rail; wheel and scrollbar on the real Home and Sources pages; Record and mode-switcher shortcuts end to end; Esc ordering with a popup menu above the popover; touch-only, pointer-only and keyboard-only journeys; the scanner page as a pushed route; DT-16-3 and DT-16-8 (skipped in code); DT-13-23 and DT-14-8 (measure-only gates); AC-LS-5 offline (no seam); the shell has no seam for an injectable destination list (AC-SH-3, AC-WS-4 with four items, DT-04-2 only at widget level).
- Not built: lane L11 (conditional stories S03-19 and S03-20).

## 3. Texts that need product review

All Russian and English strings were drafted by agents and have not been reviewed by a product owner: the ARB keys added by lane L13 (runs 2 and 3), `activityTodayMore`, `activityStaleNotice`, `activityMayBeIncomplete`, the tile labels, `activityDistanceFrom`, `activityUnitKm`, the sign-out and Sources keys, `stripSessionStarted`, `stripSessionResumed`, `stripSessionEnded`, and the recovery notice texts.

## 4. Handoff to S04

See `docs/phase2/s04/S04_DOC_READINESS.md`, including the addendum about the single-source running-session status.

## 5. Operator-owned open items (defaults apply)

Sprint size; Health Connect row wording; Apple build targets (not in S03); privacy wording approval (cloud upload stays off); the designer's five assumptions; first-release region; bucket, IAM, alerts, soft-delete and service account; Blaze billing; monetisation per mode (flags, no paywall); `master` branch name; legal status of the dossier; deletion-record retention (400 days).

## 6. Layout findings in base code (found by the S03 conformance tests, not introduced by S03)

Checked with `git blame` against the branch base `2c121242`; none of these lines was changed by S03, so S03 does not fix them.

| Where | Finding | Origin |
|---|---|---|
| `mobile/lib/shared/widgets/hud/hud_scaffold.dart` (bottom bar labels, about lines 360-382) | Labels are ellipsised: WORKOUTS and PROGRESS at 360 dp and text scale 1.0, all five at scale 2.0. A code comment already says the clipping is accepted. | commit `f458635fb` (2026-08-19), in the base |
| `mobile/lib/features/home/home_page.dart` (`_TotalCard`, about lines 855-865) | The "kg lifted" and "тренировки" labels are clipped (three `Expanded` cards in a row). | commit `d951476e6`, in the base |
| `mobile/lib/features/home/home_page.dart` (about lines 588 and 1111) | "Today's adaptive plan" is clipped at 360x640 and text scale 2.0. | commit `d951476e6`, in the base |
| `mobile/lib/features/safety/widgets/eligibility_notice.dart` (about line 200) | The Russian label of the open-profile button is clipped on 1100 and 1400 dp wide windows at scale 1.0. | commit `9e0cd325f`, in the base |

Decision for the operator (default applies if no answer): leave them for a layout pass of the existing screens outside S03; the HudButton now has a `wrap` option that can be used for the two button cases.

## 7. Decision recorded in batch 15 (deviation)

The Coming-later badge on the chooser cards and in the switcher rows bounds its text scale at 1.3, because the word needs about 140 dp at scale 2.0 and only 114 to 128 dp are available. The full meaning stays in the semantics label and hint. Alternative if rejected: a layout with the badge on its own line below the title (changes the shared setting row).
