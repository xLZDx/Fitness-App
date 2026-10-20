# AI Coach documentation: GPT-PM gate round 1 and remediation

Date: 2026-10-17. Kind: documentation only.

## What changed
- docs/ai-coach/08_GPTPM_GATE_ROUND1.md: GPT-PM verdict MODIFY on head d60cb979 (14 MAJOR F-01..F-14, 6 MINOR M-01..M-06, 0 BLOCKER).
- docs/ai-coach/06_REMEDIATION_DECISIONS.md section E: 16 decisions (epoch-bearing set id; Runtime-owned rest in tests; trusted on-screen origin for finish/abandon during a whole safety stop; deletion-fence state machine; server-enforced epoch with a callable fallback; fenced projection transaction; local emergency input vs envelope; safety marker precedence; volatile queue; quarantine only on permanent denial; charge on provider invocation; creation-time admission limit; canonical matrix; consent state machine; minor items).
- 03_DESIGN.md (revision 4, section 4.1b matrix MX-01 to MX-27), 03a_ADR_PROPOSALS.md, 01_REQUIREMENTS.md (145 requirements, 133 P0, 31 open questions), 02_BACKLOG.md (ACS-116 to 120), 03b_UI_SPEC.md (AC-LC-51 to 57), 04a_FUNCTIONAL_TEST_PLAN.md (FT-1190 to 1213, FT-2098 to 2105), 04b_E2E_AND_DEVICE_PLAN.md (X-22 to X-29, E2E-01 fixed sequence).
- Consistency fixes found by search: stale rest-ownership sentence in the design reuse map, FT-1007 exception list, MX-09 source states.

## Why
SDLC phase 8 gate: GPT-PM returned MODIFY; one remediation batch, then one focused verification round.

## Affected contracts and paths
Documents only under docs/ai-coach/. No code, rules, manifest, data or Phase 2 document changed.

## Verification state
Documentation only. Agents (Sonnet 5.5): technical-writer, business-analyst, ui-designer, functional-test-reviewer, e2e-runner; gate by GPT-PM through PM Bridge. GPT-PM reviewed only the supplied documents, not the repository. Open: OQ-31 and the PROPOSED numbers (3 export offers within 7 days, limit of 5 unfinished sessions). No tests run.
