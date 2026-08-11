/**
 * Scaling ceilings for every function in this backend.
 *
 * WHY THIS FILE EXISTS
 *
 * Before it, `grep -E "maxInstances|minInstances|concurrency|memory" src/`
 * returned nothing at all: every function ran on platform defaults. The
 * default `maxInstances` is not "unlimited", but it is uniform, which is the
 * actual problem — a runaway or simply popular function can consume the
 * regional pool and starve `stripeWebhook`, the one function here whose
 * failure loses money rather than degrading an experience.
 *
 * A ceiling is not a reservation. Setting these costs nothing until one is
 * reached; what it buys is that reaching one is contained to that function.
 *
 * WHAT IS DELIBERATELY NOT SET
 *
 * `concurrency`. The default is already 80, not 1 — the type docs are
 * explicit: "default concurrency (80 when CPU >= 1, 1 otherwise)"
 * (`firebase-functions/lib/v2/options.d.ts:67`) and CPU "defaults to 1 for
 * functions with <= 2GB RAM" (`:76`). At 256 MiB that is 1 CPU, so 80
 * requests share each instance. 30 instances x 80 = 2,400 in flight for the
 * hot path. Instance capacity was never the constraint at 1,000 concurrent
 * users; writing `concurrency: 80` here would only restate a default and
 * invite someone to "tune" it.
 *
 * THE ARITHMETIC BEHIND THE NUMBERS
 *
 * Measured target: 1,000 concurrent users. `clipUrl` is the only genuinely
 * hot function — one to two orders of magnitude above everything else — at
 * roughly 10 clip opens per 30-minute session, so ~5.5 requests/second in
 * steady state. One instance absorbs that many times over. The number that
 * sizes the ceiling is the burst: 1,000 users opening a clip inside the same
 * second needs ~4 instances at 80 concurrency. 30 leaves 8x headroom over
 * the worst burst we can construct, and still cannot swallow the region.
 *
 * Everything else is bounded by how often a human does the thing. Nobody
 * subscribes twice, and nobody generates two annual receipts.
 */
import type { CallableOptions, HttpsOptions } from "firebase-functions/v2/https";

/**
 * A profile that is required to carry a numeric ceiling.
 *
 * `CallableOptions.maxInstances` is optional and widens to
 * `number | ResetValue | Expression<number>`. Narrowing it here makes a
 * profile without a real ceiling a compile error rather than something a test
 * has to notice, which is the whole point of putting these in one file.
 */
type Capped<T> = T & { maxInstances: number };

/** One region for everything. The video bucket is EU; see the note in
 * `video_urls.ts` — signing is unaffected by the mismatch, the object fetch
 * is not, and that is a CDN question rather than a region question. */
/**
 * Same continent as the database, deliberately.
 *
 * Firestore for this project lives in `eur3` (Europe multi-region), and
 * `europe-west1` is one of the regions eur3 spans — so a function's reads and
 * writes stay local instead of crossing the Atlantic twice per document. The
 * previous value was `us-central1`, which paired a European database with
 * North-American compute; `stripeWebhook` touches several documents per call,
 * so that was a few hundred milliseconds per webhook for nothing.
 *
 * Changed during the F0 project split, while the new project had no deployed
 * functions and no Stripe endpoint yet. Region is baked into every function
 * URL, so doing this later would have meant recreating the webhook endpoint
 * and a window where payments landed nowhere.
 */
const REGION = "europe-west1";

/**
 * A6-full — App Check enforcement, staged rather than flipped.
 *
 * A6-lite made every callable REPORT whether a valid App Check token arrived
 * (`noteAppCheck` in `abuse_guard.ts`, one structured log line per call). This
 * is the switch that turns that observation into refusal. It is read from the
 * environment, so moving from stage to stage is a config change plus a
 * redeploy, not a code edit under pressure.
 *
 * ## Why it is OFF by default, and what has to be true before it goes on
 *
 * Enforcement is not free to turn on, and the failure mode is silent lockout
 * of legitimate users rather than a visible error. Three preconditions, all
 * checkable, none currently met:
 *
 *   1. **Play Integrity only attests builds distributed through Google Play.**
 *      This project ships its tester builds through Firebase App Distribution
 *      (`scripts/dev/build_release.ps1 -Distribute`), which is NOT Play. A
 *      release APK from that channel attests as a stranger. Enforcing today
 *      breaks the operator's own phone first.
 *   2. **The console has to show attestation actually succeeding.** The
 *      `attested: true` share in the `noteAppCheck` logs is the number; it is
 *      currently unmeasured because A6-lite has not been in the field.
 *   3. **A registered debug token**, or every locally-built debug APK stops
 *      working — see the `AndroidDebugProvider` branch in `main.dart:257-275`.
 *
 * ## The stages
 *
 * `APP_CHECK_ENFORCED_VIDEO` first: `clipUrl` / `clipUrls` are the functions
 * that cost real money per call (IAM signing, then bucket egress), they are
 * already quota-limited per uid by A6-lite, and a refused clip degrades one
 * screen rather than locking anyone out of their account.
 *
 * `APP_CHECK_ENFORCED` second, for everything else. It is deliberately a
 * SEPARATE variable: the day the video flag is on and healthy is not
 * automatically the day it is safe to gate `deleteAccount` behind attestation.
 *
 * Set either to the string `true` in `functions/.env` (or as a Cloud Run env
 * var) and redeploy. Any other value, including unset, is off — a typo fails
 * safe rather than locking the product.
 */
const envFlag = (name: string): boolean => process.env[name] === "true";

/** Stage 2: every callable. */
export const APP_CHECK_ENFORCED = envFlag("APP_CHECK_ENFORCED");

/**
 * Stage 1: the clip-signing pair. Inherits stage 2 when that is already on,
 * so there is no combination of flags where the cheap functions are enforced
 * and the expensive ones are not.
 */
export const APP_CHECK_ENFORCED_VIDEO =
  envFlag("APP_CHECK_ENFORCED_VIDEO") || APP_CHECK_ENFORCED;

/**
 * `clipUrl` — every clip play, on every screen, for every user.
 *
 * `minInstances: 0`, and it should stay there. Do not "restore" it to 1.
 *
 * This carried `minInstances: 1` justified by a cold start being "a black
 * rectangle rather than a slow response". That justification was already
 * false when it was written: `workout_player_page.dart:160` passes
 * `item.posterFor(body)` into the player, and `:413` paints that bundled
 * asset immediately, with the video fading in over it once ready (`:295-297`
 * says so outright). There is no black rectangle — there is a poster, cut
 * from the clip itself, shipped in the APK precisely so the first frame costs
 * no network at all. `_bootstrap()` also checks the offline cache before it
 * reaches for a signed URL, so a planned session frequently never calls this
 * function twice for the same clip.
 *
 * So a warm instance billed around the clock was buying nothing: it paid
 * continuously to hide latency that 3.6 MB of bundled posters already hides,
 * for users who work through a dozen exercises of their own plan rather than
 * browsing hundreds. Firebase's refusal to deploy this without `--force` was
 * the correct instinct about a cost with no matching benefit.
 *
 * If video start ever does feel slow, measure before buying a warm instance:
 * the signature is a couple of kilobytes, while the clip itself is megabytes
 * out of a EU bucket — a CDN in front of the bucket is the lever that
 * actually moves, and `minInstances` is not.
 */
export const VIDEO_HOT: Capped<CallableOptions> = {
  region: REGION,
  maxInstances: 30,
  minInstances: 0,
  enforceAppCheck: APP_CHECK_ENFORCED_VIDEO,
};

/**
 * `clipUrls` — the offline prefetch, up to 60 objects signed per call.
 *
 * A lower ceiling than `VIDEO_HOT` on purpose: each invocation costs up to 60
 * signing operations, so 20 instances is already 1,200 concurrent signatures.
 * This is the function most able to exhaust the IAM signing quota, and it is
 * the one whose users are least sensitive to waiting — a prefetch that queues
 * is a prefetch that still works.
 */
export const VIDEO_BATCH: Capped<CallableOptions> = {
  region: REGION,
  maxInstances: 20,
  enforceAppCheck: APP_CHECK_ENFORCED_VIDEO,
};

/**
 * `stripeWebhook` — Stripe-driven, not user-driven.
 *
 * Has its own ceiling so that no amount of `clipUrl` traffic can crowd it
 * out. Stripe retries on any non-2xx, so starving this function is the one
 * failure here that compounds instead of just degrading.
 */
export const WEBHOOK: Capped<HttpsOptions> = {
  region: REGION,
  maxInstances: 20,
};

/**
 * Deliberate, occasional user actions: subscribing, opening the billing
 * portal, reporting a broken machine, booking a coach.
 *
 * These spike on a promotion rather than on daily use. 10 instances at 80
 * concurrency is 800 simultaneous checkouts, which is more conversion than
 * 1,000 concurrent users can produce.
 */
export const INTERACTIVE: Capped<CallableOptions> = {
  region: REGION,
  maxInstances: 10,
  enforceAppCheck: APP_CHECK_ENFORCED,
};

/**
 * Once-per-account or once-per-year: the free trial, donor wall opt in/out,
 * the annual receipt, coach onboarding.
 *
 * Low ceilings are the point. `generateAnnualReceipt` paginates a customer's
 * whole invoice history and arrives as a January spike; capping it means that
 * spike queues instead of competing with everything else.
 */
export const RARE: Capped<CallableOptions> = {
  region: REGION,
  maxInstances: 5,
  enforceAppCheck: APP_CHECK_ENFORCED,
};
