# AI Coach documentation: test plans, review round 1 and remediation

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/ai-coach/04a_FUNCTIONAL_TEST_PLAN.md and 04b_E2E_AND_DEVICE_PLAN.md: functional, E2E and real-device plans, all rows PLANNED, nothing run.
- docs/ai-coach/05_REVIEW_ROUND1.md: 97 reviewer claims from five read-only reviewers (architect 18, security 18, reliability 23, silent-failure 21, product-ux 17); two BLOCKER (second-device conflict can lose confirmed sets; a journal failure could undo a safety stop).
- docs/ai-coach/06_REMEDIATION_DECISIONS.md: the single batch of design decisions and the list of questions that stay open for the operator.
- 01_REQUIREMENTS.md (AICR-010, 021, 022, 028, 032 amended; AICR-081 to 115 added), 02_BACKLOG.md, 03_DESIGN.md (revision 2), 03a_ADR_PROPOSALS.md (ADR-011 to 013 added, all PROPOSED), 03b_UI_SPEC.md, 01b_CODE_MAP.md (marketplace folder name corrected).
- docs/sdlc/STATE.md and the generated document registry.

## Why
SDLC phases 4 and 5 for TDD-001: test plans, independent review, one remediation batch.

## Affected contracts and paths
Documents only under docs/ai-coach/. No code, rules, manifest, data or Phase 2 document changed.

## Verification state
Documentation only. Agents (Sonnet 5.5): functional-test-reviewer, e2e-runner, architect, security-reviewer, reliability-reviewer, silent-failure-hunter, product-ux-reviewer, technical-writer, business-analyst, ui-designer. Reviewer claims were applied as decisions; the editing agents verified only the code lines they cite themselves (rules line numbers were checked), the other citations are reviewer claims. Round 2 verification of the fixes is still to run. No tests run.
