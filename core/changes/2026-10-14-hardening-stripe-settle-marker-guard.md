# Change record: marker guard for the Stripe same-second tie settle

## What changed
`functions/src/index.ts` `applySubscription` gets a third parameter `settleIfMarkerIs`. The tie settle (`applySubscription(fresh, undefined, eventCreated)`) now runs in one transaction that writes the freshly re-read subscription only while `lastStripeEventCreated` still equals the tie value; if a newer event landed during the Stripe round trip the settle is skipped and logged. `stripe_webhook_events.test.ts` adds three tests (one-transaction settle, newer event wins over a slow `retrieve`, marker unchanged writes the fresh state).

## Why
An independent reliability review of ca40035 found that the unconditional settle write could overwrite a newer event's state (for example a cancellation) with an older re-read, leaving a lasting wrong entitlement.

## Affected contracts and paths
Stripe subscription webhook ordering only.

## Verification state
Focused Jest run by an e2e-runner agent: stripe_webhook_events 46, delete_account 53, account_deletion_reconcile 34 pass. Real Stripe contention is modelled only by the mocked transaction.
