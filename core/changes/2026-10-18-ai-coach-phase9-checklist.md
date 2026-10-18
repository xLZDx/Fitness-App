# AI Coach: add falsifiable Phase 9 document checks

Date: 2026-10-18. Kind: documentation-only acceptance record refinement.

## What changed

- Added five falsifiable manual document checks to `docs/ai-coach/acceptance.md` for story accounting, open-question accounting, exact approval scope, release boundaries, and registry coverage.
- Regenerated `docs/DOCUMENT_REGISTRY.md` after the acceptance record changed.

## Why

The AI-COACH-00 Definition of Done says documentation-only sprints replace product tests with a documented falsifiable review checklist. The acceptance draft already referred to review evidence, but did not state the checklist as a compact set of explicit criteria and results. This makes the document-only evidence auditable while keeping product tests and runtime outcomes clearly NOT_RUN.

## Affected contracts and decisions

- No product behavior or decision changed. The checks establish document consistency only.
- Results are manual REVIEWED statements by Codex; they are not product-owner acceptance, the unavailable product-owner/technical-writer role reviews, or the prior exact-head GPT-PM approval.
- Operator remains accountable for accepting the draft; later implementation remains unauthorized.

## Verification state

- Manually compared each checklist result to the acceptance table, OQ table, cited approval records, release notes, and generated registry.
- Regenerated the derived registry with `python scripts/dev/gen_document_registry.py`.
- Product tests, builds, analyzers, device runs, and runtime measurements: NOT_RUN.
- No push performed; per-commit authorization still applies.
