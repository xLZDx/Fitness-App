# AI Coach: prepare Phase 9 acceptance and release drafts

Date: 2026-10-18. Kind: documentation-only Phase 9 preparation.

## What changed

- Added `docs/ai-coach/acceptance.md` as an explicitly unaccepted draft with proposed dispositions for ACS-001..011, ACS-100 and ACS-101, evidence links, and OQ-01..31 with proposed defaults and source owner labels.
- Added `docs/ai-coach/release-notes.md` describing the merged documentation package without claiming a product release.
- Updated the AI Coach README and SDLC state to reflect the drafts and remaining review/acceptance gates.
- Regenerated `docs/DOCUMENT_REGISTRY.md` from its canonical script.

## Why

The AI-COACH-00 backlog requires a story-level acceptance record and release notes after the documentation gate. PR #13 was merged, but these Phase 9 artifacts had not yet been prepared. Drafting them makes the remaining human and role-review gates reviewable without converting proposals into accepted product decisions.

## Affected contracts and ownership

- No application code, product behavior, safety policy, privacy decision, or implementation authorization changed.
- Acceptance dispositions and defaults are proposals only. The operator/product owner remains accountable for accepting this record; technical decisions remain with the technical owners listed in source records, where identified.
- The required Codex agent profiles `product-owner` and `technical-writer` are unavailable (`unknown agent_type`). Generic GPT-6 Luna agents drafted only their individually assigned files; they did not perform the named role reviews.
- Earlier GPT-PM rounds approved exact prior heads and scoped records; none approved these post-merge artifacts.
- AI-COACH-01 implementation and production remain unauthorized.

## Verification state

- Manually reviewed draft status, scope statements, source links, and acceptance/release distinction.
- Regenerated the derived document registry using `python scripts/dev/gen_document_registry.py`.
- Tests, builds, analyzers, device runs, runtime measurements, and the new Phase 9 role reviews: NOT_RUN. Named role agent profiles were rejected by the Codex host; exact launch errors are recorded in the phase transition record.
- No push was performed. Any later push must follow the project's per-commit authorization rule.
