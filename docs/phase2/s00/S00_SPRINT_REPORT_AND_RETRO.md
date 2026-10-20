# S00 sprint report and retrospective: Phase 1 / Phase 2 split and migration

Status: final for S00. Written 2026-10-16 from git, tool output and test results recorded in this program. Labels: MEASURED (read from git, tool output or test results) and INFERRED.

## Outcome
- MEASURED: Phase 1 PR #6 merged into `phase1/main` (`0eee9ca2`); Phase 2 PR #7 merged into `phase2/main` (`db01888f`); PR #8 merged (`89927444`, current `phase2/main`). Tag `phase1-baseline` at `42d1b849`. First Phase 1 to Phase 2 sync logged in `docs/SYNC_LOG.md` with merge commit `39dc95cd`.
- MEASURED: GPT-PM APPROVE for PR #7 head `48ad73a7` (four review rounds), PR #8 head `b5a6f752`, Phase 1 PR #6 head `e309e5ba`.
- MEASURED: 742 focused jest tests passed, 0 failed (`release_guard.test.ts` 505, `guard_scripts.test.ts` 112, `scaling.test.ts` 125), written and run by `tdd-guide`.
- MEASURED: the deploy-line guard covers every deploy target in `firebase.json` (functions[0], functions[1], firestore, hosting, storage); the `phase2` alias points at `fitness-app-phase2-korostelev`.

## Not done (carried forward, all operator or external)
- Blaze billing for the Phase 2 project: linking failed with "Cloud billing quota exceeded" on the existing billing account.
- Separate production deploy credentials or protected CI: the local guard cannot stop a CLI that uses other credentials or config.
- `functions/src/abuse_guard.ts:206` hardcodes the production project number in the kill-switch secret path (separate sprint).
- Dotenv content of candidate deploys is not verified by the guard.
- Three remote branches remain on GitHub (deletion blocked by the shell policy hook; recovery tags exist).
- Phase 1 fix PRs (coach form fixes, scan mapping fixes) are planned as P1-S1.

## Retrospective
- Went well: union merge of the two guards kept both sides' tests; reviews found real defects early (clean-tree scope, git-ignored deployables, unconditional `node_modules` allowance), each fixed in one batch.
- Went badly: the S00 branch was cut from `42d1b849`, so PR #5 conflicted late; the sync log needed a pure merge commit to name its SHA (first form had to be redone); `guard_scripts.test.ts` takes 10 to 15 minutes; agents hit turn limits and needed resuming.
- Actions: cut sprint branches from the current protected line; record the sync SHA before logging it; keep the decision log out of the generated registry (done); log each Phase 1 merge in `docs/SYNC_LOG.md`.
