# S03 code map, technical design, test plan and internal review batch 1

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/phase2/s03/S03_CODE_MAP.md: facts about the existing code that S03 touches (code-explorer).
- docs/phase2/s03/S03_DESIGN.md: technical design of sprint S03 (stories S03-0 and S03-01 to S03-20, coverage of the 124 contract acceptance criteria), with the disposition table of the internal review at the end (RV-1 to RV-19).
- docs/phase2/s03/S03_TEST_PLAN.md: the test plan (452 without and 464 with the two conditional stories planned tests), updated with the nine test-plan findings and with a guarding test for every design finding.
- docs/sdlc/STATE.md: S03 phase table (discovery, design and test plan done, document review in progress).
- core/DECISION_LOG.md, core/LESSONS_LOG.md, docs/DOCUMENT_REGISTRY.md: entries for this commit.

## Why
Documentation first: the design and the test plan are reviewed by architect, flutter-reviewer, silent-failure-hunter, security-reviewer and tdd-guide before any code exists. The review found no blocker and 21 root causes; one of them is a real defect inherited from S02 (the Android backup rules do not cover the real journal directory), which must be fixed inside story S03-0 before the journal is switched on by default.

## Affected contracts and paths
None in code. The design now requires, in the build: `core/wiring/activity_wiring.dart` (bind status), `mobile/android/app/src/main/res/xml/backup_rules.xml`, `data_extraction_rules.xml`, `journal_layout.dart` and the backup tests (story S03-0).

## Verification state
Documentation only; nothing was run. The reviewers read the documents and the code, they ran nothing. The GPT-PM documentation gate for this head has not been requested yet.
