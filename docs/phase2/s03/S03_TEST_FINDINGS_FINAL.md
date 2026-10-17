# S03 final test summary

Date: 2026-10-17. Branch `phase2/s03d-ui-design-contract`, base `phase2/main` at `2c121242`. This file is the summary of the per-epic findings files; the numbers are copied from the agents' final runs, not measured by the coordinator (the coordinator runs no tests).

## 1. Final complete runs (step 7)

Each test agent ran every file it wrote, once more, after the last production change that touches its area. Command shape: `flutter test --timeout 60s <files>` from `mobile/` with Flutter 3.27.1 / Dart 3.6.0.

| Step | Epic | Findings file | Run head | Passed | Failed | Skipped |
|---|---|---|---|---|---|---|
| 1 | Journal availability, flags, mode state, migration, wipe | S03_TEST_FINDINGS_EPIC0_1.md | `8783b58b` | 150 | 0 | 0 |
| 2 | Window class, HUD, rail, dock, surfaces, session strip | S03_TEST_FINDINGS_EPIC5A.md | `c7758293` | 230 | 0 | 0 |
| 3 | Mode chooser, questions, switcher, Record sheet | S03_TEST_FINDINGS_EPIC2.md | `c7758293` | 103 | 0 | 0 |
| 4 | Dashboards, Sources, Home, Progress, sign-out warning | S03_TEST_FINDINGS_EPIC3_4.md | `8783b58b` | 247 | 0 | 2 (in code) |
| 5 | Keyboard and pointer | S03_TEST_FINDINGS_EPIC5B.md | `8783b58b` | 63 | 0 | 0 |
| 6 | Contract conformance | S03_TEST_FINDINGS_EPIC5C.md | `c7758293` | 177 | 0 | 18 (carried base-code cells) |

Heads: `8783b58b` was the head of the first final run; `c7758293` added one helper function and changed one line in the mode switcher sheet (window width share). Steps 2, 3 and 6 were re-run on `c7758293` because their files cover that code; steps 1, 4 and 5 were not re-run after it (the difference is one function and one line in a file those steps do not assert on beyond what steps 2, 3 and 6 re-ran). This is a limit of the evidence, not a claim of equivalence.

Steps 2 to 6 include the existing test files named in each findings file (back navigation, HUD, shell insets, Home, Progress): all passed in the same runs.

## 2. Production defects found by the tests and how they were closed

| Found by | Defect | Closed in |
|---|---|---|
| First run (step 4) | Six compile errors in four lanes | `8a5c7474` |
| Step 4 | Sources kept saying In use after a failed refresh; Home two panes at large text; bare more line | `8a5c7474` |
| Step 1 | Home built the Train order while the mode loaded; stale notifier assertion after account switch | `fe67291b` |
| Step 3 | Chooser Tab order, rail Record anchor, meal row first, loading card height | `0969258b` |
| Steps 2 and 4 | Viewport jumps, rail focus ring, focus on resize, Record pill for another account, compact dock at large text, session announcements, chip icon | `e35a3f66` |
| Step 4 | Progress compensation moved a heading 116 dp | `d0b3ad54` |
| Step 5 | Shortcuts ignored pages pushed over a tab | `e78925d3` |
| Reviews (reliability) | Same-account auth re-emission restarted the bind | `fca06cba` |
| Reviews (all six) | Selected-mode provider, logging, retry during deletion, scroll compensation conditions, accessibility minors | `9b42ef53`, `7888326b`, `9063ad87` |
| Step 6 | Coming-later badge clipped (chooser card, switcher row) | `abb308c7`, `6d594805`, `711d811c` |
| Step 2 final run | Raw window width read in the switcher sheet | `c7758293` |

Process failures that cost rounds (all recorded in `core/LESSONS_LOG.md`): a review batch committed with a compile error (`7888326b`), a guessed constant for the badge cap, and a fix instruction of mine that contradicted the contract test (shortcuts).

## 3. Not run or only partly proved (carried)

See `S03_CARRIED_ITEMS.md` section 2 for the full list. Main items: real-app first Home frame and the dashboard-widget part of the availability row; Home/End keys in the rail; wheel and scrollbar on the real Home and Sources pages; Record and mode-switcher shortcuts end to end; end-to-end touch-only, pointer-only and keyboard-only journeys; the scanner page as a pushed route; an injectable destination list for the shell; RTL on the shell and chooser; platform and haptic runs; real-device checks with TalkBack and VoiceOver; offline (no seam); Record row flag inputs.

## 4. Not done by design

Mutation testing, full-suite runs, CI, lint and analyzer runs were not performed (operator rule). Compile and type safety rest on the test agents' runs only.
