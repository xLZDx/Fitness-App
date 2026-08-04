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
const REGION = "us-central1";

/**
 * `clipUrl` — every clip play, on every screen, for every user.
 *
 * `minInstances: 1` because a cold start here is not a slow API call, it is a
 * black rectangle: `workout_player_page.dart:333-343` awaits the signature
 * before it constructs the video controller. One warm instance is the
 * cheapest thing in this file and it removes the app's most visible latency.
 */
export const VIDEO_HOT: Capped<CallableOptions> = {
  region: REGION,
  maxInstances: 30,
  minInstances: 1,
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
};
