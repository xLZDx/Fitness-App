# AI Coach: align README decision summary with OQ-19

Date: 2026-10-18. Documentation-only correction discovered while searching the full AI Coach document set after the OQ-19 clarification.

## What changed and why

The operator-decision summary in `docs/ai-coach/00_README.md` still said that nothing left the phone except what the user said. This was misleading because the utterance itself may contain health information and is sent to the remote model on a turn only when current server-confirmed consent exists. The summary now distinguishes app-derived restriction/screening fields (excluded from model context) from potentially health-bearing speech, and keeps operator acceptance and privacy wording open under OQ-08/OQ-19. Historical wording in `06_REMEDIATION_DECISIONS.md` remains unchanged as a record of the prior proposal.

## Paths and contracts

- `docs/ai-coach/00_README.md`: current operator-decision summary, aligned with requirements, design and acceptance.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after the document edit.

No application code, runtime behavior, product decision or authorization boundary changed.

## Verification state

- Exact-text search across `docs/ai-coach` found the stale summary; other occurrences are historical reviewer/decision evidence or test-plan descriptions consistent with the health-bearing utterance contract.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only change.
- Push and merge: not performed.

## Remaining acceptance

OQ-19 remains an open operator decision. Runtime payload and logging behavior are not verified by this documentation update.
