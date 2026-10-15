# S01: UI-0 baseline audit report

Date: 2026-10-15. Branch: `phase2/s01-contracts`.

## What changed
- `docs/phase2/s01/UI0_BASELINE_AUDIT.md`: read-only audit of `mobile/lib` (design tokens, HUD migration status, component and screen inventory, per-screen states, accessibility basics, plug-in points for the four-mode selector and global dashboard, discrepancies with the UI direction document, unknowns).
- `core/DECISION_LOG.md`: one entry.

## Why
Sprint S01 part (c) of the approved plan: UI-0 baseline audit, no code. The direction document had not opened the token files, so its token values were unverified.

## Affected contracts and paths
Documentation only. No code, rules or flags changed.

## Verification state
No tests or checks run. The audit was produced by a read-only agent; each statement is labelled FACT (with path) or INFERENCE. The agent did not run git and did not recompute contrast ratios. Review by product-ux-reviewer and a11y-architect, then GPT-PM, is pending.
