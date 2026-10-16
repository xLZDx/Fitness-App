# S02 test epic 11b: activityDelete quota 1000 (remediation E2 server)

## What
- Pinned values moved from 100 to 1000: `functions/src/__tests__/abuse_guard.test.ts`, `functions/src/__tests__/activity/support/seven.ts`, `functions/src/__tests__/activity/settings_consent.test.ts`, and the exhaust loop in `functions/src/__tests__/activity/callable_hardening.test.ts`.
- New test in `callable_hardening.test.ts`: the limit is 1000 (1000th call accepted, 1001st refused with a bare quota code), it is per user (another account is not affected), and a fence refusal refunds the charge.
- F82 row of `docs/phase2/s02/S02_TEST_PLAN.md` updated (one line, revision note E2).

## Why
MAJOR-03: the daily `activityDelete` quota of 100 could block erasure of a larger offline backlog; design section 17 item 21(d) raised it to 1000. Oracle: the E2 test notes and the design, not the code.

## Affected paths
The five test files above and `docs/phase2/s02/S02_TEST_PLAN.md`.

## Verification state
Run with jest, see `docs/phase2/s02/S02_TEST_FINDINGS_EPIC11.md`.
