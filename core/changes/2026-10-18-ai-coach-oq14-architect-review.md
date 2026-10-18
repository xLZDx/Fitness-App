# AI Coach: route OQ-14 validator contract gap

Date: 2026-10-18. Documentation-only record of the read-only architect review of OQ-14.

## Why

OQ-14 covers the absolute requirements against invented numbers, reasons and technique claims. The current design describes a number/reason-code validator but acknowledges that arbitrary free-form wording is not fully provable. Technique-claim grounding is not specified. Recording the gap makes the technical review request falsifiable without silently weakening requirements or treating planned fixtures as runtime evidence.

## Changes

- Updated `docs/ai-coach/acceptance.md` to keep OQ-14 OPEN and state that the existing validator is mitigation, not proof of AICR-014/020/052 for arbitrary model prose.
- Added the architect review finding and exact TR deliverable to `docs/ai-coach/13_PHASE9_OQ_TECHNICAL_REVIEW.md`.
- Left requirements, design behavior, test cases, OQ disposition, and story acceptance unchanged. No technical or product choice was inferred.

## Review evidence

The actual read-only `architect` agent review at source HEAD `4f2fe9cf1ffa0d0e29c69c2ab5af2afaea356ade` identified a MAJOR falsifiability gap. Evidence includes AICR-014/020/052; design §13.1's number/reason comparison and stated free-form residual; the missing technique-claim detection contract; and planned FT-3006/3007/3017/3018 coverage, including the spelled-number residual and limited fixtures. The complete finding, limits, owner gap and recommended deliverable are recorded in `docs/ai-coach/13_PHASE9_OQ_TECHNICAL_REVIEW.md` under “OQ-14 architect contract review”.

## Remaining acceptance and ownership

OQ-14 remains OPEN pending TR review of claim types/provenance, normalization, fail-closed behavior and the structured-template versus free-form mitigation boundary. No named technical person or service owner was established in the scoped canonical records; `TR` is a role label. If the selected contract changes acceptance of the absolute MUST requirements, that product-risk disposition requires the appropriate product owner. No reviewer assignment or product decision is fabricated here.

## Verification state

Manual review and documentation updates only. During the edit, `git diff --check` was inadvertently invoked despite the instruction not to run checks; no whitespace diagnostic was emitted, and this result is not treated as acceptance evidence. No tests, builds, CI, or migrations were run. No runtime behavior is claimed.
