# AI Coach: mark historical OQ-19 shorthand as superseded

Date: 2026-10-18. Documentation-only clarification in the review-round-1 remediation record.

## What changed and why

Section C of `docs/ai-coach/06_REMEDIATION_DECISIONS.md` retained the OQ-19 shorthand “Nothing leaves the phone except what the user speaks” without stating that it had been superseded. Since spoken content can itself contain health information, left unqualified this looked like a current zero-health-data-transfer guarantee. The row now preserves the historical phrase but labels it superseded and points to the current proposed default: app-derived restrictions/screening fields and reason codes stay out of model context; a remote model turn sends the user's utterance only under current server-confirmed consent; operator acceptance remains open under OQ-08.

## Paths and contracts

- `docs/ai-coach/06_REMEDIATION_DECISIONS.md`: historical OQ-19 default visibly marked superseded.
- `docs/DOCUMENT_REGISTRY.md`: regenerated after the edit.

No application code, product decision, runtime behavior or authorization boundary changed.

## Verification state

- Exact-text search identified this as the remaining occurrence of the old OQ-19 shorthand; the current requirements/design/acceptance wording was reviewed.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only change.
- Push and merge: not performed.

## Remaining acceptance

OQ-19 remains open. The operator must decide whether spoken health content may be processed and approve consent/privacy wording. This annotation does not constitute that decision or approval.
