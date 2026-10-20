# AI Coach documentation: review round 2 and second remediation batch

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/ai-coach/07_REVIEW_ROUND2.md: verification of the round 1 fixes by four read-only reviewers (architect, security, silent-failure and reliability, product-ux); 0 BLOCKER and 23 new MAJOR found in the first remediation itself.
- docs/ai-coach/06_REMEDIATION_DECISIONS.md section D: 15 decisions for the second batch (safety stop scope and user-only restart, performed facts allowed in PAUSED, internal commands applied in memory, safety marker, takeover and parked journals, owner epoch in replica documents and set ids, quarantine rules, build gate versus flag, lease and charge-on-invocation cost rules, server consent check, model-bound plan projection, late replies discarded, locked-screen talk under tap-to-talk, document corrections).
- 01_REQUIREMENTS.md (AICR-045, 047, 051, 082 amended; AICR-116 to 138 added; 138 requirements, 126 P0; OQ-29 and OQ-30), 02_BACKLOG.md (ACS-110 to 115), 03_DESIGN.md (revision 3), 03a_ADR_PROPOSALS.md (ADR-011 and ADR-012 amended), 03b_UI_SPEC.md (LC-16, exercise-level pain stop, AC-LC-40 to 50), 04a_FUNCTIONAL_TEST_PLAN.md (59 new rows), 04b_E2E_AND_DEVICE_PLAN.md (new scenarios, spike criteria, operator blockers OB-16 to OB-18).
- docs/ai-coach/00_README.md: package index.

## Why
SDLC phase 5: the verification round found that the first remediation introduced new gaps; they are fixed in one batch.

## Affected contracts and paths
Documents only under docs/ai-coach/. No code, rules, manifest, data or Phase 2 document changed.

## Verification state
Documentation only. Agents (Sonnet 5.5): architect, security-reviewer, silent-failure-hunter, product-ux-reviewer, technical-writer, business-analyst, ui-designer, functional-test-reviewer, e2e-runner. Reviewer claims were applied as decisions; editing agents re-opened only the code lines they cite themselves. Open: operator acceptance of the unpersisted safety-stop residual risk (OQ-29), numeric caps, symptom list signer. No tests run.
