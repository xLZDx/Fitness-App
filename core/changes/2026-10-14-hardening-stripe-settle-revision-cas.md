# Change record: write-revision compare-and-swap for the Stripe tie settle

## What changed
`functions/src/index.ts`: the subscription document carries `stripeWriteSeq`, incremented by every event write in `applySubscription`. The same-second tie settle captures the revision its own write produced and writes the re-read subscription only while the stored revision is unchanged (replaces the `lastStripeEventCreated` marker guard). `stripe_webhook_events.test.ts`: faithful optimistic transaction mock, the regression of two events in the same second (a late older re-read cannot overwrite the later event), and updated expectations. `core/DECISION_LOG.md`: duplicate entry removed.

## Why
GPT-PM review of 4995369 (MAJOR): the `event.created` marker cannot distinguish two events in the same second, so a delayed settle could overwrite the later event's state.

## Affected contracts and paths
Stripe subscription webhook path; a new server-written field `stripeWriteSeq` on `users/{uid}/subscription/main`. Other writers of that document (lifetime payment) do not bump it, so a settle racing such a write is not guarded by this mechanism (unchanged exposure, documented).

## Verification state
Focused Jest by an e2e-runner agent: stripe_webhook_events 49, delete_account 53, account_deletion_reconcile 34 pass. Real Stripe/Firestore contention is modelled by the test transaction mock only.
