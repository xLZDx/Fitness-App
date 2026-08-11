/**
 * Cloud Functions backend for the Fitness App.
 *
 * Entry points:
 *   - startFreeTrial         (callable) — writes the user's 14-day trial
 *                                         state into Firestore.
 *   - createCheckoutSession  (callable) — returns a Stripe Checkout URL.
 *   - createPortalSession    (callable) — returns a Stripe Customer Portal URL.
 *   - stripeWebhook          (HTTPS)    — verifies Stripe events and mirrors
 *                                         the subscription state into
 *                                         users/{uid}/subscription/main.
 *   - optInDonorWall         (callable) — adds active donor to public wall.
 *   - optOutDonorWall        (callable) — removes caller from wall.
 *   - generateAnnualReceipt  (callable) — annual summary of subscription
 *                                         payments for the requested year.
 *   - startCoachOnboarding   (callable) — Stripe Connect Express
 *                                         onboarding link for marketplace.
 *   - bookCoachSession       (callable) — PaymentIntent + 15% platform
 *                                         fee + transfer to coach Connect
 *                                         account.
 *   - reportEquipment        (callable) — TX.7. Stores a broken-equipment
 *                                         report and dispatches to the gym's
 *                                         registered webhook.
 *
 * Secrets (set via `firebase functions:secrets:set`):
 *   - STRIPE_SECRET_KEY        sk_test_... (server-only, never in the app)
 *   - STRIPE_WEBHOOK_SECRET    whsec_...   (set after the first deploy)
 *   - STRIPE_PRICE_STANDARD    price_...   (Supporter, $9.99/mo)
 *   - STRIPE_PRICE_CELEBRITY   price_...   (Sustainer, $19.99/mo)
 *   - STRIPE_PRICE_STANDARD_ANNUAL     price_... (Supporter, $59.99/yr)
 *   - STRIPE_PRICE_CELEBRITY_ANNUAL    price_... (Sustainer, $119.99/yr)
 *   - STRIPE_PRICE_STANDARD_FAMILY2    price_... (Supporter 2 seats, $14.99/mo)
 *   - STRIPE_PRICE_STANDARD_FAMILY4    price_... (Supporter 4 seats, $19.99/mo)
 *   - STRIPE_PRICE_CELEBRITY_LIFETIME  price_... (Sustainer, $499 one-time)
 *
 * The five above are created by `scripts/create_prices.mjs`. Their amounts come
 * from what the paywall already displays (mobile subscription_models.dart:16-23)
 * — charging something other than the shown price would be a worse bug than
 * having no price at all. Secret VERSIONS bind at DEPLOY time, so changing a
 * secret requires a redeploy before it takes effect.
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import type Stripe from "stripe";
import { tierForPriceId } from "./tiers";
import { INTERACTIVE, RARE, WEBHOOK } from "./scaling";
import { noteAppCheck } from "./abuse_guard";

admin.initializeApp();
const db = admin.firestore();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_PRICE_STANDARD = defineSecret("STRIPE_PRICE_STANDARD");
const STRIPE_PRICE_CELEBRITY = defineSecret("STRIPE_PRICE_CELEBRITY");
// Phase A6: annual + family + lifetime SKUs. Each is a separate Stripe
// price id; the dashboard owner sets the values via
// `firebase functions:secrets:set STRIPE_PRICE_STANDARD_ANNUAL ...`.
const STRIPE_PRICE_STANDARD_ANNUAL =
  defineSecret("STRIPE_PRICE_STANDARD_ANNUAL");
const STRIPE_PRICE_CELEBRITY_ANNUAL =
  defineSecret("STRIPE_PRICE_CELEBRITY_ANNUAL");
const STRIPE_PRICE_STANDARD_FAMILY2 =
  defineSecret("STRIPE_PRICE_STANDARD_FAMILY2");
const STRIPE_PRICE_STANDARD_FAMILY4 =
  defineSecret("STRIPE_PRICE_STANDARD_FAMILY4");
const STRIPE_PRICE_CELEBRITY_LIFETIME =
  defineSecret("STRIPE_PRICE_CELEBRITY_LIFETIME");

/**
 * The Stripe client, loaded on first use rather than on module load.
 *
 * `clipUrl` and `clipUrls` are re-exported from the bottom of this file, so
 * every cold start of the app's hottest function loads this module. A
 * top-level `import Stripe` meant it also parsed the Stripe SDK it never
 * calls, in front of a video's first frame. The type import above is erased
 * at compile time; this dynamic `import()` compiles to a lazy `require`
 * under `"module": "commonjs"` (tsconfig.json:3), so the SDK now loads only
 * inside the handlers that actually bill someone.
 *
 * One constructor instead of the six identical ones this replaced -- the
 * apiVersion was repeated at each call site and had to be kept in step by
 * hand.
 */
async function stripeClient(): Promise<Stripe> {
  const { default: StripeCtor } = await import("stripe");
  return new StripeCtor(STRIPE_SECRET_KEY.value(), {
    apiVersion: "2025-02-24.acacia",
  });
}

/* ---------------------------------------------------------------------------
 * Reading Stripe objects across the Acacia -> Basil field moves.
 *
 * Two fields this code depends on were relocated in API version 2025-03-31
 * ("Basil"):
 *
 *   subscription.current_period_end -> subscription.items.data[].current_period_end
 *   invoice.subscription            -> invoice.parent.subscription_details.subscription
 *
 * The client above PINS `2025-02-24.acacia`, so direct API calls still return
 * the old shape and are not at risk. **Webhooks are the exposure**: Stripe
 * serialises an event at the ACCOUNT's default version (or the version pinned
 * on the endpoint), not at the SDK's — so a payload can arrive in the new
 * shape regardless of the line above.
 *
 * If that happens, the old code did not throw. `s.current_period_end` would be
 * `undefined`, `periodEnd` would be written as `null`, and a paying
 * subscriber's record would quietly lose its renewal date. Silent, and only
 * visible later as a subscriber who looks lapsed.
 *
 * Rather than migrate to Basil-only — which would break in the opposite
 * direction if the account is still on Acacia, and which cannot be verified
 * from here without the Stripe key — both readers accept EITHER shape. The
 * account's version then stops mattering, which is the point: this code should
 * not depend on a setting it cannot see.
 * ------------------------------------------------------------------------ */

/** Renewal timestamp as ISO-8601, from either field position. */
export function subscriptionPeriodEnd(
  s: Stripe.Subscription,
): string | null {
  // Acacia: on the subscription itself.
  const flat = (s as unknown as { current_period_end?: number })
    .current_period_end;
  if (typeof flat === "number") {
    return new Date(flat * 1000).toISOString();
  }
  // Basil: on each item. A subscription can hold several items with different
  // periods; the LATEST is the date the customer keeps access until, which is
  // what `currentPeriodEndsAt` is read as everywhere downstream.
  const items = (s as unknown as {
    items?: { data?: Array<{ current_period_end?: number }> };
  }).items?.data;
  if (!items?.length) return null;
  const ends = items
    .map((i) => i.current_period_end)
    .filter((v): v is number => typeof v === "number");
  if (!ends.length) return null;
  return new Date(Math.max(...ends) * 1000).toISOString();
}

/** Subscription id carried by an invoice, from either field position. */
export function invoiceSubscriptionId(
  inv: Stripe.Invoice,
): string | null {
  // Acacia: a top-level field, string id or expanded object.
  const flat = (inv as unknown as {
    subscription?: string | { id?: string } | null;
  }).subscription;
  if (typeof flat === "string") return flat;
  if (flat && typeof flat === "object" && typeof flat.id === "string") {
    return flat.id;
  }
  // Basil: moved under `parent`.
  const nested = (inv as unknown as {
    parent?: {
      subscription_details?: { subscription?: string | { id?: string } };
    };
  }).parent?.subscription_details?.subscription;
  if (typeof nested === "string") return nested;
  if (nested && typeof nested === "object" && typeof nested.id === "string") {
    return nested.id;
  }
  return null;
}

type Tier = "standard" | "celebrityTrainer";
type Period =
  | "monthly"
  | "annual"
  | "family2"
  | "family4"
  | "lifetime";

function priceFor(tier: Tier, period: Period = "monthly"): string {
  switch (tier) {
    case "standard":
      switch (period) {
        case "monthly":
          return STRIPE_PRICE_STANDARD.value();
        case "annual":
          return STRIPE_PRICE_STANDARD_ANNUAL.value();
        case "family2":
          return STRIPE_PRICE_STANDARD_FAMILY2.value();
        case "family4":
          return STRIPE_PRICE_STANDARD_FAMILY4.value();
        case "lifetime":
          throw new HttpsError(
            "invalid-argument",
            "Standard does not offer a lifetime plan.",
          );
      }
      break;
    case "celebrityTrainer":
      switch (period) {
        case "monthly":
          return STRIPE_PRICE_CELEBRITY.value();
        case "annual":
          return STRIPE_PRICE_CELEBRITY_ANNUAL.value();
        case "lifetime":
          return STRIPE_PRICE_CELEBRITY_LIFETIME.value();
        case "family2":
        case "family4":
          throw new HttpsError(
            "invalid-argument",
            "Celebrity tier does not offer family seats yet.",
          );
      }
      break;
  }
  throw new HttpsError("invalid-argument", `Unknown period: ${period}`);
}

function isOneTime(period: Period): boolean {
  return period === "lifetime";
}

/**
 * Where Stripe sends the browser after checkout.
 *
 * This project's own Firebase Hosting site. The previous value was
 * `https://fitnessapp.example.com`, which is a placeholder domain and does not
 * resolve — so a successful payment ended on a browser error page. The pages
 * live in `public/` and ship with `firebase deploy --only hosting`.
 *
 * F0·1: derived from the project the function is actually deployed into,
 * rather than hardcoded. `GCLOUD_PROJECT` is set by the Cloud Functions
 * runtime itself, so a deploy into a different Firebase project returns the
 * browser to THAT project's hosting site with no code change. The hardcoded
 * value was `traidingbot-b4061` — the trading bot's project, which this app
 * used to share; that string surviving the split would have sent paying
 * users to the wrong product's domain after checkout.
 *
 * F0·3 moved the fallback to this app's own project. The fallback only
 * applies locally/in the emulator, where the runtime var is unset — but
 * leaving the bot's id there would have meant a local misconfiguration
 * silently pointing at another product.
 */
const RETURN_ORIGIN = `https://${
  process.env.GCLOUD_PROJECT ?? "fitness-app-korostelev"
}.web.app`;

/**
 * The locale Stripe should render checkout in.
 *
 * Stripe defaults to guessing from the browser's Accept-Language, which is how
 * a Russian-speaking user got an English payment sheet from an app that had
 * just walked them through a Russian onboarding.
 *
 * Only the two languages the app itself ships are honoured. Anything else —
 * including nothing at all — becomes "auto", because passing an unsupported
 * value makes Stripe reject the whole session, and failing to sell somebody a
 * subscription is a far worse outcome than showing them English.
 */
function checkoutLocale(raw: unknown): Stripe.Checkout.SessionCreateParams.Locale {
  const code = String(raw ?? "").slice(0, 2).toLowerCase();
  return code === "ru" ? "ru" : code === "en" ? "en" : "auto";
}

/**
 * Looks up the Stripe customer id stored on the user's subscription doc, or
 * creates a fresh customer the first time we see them. The customer's
 * metadata carries the firebase uid so the webhook can route events back to
 * the right user.
 */
async function ensureCustomer(
  stripe: Stripe,
  uid: string,
  email: string | null,
): Promise<string> {
  const ref = db.doc(`users/${uid}/subscription/main`);
  const snap = await ref.get();
  const existing = snap.data()?.stripeCustomerId as string | undefined;
  if (existing) return existing;

  // Idempotency key rather than a bare create. This is a read-modify-write
  // called from both `createCheckoutSession` and `bookCoachSession`, so two
  // concurrent calls for one uid -- an impatient double-tap on Subscribe, or
  // a checkout racing a booking -- both read no customer and both create one.
  // Stripe returns the SAME customer for a repeated key rather than a second
  // one, which is what stops the loser of that race leaving an orphan behind.
  //
  // The orphan mattered more than it looks: `generateAnnualReceipt` lists
  // invoices for the current customer only, so donations billed to the
  // discarded one silently vanish from the user's tax receipt.
  const customer = await stripe.customers.create(
    {
      email: email ?? undefined,
      metadata: { firebaseUid: uid },
    },
    { idempotencyKey: `customer_${uid}` },
  );

  // The write is guarded too: whoever commits first owns the field, and the
  // loser adopts it instead of overwriting. Without this the two racers agree
  // on the customer (the key above) but still race on the document.
  return db.runTransaction(async (tx) => {
    const fresh = await tx.get(ref);
    const raced = fresh.data()?.stripeCustomerId as string | undefined;
    if (raced) return raced;
    tx.set(ref, { stripeCustomerId: customer.id }, { merge: true });
    return customer.id;
  });
}

/* ------------------------------------------------------------------ */
/* startFreeTrial                                                     */
/* ------------------------------------------------------------------ */

const TRIAL_DAYS = 14;

export const startFreeTrial = onCall(
  RARE,
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to start a trial.");
    }
    noteAppCheck(request, "startFreeTrial");
    const tier = request.data?.tier as Tier | undefined;
    if (tier !== "standard" && tier !== "celebrityTrainer") {
      throw new HttpsError(
        "invalid-argument",
        `Unknown tier: ${String(tier)}`,
      );
    }

    const ref = db.doc(`users/${auth.uid}/subscription/main`);
    const snap = await ref.get();
    const data = snap.data();

    // Don't let users farm fresh trials by re-tapping the button after a
    // prior trial / paid subscription has been recorded. Stripe is the
    // source of truth for paid state; the local "trialStartedOnce" flag
    // covers the local-only trial.
    if (data?.trialStartedOnce === true) {
      throw new HttpsError(
        "failed-precondition",
        "Trial already used. Choose a paid plan to continue.",
      );
    }

    const now = new Date();
    const trialEndsAt = new Date(
      now.getTime() + TRIAL_DAYS * 24 * 60 * 60 * 1000,
    );

    await ref.set(
      {
        tier,
        status: "trial",
        trialEndsAt: trialEndsAt.toISOString(),
        trialStartedOnce: true,
        currentPeriodEndsAt: null,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );

    logger.info("started free trial", { uid: auth.uid, tier });
    return { trialEndsAt: trialEndsAt.toISOString() };
  },
);

/* ------------------------------------------------------------------ */
/* createCheckoutSession                                              */
/* ------------------------------------------------------------------ */

export const createCheckoutSession = onCall(
  {
    ...INTERACTIVE,
    secrets: [
      STRIPE_SECRET_KEY,
      STRIPE_PRICE_STANDARD,
      STRIPE_PRICE_CELEBRITY,
      STRIPE_PRICE_STANDARD_ANNUAL,
      STRIPE_PRICE_CELEBRITY_ANNUAL,
      STRIPE_PRICE_STANDARD_FAMILY2,
      STRIPE_PRICE_STANDARD_FAMILY4,
      STRIPE_PRICE_CELEBRITY_LIFETIME,
    ],
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to subscribe.");
    }
    noteAppCheck(request, "createCheckoutSession");

    const tier = request.data?.tier as Tier | undefined;
    if (tier !== "standard" && tier !== "celebrityTrainer") {
      throw new HttpsError(
        "invalid-argument",
        `Unknown tier: ${String(tier)}`,
      );
    }
    const period = (request.data?.period as Period | undefined) ?? "monthly";
    if (
      period !== "monthly" &&
      period !== "annual" &&
      period !== "family2" &&
      period !== "family4" &&
      period !== "lifetime"
    ) {
      throw new HttpsError(
        "invalid-argument",
        `Unknown period: ${String(period)}`,
      );
    }

    const stripe = await stripeClient();
    const customerId = await ensureCustomer(
      stripe,
      auth.uid,
      auth.token?.email ?? null,
    );

    const oneTime = isOneTime(period);

    // A4 — refuse a SECOND recurring subscription for a customer who already
    // has a live one.
    //
    // Asked of Stripe, not of `users/{uid}/subscription/main`: that document
    // holds one `stripeSubscriptionId`, so if two subscriptions already exist
    // it describes only the later one, and a check against it would wave the
    // duplicate through on the strength of a record of the duplicate itself.
    // Stripe is the system of record; the document is a cache.
    //
    // One-time purchases (lifetime, donations) are exempt on purpose: buying
    // one is not mutually exclusive with holding a subscription.
    if (!oneTime) {
      const live = await listAllSubscriptions(stripe, customerId);
      const blocking = live.find((s) =>
        ["active", "trialing", "past_due", "unpaid"].includes(s.status),
      );
      if (blocking) {
        throw new HttpsError(
          "failed-precondition",
          "You already have an active subscription. Manage or cancel it " +
            "from the billing portal before starting a new one.",
        );
      }
    }

    const session = await stripe.checkout.sessions.create({
      mode: oneTime ? "payment" : "subscription",
      customer: customerId,
      line_items: [{ price: priceFor(tier, period), quantity: 1 }],
      // Real pages on this project's own hosting site. They used to point at
      // `fitnessapp.example.com`, a domain that does not exist: the payment
      // went through and the user landed on a browser error, which reads as
      // "it failed" on the one screen where that matters most.
      success_url: `${RETURN_ORIGIN}/checkout-success`,
      cancel_url: `${RETURN_ORIGIN}/checkout-cancel`,
      // Stripe otherwise guesses from the browser, which is why a Russian
      // user saw an English checkout. Passed from the app's current locale;
      // "auto" when it sends nothing, which is still better than a guess made
      // by whichever browser the payment sheet happened to open in.
      locale: checkoutLocale(request.data?.locale),
      client_reference_id: auth.uid,
      ...(oneTime
        ? {
            payment_intent_data: {
              metadata: {
                firebaseUid: auth.uid,
                tier,
                period,
              },
            },
          }
        : {
            subscription_data: {
              metadata: {
                firebaseUid: auth.uid,
                tier,
                period,
              },
            },
          }),
      allow_promotion_codes: true,
    }, {
      // A4 — one Checkout session per (user, tier, period) per 24h, which is
      // how long Stripe remembers a key.
      //
      // The precheck above closes the case where a subscription already
      // exists; this closes the one it cannot see — two sessions opened
      // seconds apart, both before either has completed, from a double-tap or
      // a retried request. Without the key each creates its own session and
      // each session can be paid.
      //
      // A repeat within the window returns the SAME session rather than an
      // error, so a user who backed out of Checkout and tapped Subscribe
      // again lands on the same page instead of being blocked.
      //
      // The locale is part of the key because it is part of the REQUEST BODY
      // (`locale:` above, from the client's current language). Stripe returns
      // an error, not the cached response, when one key is replayed with a
      // different body -- so a user who backs out of Checkout, switches the
      // app to Russian and taps Subscribe again would otherwise hit an opaque
      // internal error instead of a Russian checkout page.
      idempotencyKey:
        `checkout_${auth.uid}_${tier}_${period}_` +
        `${checkoutLocale(request.data?.locale)}`,
    });

    if (!session.url) {
      throw new HttpsError("internal", "Stripe returned no checkout URL.");
    }
    logger.info("created checkout session", {
      uid: auth.uid,
      tier,
      period,
      sessionId: session.id,
    });
    return { url: session.url };
  },
);

/* ------------------------------------------------------------------ */
/* createPortalSession                                                */
/* ------------------------------------------------------------------ */

export const createPortalSession = onCall(
  { ...INTERACTIVE, secrets: [STRIPE_SECRET_KEY] },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to manage billing.");
    }

    const ref = db.doc(`users/${auth.uid}/subscription/main`);
    const snap = await ref.get();
    const customerId = snap.data()?.stripeCustomerId as string | undefined;
    if (!customerId) {
      throw new HttpsError(
        "failed-precondition",
        "No Stripe customer on file. Subscribe first.",
      );
    }

    const stripe = await stripeClient();
    const portal = await stripe.billingPortal.sessions.create({
      customer: customerId,
      return_url: "https://fitnessapp.example.com/portal-return",
    });
    return { url: portal.url };
  },
);

/* ------------------------------------------------------------------ */
/* stripeWebhook                                                      */
/* ------------------------------------------------------------------ */

/**
 * Maps a Stripe subscription's `status` to the app's
 * SubscriptionStatus enum. Stripe has more states than the app cares
 * about — anything we don't recognise lands on `expired` so the user
 * loses premium access by default rather than silently keeping it.
 */
function mapStatus(s: Stripe.Subscription.Status): string {
  switch (s) {
    case "trialing":
      return "trial";
    case "active":
      return "active";
    case "canceled":
      return "cancelled";
    case "past_due":
    case "unpaid":
    case "incomplete":
    case "incomplete_expired":
      return "expired";
    default:
      return "expired";
  }
}

/**
 * Determines which app tier this Stripe subscription bills.
 *
 * Must cover EVERY recurring price `priceFor()` can hand to Checkout, not just
 * the two monthly ones: it used to match only STANDARD and CELEBRITY, so an
 * annual or family subscriber paid and was then written back as tier `free`.
 * Lifetime is deliberately absent — it is a one-time payment and arrives on
 * `payment_intent.succeeded`, never as a Subscription.
 *
 * Defaulting to `free` for an unknown price stays: a price we do not recognise
 * must never silently grant a paid tier.
 */
function tierFromSubscription(s: Stripe.Subscription): string {
  return tierForPriceId(s.items.data[0]?.price.id, {
    standard: [
      STRIPE_PRICE_STANDARD.value(),
      STRIPE_PRICE_STANDARD_ANNUAL.value(),
      STRIPE_PRICE_STANDARD_FAMILY2.value(),
      STRIPE_PRICE_STANDARD_FAMILY4.value(),
    ],
    celebrity: [
      STRIPE_PRICE_CELEBRITY.value(),
      STRIPE_PRICE_CELEBRITY_ANNUAL.value(),
    ],
  });
}

/**
 * Writes subscription state, refusing to apply an event older than the one
 * already written.
 *
 * Stripe does not guarantee delivery order, and its retry backoff widens the
 * window in which two events for one subscription are in flight at once. The
 * write here is a `set(..., {merge: true})` that overwrites `status`
 * unconditionally, so out-of-order delivery is not a transient glitch: a
 * delayed `customer.subscription.updated`(active) landing after
 * `customer.subscription.deleted`(cancelled) restores premium to a cancelled
 * account permanently, because nothing ever re-reconciles it.
 *
 * `event.created` is Stripe's own ordering clock and is stamped when the
 * event happened rather than when it was delivered, which is exactly the
 * distinction that matters. Kept on the document so the comparison survives a
 * cold start.
 *
 * Retries were already safe by accident -- every write is deterministic from
 * the event body, so a replay rewrites the same fields and there is no
 * double-grant -- and this makes that property deliberate rather than lucky.
 */
async function applySubscription(
  s: Stripe.Subscription,
  eventCreated?: number,
) {
  const uid = s.metadata?.firebaseUid as string | undefined;
  if (!uid) {
    // Every checkout flow stamps `subscription_data.metadata.firebaseUid`,
    // so a missing uid is a bug we want to fix at the source rather than
    // silently bridge with a customer-id lookup.
    logger.error("subscription event without firebaseUid", {
      subscriptionId: s.id,
      customer: s.customer,
    });
    return;
  }

  const status = mapStatus(s.status);
  const tier = tierFromSubscription(s);
  const period = (s.metadata?.period as string | undefined) ?? "monthly";
  const seatCount =
    period === "family2" ? 2 : period === "family4" ? 4 : 1;

  // Stripe surfaces these timestamps as Unix seconds.
  const periodEnd = subscriptionPeriodEnd(s);
  const trialEnd = s.trial_end
    ? new Date(s.trial_end * 1000).toISOString()
    : null;

  const ref = db.doc(`users/${uid}/subscription/main`);
  const payload = {
    tier,
    status,
    period,
    seatCount,
    currentPeriodEndsAt: periodEnd,
    trialEndsAt: trialEnd,
    stripeCustomerId: s.customer,
    stripeSubscriptionId: s.id,
    updatedAt: admin.firestore.FieldValue.serverTimestamp(),
  };

  if (eventCreated === undefined) {
    // No clock to compare against -- an internal caller rather than the
    // webhook. Write as before rather than invent an ordering.
    await ref.set(payload, { merge: true });
    return;
  }

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const seen = snap.data()?.lastStripeEventCreated as number | undefined;
    if (seen !== undefined && eventCreated < seen) {
      logger.info("ignoring out-of-order stripe event", {
        uid,
        subscriptionId: s.id,
        eventCreated,
        alreadyApplied: seen,
      });
      return;
    }
    tx.set(
      ref,
      { ...payload, lastStripeEventCreated: eventCreated },
      { merge: true },
    );
  });
}

/**
 * Handles the one-time `lifetime` purchase that arrives as a Stripe
 * PaymentIntent (mode: "payment") rather than a Subscription. Writes
 * the same shape as the recurring path, with `currentPeriodEndsAt` set
 * to the year 9999 sentinel and `isLifetime: true`.
 */
async function applyLifetimePayment(pi: Stripe.PaymentIntent) {
  const uid = pi.metadata?.firebaseUid as string | undefined;
  const tier = pi.metadata?.tier as string | undefined;
  if (!uid || !tier) {
    logger.error("lifetime payment without uid/tier", {
      paymentIntentId: pi.id,
    });
    return;
  }
  await db.doc(`users/${uid}/subscription/main`).set(
    {
      tier,
      status: "active",
      period: "lifetime",
      seatCount: 1,
      currentPeriodEndsAt: "9999-12-31T23:59:59.000Z",
      trialEndsAt: null,
      isLifetime: true,
      stripeCustomerId: pi.customer,
      stripePaymentIntentId: pi.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
  logger.info("lifetime payment applied", { uid, tier });
}

export const stripeWebhook = onRequest(
  {
    ...WEBHOOK,
    // Every secret `tierFromSubscription` reads must be here. An unbound
    // secret does not throw -- firebase-functions logs a warning and hands
    // back "" (params/types.js, runtimeValue) -- and `known()` in tiers.ts
    // discards falsy ids, so the four that were missing made every annual and
    // family price match nothing and fall through to "free". The subscriber
    // paid and was written back as a free user, on purchase and again on
    // every renewal, with nothing failing anywhere. A test now asserts this
    // array against what the mapping reads, because the two drifting apart is
    // the entire bug and no amount of care keeps two lists in step by hand.
    secrets: [
      STRIPE_SECRET_KEY,
      STRIPE_WEBHOOK_SECRET,
      STRIPE_PRICE_STANDARD,
      STRIPE_PRICE_CELEBRITY,
      STRIPE_PRICE_STANDARD_ANNUAL,
      STRIPE_PRICE_CELEBRITY_ANNUAL,
      STRIPE_PRICE_STANDARD_FAMILY2,
      STRIPE_PRICE_STANDARD_FAMILY4,
    ],
  },
  async (req, res) => {
    const sig = req.headers["stripe-signature"];
    if (typeof sig !== "string") {
      res.status(400).send("Missing stripe-signature header");
      return;
    }

    const stripe = await stripeClient();

    let event: Stripe.Event;
    try {
      event = stripe.webhooks.constructEvent(
        // onRequest preserves the raw body on `rawBody`; that's what
        // Stripe's signature is computed over.
        (req as unknown as { rawBody: Buffer }).rawBody,
        sig,
        STRIPE_WEBHOOK_SECRET.value(),
      );
    } catch (err) {
      logger.error("webhook signature verification failed", { err });
      res.status(400).send(`Bad signature: ${(err as Error).message}`);
      return;
    }

    try {
      switch (event.type) {
        case "customer.subscription.created":
        case "customer.subscription.updated":
        case "customer.subscription.deleted":
          await applySubscription(
            event.data.object as Stripe.Subscription,
            event.created,
          );
          break;
        case "invoice.paid":
        case "invoice.payment_failed": {
          // Refresh the subscription state so periodEnd advances.
          const inv = event.data.object as Stripe.Invoice;
          const subId = invoiceSubscriptionId(inv);
          if (typeof subId === "string") {
            const sub = await stripe.subscriptions.retrieve(subId);
            await applySubscription(sub, event.created);
          }
          break;
        }
        case "payment_intent.succeeded": {
          const pi = event.data.object as Stripe.PaymentIntent;
          if (pi.metadata?.period === "lifetime") {
            await applyLifetimePayment(pi);
          } else if (pi.metadata?.kind === "coach_booking") {
            const bookingId = pi.metadata.bookingId;
            if (bookingId) {
              await db.doc(`coach_bookings/${bookingId}`).set(
                {
                  status: "confirmed",
                  confirmedAt:
                    admin.firestore.FieldValue.serverTimestamp(),
                },
                { merge: true },
              );
            }
          }
          break;
        }
        default:
          logger.debug("ignoring stripe event", { type: event.type });
      }
      res.status(200).send("ok");
    } catch (err) {
      logger.error("webhook handler crashed", { err });
      res.status(500).send("handler error");
    }
  },
);

/* ------------------------------------------------------------------ */
/* Donor wall (opt-in)                                                */
/* ------------------------------------------------------------------ */

/**
 * Adds (or updates) the calling user on the public donor wall. Requires
 * an active Stripe-backed donation — trial-only users can't opt in.
 *
 * Server-side write is the only way into `donor_wall/{uid}`; the
 * security rules deny client writes so a malicious client can't spoof
 * a donation badge.
 */
export const optInDonorWall = onCall(
  RARE,
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to opt in.");
    }
    const subSnap = await db.doc(`users/${auth.uid}/subscription/main`).get();
    const sub = subSnap.data();
    const hasActive =
      sub?.status === "active" || sub?.status === "cancelled";
    if (!hasActive) {
      throw new HttpsError(
        "failed-precondition",
        "Donor-wall opt-in requires an active recurring donation.",
      );
    }

    const data = request.data ?? {};
    const rawName = (data.displayName as string | undefined)?.trim() ?? "";
    const message = (data.message as string | undefined)?.trim() ?? "";
    const tierFromSub =
      sub?.tier === "celebrityTrainer" ? "sustainer" : "supporter";
    const isLifetime = sub?.isLifetime === true;

    if (rawName.length > 60) {
      throw new HttpsError(
        "invalid-argument",
        "Display name must be 60 characters or fewer.",
      );
    }
    if (message.length > 200) {
      throw new HttpsError(
        "invalid-argument",
        "Message must be 200 characters or fewer.",
      );
    }

    await db.doc(`donor_wall/${auth.uid}`).set(
      {
        displayName: rawName.length === 0 ? "Anonymous donor" : rawName,
        tier: tierFromSub,
        since:
          (await db.doc(`donor_wall/${auth.uid}`).get()).data()?.since ??
          new Date().toISOString(),
        ...(message.length > 0 ? { message } : {}),
        ...(isLifetime ? { isLifetime: true } : {}),
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      },
      { merge: true },
    );
    return { ok: true };
  },
);

/** Removes the caller from the donor wall. */
export const optOutDonorWall = onCall(
  RARE,
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    await db.doc(`donor_wall/${auth.uid}`).delete();
    return { ok: true };
  },
);

/* ------------------------------------------------------------------ */
/* generateAnnualReceipt (callable, on demand)                        */
/* ------------------------------------------------------------------ */

/**
 * Returns an annual summary of the caller's subscription payments. A JSON
 * document the app can render or email; deliberately not a PDF (lower attack
 * surface, easier to localise client-side).
 *
 * The amount is derived from Stripe invoices marked `paid` between
 * Jan 1 and Dec 31 of the requested year. No client field accepted.
 *
 * ## Why this stopped calling itself a donation receipt (P0, 2026-08-05)
 *
 * It used to return `orgName: "Fitness App (501(c)(3) pending)"` and a notice
 * promising that "prior-year donations made under our fiscal sponsor are
 * retroactively deductible", and it persisted both to
 * `users/{uid}/receipts/{year}`.
 *
 * None of it was true: there is no 501(c)(3), no application pending, and no
 * fiscal sponsor. S0b removed that framing from every Flutter surface but
 * never grepped this file, so the backend kept asserting it — on a *receipt*,
 * the one document a user might hand to a tax authority, and in a shape that
 * outlived the response by being written to Firestore.
 *
 * The published Terms now say the opposite in as many words ("These payments
 * are not tax-deductible donations"), which is what made the contradiction
 * load-bearing rather than merely embarrassing. `donorName`/`donorUid` went
 * with it: this endpoint has no client callers, so nothing depended on the old
 * field names, and leaving "donor" in a payload the Terms call a subscription
 * would have re-created the same drift one level down.
 */
export const generateAnnualReceipt = onCall(
  {
    ...RARE,
    secrets: [STRIPE_SECRET_KEY],
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const year = Number(request.data?.year ?? new Date().getUTCFullYear());
    if (!Number.isInteger(year) || year < 2024 || year > 2100) {
      throw new HttpsError("invalid-argument", `Invalid year: ${year}`);
    }

    const subSnap = await db.doc(`users/${auth.uid}/subscription/main`).get();
    const customerId = subSnap.data()?.stripeCustomerId as string | undefined;
    if (!customerId) {
      // Trial-only / never-paid user — return a zero summary rather than
      // 4xx so the client can show "no payments recorded" instead of an
      // error.
      return {
        year,
        currency: "USD",
        totalCents: 0,
        invoiceCount: 0,
        items: [],
        payerName: auth.token?.name ?? auth.token?.email ?? "Anonymous",
        payerUid: auth.uid,
        issuedBy: "Fitness App",
        notice:
          "No payments were recorded under your account in this year.",
      };
    }

    const stripe = await stripeClient();

    const start = Math.floor(Date.UTC(year, 0, 1) / 1000);
    const end = Math.floor(Date.UTC(year + 1, 0, 1) / 1000);

    let totalCents = 0;
    const items: Array<{
      created: string;
      amountCents: number;
      currency: string;
      number: string | null;
      description: string;
    }> = [];

    let starting_after: string | undefined;
    while (true) {
      const page = await stripe.invoices.list({
        customer: customerId,
        status: "paid",
        created: { gte: start, lt: end },
        limit: 100,
        starting_after,
      });
      for (const inv of page.data) {
        const amt = inv.amount_paid ?? 0;
        totalCents += amt;
        items.push({
          created: new Date((inv.created ?? 0) * 1000).toISOString(),
          amountCents: amt,
          currency: inv.currency ?? "usd",
          number: inv.number ?? null,
          description: inv.lines?.data?.[0]?.description ?? "Subscription",
        });
      }
      if (!page.has_more || page.data.length === 0) break;
      starting_after = page.data[page.data.length - 1]?.id;
    }

    const receipt = {
      year,
      currency: "USD",
      totalCents,
      invoiceCount: items.length,
      items,
      payerName: auth.token?.name ?? auth.token?.email ?? "Anonymous",
      payerUid: auth.uid,
      issuedBy: "Fitness App",
      generatedAt: new Date().toISOString(),
      notice: totalCents > 0
        ? "Keep this summary for your records. These are subscription " +
          "payments, not charitable donations, and they are not " +
          "tax-deductible."
        : "No payments were recorded under your account in this year.",
    };

    // Persist a copy so the year-end batch job has a known address.
    await db
      .doc(`users/${auth.uid}/receipts/${year}`)
      .set(receipt, { merge: true });

    return receipt;
  },
);

/* ------------------------------------------------------------------ */
/* Stripe Connect for Coach Marketplace (TX.5)                        */
/* ------------------------------------------------------------------ */

/**
 * Creates (or returns) a Stripe Connect Express account for the
 * calling user, then mints an account-onboarding link the client
 * redirects to. This is how coaches set up their payout details.
 *
 * The 15% platform fee is applied at booking time (see
 * `bookCoachSession`); the Connect account is just the payout target.
 */
export const startCoachOnboarding = onCall(
  { ...RARE, secrets: [STRIPE_SECRET_KEY] },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const stripe = await stripeClient();
    const ref = db.doc(`coach_listings/${auth.uid}`);
    const snap = await ref.get();
    let accountId =
      snap.data()?.stripeConnectAccountId as string | undefined;
    if (!accountId) {
      const account = await stripe.accounts.create({
        type: "express",
        capabilities: {
          card_payments: { requested: true },
          transfers: { requested: true },
        },
        metadata: { firebaseUid: auth.uid },
      });
      accountId = account.id;
      await ref.set(
        {
          stripeConnectAccountId: accountId,
          createdAt: admin.firestore.FieldValue.serverTimestamp(),
        },
        { merge: true },
      );
    }
    const link = await stripe.accountLinks.create({
      account: accountId,
      refresh_url: "https://fitnessapp.example.com/coach/onboarding-refresh",
      return_url: "https://fitnessapp.example.com/coach/onboarding-done",
      type: "account_onboarding",
    });
    return { url: link.url, accountId };
  },
);

/**
 * Books a coaching session: creates a PaymentIntent on the platform
 * account that transfers (price - platformFee) to the coach's Connect
 * account. PaymentIntent metadata carries the booking id so the
 * webhook can mark the booking confirmed once the charge succeeds.
 */
export const bookCoachSession = onCall(
  { ...INTERACTIVE, secrets: [STRIPE_SECRET_KEY] },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const data = request.data ?? {};
    const coachUid = data.coachUid as string | undefined;
    const startsAt = data.startsAt as string | undefined;
    const durationMinutes =
      (data.durationMinutes as number | undefined) ?? 60;
    if (!coachUid || !startsAt) {
      throw new HttpsError(
        "invalid-argument",
        "coachUid and startsAt are required.",
      );
    }
    const coachSnap = await db.doc(`coach_listings/${coachUid}`).get();
    const coach = coachSnap.data();
    if (!coach) {
      throw new HttpsError("not-found", "Coach listing not found.");
    }
    const priceCents = (coach.priceCentsPerSession as number | undefined) ?? 0;
    const accountId = coach.stripeConnectAccountId as string | undefined;
    if (!accountId || priceCents <= 0) {
      throw new HttpsError(
        "failed-precondition",
        "Coach has not finished onboarding.",
      );
    }
    const platformFeeCents = Math.round(priceCents * 0.15);

    const stripe = await stripeClient();
    const customerId = await ensureCustomer(
      stripe,
      auth.uid,
      auth.token?.email ?? null,
    );

    const bookingId = `bk_${Date.now()}_${auth.uid}`;
    const intent = await stripe.paymentIntents.create({
      amount: priceCents,
      currency: (coach.currency as string | undefined) ?? "usd",
      customer: customerId,
      application_fee_amount: platformFeeCents,
      transfer_data: { destination: accountId },
      metadata: {
        firebaseUid: auth.uid,
        coachUid,
        bookingId,
        kind: "coach_booking",
      },
    });

    await db.doc(`coach_bookings/${bookingId}`).set({
      coachUid,
      clientUid: auth.uid,
      startsAt,
      durationMinutes,
      priceCents,
      platformFeeCents,
      status: "pending",
      stripePaymentIntentId: intent.id,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });

    return {
      bookingId,
      clientSecret: intent.client_secret,
      amountCents: priceCents,
    };
  },
);

/* ------------------------------------------------------------------ */
/* reportEquipment (TX.7)                                             */
/* ------------------------------------------------------------------ */

/**
 * Persists a broken-equipment report at `equipment_reports/{id}` and
 * dispatches a Slack-compatible webhook for the gym (if registered at
 * `gyms/{gymId}.maintenanceWebhookUrl`). The dispatch is best-effort —
 * if the webhook fails, the Firestore write still succeeds so the gym's
 * admin console can pick the report up later.
 */
export const reportEquipment = onCall(
  INTERACTIVE,
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to file a report.");
    }
    noteAppCheck(request, "reportEquipment");
    const data = request.data ?? {};
    const equipmentId = data.equipmentId as string | undefined;
    const gymId = (data.gymId as string | undefined) ?? "unknown";
    const fault = (data.fault as string | undefined) ?? "other";
    const note = (data.note as string | undefined) ?? "";
    if (!equipmentId) {
      throw new HttpsError("invalid-argument", "equipmentId is required.");
    }

    const reportId =
      (data.id as string | undefined) ??
      `${Date.now()}_${equipmentId}`;
    const reportedAt = (data.reportedAt as string | undefined) ??
      new Date().toISOString();

    await db.doc(`equipment_reports/${reportId}`).set({
      equipmentId,
      gymId,
      fault,
      note,
      reportedAt,
      reporterUid: auth.uid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: "open",
    });

    // Best-effort webhook dispatch. We look up gyms/{gymId} to see
    // whether the chain registered a maintenance endpoint.
    try {
      const gymSnap = await db.doc(`gyms/${gymId}`).get();
      const webhookUrl =
        gymSnap.data()?.maintenanceWebhookUrl as string | undefined;
      if (webhookUrl) {
        const payload = {
          text:
            `Equipment report — ${fault.toUpperCase()}\n` +
            `Gym: ${gymId}  ·  Equipment: ${equipmentId}\n` +
            (note ? `Note: ${note}\n` : "") +
            `Reporter: ${auth.uid}`,
          equipmentId,
          gymId,
          fault,
          note,
          reportedAt,
          reportId,
        };
        // Bounded, because the endpoint belongs to a gym and not to us. A
        // chain whose Slack or custom receiver accepts the connection and
        // never answers would otherwise hold this instance until the
        // platform's 60-second default kills it -- with the user watching a
        // spinner the whole time, since this is a callable they are waiting
        // on, and with the instance unavailable to anyone else reporting a
        // fault. One dark endpoint at a busy chain is enough to make
        // reporting fail for every other gym.
        await fetch(webhookUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
          signal: AbortSignal.timeout(3000),
        });
      }
    } catch (err) {
      // Still swallowed, and the ordering is what makes that right: the
      // report is already durably written, so the gym's admin console has it
      // whether or not the webhook landed.
      //
      // Now identifiable, though. The warning named only the gym, so a
      // recurring failure could not be tied back to the report it belonged to.
      logger.warn("equipment report webhook failed", {
        err,
        gymId,
        equipmentId,
        reportId,
      });
    }

    return { reportId };
  },
);

/* ------------------------------------------------------------------ */
/* deleteAccount                                                      */
/* ------------------------------------------------------------------ */

/**
 * L0b — irreversible by design, and ordered so that a failure partway
 * through never leaves the account both billed AND unreachable.
 *
 * A client-only version of this was rejected. Two things it structurally
 * cannot do: cancel the Stripe subscription (no secret key on the client,
 * ever), and delete `users/{uid}/subscription/main` (`firestore.rules`'s
 * `coll != 'subscription'` carve-out denies client writes to it by design --
 * the exact thing that would leave a stale subscription record billing
 * someone with no in-app way left to manage it). Both require the Admin SDK,
 * so the whole flow is one server call rather than a client-driven sequence
 * racing a server-driven Stripe step.
 *
 * ORDER, and why it is this order:
 *   1. Cancel Stripe first. Reversible in principle (the operator can
 *      resurrect a cancelled subscription from the Stripe dashboard if this
 *      call is ever made in error); nothing else here is.
 *   2. Delete Firestore data. `recursiveDelete` is safe to re-run --
 *      "the provided reference is deleted regardless of whether all deletes
 *      succeeded" (`@google-cloud/firestore` `recursiveDelete` doc) -- so a
 *      partial failure here can be retried without re-running step 1.
 *   3. Delete the Auth user LAST. This is the one truly irreversible step:
 *      once gone, the uid can never sign back in, by anyone, including this
 *      function on a retry. Doing it last means every earlier failure mode
 *      still leaves an account someone could get back into and try again.
 *
 * `firestore.rules` needs no change for this. The plan flagged one, written
 * against a client-driven deletion flow; the Admin SDK this function runs
 * under bypasses Firestore rules entirely, so there is nothing for a rule to
 * grant or deny here. Recorded rather than silently dropped, because the
 * plan named it explicitly.
 *
 * NOT covered: progress-photo storage. `ProgressPhotosRepository` has no
 * real backend yet (M0) -- there is nothing in Cloud Storage to delete until
 * one exists, and this function has nothing to call. Whoever builds that
 * backend has to add its cleanup here in the same change, not as a follow-up
 * that is easy to forget once this function already looks complete.
 */
/**
 * What replaces a departing user's id in a record that is not theirs alone.
 *
 * Not a real uid, and deliberately not an empty string: an empty `clientUid`
 * reads as "field never set" to every query in this file, while this value
 * reads as "there was someone here and they are gone", which is what actually
 * happened.
 */
const DELETED_UID = "deleted_user";

/**
 * Every subscription on a customer, following Stripe's pagination.
 *
 * A single `list({limit: 100})` silently truncates at 100, which turns both
 * callers into quiet lies: the deletion path would claim to cancel "every"
 * subscription while leaving the 101st billing, and the duplicate guard would
 * wave a new purchase through because it could not see the existing one.
 * 100 sounds like plenty until a webhook retry storm has created the objects
 * itself -- which is the exact class of bug this file is closing.
 */
async function listAllSubscriptions(
  stripe: Stripe,
  customerId: string,
): Promise<Stripe.Subscription[]> {
  const out: Stripe.Subscription[] = [];
  let startingAfter: string | undefined;
  // Bounded: 20 pages x 100 is 2000 subscriptions for one customer. Past that
  // the data is pathological and a loop that never ends is worse than a
  // truncated answer, so the bound is explicit rather than accidental.
  for (let page = 0; page < 20; page++) {
    const res = await stripe.subscriptions.list({
      customer: customerId,
      status: "all",
      limit: 100,
      ...(startingAfter ? { starting_after: startingAfter } : {}),
    });
    out.push(...res.data);
    if (!res.has_more || res.data.length === 0) break;
    startingAfter = res.data[res.data.length - 1].id;
  }
  return out;
}

/**
 * Firestore commits at most 500 writes per batch, and the sweep below has no
 * upper bound on how many documents it matches: a coach with a long booking
 * history blows the cap, `commit()` throws, and the caller's own message tells
 * the user the step "is safe to repeat" -- which it is, and it fails again
 * identically every time, leaving the account permanently half-deleted.
 *
 * 450 rather than 500: the margin costs one extra round trip in the rare case
 * and removes any dependence on the cap being exactly 500 forever.
 */
async function commitInChunks(
  ops: Array<(batch: FirebaseFirestore.WriteBatch) => void>,
): Promise<void> {
  const chunkSize = 450;
  for (let i = 0; i < ops.length; i += chunkSize) {
    const batch = db.batch();
    for (const apply of ops.slice(i, i + chunkSize)) apply(batch);
    await batch.commit();
  }
}

/**
 * The three collections A0's inventory found outside `users/{uid}` that name a
 * user and survived `deleteAccount`.
 *
 * Two different treatments, because they are two different kinds of record:
 *
 *   - `coach_bookings` and `equipment_reports` are SHARED. A booking is a
 *     transaction between two people and a report is a fault the gym still has
 *     to fix; deleting either would erase a counterparty's own record of
 *     something that really happened. The departing user's id is replaced, so
 *     nothing remaining identifies them, and a booking whose BOTH sides are
 *     gone is then deleted outright -- otherwise the collection accumulates
 *     rows nobody can ever read again.
 *   - `debug_sessions` is SOLE. It is device telemetry about one person with
 *     no counterparty, so it is deleted. It also cannot be cleaned up any
 *     other way: `firestore.rules:82-87` sets `allow update, delete: if false`,
 *     so even the owner's own client cannot remove it -- only the Admin SDK,
 *     which bypasses rules, can.
 *
 * Each query is a single-field equality, so none of them needs a composite
 * index that a fresh project would not already have.
 */
async function sweepSharedRecords(uid: string): Promise<void> {
  const ops: Array<(batch: FirebaseFirestore.WriteBatch) => void> = [];

  const [asClient, asCoach, reports, debugSessions] = await Promise.all([
    db.collection("coach_bookings").where("clientUid", "==", uid).get(),
    db.collection("coach_bookings").where("coachUid", "==", uid).get(),
    db.collection("equipment_reports").where("reporterUid", "==", uid).get(),
    db.collection("debug_sessions").where("uid", "==", uid).get(),
  ]);

  // Both sides queried separately rather than with an `or`: a user can be the
  // client on one booking and the coach on another, and one query per field
  // is what keeps "which field do I anonymise" decidable per document.
  for (const doc of asClient.docs) {
    const other = doc.data()?.coachUid;
    if (other === DELETED_UID || other === undefined) {
      ops.push((b) => b.delete(doc.ref));
    } else {
      ops.push((b) => b.update(doc.ref, { clientUid: DELETED_UID }));
    }
  }
  for (const doc of asCoach.docs) {
    const other = doc.data()?.clientUid;
    if (other === DELETED_UID || other === undefined) {
      ops.push((b) => b.delete(doc.ref));
    } else {
      ops.push((b) => b.update(doc.ref, { coachUid: DELETED_UID }));
    }
  }
  for (const doc of reports.docs) {
    ops.push((b) => b.update(doc.ref, { reporterUid: DELETED_UID }));
  }
  for (const doc of debugSessions.docs) {
    ops.push((b) => b.delete(doc.ref));
  }

  await commitInChunks(ops);
}

export const deleteAccount = onCall(
  { ...RARE, secrets: [STRIPE_SECRET_KEY] },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in first.");
    }
    const uid = auth.uid;

    // Step 1 — cancel Stripe, if there is anything left to cancel.
    //
    // Idempotent by construction: retrieve the subscription's OWN status
    // first and only call `cancel()` if it is not already in a terminal
    // state. Three independent reviewers converged on the same failure this
    // avoids -- a client retry (a dropped response after the server already
    // finished, or the client's own token-refresh-and-retry on
    // 'unauthenticated') would otherwise hit an "already canceled" error
    // from Stripe and report "your account has not been deleted" for an
    // account that, in fact, already was. Checking status first sidesteps
    // matching a specific Stripe error code, which is not something to
    // guess without a live fixture to verify it against.
    //
    // A failure that DOES throw here still aborts the whole call: proceeding
    // to delete data or the account while Stripe keeps billing is the exact
    // harm this function exists to prevent.
    const subSnap = await db.doc(`users/${uid}/subscription/main`).get();
    const subData = subSnap.data();
    const subscriptionId = subData?.stripeSubscriptionId as string | undefined;
    const customerId = subData?.stripeCustomerId as string | undefined;
    if (subscriptionId || customerId) {
      try {
        const stripe = await stripeClient();

        // EVERY subscription on the customer, not the one id this document
        // happens to remember. `users/{uid}/subscription/main` stores a
        // single `stripeSubscriptionId`, so a second concurrently-created
        // subscription overwrites the first here while BOTH keep billing in
        // Stripe. Cancelling only the remembered one leaves the other
        // charging a card whose owner no longer has an account to cancel it
        // from -- the exact harm the audit named. Stripe is the system of
        // record for subscriptions; this document is a cache of it, so the
        // deletion path asks Stripe rather than trusting the cache.
        //
        // `status: "all"` deliberately: `past_due` and `unpaid` still bill,
        // and `trialing` still converts. Only `canceled` is genuinely inert,
        // and that is filtered per-id below.
        const ids = new Set<string>();
        if (subscriptionId) ids.add(subscriptionId);
        if (customerId) {
          for (const s of await listAllSubscriptions(stripe, customerId)) {
            ids.add(s.id);
          }
        }

        for (const id of ids) {
          const current = await stripe.subscriptions.retrieve(id);
          if (current.status !== "canceled") {
            // Immediate cancellation, not `cancel_at_period_end` — the
            // account is being deleted now, not at the end of a billing
            // period nobody will be signed in to see.
            await stripe.subscriptions.cancel(id);
          }
        }
      } catch (err) {
        logger.error("account deletion: failed to cancel subscription", {
          uid,
          subscriptionId,
          customerId,
          err,
        });
        throw new HttpsError(
          "internal",
          "Could not cancel your subscription. Your account has not been " +
            "deleted. Please try again or contact support.",
        );
      }
    }

    // Step 2 — delete every document under this uid, plus the two other
    // top-level collections a user can be written into elsewhere in this
    // file: `donor_wall/{uid}` (optInDonorWall) and `coach_listings/{uid}`
    // (startCoachOnboarding). Both are keyed by uid but live outside
    // `users/{uid}`, so the original single recursiveDelete silently missed
    // both -- a deleted donor's name stayed permanently public
    // (`donor_wall` is publicly readable), and a deleted coach stayed
    // bookable against a uid that could never fulfil the session.
    //
    // `recursiveDelete` is already idempotent: deleting a reference with
    // nothing under it (the common case for the two extra collections, and
    // for a retried call against `users/{uid}`) just completes.
    try {
      await Promise.all([
        db.recursiveDelete(db.collection("users").doc(uid)),
        db.recursiveDelete(db.collection("donor_wall").doc(uid)),
        db.recursiveDelete(db.collection("coach_listings").doc(uid)),
      ]);

      // The three collections `recursiveDelete` cannot reach, because they
      // are not keyed by uid -- they only MENTION it. See sweepSharedRecords.
      await sweepSharedRecords(uid);
    } catch (err) {
      logger.error("account deletion: failed to delete Firestore data", {
        uid,
        err,
      });
      throw new HttpsError(
        "internal",
        "Your subscription was cancelled, but some of your data could not " +
          "be deleted. Please try again — this step is safe to repeat.",
      );
    }

    // Step 3 — delete the Auth user. Last, and irreversible: once this
    // succeeds there is no retry path left, by design.
    //
    // `auth/user-not-found` is treated as success, not failure -- the same
    // idempotency reasoning as step 1. It is exactly what a retry against an
    // already-completed deletion looks like: the uid genuinely no longer
    // exists, which is this step's own goal already met.
    try {
      await admin.auth().deleteUser(uid);
    } catch (err) {
      if ((err as { code?: string }).code !== "auth/user-not-found") {
        logger.error("account deletion: failed to delete the Auth user", {
          uid,
          err,
        });
        throw new HttpsError(
          "internal",
          "Your data was deleted, but signing out could not be completed. " +
            "Please contact support to finish closing your account.",
        );
      }
    }

    // KNOWN, UNCLOSED GAP: a Firebase ID token minted just before this call
    // remains cryptographically valid for up to ~1 hour after the Auth user
    // is deleted above. `onCall`'s built-in token verification
    // (`firebase-functions` -> `verifyIdToken`, no `checkRevoked`) does not
    // re-check that the uid still exists, so a client still holding that
    // token could keep invoking OTHER authenticated callables in this file
    // as this now-deleted uid until the token expires on its own. This is a
    // platform-level property of every `onCall` function in this codebase,
    // not something introduced by or fixable inside this one function --
    // closing it project-wide would mean passing `checkRevoked: true`
    // through every callable's auth verification, which `onCall` does not
    // expose as a per-function option. Recorded here rather than silently
    // shipped as if "irreversible" meant "immediate everywhere."
    logger.info("account deleted", { uid });
    return { success: true };
  },
);

// Signed, expiring URLs for the licensed clip library. Kept in its own module
// because it is the one part of this file that exists to satisfy a contract
// rather than a feature request — see the header of video_urls.ts.
export { clipUrl, clipUrls } from "./video_urls";

// A3. Separate module for the same reason as the clip signer: it exists to
// satisfy a written promise (`public/privacy.html:89`) rather than a feature
// request, and it is the only function here that reads across every
// collection a user touches.
export { exportAccountData } from "./account_export";
