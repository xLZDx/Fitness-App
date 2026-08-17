# Operator decision — should a coach be able to book themselves?

**Status: DECIDED 2026-08-17. Option B — PROHIBITED.** Implemented in
[functions/src/index.ts](functions/src/index.ts), refused before the coach listing is read and
therefore before any Stripe call or Firestore write. Reverting is deleting the guard.

**The reasoning below was WRONG in its first draft and is corrected in place.** Two independent
reviews went looking for something a self-booking could inflate — a leaderboard, a session count, a
payout tier, a ranking — and found none in this repository. The fraud argument was empty. It is
recorded as DISPROVED rather than quietly dropped, because the decision was nearly taken on it.

The first draft also said a completed coach listing "is a first-class state in the product". That is
**false**. See *What is actually reachable* below. The verdict did not change; the reason did.

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

## What is actually reachable — a correction

The first draft called a completed coach listing "a first-class state in the product". Measured:

| Claim | Reality |
|---|---|
| A coach can create a listing | `startCoachOnboarding` writes only the Connect id. `startOnboarding()` has **no caller in any screen** — it exists in a service interface and its tests. |
| A listing has a price | `priceCentsPerSession` is **never written by any production code**. It is read at `index.ts:1327` and written only in tests and a Dart model. |
| Clients can reach listings | `firestore.rules` has **no `coach_listings` block at all**. |
| The marketplace shows real coaches | It binds `MockCoachListingRepository`; the book affordance is disabled for everyone because the listings are demo data. |

So a bookable listing is a state **no shipped code can produce**. It can exist — the Admin SDK and
the console bypass rules — and the callable is deployed and reachable by a crafted request from any
authenticated user. That is why the guard is still worth its four lines. But the severity is
**API-only**, not "a user can do this today", and saying otherwise would have overstated the case.

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

## Decision — Option B, and why the stated reason matters

**PROHIBITED.** Not on the fraud argument, which two independent reviews disproved: there is no
metric in this repository to inflate, no payout to game, and the actor ends up down the platform fee.
A self-booking is a pure loss for whoever makes it.

The reason is **accounting**. This callable charges a real card. There is no refund handling anywhere
in this codebase — no `refunds.create`, no `charge.refunded` webhook — so an issued charge can only be
unwound from the Stripe dashboard, where by default the application fee is not returned and the
transfer is not reversed. A booking whose two sides name the same person is a payment shape nobody
decided to ship, and there is no machinery to undo one.

Option A was never "leave it alone". It commits to a fee policy, a disclosure and a metrics stance,
none of which exist. Arriving there by default is how a feature ships without anybody choosing it.

**Honest limitation of this fix.** It closes a small, API-only path. The larger defects on the same
callable are untouched and are recorded separately below — a reader who sees this guard should not
conclude the booking path has been audited.

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

## What this fix does NOT address — findings raised by the same reviews

Recorded here rather than fixed, because each is a separate gate and none is made better or worse by
the self-booking decision. All were measured, not inferred.

1. **No refund handling exists at all.** No `refunds.create`, no `charge.refunded` or dispute webhook
   anywhere in `functions/src`. A dashboard refund leaves the platform holding the 15% and the coach
   holding the 85%, and the booking document stays `status: "confirmed"` forever because nothing
   listens. True for every booking, not just a self-booking.
2. **No double-booking protection.** `startsAt` is an opaque bounded string, written verbatim, never
   parsed or range-queried. `bookCoachSession` never queries existing bookings. Two clients can book
   the same coach at the same instant and both are charged. This is the defect that harms real users,
   and it is strictly larger than the one fixed here.
3. **The booking UI charges with no confirmation.** A single tap fires the paid call with `startsAt`
   hardcoded to now + 1 day. Currently unreachable (listings are mock-only), and unshippable as it
   stands regardless of the self-booking question.
4. **The platform fee can be net-negative.** 15% of a small `priceCents` is less than Stripe's fixed
   per-charge component. Nothing validates a minimum price beyond `priceCents <= 0`.
5. **`yourRole` in the account export is always `"client"`** for a booking where both sides are the
   same uid. Moot for new bookings once this guard ships; still wrong for any that exist.
6. **No slot or availability model exists.** So "a coach holding their own calendar" — the strongest
   argument for Option A — is not served by self-booking either. If slot-holding is wanted, it is its
   own feature and would also close (2).

Also out of scope and separately open: whether the 15% fee is right in general, and whether anonymous
accounts should be able to book — that is the N-05 App Check question.
