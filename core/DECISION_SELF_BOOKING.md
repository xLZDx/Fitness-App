# Operator decision — should a coach be able to book themselves?

**Status: OPEN. Not decided here.** This document exists so the decision can be taken on evidence
rather than discovered in a support ticket. It states what the code does today, what each option
costs, and what would have to be built either way. It does not choose, because the choice is a
payments and product question and this repository does not hold the authority for it.

Raised by the R4 independent review as a MINOR whose data-export half was fixed and whose product
half was not. See `core/DECISION_LOG.md` under *Unreviewed area 2* and the 2026-08-17 reconciliation.

---

## What happens today — FACT, read from source

[functions/src/index.ts](functions/src/index.ts), `bookCoachSession`. The callable validates the
caller is signed in, that the account still exists, that `coachUid` is a bounded string with a usable
path shape, that `startsAt` is bounded and that `durationMinutes` is a whole number from 1 to 480.

**It never compares `coachUid` to `auth.uid`.**

So a coach who has finished Stripe Connect onboarding can call it with their own uid. What follows is
the ordinary path, with no branch taken differently:

```text
priceCents          = coach_listings/{self}.priceCentsPerSession
platformFeeCents    = round(priceCents * 0.15)
PaymentIntent       amount                 = priceCents
                    customer               = the caller's own Stripe customer
                    application_fee_amount = platformFeeCents
                    transfer_data.destination = the caller's own Connect account
coach_bookings/{id} coachUid = clientUid = the caller
```

The money movement is real. The caller is charged `priceCents` on their saved card; the platform
keeps 15%; the remainder is transferred to the caller's own Connect account, minus whatever Stripe
charges for the card and the transfer. **The caller ends up strictly worse off by roughly the
platform fee plus processing**, and both sides of the resulting booking document name the same
person.

This is reachable, not hypothetical: it needs only a completed coach listing, which is a first-class
state in the product.

## What has already been fixed, and what has not

The **data-export** consequence is fixed. One self-booked document satisfied both the "bookings I
made" and "bookings made with me" queries, so it appeared twice in the account export. That is a
correctness bug regardless of what the product decides, and
[functions/src/account_export.ts](functions/src/account_export.ts) now de-duplicates by `id`. Pinned
by `functions/src/__tests__/booking_export_parity.test.ts`.

The **deletion sweep** consequence was fixed earlier, in P1f: `sweepSharedRecords` queued two
`update()` calls against the same reference and the row survived a both-sides-deleted sweep. Merged
per document; measured with the pre-fix loop restored.

**Nothing has been decided about whether the booking should be possible.** Both fixes make a
self-booking behave correctly; neither expresses an opinion about whether one should exist.

---

## Option A — allow it

Self-booking stays legal. The two fixes above already make it behave consistently.

**Argument for.** A coach blocking out their own calendar through the same mechanism everyone else
uses is a coherent product story, and refusing it means a coach cannot use their own booking flow to
hold a slot. Some marketplaces deliberately allow it for exactly this reason.

**What it costs.** It cannot be left as-is if it is allowed deliberately, because the current
behaviour charges a card to do it. Allowing it properly means at minimum:

- a UI that does not present a coach with a "book" button priced at their own rate without saying
  what will happen to their card;
- a decision about whether the platform fee applies to a self-booking, and if not, a fee-free path,
  which is a second payment shape to build and test;
- accepting that self-bookings sit inside every revenue and utilisation figure the platform reports,
  and that a coach can therefore inflate their own session count at a known cost per session. Whether
  that matters depends on what those numbers are used for — rankings, payouts, tier thresholds — and
  that is not visible from here.

**Fraud surface, stated plainly.** Charging one's own card and receiving 85% back is a loss, not a
gain, so this is not a cash-out. It becomes interesting only where a *metric* is worth more than 15%
of a session — a leaderboard, a "sessions completed" badge, a payout tier, or a promotional credit.
If any of those exist or are planned, Option A needs a separate answer for each.

## Option B — prohibit it

Refuse the call when `coachUid === auth.uid`.

**Argument for.** It is the smallest possible change, it removes the class of question above rather
than answering each instance, and it is what a reader of the code expects — the absence of the check
currently reads as an oversight, which is why the review raised it.

**What it costs.** A coach loses the ability to hold their own slot through this path. If the product
wants that, it needs a separate non-charging mechanism, which is a real piece of work and is not
implied by taking Option B.

**Migration.** Existing self-bookings, if any, keep working; the refusal is on creation only. Whether
any exist in production is not knowable from this repository and should be measured before deploying,
because a refusal that breaks an existing user flow is worse than the flow it was protecting against.

---

## Recommendation

**Option B, as the reversible default.**

Not because self-booking is clearly wrong — it may well be a feature — but because of the asymmetry.
Option B is four lines and one test, it is trivially reversible, and until it is taken the product
has a payment path nobody has decided should exist. Option A is not a decision to leave things alone;
it is a decision to build a fee policy, a UI disclosure and a metrics stance, and doing that by
default is how a feature gets shipped without anybody choosing it.

If the operator wants self-booking, Option B does not close it off. Reverting a refusal is cheap;
recovering from a season of undisclosed self-charges is not.

## Reversibility

| | Option A (allow) | Option B (prohibit) |
|---|---|---|
| Code change | none now; fee/UI/metrics work later | one guard, one test |
| Reversible | reverting means refusing something users may already do | reverting is deleting the guard |
| Charges a card unexpectedly | yes, until the UI work lands | no |
| Needs a product/payments decision | yes, several | no |

## Tests required

**If Option B is chosen:**

1. `bookCoachSession` refuses when `coachUid === auth.uid` — `HttpsError("invalid-argument")` or
   `"failed-precondition"`, decided when implemented.
2. The refusal happens **before** `ensureCustomer` and before any Stripe call, so a refused
   self-booking creates no Stripe customer and no PaymentIntent. This is the assertion that matters:
   a guard placed after the Stripe call refuses the booking and still charges.
3. Control: a booking of a *different* coach still succeeds, so the guard is not satisfied by an
   endpoint that refuses everything.
4. Mutation: remove the guard and case 1 must go red; move the guard below `ensureCustomer` and case
   2 must go red.

**If Option A is chosen:** the fee policy and the disclosure are what need tests, and they cannot be
written until that policy exists.

## What is NOT in scope of this decision

- The double-listing in the account export. Fixed, and correct either way.
- The deletion-sweep survival. Fixed, and correct either way.
- Whether the 15% platform fee is right in general.
- Whether anonymous accounts should be able to book at all — that is the N-05 App Check decision,
  which is separate and also open.
