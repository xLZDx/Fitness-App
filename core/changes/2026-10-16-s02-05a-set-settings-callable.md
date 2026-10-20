# S02-05a change record: setActivityCloudSettings callable, quota name, export

Date: 2026-10-16. Story: S02-05a (design 5.3, 5.4, 6.1, 9, 9.1; test ids F13, F68, F75, F82, I28).

## What changed

- `functions/src/activity_streams/set_settings.ts` (new): the callable `setActivityCloudSettings` on the `RARE` profile (App Check follows `APP_CHECK_ENFORCED`, plus `noteAppCheck`).
  - Pipeline: auth -> App Check note -> anonymous refused -> strict parse -> feature flag (only when granting) -> daily quota `activitySettingsSet` -> one transaction.
  - The transaction reads `users/{uid}/activity_settings/main`, the delete fence `activity_account_state/{uid}` and `accountDeletionRetries/{uid}`, refuses (`account_deleting`) if either fence exists, checks Auth user existence (`account_deleted`), then writes retention, `settingsGeneration + 1`, `recomputePending = true` and `recomputeCursor = null` (retention change) and the consent fields (server timestamps) in a single `set` merge (F75). A request equal to the stored state writes nothing.
  - Withdrawal records `cloudStreams.withdrawnAt` and increments the generation; re-granting clears `withdrawnAt`. Upload refusal with `consent_withdrawn` is done by S02-04b through `cloudStreamsConsentState`.
  - Seams for tests: `applyActivityCloudSettings(deps, uid, req)` and `handleSetActivityCloudSettings(deps, uid, signInProvider, data)` take injectable Firestore, Auth-existence check and clock.
  - Errors are bare codes only: `invalid_request`, `invalid_retention`, `invalid_consent`, `account_deleting`, `account_deleted`, `quota_exceeded`, `settings_failed`; logs carry slugs and counts, never a uid.
- `functions/src/abuse_guard.ts`: `QUOTAS.activitySettingsSet = 20` and the name added to `REDACTED_QUOTA_ACTIONS` (list edit only; the pinned test is updated by test agents).
- `functions/src/index.ts`: export of the callable.

## Why

Settings are the one input the upload callables trust, so they are server-written and fenced exactly like the other new callables (design 5.4, 6.1).

## Deviations and notes

- A pure withdrawal request is NOT charged against the daily quota (design 9.1: an erasure-side action must never be rate-limited); every other request is charged and refunded when nothing was written.
- Only the quota name of this callable was added; the other six names arrive with their stories (the design's "seven names" pinned-test update is therefore done incrementally by test agents).
- Anonymous callers are refused (`permission-denied: anonymous_not_allowed`), by an own check rather than the AI-specific `enforceNonAnonymousForAi`.
- Granting consent answers `feature-disabled` while `ACTIVITY_STREAM_BUCKET` is unset; retention changes and withdrawal are always allowed.
- OPEN-DEFAULT (still unanswered): default 730 days, allowed set 90/365/730, "never" (`null`) offered; constants in `settings.ts`.
- Not owned by this story: bulk delete job (`deleteAllActivityStreams`, S02-06b), reconciler abort of pending rows, `firestore.indexes.json` (S02-05b).

## Verification state

No tests, builds, lint or type checks were run (operator rule v4); `node_modules` is absent in this worktree. Test agents verify with F13, F68, F75, F82 (quota part), I28 (client side, not touched here).
