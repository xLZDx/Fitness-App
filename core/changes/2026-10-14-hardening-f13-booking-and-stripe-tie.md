# Change record: F13 follow-ups, booking sweep transaction and Stripe same-second tie

## What changed
- `functions/src/index.ts`: `bookingOps` (batch ops decided from stale snapshots) is replaced by `sweepBookings(uid)`: paged queries on `coach_bookings` by `clientUid` and `coachUid`, then one `runTransaction` per booking that re-reads the document, anonymises this user's side and deletes the row when both sides are gone (a self-booking deletes). When both parties delete their accounts at the same moment the second transaction now sees the first one's write and deletes the row. A failed transaction rejects, so the deletion record stays pending and the reconciler retries.
- `applySubscription`: events with equal `event.created` (one-second resolution) are still applied and then settled by re-reading the subscription from Stripe (`subscriptions.retrieve`) and applying the fresh object without moving the ordering marker; a retrieve failure logs a warning and keeps the tie-applied event.
- Tests: `account_deletion_reconcile.test.ts` (optimistic transaction fake, concurrent A/B race, self-booking, paging, failure), `delete_account.test.ts` (transaction-based expectations), `stripe_webhook_events.test.ts` (six tie tests).
- Plan R2-8 and R2-9: the two F13 items moved from not done to done.

## Why
They were the documented F13 leftovers of the hardening sprint; the Firestore emulator suite is now runnable on this host, so the booking change could be proven against real transactions.

## Affected contracts and paths
Account deletion sweep of shared booking rows; Stripe subscription webhook ordering. No client-visible change.

## Verification state
Focused runs by an e2e-runner agent: Jest account_deletion_reconcile 34, delete_account 53, stripe_webhook_events 43, booking_export_parity 3, alert_definitions 56 pass; the real emulator e2e of deletion (ports 18080/19099) 11 passed. Not done: Firestore shape rules (F13 third item) and the bench/rack questionnaire option, both product-scope.
