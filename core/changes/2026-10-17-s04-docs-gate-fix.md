# S04 documentation gate fixes (GPT-PM MODIFY on 535ae9e4)

Date: 2026-10-17. Kind: documentation only.

## What changed
- S04_DESIGN.md, S04_REQUIREMENTS.md, S04_STORIES.md, S04D_UI_DESIGN_CONTRACT.md, S04_TEST_PLAN.md: Z1 (resume enters acquiring), Z2 (revocation seals, Keep hands off, Delete removes), Z3 (strict sign-out path plus 30-day fallback only on failed hand-off), Z4 (AC-D4-B-4 and a mechanical id comparison). Test plan now has 804 unconditional rows (838 with conditional), 108 AC ids and 58 requirements all mapped (grep set comparison empty).
- docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md: a PROPOSED S04 clarification note next to GPS-PRIV-014, pending operator approval.
- S04_REVIEW_FINDINGS_ROUND1.md: section 4 (gate findings and decisions).

## Why
GPT-PM documentation gate returned MODIFY with 3 MAJOR and 1 MINOR.

## Affected contracts and paths
Only documents; the S01 note is a proposal, not an approved change.

## Verification state
Documentation only; id comparisons run by grep.
