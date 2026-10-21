# Change record: preserve uncommitted work from two retired worktrees (2026-10-21)

## What changed
- AI Coach worktree: its uncommitted work (the section 3 edit of `docs/ai-coach/24_PHASE9_AI_COACH_01_TRANSACTION_SCOPE.md`, the Phase 9 remediation review record and the two Phase 9 status reports) was compared with master and is already there byte for byte (the edit applied with no diff and the files exist on master), so nothing is added for it.
- Body Scan worktree: its SDLC state file is kept as history in `docs/sdlc/history/BODY_SCAN_SPRINT_STATE_2026-10-15.md` (master has its own `docs/sdlc/STATE.md`, which is not touched), and a scratch EXIF probe is kept as `core/evidence/body-scan/exif_strip_probe_test.dart.txt` (not compiled, not part of the test suite).

## Why
Operator instruction of 2026-10-21: commit the uncommitted work of both worktrees, merge it into master, then remove the worktrees.

## Affected contracts and paths
Documentation, reports and an archived text file only. No source, test or build file changes.

## Verification state
Documentation only; nothing was run. The AI Coach edit applied cleanly to master's current file (`git apply --3way`).
