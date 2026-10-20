# S02 test epic 6b: lifecycle policy checkers, indexes, privacy text and ops log metrics (S02-08)

## What
New `lifecycle_policy.test.ts`: F38 (both node checkers run as real processes on the repository), F39 (mutated copies in a throw-away fixture root, five rows removed in turn, both checkers must fail), F40 (index entries, withdrawn index absent, old entries kept), F42, F43, F92 (empty-run entries, no uid, pinned event names, runbook name parity). Production fixes found by F38: (1) `scripts/ci/data_lifecycle_policy.json` declared `/activity_account_state/{uid}` but the access checker discovers `/activity_account_state/{docId}`, so the row never matched; path changed. (2) `scripts/ci/check_data_access_policy.js`: the audited dynamic call-site list was stale (account_export.ts `owned()` moved from line 143 to 323) and lacked the S02 call sites (account_export.ts 234 and 237, delete_all_streams.ts 183, late_sweep.ts 179, recompute.ts 173 and 204); entries added with reasons. (3) `public/privacy.html`: no statement on GPS upload, expiry setting or heart rate staying on the device (F42); one paragraph added, wording is subject to the DQ-10 operator/legal review.

## Why
The access checker exited nonzero on the repository for S02 reasons. Five further violations (body_scan/manage.ts 218, 317, 355 and nutrition_cache.ts 74, 109) pre-date S02 and are NOT fixed here; the test pins them so any new violation fails.

## Affected paths
- `functions/src/__tests__/activity/lifecycle_policy.test.ts`
- `scripts/ci/data_lifecycle_policy.json`
- `scripts/ci/check_data_access_policy.js`
- `public/privacy.html`

## Verification state
Command (cwd functions): `npx jest src/__tests__/activity/lifecycle_policy.test.ts`: 1 suite, 24 tests passed. Not covered: the emulator test functions/src/__rules__/data_access_policy.test.ts (needs the Firestore emulator, epic 5).
