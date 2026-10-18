# AI Coach: clarify OQ-19 privacy boundary and OQ-28 limits

Date: 2026-10-18. Documentation-only clarification based on the selected technical reviews in `docs/ai-coach/13_PHASE9_OQ_TECHNICAL_REVIEW.md`.

## What changed and why

OQ-19 previously used “nothing leaves the phone except what the user speaks,” which could be read as a zero-health-data-transfer guarantee. Updated the current requirements, design, backlog and acceptance wording to distinguish app-derived health fields (excluded from model context) from spoken utterances (which may themselves contain health information and are sent for remote turns only under current server-confirmed consent). The operator decision and OQ-08 consent/privacy approval remain open. The historical text in `06_REMEDIATION_DECISIONS.md` is retained as a historical record; current governing wording supersedes its shorthand.

OQ-28 previously bundled several distinct operating controls under one “numeric limits” phrase. The current requirements, design, backlog and acceptance records now separate reservation lease/heartbeat, per-session turns, per-turn deadline/output, local journal size/count and sync attempt/backlog age. TR must specify each invariant and measurement method; numeric values remain open pending spike/load/fault evidence. AI cost caps remain under OP-owned OQ-05; session/export policy remains proposed under OQ-31. No numeric value or operator decision was added.

## Paths and contracts

- `docs/ai-coach/01_REQUIREMENTS.md`: OQ-19 and OQ-28 definitions/defaults.
- `docs/ai-coach/02_BACKLOG.md`: current open-question summaries.
- `docs/ai-coach/03_DESIGN.md`: D14, §9.2, §22 privacy wording and OQ-28 split.
- `docs/ai-coach/acceptance.md`: OQ summary and owner/next-step wording.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after document edits.

No application code, data contract or authorization boundary changed.

## Verification state

- Read-only exact-text review of affected current documents: performed.
- Search for stale shorthand in current requirements, backlog, design and acceptance: performed; historical decision record intentionally retained.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only work.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed successfully and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Push and merge: not performed.

## Remaining acceptance

The clarification does not decide whether the operator accepts health-bearing spoken content, consent wording, numerical operating targets or session/export limits. Those remain assigned to OP/TR by the source records and are not changed by this commit.
