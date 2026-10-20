# Integrate origin/phase2/main (85e7e91e): AI Coach TDD-001 documentation line

What: 14 docs(ai-coach) commits on top of 14513a87 (discovery, design, ADR proposals, UI spec, test plans, review rounds, GPT-PM gate records). 28 files added (docs/ai-coach/*, core/changes/*), docs only, no code, 0 deleted.
Conflicts (each read on both sides):
- core/DECISION_LOG.md, core/LESSONS_LOG.md: append-only, both sides kept (HEAD first, so the integration entries sit before the ai-coach entries).
- docs/sdlc/STATE.md: two different sections (S04 status vs AI Coach line); kept both, blank line between.
- docs/DOCUMENT_REGISTRY.md: generated file; both sides were stale row sets, so it was regenerated with scripts/dev/gen_document_registry.py (401 documents) instead of hand-merging.
Checks: no deleted files; no conflict markers; lost-content: files shared with the tip differ from it only by content that comes from s04/BASE (docs/ai-coach files identical to the tip); no code touched so analyze/tests are unchanged from the previous merge.
