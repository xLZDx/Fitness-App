# AI Coach Phase 9: refresh registry evidence in acceptance record

Date: 2026-10-18. Documentation-only correction to a stale registry count; no product behavior changed.

## What changed and why

- Updated acceptance check D-5 to distinguish the historical 362-entry supplied snapshot and 367-document ownership-audit generation from the later 368-document local registry generation.
- Clarified that the registry was regenerated again with the continuation checkpoint transport record and state update, while per-commit change records are intentionally excluded from the registry.
- Kept the evidence claim bounded: generated registry contents establish local inventory, not independent exact-head review approval or operator acceptance.

## Affected paths

- `docs/ai-coach/acceptance.md`
- `docs/DOCUMENT_REGISTRY.md` (regenerated)
- `core/changes/2026-10-18-ai-coach-phase9-registry-evidence-refresh.md` (this record; change records are not indexed)

## Decisions

- The old 362 and 367 counts remain as historical snapshots and are not described as current.
- No owner, story disposition, OQ decision, implementation approval, or test result was inferred.

## Verification state

- Ran `python scripts/dev/gen_document_registry.py`; it reported 368 documents. Confirmed the generated registry lists `docs/ai-coach/acceptance.md` at 33,677 bytes and contains 368 indexed document rows.
- No tests, checks, builds, CI, migrations, runtime operations, or product-code changes were run or made.
