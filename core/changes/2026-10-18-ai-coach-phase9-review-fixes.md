# AI Coach: correct Phase 9 acceptance evidence and record OQ-18 facts

Date: 2026-10-18. Kind: documentation-only Phase 9 review remediation.

## What changed

- Corrected ACS-010's stale claim: the current generated registry lists the later round-4/5 records, acceptance and release-note artifacts; the acceptance record now recommends ACCEPT for this documentation criterion while retaining open OQ-17/18 proposals.
- Clarified the closure route for OQ items: technical-review-only items go to the relevant technical review; operator-owned items go to the operator/product owner; mixed-owner items receive technical review before the operator decision. The record now distinguishes role labels from named owners.
- Re-read the existing `ai_planner`, `training_context`, `recovery/deload_detector`, and `visual_equipment` interfaces and recorded their paths, data shapes, responsibilities, and live-coach integration limits in `01b_CODE_MAP.md`, OQ-18, and design §16 item 17.
- Updated AI Coach README and SDLC state with the supplementary reviews and OQ-18 evidence.
- Regenerated the derived document registry.

## Why

At exact head `bdf089c83b23ef35569ec09fc8ff117ac52b1194`, read-only `doc-updater` review (GPT-6 Luna, medium effort) found the ACS-010 registry statement stale. `product-ux-reviewer` (GPT-6 Luna, medium effort) found the same contradiction and ambiguous routing of technical and operator-owned OQs. Both findings were corrected. A `code-explorer` (GPT-6 Luna, medium effort) inspected OQ-18 interfaces and cautioned against calling the question fully resolved until the facts were added to the design/code map; the facts are now recorded, while the multi-week composition contract remains a technical design item.

## Affected contracts and decisions

- No application code, runtime behavior, product decision, safety policy, privacy decision, or implementation authorization changed.
- ACS-010 is a proposed documentation acceptance only. OQ-17/18 and all proposed defaults remain subject to their source owner labels.
- OQ-18 interface facts do not establish a live-coach API. The multi-week deterministic composer and source of weekly set/rep/rest rules remain future technical design work.
- Supplementary reviews do not replace `product-owner` or `technical-writer`, whose Codex profiles remain unavailable (`unknown agent_type`), and do not constitute operator acceptance or prior GPT-PM approval.

## Verification state

- Manually rechecked the two review findings against the updated acceptance row and closure text; compared OQ-18 facts to source code and the design pointer.
- Re-generated `docs/DOCUMENT_REGISTRY.md` using `python scripts/dev/gen_document_registry.py`.
- Tests, builds, analyzers, device runs, and runtime measurements: NOT_RUN.
- No push performed. The project requires exact-head review and explicit authorization for the exact commit list before push.
