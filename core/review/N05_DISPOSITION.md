# N-05 — disposition

**`N-05 = OPERATOR / PLATFORM DECISION REQUIRED`.**

Not closed, and not closed by anything in this repository. Two independent review rounds converged
on the same conclusion: **per-account uniqueness is not the binding constraint**, so the control
N-05 asks for cannot be built here, and the three controls that were proposed to build it are
either unshippable, unsizable, or aimed at the wrong thing.

This document records what was measured, what was tried, what was rejected and why, and the exact
decision that is left for a person. Everything below carries a `file:line`. Where a number could
not be obtained from the repository it says so rather than estimating.

---

## 1. What N-05 asked for

A per-account limit that binds — such that creating another account is not a free reset of an
expensive resource budget. The expensive resource is a GCS V4 signed URL for a licensed video clip.

## 2. Why the per-account framing fails — two independent reasons

### 2.1 The signed URL is a caller-agnostic bearer token

`functions/src/video_urls.ts` mints a V4 signature over the bucket, the object, the expiry and the
signing identity. Its own comment: *"Nothing about the caller enters it."* There is no IP
condition, no byte cap and no single-use constraint — GCS V4 supports none of them. Life is
`TTL_MINUTES` 15 + `REUSE_MINUTES` 5 = **20 minutes**, and signatures are cached module-scope keyed
on the object alone (`video_urls.ts:138`, the module-scope `signatures` map), handed to every caller on that instance.

**Therefore the quota meters signature MINTS, not egress bytes.** One URL given to N people and
fetched M times costs N×M egress and one unit of quota. No per-account control touches redemption
of an already-minted URL, and none of P1/P2/P3 below would have.

### 2.2 There is no lifetime cap at all

`enforceDailyQuota` keys on `users/{uid}/usage/{yyyy-mm-dd}` (`abuse_guard.ts:81-82`), so the
counter resets at every UTC midnight, forever. The library is **2,539 distinct storage objects**
(1,235 exercises with one variant, 652 with two — the figure `abuse_guard.ts:164` already states).

So: 17 free anonymous accounts sweep the library in one day at 150 objects each. **One verified
account sweeps it in three days** on the undivided 1,200, with zero rotation and nothing to detect.
Requiring a real identity makes the per-identity attack slower and quieter, not impossible — and it
looks like a fix.

## 3. What the exposure actually is

**Not the money.** Full-library extraction costs SPTR about **$0.077–$0.31** (2,539 objects at the
measured 0.25–0.283 MB post-transcode, `runbooks/video_bundle_import.md:37,68`, at $0.12/GB,
`runbooks/video_hosting.md:36`, no free tier in `europe-west1`). Egress is 96–99% of the bill.

The two real exposures are:

1. **The licence condition**, quoted at `video_urls.ts:9-12`: users must not receive *"raw files,
   public storage folders, or permanent downloadable links."* Note what it does **not** say — it
   places no cap on volume. What would breach it is links outliving the app session, which
   `TTL_MINUTES`, `REUSE_MINUTES` and the private bucket already govern, and which no request
   counter affects.
2. **Amplification.** One free uid mints 150 bearer URLs, each redeemable without bound for 20
   minutes. A thousand free accounts at ten thousand redemptions each is roughly $44,000/day, and
   there is **no project-wide cap of any kind** (`scaling.ts` sets concurrency ceilings, not cost
   ceilings; grep for `global`/`aggregate`/`projectUsage` in `functions/src` returns nothing).

## 4. What was proposed, and why each part failed

The round-1 synthesis proposed three reversible controls. Round 2 was instructed to break them, and
did.

### P1 — a per-account cumulative ceiling on distinct objects ever signed

**Rejected: structurally irreconcilable with the refund invariant.**

`clipUrls` charges **before** it signs, deliberately — `abuse_guard.ts:117-121`: *"charging
afterwards would let a caller consume IAM signing operations for free by requesting objects that
fail."* It then refunds what it could not sign (`video_urls.ts:331-335`), because stale catalogue
paths are a live case (`video_urls.ts:311-314`).

A cumulative **distinct** set cannot join that scheme:

* **Add at charge time** — `arrayRemove` on refund is wrong, because the object may have been
  legitimately signed on an earlier day, so refunding would hand back budget genuinely consumed.
  A stale catalogue entry therefore becomes a permanent, irreversible lifetime debit for a clip the
  user never received.
* **Add after signing** — the check and the write are no longer atomic, which is exactly the race
  `abuse_guard.ts:64-67` says the transaction exists to prevent. Two concurrent calls at 999 against
  a ceiling of 1,000 both pass and both add 60.

There is no third option: Firestore's `arrayUnion` is commutative and server-side, but nothing can
condition on post-union cardinality in the same operation.

Secondary, and independent: at a measured mean object-key length of 57.9 bytes over 3,210 real keys,
the full set is ~146 KiB — 14% of the document limit, so **size is not the objection** — but the
transaction must read it to decide, which is a ~750× byte increase on the function
`scaling.ts:29-34` names as the only genuinely hot one, plus ~5,078 auto-index entry writes per
update against `firestore.indexes.json:3` = `"fieldOverrides": []`, i.e. no exemption exists.

**And it would buy fairness, not security.** Against a harvester — one request per object —
distinct and a plain counter are numerically identical. The difference only appears for a
legitimate re-watcher, because free users never populate the offline cache (`cache.download` has one
call site, `offline_video_providers.dart:143`, premium-gated) and the in-memory resolver cache dies
with the process, so a free user re-signs the same clip every launch.

### P2 — an identity requirement above a threshold

**Was unshippable; the blocking half is now fixed, and the remaining half is not.**

At the time of review the remedy P2 offers a guest — "sign in with Google" — had no reachable UI,
and the only alternative orphaned their data. **That is fixed in this branch** (see the guest
upgrade commit). What is not fixed is that P2's promise is conditionally false: on
`credential-already-in-use` the code falls back to `signInWithCredential` and, at
`firebase_auth_repository.dart:179-182`, *"this device's guest data stays orphaned but intact."*
That is the reinstall and second-device case.

Making that path the escape hatch from a quota refusal means a user is told "sign in to keep
watching", complies, and loses their history. **P2 must not ship on top of it without either
handling the collision or warning before the tap.** The copy in this branch names the exception; the
flow still does not handle it.

### P3 — a project-wide daily ceiling

**Rejected: it is a Sybil-powered denial of service on paying customers.**

A global ceiling is a shared resource any free caller can exhaust on everyone else's behalf, and the
attacker's cost to trip it equals their cost to harvest — free uids (`abuse_guard.ts:198-201`). The
same seventeen throwaway accounts that sweep the library can instead turn every subscriber's video
off until midnight UTC, at a time they choose. This holds even if the ceiling is sized correctly.

It also cannot be sized honestly. The only telemetry that ships is `firebase_crashlytics`
(`pubspec.yaml:95`) — no analytics, no performance, no aggregate counter anywhere in
`functions/src`. The real population is *"5–10 testnet users today"*
(`core/business/USER_GROWTH_PLAN.md:1,6`). The 1,000-user / 10-opens-per-session model at
`scaling.ts:29-31` is labelled a *"measured target"* and cites no source. The honest range spans
three orders of magnitude.

**The useful part of P3 survives if alarm is separated from brake.** A threshold that *pages*
someone is set from the same bad data, costs the same day of work, and cannot take the product
down: mis-sized low it costs a false alert, mis-sized high it costs one day of egress bounded at
cents. Note that a GCP budget alert may need no code at all — **whether one is configured is
UNKNOWN, because it is not in this repository.**

## 5. What was refused, and stays refused

Device fingerprinting, install-ID quotas, IP reputation stores, and anything keyed on
`instanceIdToken`. Three separate grounds, each sufficient:

* **Unavailable.** `CallableRequest` in the installed `firebase-functions@6.6.0` surfaces nothing
  harder to rotate than a uid. `AppCheckData.sub` is the App ID — identical on every install.
  Firebase Installations IDs are not surfaced to a callable. `instanceIdToken` is documented
  unverified and must never key a quota.
* **Contradicted by published policy.** Every such control must survive `deleteAccount` to work at
  all, which contradicts `public/privacy.html:87-88,93`.
* **Already refused on the record, for better reasons.** `functions/src/index.ts:462-465`: defeated
  by a factory reset, collides on shared or refurbished phones, and is personal data collected for
  no other purpose.

## 6. Adjacent findings this review produced

These are separate from N-05 and are recorded so they are not lost with it.

| # | Status | Finding |
|---|---|---|
| F2 | **FIXED** in this branch | A `resource-exhausted` refusal rendered as "The clip link is unavailable". No quota control — including the one already shipped — is honestly shippable until a refusal is distinguishable from a fault. |
| F5 | **FIXED** in this branch — option 1 | `createCheckoutSession` (`index.ts:538-546`) accepts anonymous callers for real money **including `lifetime`**, while `startFreeTrial` (`index.ts:467`) rejects them for a free trial. `quotaFor` (`abuse_guard.ts:219-225`) never reads tier, so that paying subscriber then runs at 1/8. Since the prefetch is premium-gated, **the anonymous 150 objects/day ceiling exists exclusively for anonymous users who have PAID.** |
| F-prefetch | **OPEN, recorded** | `resolveAll` still swallows a quota refusal; a prefetch stopped by the cap reports nothing. Needs a result type that can say "38 of 84, limit reached". |

**F5 was not fixed when this file was written, and now is — option 1.** What changed is evidence,
not appetite. Two independent reviews, run separately and agreeing without being shown each other's
output, established two facts this section did not have:

* **The subscription is not merely unrecoverable, it is UNCANCELLABLE.** `createPortalSession`
  (`index.ts:680`) reads the customer id from `users/{uid}/subscription/main`, and `deleteAccount`
  cancels through the same document. Both require still holding the anonymous session that is gone.
  A person who pays on a guest account and reinstalls is billed indefinitely with no route in the
  product to stop it. That is a consumer-protection defect, not a revenue trade-off, and it is what
  moved this from a product preference to a correctness fix.
* **Option 2 is affirmatively unsafe.** Exempting subscribers from the divisor makes one Stripe
  authorisation — on a stolen card — enough to unlock the undivided 1,200 objects/day, sweeping the
  licensed library in three days, comfortably inside the window before a chargeback lands. It would
  trade this defect for a licensing one.

Option 1 is four lines, reverts by deletion, and imposes exactly the friction `startFreeTrial`
already imposes. It does **not** touch what the operator reserved: anonymous sign-in keeps its video
access, and nothing about the anonymous product experience changes except that paying requires an
account that can be signed back into. The three options, with their costs, as originally recorded:

1. **Reject anonymous at `createCheckoutSession`**, as `startFreeTrial` already does. ← **CHOSEN** Consistent,
   four lines, and defensible on consumer-protection grounds — a lifetime purchase tied to an
   account with no credential to sign back into is unrecoverable. It also turns away money.
2. **Exempt an active subscriber in `quotaFor`.** Consistent with the divisor's own stated
   rationale (an anonymous uid costs nothing; one attached to a live subscription does). Costs one
   extra Firestore document read per `clipUrl` — on the hot path.
3. **Carry the tier as a custom claim**, written where the Stripe webhook already writes
   `users/{uid}/subscription/main`. Free at read time; adds a new mechanism with up-to-an-hour
   propagation on token refresh.

## 7. The decision that is actually left

Nothing in this repository can make an anonymous uid cost something. Three levers exist and all
three are outside it:

1. **App Check enforcement.** `APP_CHECK_ENFORCED` and `APP_CHECK_ENFORCED_VIDEO` both default off.
   All callables now measure attestation (`noteAppCheck`), so the production attested share is
   measurable — but it is **currently UNMEASURED**, and enforcing before measuring locks out every
   unattested real install. This is the one lever that binds a caller to an app instance, and it is
   a deployment decision.
2. **Product identity policy.** Whether anonymous sign-in keeps unrestricted video access at all.
   Anonymous sign-in is a first-class login button in this app; removing video from it is a product
   decision, and the repository has said so since the divisor was introduced.
3. **Platform cost controls.** A GCP budget alert, and whether a global brake is ever acceptable
   given §4's DoS argument. Neither lives in this codebase.

Until one of those is decided, the honest statement is the one at the top of this file. Anything
else in the repository would be a control that looks like a fix and is not — which is the specific
failure mode N-05 was opened to avoid.
