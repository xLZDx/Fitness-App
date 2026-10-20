# AI Coach: GPT-PM product dispositions for OQ-14 and OQ-18

Date: 2026-10-18. Documentation and decision-register update; no implementation changes.

## Why

The operator directly assigned GPT-PM as product decision owner/signatory and delegated execution of the OQ owner/routing work. The earlier GPT-PM request covered OQ-07 and ACS-100 only and failed before send. This separate request obtains the product direction for OQ-14/OQ-18 without misrepresenting it as technical-contract approval.

## Decision evidence

GPT-PM returned `ACCEPT` for both bounded product directions on source commit `f54b05c3fec4a8f974385174039cd6fcd41aca7b`, tree `d21ef1804d43cf8450ad31805de428e0eaf7263c`. Exact PM Bridge correlation:

- Request: `e5024ec8-f0ec-4a15-a3d3-68a8daa7a073`
- Job: `eee66704-a7e2-4d46-958b-03ba6aeebd8e`
- User turn: `fe4cd638-5f39-4f68-a10e-5482e7dae331`
- Reply: `17ab61ae-fcfb-4bcf-b491-beac80ac9e21`
- Durable PM decision IDs: `AICOACH-OQ14-PRODUCT`, `AICOACH-OQ18-PRODUCT` (`APPROVED`)

### OQ-14 — accepted product direction

Use source-bound structured factual claims rendered through deterministic templates. Normalize units, numbers and locale deterministically. Missing, ambiguous, contradictory or unparsable evidence must yield refusal, clarification, or an explicitly unavailable result. Unsupported free-form factual claims are outside initial scope unless separately approved through product-risk review.

### OQ-18 — accepted product direction

Use immutable/versioned inputs and deterministic idempotent generation/persistence. Keep observed and projected volume separate unless an approved calculation rule connects them. Bound recovery inference to supported evidence, keep visual matches as candidates until confirmed, and constrain AI proposals with deterministic safety/eligibility/exercise/progression policies.

## Boundaries and remaining work

These product dispositions do not approve detailed TR contracts, schemas, freshness thresholds, formulas, recovery implementation, conflict ordering, transaction mechanisms, or weekly prescription policies. Those contracts remain `NOT_RECORDED` and require technical specification/review. The response does not sign clinical OQ-07 limits, assign an ACS-100 service/on-call owner, authorize implementation, or dispose of the 13 PENDING story decisions. The earlier OQ-07/ACS-100 request remains failed before send under its own request ID.

The operator is accountable for the delegated task; GPT-PM is the assigned product decision owner/signatory; Codex executed the documentation/decision routing; `architect` is the independent technical reviewer. No production service owner is claimed.

## Verification

Manually reconciled the correlated GPT-PM reply, durable PM decision entries, acceptance table, route record, decision log and SDLC state. No tests, checks, builds, CI, migrations, runtime actions, alert setup, push or merge were run or performed.
