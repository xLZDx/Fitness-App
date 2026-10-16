# S03-D UI design contract draft and SDLC state update

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
- `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` (new): draft UI design contract for the next sprint item S03-D (app shell, mode chooser, dashboard skeleton). It records 22 repository facts, the mode model, the shell options for open question U-1 (keep five tabs with a Record shell action vs a context-sensitive Record that replaces Scan), journeys, ten screens with all states, component contracts, responsive, accessibility and localization notes, per-screen acceptance criteria and the open operator decisions with the consequence of each option.
- `docs/sdlc/STATE.md`: S02 moves from phase 6 Build to phase 7 Verify; the next role is the specialist review set, then the final GPT-PM gate.
- `docs/DOCUMENT_REGISTRY.md` regenerated.

## Why
Development rule 7: when the current sprint enters testing and review, the documentation of the next sprint is prepared in parallel by allowed-model agents without delaying the current sprint. The draft is prepared by a `ui-designer` agent (Sonnet 5.5, medium effort) and is reviewed by `product-ux-reviewer` and `a11y-architect` before any GPT-PM review.

## Affected contracts and paths
Documentation only: `docs/phase2/s03/`, `docs/sdlc/STATE.md`, `docs/DOCUMENT_REGISTRY.md`. No code, no runtime behaviour.

## Verification state
The contract is a draft. It has not been approved by the operator or GPT-PM. Open decisions (U-1, U-2, D-9 and the items listed in section 15 of the contract) remain open; the contract states a recommendation and a default for each. No tests apply to a documentation-only change.
