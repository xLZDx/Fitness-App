# AI Coach docs: record merged gate and Phase 9 transition

Date: 2026-10-18. Kind: documentation/status transition after AI-COACH-00 Gate.

## What changed

- Updated `docs/sdlc/STATE.md` to record Phase 8 completion, PR #13 merge commit `85e7e91`, and Phase 9's missing acceptance/release artifacts and unavailable authoring profiles.
- Updated `docs/ai-coach/00_README.md` to replace obsolete pre-gate instructions with the merged documentation status and current next gates.

## Why

The source of phase truth still described Phase 8 as awaiting merge, and the package README still said focused reviews and the GPT-PM gate were pending. PR #13 is now merged from approved head `e6a85647`; those instructions were stale. Phase 9 requires acceptance and release notes, which are not present.

## Affected contracts and decisions

- No product or implementation contract changed.
- AI-COACH-00 remains documentation-only. Implementation, deployment, and data migration remain unauthorized.
- `docs/ai-coach/02_BACKLOG.md` requires `acceptance.md`; the SDLC Phase 9 roster requires product-owner acceptance and technical-writer release notes.
- Launching `product-owner` and `technical-writer` through the current Codex agent host failed with exact errors `unknown agent_type 'product-owner'` and `unknown agent_type 'technical-writer'`. The configured global subagent model is `gpt-6-luna`; those profiles are not in the installed Codex profile list. No substitute role was launched.
- No operator product acceptance has been recorded.

## Verification state

- Manually confirmed PR #13 is MERGED, exact source head `e6a85647`, merge commit `85e7e91`, base `phase2/main`.
- Confirmed merge commit `85e7e91ed042b0395b7442839868a35975b62905` is an ancestor of fetched `origin/phase2/main`.
- Tests, builds, and runtime checks: NOT_RUN; documentation-only transition.
- No push was performed for this follow-up. Any later push must follow the project's per-commit authorization rule.
