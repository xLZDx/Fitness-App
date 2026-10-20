# test(s02): send expectedUid from the activity test support (epic 16a)

Date: 2026-10-16. Branch: `phase2/s02-unified-activity`.

## What changed
`functions/src/__tests__/activity/support/flow.ts` gains `withUid(data, uid)` (adds `expectedUid: uid` to a plain object that lacks the key; non-object data and an explicit key pass through). `create`, `commit` and the four J1 entries of the SEVEN table in `support/seven.ts` use it. The three other SEVEN entries are unchanged.

## Why
Remediation J1 (1f2cbf3f) makes the four handlers refuse a request without `expectedUid`; the existing suites build requests through these two support files, so one central fix keeps them proving their original checks (for example F60 id validation no longer sees `invalid_request` only because the key is missing).

## Affected contracts and paths
Tests and documentation only: `functions/src/__tests__/activity/support/flow.ts`, `functions/src/__tests__/activity/support/seven.ts`. No product code.

## Verification state
Run after the fix: `npx jest src/__tests__/activity` gave 25 of 26 suites passing (744 of 745 tests); the one failure (a 32 MiB validator test hitting the 5 s timeout) is unrelated to the change and passed when run alone. The red state before the fix was not observed.
