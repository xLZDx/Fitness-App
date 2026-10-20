# AI Coach: align OQ-18 backlog status with verified interface facts

Date: 2026-10-18. Documentation-only correction found while searching open-question status references.

## What changed and why

The backlog still said the OQ-18 interfaces had not been read, although the source facts were re-read and recorded in `docs/ai-coach/01b_CODE_MAP.md` and `docs/ai-coach/acceptance.md`. Updated the backlog to point to that evidence and preserve the actual unresolved work: a deterministic multi-week composer and the source of weekly sets/reps/rest remain new technical design.

## Paths and contracts

- `docs/ai-coach/02_BACKLOG.md`: OQ-18 current status.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after the document edit.

No application code, product decision or authorization boundary changed.

## Verification state

- Exact-text search found the stale “not yet read” status; the current code map and acceptance evidence were inspected.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only change.
- Push and merge: not performed.

## Remaining acceptance

OQ-18 remains open for technical design and approval of the multi-week composer. This correction does not claim that Live Coach integration exists.
