# Change record: deletion and webhook hardening, export coverage, silent-failure fixes in functions

## What changed
- `functions/src/index.ts`
  - Stripe webhook: `authUserExistsForWebhook` runs before any write under `users/{uid}` (subscription, lifetime payment); `auth/user-not-found` answers 200 with a named log event, any other lookup error throws so Stripe retries. After the write `removeWriteIfAccountGone` re-checks the Auth user and removes the document just written if the user is gone, so a write that raced the Auth deletion does not survive.
  - Booking confirmation uses `update` (a booking removed by the deletion sweep answers NOT_FOUND and is acknowledged) with named log events instead of a silent `set` merge.
  - `deleteAccount` order: cancel Stripe, revoke refresh tokens, recursive delete, shared-record sweep, delete the Auth user, then one final idempotent sweep of `users/{uid}`, `donor_wall/{uid}` and `coach_listings/{uid}`. Revocation moved after a successful cancel so a failed attempt can still refresh a token and retry; the final sweep closes the window between the first wipe and the Auth deletion. A failed final sweep logs `delete_account_final_sweep_failed` and is handed to the durable reconciler (`accountDeletionRetries/{uid}` plus the scheduled `reconcileAccountDeletions`); this commit left it log-only, and the follow-up commit supersedes that.
- `functions/src/account_export.ts`: exports `stats/workout_sessions`.
- `functions/src/abuse_guard.ts`, `functions/src/monitoring/log_signals.ts`: quota-refund failures log a named event.
- `functions-equipment-identity/src/p2/text_key_index.ts`: batched writes in chunks of 450 (Firestore's batch limit is 500).
- `scripts/ci/data_lifecycle_policy.json`: `stats` classified BOTH; the equipment-identity server stores are recorded as an explicit EXPORT GAP (still deleted by account deletion) instead of claiming no Admin writer.
- `scripts/ci/check_data_access_policy.js` and its self-test: the audited dynamic-call allow-list follows `account_export.ts` (lines 107, 131, 143).
- Tests: new `stripe_webhook_events.test.ts`, `text_key_store_chunking.test.ts`; extended `delete_account`, `abuse_guard`, `account_export`, `stripe_webhook` tests; `booking_export_parity.test.ts` now scans for the `update` call shape.

## Why
After deletion a late Stripe event could re-create a subscription document with the Stripe customer id (F3), the export and policy missed data the server writes (F12), and several failures were silent (F13).

## Affected contracts and paths
- Webhook responses: 200 for a deleted user, 500 for an unknown Auth error (retry), unchanged for valid users.
- Account deletion keeps its public contract; only the order of internal steps changed. Residual risk, documented in the plan's exception register: an ID token issued before deletion stays valid for up to about an hour and Firestore rules check only `request.auth.uid`; the final sweep removes most of what such a token could write, a hard fence would need a tombstone store and is deferred.

## Verification state
Jest, `functions`: all suites pass (679 tests) after `booking_export_parity` was updated; `tsc --noEmit` clean. Jest, `functions-equipment-identity`: 518 tests pass. `scripts/ci/check_data_access_policy.js`, `check_data_lifecycle_coverage.js` and the access-policy self-test pass. Not verified here: the Firestore emulator suite and rules tests (no emulator on the host).
