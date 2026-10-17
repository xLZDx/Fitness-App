# S03-D gate round 1 fixes

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md: S-1 layout table (Compact and Medium rows), a new grid rule paragraph with the arithmetic, AC-CH-10 (new cases 640x360, 700x420, 600x400, 360x420), the phone table in section 10.7 (136 dp floor, 2x2 with scroll on a Compact short window), AC-WS-3 (expected rail form computed from the measured-width rule), the scale-1.3 Home assertion and the pane arithmetic note, OD-11 status, and a "GPT-PM gate round 1 disposition" table in section 19.
- core/DECISION_LOG.md, core/LESSONS_LOG.md, docs/DOCUMENT_REGISTRY.md.

## Why
GPT-PM returned MODIFY on 5302915e: the short-window chooser constraints could not be satisfied together (MAJOR), plus two stale or hard-coded statements (MINOR).

## Affected contracts and paths
None in code. S03 build will implement the chooser grid from the width-based rule.

## Verification state
Documentation only; nothing was run. The arithmetic was recomputed by hand: 608 dp grid width at 640x360 and 700x420 gives 4 cards of 143 dp; 568 dp at 600x400 and 328 dp at 360x420 give 2x2; 138 dp per card at 320 dp wide.
