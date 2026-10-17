# S03 sprint report and retrospective: shell, mode chooser, dashboard skeleton (E2)

Phase 10 of the SDLC for sprint S03. This is the final record. No test, build or scanner was run to write this report: every number below is MEASURED (read from a git command, a file or a findings file, source named), INFERRED (stated as such) or UNKNOWN. Review verdicts are quoted from the repository records (STATE.md, decision log, lessons log) and are the reviewers' claims, not own measurements. Test counts are copied from the test agents' findings files; the coordinator ran no tests.

## 1. Goal

Source: S03 row of `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`, restated in `docs/phase2/s03/S03_DESIGN.md` and `docs/sdlc/STATE.md`.

Goal: make the unified activity of S02 visible and usable on every device family without recording anything yet. Epics: EP-1 mode state (which mode is selected, whether the chooser is still due, saved per account on the device), EP-2 mode chooser, per-mode first-run questions, mode switcher and Record sheet, EP-3 Today / This week / Progress built from `ActivitySession`, EP-4 Sources panel and the sign-out warning, EP-5 responsive shell (window-size class, bottom bar versus side rail, Record button and strip, adaptive surfaces, keyboard and pointer, conformance). Story S03-0 (the local activity journal opens in the default build) carried over from S02 (OD-9).

Operator decisions that bind the sprint (STATE.md): one app, five tabs with Record as a button; design for Android phone, iPhone, iPad, Android tablet and MacBook while only the Android platform folder exists (no Apple build targets in S03); no "never" retention.

## 2. Outcome in one paragraph

Stories S03-0 to S03-18 (19 stories) were built and tested; the two conditional stories S03-19 (shared width-cap frame for pushed pages) and S03-20 (reminder-notification tap routing), lane L11, were not built. PR #11 (branch `phase2/s03d-ui-design-contract`) was merged into `phase2/main` as merge commit `f605cf3e` on 2026-10-17 11:58 +0300 (MEASURED: `git log`). The tree of the merge equals the approved head: `git diff --shortstat 1e56d651 f605cf3e` prints nothing (MEASURED). The merge followed GPT-PM APPROVE on exact head `1e56d651` in code-gate round 2. Round 1 (`95a7ea04`) returned MODIFY with two MAJOR defects, both verified and fixed. Product acceptance (phase 9) is open: agent-drafted texts need product review, and no operator acceptance of the sprint is stated in any file read.

## 3. Heads and gate evidence

| Item | Value | Source |
|---|---|---|
| Branch base | `2c121242` (S02 merge, 2026-10-16 23:05 +0300) | git, STATE.md |
| Approved head | `1e56d651` (2026-10-17 06:33 +0300) | git log, STATE.md |
| Merge commit | `f605cf3e` (2026-10-17 11:58 +0300) | git log |
| Commits `2c121242..1e56d651` | 68 (MEASURED: `git rev-list --count`); 69 to the merge commit | git |
| Diff `2c121242..1e56d651` | 216 files changed, 30678 insertions, 473 deletions (MEASURED: `git diff --shortstat`; includes the S02 follow-up commits and documents on the same branch) | git |
| Production code in that diff | `mobile/lib`: 57 files, +11133 / -267 (MEASURED: `git diff --numstat`) | git |
| Test code in that diff | `mobile/test`: 45 files, +12215 / -20 (MEASURED: `git diff --numstat`) | git |
| Change records | 66 files named `2026-10-17-*` in `core/changes/`, of which 63 start with `2026-10-17-s03` (MEASURED: directory count) | core/changes |

The branch also carries pre-S03 commits that landed after the S02 merge: `63de75af` (operator answers), `da3279f7` (fake uid sentinel rename), `849abd5e` (S02 follow-up: retention and privacy answers, phase 9 of S02). They are in the 68 commits above and are not S03 stories.

Gates, in order (verdicts are the reviewers' claims, each verified against source by the coordinator before any fix, per the lessons log):

| Gate | Round | Head | Verdict |
|---|---|---|---|
| UI design contract (S03-D) | 1 | `5302915e` | MODIFY, 1 MAJOR and 2 MINOR: chooser grid rule contradicted card minimum widths |
| UI design contract (S03-D) | 2 | `45b9184b` | APPROVE, 0 BLOCKER, 0 MAJOR |
| Technical documentation (design and test plan) | 1 | `3bedcba4` | MODIFY, 1 MAJOR: test row DT-0-5 contradicted the retained automatic bind retry |
| Technical documentation | 2 | `27d6dc44` | MODIFY, 1 MAJOR: rewritten DT-0-5 expected a "failedToOpen" state no code path can reach |
| Technical documentation | 3 | `59828804` | APPROVE, 0 BLOCKER, 0 MAJOR |
| Code | 1 | `95a7ea04` | MODIFY, 2 MAJOR: rail Record slot and Record shortcut ignored a foreign-account session; same-account mode writes were not ordered |
| Code | 2 | `1e56d651` | APPROVE |

Internal reviews (STATE.md, merged findings in `S03_DESIGN.md` RV-1 to RV-19): before the documentation gate, five role reviews (architect 0 BLOCKER / 4 MAJOR / 3 MINOR; flutter-reviewer 0/6/5; silent-failure-hunter 0/7/4; security-reviewer 0/2/5; tdd-guide on the test plan 0/4/5), merged into 19 design findings and 9 test-plan findings; one independent reliability review of the retry state machine (0/5/4) before documentation round 3. After the build, six read-only reviews (reliability, security, architecture, silent failures, Flutter, accessibility): 0 BLOCKER, 3 MAJOR, about 30 MINOR (lessons log, entry "apply the review findings"). Verification rounds by the code-reviewer and the Flutter reviewer then found four further defects in the remediation itself (section 6).

Agents and models: STATE.md and the lessons log name the roles (code-explorer, technical-writer, functional-test-reviewer, ui-designer, product-ux-reviewer, a11y-architect, architect, flutter-reviewer, silent-failure-hunter, security-reviewer, tdd-guide, doc-updater, code-reviewer, implementation lanes, six test agents). A per-run model and effort table was not found in any file (UNKNOWN per run). Sprint policy at the time: Sonnet 5.5 for agents, reviewers Sonnet 5.5 medium or GPT-5.6 Luna.

## 4. Scope delivered versus planned

Planned: 21 stories S03-0 to S03-20 in `S03_DESIGN.md` (MEASURED: story table). Built: lanes L1 to L10 and L13 (localization keys), plus fix lane L12 with 20 batches. Not built: lane L11.

| Epic | Stories | State | Main limit (from `S03_CARRIED_ITEMS.md`) |
|---|---|---|---|
| S03-0 journal on by default | S03-0 | built; bind retry state machine, backup exclusion fixed first | no timeout on a hung journal open; second uncoordinated bind path in cloud sync wiring |
| EP-1 mode state | S03-01 | built | two owners of the TRAIN answer, two non-atomic writes; mode change bus has no production consumer |
| EP-5 shell | S03-02 to S03-07, S03-17 | built | shell has no injectable destination list, three rows tested at widget level only |
| EP-2 modes | S03-08 to S03-11 | built | Record row flag inputs missing; Record sheet shows neutral Train rows while the mode loads |
| EP-3 dashboards | S03-12 to S03-14 | built | no Try again on `failedToOpen` (deviation AC-PR-2); loading up to 11 min 20 s while a bind keeps failing (R14) |
| EP-4 Sources | S03-15, S03-16 | built | extra keep-data action on the sign-out sheet; guest who keeps data cannot reach it again |
| Conformance | S03-18 | built | 18 matrix cells skipped as base-code findings |
| Conditional | S03-19, S03-20 (lane L11) | NOT BUILT | not needed for the S03 goal; stay open for a later sprint |

Unplanned work: fix lane L12 batches 1 to 20 (defects from test runs, reviews and the code gate), two ARB lanes' extra keys (129 keys per language in the first run, 19 more later, then 7 per language for Progress; MEASURED from the lessons log), an S04 documentation readiness note (12 gaps, 8 entry decisions), and the S02 phase 10 report.

## 5. Test evidence recorded in the findings files

Command shape (from `S03_TEST_FINDINGS_FINAL.md`): `flutter test --timeout 60s <files>` from `mobile/`, Flutter 3.27.1 / Dart 3.6.0. Final complete runs, all six steps on head `489e486d` (the head after the last production change of the main build):

| Step | Scope | Passed | Failed | Skipped | Findings file |
|---|---|---|---|---|---|
| 1 | Journal availability, flags, mode state, migration, wipe | 151 | 0 | 0 | `S03_TEST_FINDINGS_EPIC0_1.md` |
| 2 | Window class, HUD, rail, dock, surfaces, session strip | 233 | 0 | 0 | `S03_TEST_FINDINGS_EPIC5A.md` |
| 3 | Chooser, questions, switcher, Record sheet | 106 | 0 | 0 | `S03_TEST_FINDINGS_EPIC2.md` |
| 4 | Dashboards, Sources, Home, Progress, sign-out warning | 247 | 0 | 2 (in code) | `S03_TEST_FINDINGS_EPIC3_4.md` |
| 5 | Keyboard and pointer | 63 | 0 | 0 | `S03_TEST_FINDINGS_EPIC5B.md` |
| 6 | Contract conformance | 177 | 0 | 18 (carried base-code cells) | `S03_TEST_FINDINGS_EPIC5C.md` |
| Total | | 977 | 0 | 20 | `S03_TEST_FINDINGS_FINAL.md` |

Sum check (MEASURED here): 151 + 233 + 106 + 247 + 63 + 177 = 977; skips 2 + 18 = 20.

Code-gate regression runs after the MODIFY (section 1a of the final file):

| Area | Head | Passed | Failed | Skipped |
|---|---|---|---|---|
| Shell, dock, shortcuts (12 new tests plus existing shell files) | `85f88bb2` | 243 | 0 | 0 |
| Mode state and write order (9 new tests plus mode and journal files) | `20b39611` | 94 | 0 | 2 (in code) |

Gaps stated by the files themselves:
- The complete runs are on `489e486d`, not on the approved head `1e56d651`. Between them production code changed in `20b39611` and `85f88bb2` (gate fixes). The mode run is on `20b39611`; the file states `85f88bb2` changes only the rail slot widget, which the mode files do not exercise. No single complete run of all six steps exists on `1e56d651` (UNKNOWN whether one exists elsewhere).
- Earlier counts in the lessons log (150, 230, 103) are from the `7888326b` and `c7758293` cycles and are superseded by the table above.
- Not run: mutation runs, full-repo suites, lint, analyzer, CI (operator rules). Compile and type safety rest on the test agents' runs only.
- Not proved (NOT_RUN, carried): real-app first Home frame; Home and End keys in the rail; wheel and scrollbar on real Home and Sources pages; Record and mode-switcher shortcuts end to end; Esc ordering above the popover; touch-only, pointer-only and keyboard-only journeys; scanner as a pushed route; RTL on shell and chooser; platform and haptic runs; real-device TalkBack and VoiceOver; offline (no seam); contrast of text on the photograph.

## 6. Defects found and by which layer

Counts below are MEASURED from the table in `S03_TEST_FINDINGS_FINAL.md` section 2 and the lessons log entries dated 2026-10-17; "defect group" is one row or one lessons entry, not a count of root causes in code.

| Layer that caught it | Defects and examples | Source |
|---|---|---|
| Internal design reviews (before code) | Android backup exclusion never matched the real journal path (inherited from S02); start-up migration race; "otherwise open" availability; 21 root causes in the first design and plan | lessons log; `S03_DESIGN.md` RV table |
| GPT-PM documentation gate | 2 MAJOR in the retry contract (DT-0-5 twice); 1 MAJOR in the contract chooser grid (S03-D gate) | lessons log |
| Implementation agents (before any run) | Design claims that were wrong: aggregates path, bottom clearance formula, missing providers and keys, no owner for ARB files, flag default test in the wrong file | lessons log |
| Test agents, first run | 6 compile errors in four lanes; Sources "In use" after failed refresh; Home two panes at large text; wrong-mode flash; stale notifier assertion; chooser Tab order; rail Record anchor; meal row order; loading card height; viewport jumps (376 dp, 155 dp); rail focus ring; focus on resize; Record pill for another account; compact dock; session announcements; Progress compensation 116 dp; shortcuts ignoring pushed pages | `S03_TEST_FINDINGS_FINAL.md` section 2 |
| Test agents, conformance matrix | 6 clipped texts: 2 S03 (Coming-later badge), 4 in base code (carried) | lessons log |
| Final complete run | raw window width read in the switcher sheet (design-rule scan) | `c7758293` |
| Internal reviews after the build | same-account auth re-emission restarted the bind (reliability, no test had a re-emission row); 2 MAJOR in scroll compensation (Flutter); logging, retry during deletion, accessibility minors | lessons log |
| Verification reviews of the remediation | explicit Train choice not persisted over a rolled-back mode; focus restored to the wrong destination; chip not at card end; started announcement dropped after a rest | lessons log |
| GPT-PM code gate | 2 MAJOR (foreign-session Record entry points; unordered mode writes) | decision log, lessons log |

Missed by the author in every group above; missed by the tests in the re-emission, foreign-session rail, write-order, chip-position and announcement-sequence cases (tests covered the cases the authors thought of).

## 7. Process failures with cost

| Failure | Facts and cost | Source |
|---|---|---|
| Compile error batch | Review batch 8 (`9b42ef53`) replaced a line that declared the mode state in the switcher sheet and left its use; the app did not compile until `7888326b`. Two test agents found it on their next run; one step-3 agent waited long and tested in a scratch copy. I committed after reading the agent's summary, without reading the risky diff. Earlier, six compile errors in four lanes were found only at the first test run because implementers may not build. | lessons log |
| Coming-later badge clamp, four rounds | `abb308c7`, `6d594805`, `711d811c` (and the chip cap follow-up `c7758293`): the first two rounds changed layout without measuring (a guessed 104 dp cap), 5 conformance cells still clipped; the measurement showed the word needs about 140 dp at scale 2.0 and 114 to 128 dp are available, so the badge text scale is bounded at 1.3 (a deviation from the contract). The conformance matrix ran after all lanes instead of after the first UI wave. | lessons log; `S03_CARRIED_ITEMS.md` section 7 |
| Shortcut instruction | My instruction to the fix agent said to replace the stack like the dock; the contract tests require Back to pop a pushed page and tab shortcuts to do nothing while one is on top. The location was also read from the router configuration uri, which ignores pushed pages (`e78925d3`). Two contract tests failed; corrected in the decision log. | decision log (`_location` entry); lessons log |
| Foreign-owner rail slot missed | Batch 4-5 applied the foreign-session rule to the dock only; the rail Record slot and the Record shortcut were not enumerated. Six internal reviews and six test steps asserted the dock and the pill, not the other entry points. Cost: one gate round (MODIFY). | lessons log, `20b39611` |
| Unordered mode writes | The mode notifier awaited the store directly, no write queue; an older write could land last. Same gate round. | lessons log, `20b39611` |
| Rail slot 16 dp shift | My fix replaced the hidden control with a fixed 64 dp box; the compact rail then moved Progress up 16 dp on an account change. Caught by the test agent's regression test, which was kept red until fixed in `85f88bb2`. | lessons log |
| Smaller | Parallel authors minted the same test ids (83 in design, 144 in plan; caught by a set comparison before the gate); six test agents shared one build cache (hours of wall clock) and one wrote to another agent's output file name; agents hit turn limits (L4b, L7, L8, designer four times) and were resumed. | lessons log |

## 8. Carried items, deviations and accepted risks

Full list in `docs/phase2/s03/S03_CARRIED_ITEMS.md`. Summary:
- Deviations from the contract or design (10 rows): no Try again in `failedToOpen`; loading up to 11 min 20 s (R14); one popup route for all surfaces; Home one column above scale 1.3 and compact dock above 1.5 (coordinator values); extra keep-data action on sign-out; "Health platform" label; session owner not cleared on account switch; pause announcements cannot tell rest from set pause; neutral Train rows in Record while loading; Coming-later badge scale bound at 1.3.
- Minor findings not fixed: Record row flag inputs (DT-11-1b pins current behaviour and must be replaced); reliability, security, silent-failure, architecture, Flutter and accessibility minors listed in section 2 of that file.
- Base-code layout findings found by the conformance tests (not introduced by S03, checked with `git blame`): bottom bar labels, Home total cards, Home adaptive plan, eligibility notice button. Default: left for a layout pass outside S03.
- Not built: lane L11 (S03-19, S03-20).
- Handoff to S04: `docs/phase2/s04/S04_DOC_READINESS.md`, including the single-source running-session status addendum.
- Product review needed: all agent-drafted English and Russian strings (ARB keys, announcements, recovery notice, tile labels).

Operator-owned open items (carried file section 5, STATE.md): sprint size; Health Connect row wording; Apple build targets; privacy wording approval (cloud upload stays off); the designer's five assumptions; first-release region; bucket, IAM, alerts, soft-delete and service account; Blaze billing; monetisation per mode; `master` branch name; legal status of the dossier; deletion-record retention (400 days); decision on the base-code layout pass; decision on the badge clamp (alternative: badge on its own line, which changes the shared setting row).

## 9. Retrospective

What worked (kept):
- Five role-scoped reviews before the documentation gate, one merged remediation batch, and an independent reliability review before gate round 3 (it found the root cause the gate had only counted).
- Test agents that wrote tests against contract rows, ran their complete set after each epic and kept failing tests red; the final complete run found a late rule violation.
- Implementation agents that reported deviations and UNKNOWNs instead of inventing code; the S04 readiness note produced in parallel without delaying the sprint.
- Landing the backup exclusion before switching the journal on.

Actions (each derived from a lessons log entry; owner is the coordinator unless stated):

1. Compile smoke after every uncompilable batch. After any batch edited by agents that cannot build, one test agent runs a compile-only smoke before the commit; the first test run starts after wave 1, not after the last lane. Read the diff of every risky edit myself. Source: entries "fix the compile errors", "declare the mode state in the switcher sheet build method".
2. Enumerate entry points of a capability. When a rule applies to a capability (foreign-session Record), list dock, rail, shortcut and sheet opener and give each a test row; any notifier that persists state gets an ordered write path. Source: entry "hide every Record entry point for a foreign session and order mode writes".
3. Keep the hidden layout. A hidden control keeps its size (Visibility with maintainSize), and a regression test checks neighbouring positions. Source: entry "keep the rail Record slot height".
4. Measure before choosing wrap, cap or clamp. Stop after one fix round and measure the word at the target scale; run the layout conformance matrix once after the first UI wave. Source: entries on the badge (three), "final complete test runs".
5. Check instructions against contract tests. Before sending a fix instruction, read the contract test it must satisfy; do not accept a guessed constant from an agent. Brief fix agents with the design rules that have scan tests (no raw widths, no raw colours). Source: decision log `_location` entry, entries "drop the chip under the icon" and "take the chip width cap from the window helper".
6. State machines: list all events of the source stream. For every stream a state machine listens to, list all event kinds the source emits and add a row for repeated and equal values; trace every new test expectation along the real call graph; send a state-machine remediation to an independent read-only review before the gate. Source: entries "ignore a repeated auth value", "failedToOpen is defensive", "one retry state machine".
7. Remediation adds state, so walk the exits. List every function that reads or resets a new state field, give each exit a test row; a layout fix gets a position assertion and a filter on transitions gets a sequence test. Source: entries "persist an explicit Train choice", "put the chip at the card end".
8. Verify design statements against files. Open any test file a design cites, grep every key, provider and path before approving, quote ownership-table paths verbatim in briefs, own shared resource files (ARB, router, main.dart) as lane rows. Source: entries on the flag default, aggregates path, L4b, copy tables.
9. Data protection before data on, and tests against real paths. Backup or wipe tests walk the real directory the factory creates, never a hand-copied name list. Source: entries "exclude the per-account activity_journal tree".
10. Test infrastructure. Each test agent uses a private output file name; schedule final runs in sequence or two waves; record each gate round head, severities and models in the sprint findings file in the same commit; record the final complete run on the approved head. Source: entries "record the final complete test runs", "S02 sprint report" (shortcoming).

Open question for the next retro: whether a final complete run on the exact approved head can be made routine, since S03 repeated the S02 gap (complete runs one fix cycle behind the approved head).
