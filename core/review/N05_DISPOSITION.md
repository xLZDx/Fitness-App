# N-05 — disposition

**Correction, 2026-08-28 (MVP1.G4 Step 2,
`core/G4_STEP2_APP_CHECK_BOUNDARY_2026-08-28.md`):** the User-impact row below states
"Play Integrity attests only Play-distributed builds" as an unconditional fact. That
overstates the case — Firebase's current documentation explicitly supports Android apps
distributed outside Google Play, via a documented per-app App Check console
configuration (PLAY_RECOGNIZED not required, LICENSED not required, Device Integrity
required), independently verified live before this correction was written. Whether that
configuration is actually applied in this project's Firebase Console is unverified as of
this note — until proven, App Distribution builds should still be assumed to attest as
strangers under the DEFAULT config, so this document's practical conclusions (App
Distribution testers refused under naive enforcement) are not retracted, only their
stated REASON. See the Step 2 document for the live proof plan (Option D). Left as a
pointer rather than rewritten below, since this document's own claims are otherwise
intact and load-bearing for the video-flag decision.

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
flow, at the time this was written, did not handle it.

**The flow now handles it (2026-08-18).** `signInWithGoogle` returns a `SignInResult` carrying a
`GuestUpgrade` — `linked`, `orphaned`, or `notAGuest` — instead of a bare `AuthUser` that could not
express the difference, and the login screen renders a persistent notice on `orphaned`. This is the
same remedy the quota refusal got, for the same reason: a refusal that arrives dressed as a success
is not a display problem, it is a type that failed to ask a question. The copy says the workouts
*stayed behind and are not shown here*, and a test forbids the words "deleted", "erased", "lost" and
"removed" in it, because none of them is true — the documents are intact under a uid with no
credential to sign into.

This closes the half of P2 that was engineering. **It does not make P2 shippable**, and nothing here
should be read as recommending it: whether a quota refusal may demand identity at all remains the
operator decision recorded at the top of this file. What changed is that the collision is no longer
silent, so the decision can now be taken on its merits rather than on top of a hidden data loss.

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
| F-prefetch | **FIXED** in this branch | `resolveAll` swallowed a quota refusal; a prefetch stopped by the cap reported nothing. It asked for a result type that could say "38 of 84, limit reached", and it now has two. See below. |

**F-prefetch was open when this file was written, and now is closed.** The symbol it names no
longer exists: `resolveAll` was replaced by `resolveBatch`
(`mobile/lib/features/equipment/data/clip_url_resolver.dart:82`), which returns `ClipBatch`
(`:43`) carrying `urls` and a `quotaExhausted` flag rather than a bare `Map`. The prefetch layer
converts that into `PrefetchOutcome`
(`mobile/lib/features/workouts/data/prefetch_outcome.dart:59`), whose `requested`/`ready` counts
and `quotaExhausted` flag resolve into the five mutually exclusive states of `PrefetchState`
(`:93-104`) — including `partialQuota`, which is precisely the "38 of 84, limit reached" this row
asked for. `prefetchLine` renders those states as localized sentences; nothing reaches the user
through `toString()`.

One correction to the fix is worth recording here, because it is the sort of thing a status row
hides. The first version of the chunk loop `break`-ed on the first refusal, justified by a comment
claiming the backend would refuse every later chunk too. It does not: `enforceDailyQuota` refuses
on `used + cost > limit` (`functions/src/abuse_guard.ts`) and `clipUrls` passes each chunk's own
size as `cost` (`functions/src/video_urls.ts`), so a refusal proves only that THAT chunk does not
fit in what remains. A prefetch that has spent 1,190 of a 1,200 budget still has room for a
trailing chunk of ten. `break` became `continue`; a refused chunk is charged nothing, because the
transaction throws before it writes.

**Do not read this row as evidence that an OPEN row ages into a FIXED one.** It changed because
the symbol it names is gone from `lib/` and a typed replacement is in place, both checkable at
HEAD — not because time passed.

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

Nothing in this repository can make an anonymous uid cost something. Four options exist; three are
levers and the fourth is declining to pull any of them. They are **independent** — different
systems, different costs, different blast radii — and can be taken in any order or not at all.

An audit of the previous version of this section found it was an enumeration of levers rather than
a package: of the eight fields an operator needs per option, fifteen of twenty-four were absent.
What follows is the same three levers with nothing added to the threat model and nothing new
proposed, restated so the decision can be taken without a follow-up question.

---

### Option 1 — turn on App Check enforcement

| | |
|---|---|
| **Threat addressed** | Binds a caller to an attested app instance, so uid rotation from a script that is not the real app binary stops working. This is the only lever that touches the mechanism §2.2 describes. |
| **Threat NOT addressed** | Nothing about redemption of an already-minted URL — a signed URL is a bearer token and stays one (§2.1). Nor a scripted attacker driving the genuine Play-installed binary. |
| **Privacy impact** | None new. App Check is already a declared Google processor in the published policy (`public/privacy.html:84`), and no additional personal data is collected. |
| **User impact** | Every unattested install is refused outright. That includes the operator's own phone: Play Integrity attests only Play-distributed builds, and this project ships testers through Firebase App Distribution, which is not Play (`functions/src/scaling.ts:86-91`). A device without Play Services ships no token at all and `activate()` is caught and continues (`mobile/lib/main.dart:277-280`), so it fails closed under enforcement. |
| **Cost** | No engineering work. Two environment variables and a redeploy. |
| **Reversibility** | Complete, in one redeploy. `envFlag` is strict equality against the literal `"true"` (`scaling.ts:113`), so unsetting the variable — or setting it to anything else, including `"1"` or `"TRUE"` — turns it off. |
| **Production dependency** | Larger than "measure first" suggests. The measurable population today is 5–10 App Distribution installs that attest as strangers *by design*, so measuring now returns a near-zero attested share that says nothing about a Play release. The real precondition is: **ship through Google Play, accumulate real installs, then measure.** |
| **Staging note** | There is no combination that enforces the cheap functions and not the expensive ones: `APP_CHECK_ENFORCED_VIDEO` inherits `APP_CHECK_ENFORCED` (`scaling.ts:118-124`). Video-only is a valid first stage; the reverse is not available. |
| **To authorize** | *"Set `APP_CHECK_ENFORCED_VIDEO=true` in the functions environment and redeploy. I accept that unattested installs, including App Distribution testers, will be refused."* |

### Option 2 — change the product policy on anonymous video access

| | |
|---|---|
| **Threat addressed** | Makes each uid cost a real identity, so harvesting the library needs many real accounts rather than many free ones. |
| **Threat NOT addressed** | It does not solve the problem, and this matters: §2.2 measured that **one verified account sweeps the library in three days**. Requiring identity makes the attack slower and quieter, not impossible — *and it looks like a fix*, which is the specific failure mode N-05 was opened to avoid. |
| **Privacy impact** | The largest of the three. It converts an anonymous product into an identified one for the video surface. |
| **User impact** | Unsized, and unsizable here. Anonymous sign-in is a first-class login button. The app ships no analytics — `firebase_crashlytics` is the only Firebase telemetry package, and the published policy commits to *"no third-party analytics or attribution SDK"* (`public/privacy.html:81`) — so the anonymous share of the live base cannot be obtained from this repository or the app. |
| **Cost** | Client and backend work, plus copy in two locales. Not priced further, because the option is not recommended. |
| **Reversibility** | Worst of the three, and the only one that is not clean. Accounts created under a stricter policy do not un-create themselves when it relaxes. |
| **Production dependency** | None blocking. The guest-upgrade collision that would have made this actively harmful is now handled (§4/P2), so the option is at least safe to consider, which it previously was not. |
| **To authorize** | *"Anonymous accounts lose video access. Accept the sign-up friction and the loss of the guest trial for video."* |

### Option 3 — configure platform cost controls

Two instruments, deliberately separated because §4 concluded they must be: the alarm and the brake
are not the same decision and should not be taken together.

| | **3a — budget alert** | **3b — global brake** |
|---|---|---|
| **Threat addressed** | Nobody noticing a $44,000 day (§3). | The spend itself. |
| **Threat NOT addressed** | Does not stop anything; it tells a person. | — |
| **Privacy impact** | None. | None. |
| **User impact** | **Zero.** | Severe: a Sybil-powered denial of service on paying customers, which is why §4 rejects it. Cheap for an attacker to trigger, and the victims are subscribers. |
| **Cost** | Possibly no code at all — a console setting. | Engineering plus the above. |
| **Reversibility** | Trivial. | Trivial to remove, not to undo the outage. |
| **Production dependency** | Whether one already exists is **UNKNOWN**: it is console state, outside this repository. First action is to go and look. | — |
| **To authorize** | *"Configure a GCP budget alert at $X/day for the project. Notification only, no automatic action."* | Not recommended; see §4. |

### Option 4 — accept the residual risk and revisit at Play launch

Stated explicitly because a package offering only actions is not a decision package. §3 prices full
extraction of the licensed library at **$0.077–$0.31**. On that number, accepting the risk while the
user base is 5–10 testers is defensible, and it is the only option whose preconditions are all
already met.

| | |
|---|---|
| **Threat addressed** | None. |
| **Cost** | The priced exposure above, plus whatever the library is worth to a competitor, which is a commercial judgement engineering cannot make. |
| **Reversibility** | Total — no code, no policy, no user impact. |
| **To authorize** | *"Accept the residual risk for now. Revisit N-05 when the app ships through Google Play and the attested share can be measured on real installs."* |

---

### Recommended default

**Option 3a now, Option 4 as the standing position, Option 1 staged at Play launch, Option 2 not
recommended.**

3a is free, reversible, has zero user impact, needs no code and no measurement — and the fact that
nobody currently knows whether an alert exists is itself the argument for going to look. 4 is the
honest position while the user base is small and the priced exposure is cents. 1 becomes decidable
once Play distribution makes the attested share mean something, and should go video-first. 2 buys
less than it appears to and costs the most, on the repository's own measurement.

None of this is engineering's to enact. Every option above is a deployment, a console action, or a
product policy, and the disposition at the top of this file is unchanged: **`N-05 = OPERATOR /
PLATFORM DECISION REQUIRED`.**

---

## 8. What a devil's advocate did to §7 (2026-08-18)

The recommendation above was put to an adversarial reviewer whose only instruction was to break it.
**The conclusion survived; three of the arguments for it did not.** All four findings below were
reproduced against source before being written down, and the recommendation is restated at the end
with the defects removed rather than quietly re-asserted.

### 8.1 3a and 4 answer different threats, and §7 let them read as one plan

`§3` opens by saying the exposure is **"Not the money"** and prices full extraction of the library
at **$0.077–$0.31**. `3a`'s stated threat is *"nobody noticing a $44,000 day"*. A budget alert set
at any threshold that survives normal operation **cannot fire on a $0.31 event** — so the leg that
acts is blind to the exposure the other leg accepts, and the leg that accepts is silent about the
scenario the first one watches.

Both are still worth taking. They are not a package, they are **two independent insurances against
two different failures**, and §7 presented them under one heading as though the first mitigated what
the second accepted. It does not, and nothing available here does.

### 8.2 The number Option 4 is justified by was quietly set to zero

§7 called the competitor-value of the library *"a commercial judgement engineering cannot make"* and
left it unpriced. Leaving *competitor value* unpriced is legitimate. Leaving the reader to infer
zero is not, because **this repository records what the library cost**:
`core/VIDEO_SOURCES_RESEARCH_2026-08-01.md:500,613,633` — **$329** for ~1,700+ exercises, list
$599, under $0.20 each.

So the honest framing of Option 4 is: *accept a $0.077–$0.31 serving cost to a party extracting
content with a documented $329 replacement floor, whose vendor permission is conditional
(`functions/src/video_urls.ts:9-12`).* That is roughly a thousandfold arbitrage, and it is still
defensible at 5–10 testers — but the operator is entitled to agree to it in those words rather than
in the cents.

### 8.3 "Revisit at Play launch" had no trigger, and was not yet a well-formed instruction

Two separate defects, both measured:

* **Nothing fires.** The only automated tripwire on this row is `n05_premise_holds`
  (`scripts/review/state_ledger.py`), which watches the deletion sentence in `public/privacy.html`.
  Shipping to Play changes no source file, so the one mechanism guarding N-05 is structurally
  incapable of firing on the nominated event. `core/RELEASE_BUILD_2026-08-16.md` contains no
  occurrence of `N-05`, `App Check` or `APP_CHECK`.
* **The sequence was stated backwards.** `core/PLAY_DATA_SAFETY_2026-08-05.md:197`: the Play App
  Signing SHA-256 *"cannot be added to App Check until the first bundle upload creates the key"*.
  So Option 1 is not merely gated on Play distribution existing; it is gated on a key that does not
  exist until the first upload. "Stage App Check at Play launch" is a sentence that cannot be
  executed on the day it names.

The correct form is a sequence, and it is a **calendar item owned by a person, not a tripwire**:
first bundle upload → register the Play App Signing SHA-256 with App Check → accumulate real
installs → read the attested share → then, and only then, decide on `APP_CHECK_ENFORCED_VIDEO`.
Saying so is more useful than implying a mechanism that does not exist.

### 8.4 Option 2 was judged on the wrong axis

§7 rejected Option 2 on time-to-extraction (1 day across 17 uids versus 3 days on one verified
account). That is the metric of the *extraction* scenario. But **free-account count is the only
multiplier in the $44,000 figure** — a thousand free accounts at ten thousand redemptions each —
and Option 2 is the only lever in the package that touches it. `functions/src/abuse_guard.ts:215-219`
says of the divisor already in production: *"What this does: raises the number of rotations needed
by 8×. What it does NOT do: make rotation expensive, because nothing here can."* Option 2 is the
only option that makes rotation expensive; it is the one lever that repairs the premise of a control
this backend already ships.

It is still not recommended — the privacy cost remains the largest of the four, extraction still
completes, and §2.2's *"it looks like a fix"* objection stands. But that scepticism was applied to
Option 2 and never to Option 1, whose measured capability reduction **today** is approximately zero,
and Options 1 and 2 cover disjoint attackers rather than competing on one axis.

### 8.5 One premise weakened, not broken

§7 said whether a budget alert exists is UNKNOWN *because it is console state, outside this
repository*. The **UNKNOWN stands** — nothing in this tree reads a billing budget. The **reason is
weaker than stated**: `scripts/dev/production_manifest.py:190-200` already authenticates with a
`gcloud` token and materialises live console state as a repository fact, including App Check
service configuration. So "the repository cannot know console state" is not a property of this
repository; it is a gap in one script. Whether to close that gap for billing budgets is a real
option, and it is deliberately **not** taken here: it would be built against an API nobody can
exercise from this machine, and an unrunnable reader is not a measurement.

### 8.6 The recommendation, restated

**Unchanged in substance: 3a now; 4 as the standing position; 1 sequenced after the first Play
upload; 2 not recommended.** What changed is what the operator is being asked to agree to:

1. **3a is an alarm for the money scenario only.** It will not detect the licence exposure, which
   would surface as a message from the vendor and nowhere else.
2. **4 accepts a thousandfold arbitrage against a $329 documented floor**, not merely "cents".
3. **1 is a sequence beginning at the first bundle upload**, not an event on launch day, and no
   mechanism will remind anyone.
4. **2 remains refused on privacy cost**, now with its strongest argument recorded rather than
   omitted.

An argument that survives being attacked on four axes is worth more than one that was never
attacked. It is worth less than one whose numbers were right the first time.
