/**
 * Cloud Functions backend for the Fitness App's Phase 4B Stripe billing.
 *
 * Four entry points:
 *   - startFreeTrial         (callable) — writes the user's 14-day trial
 *                                         state into Firestore. The
 *                                         tightened firestore.rules deny
 *                                         client writes to the
 *                                         subscription doc, so the trial
 *                                         start has to land server-side
 *                                         too even though it doesn't
 *                                         touch Stripe.
 *   - createCheckoutSession  (callable) — returns a Stripe Checkout URL.
 *   - createPortalSession    (callable) — returns a Stripe Customer Portal URL.
 *   - stripeWebhook          (HTTPS)    — verifies Stripe events and mirrors
 *                                         the subscription state into
 *                                         users/{uid}/subscription/main.
 *
 * Secrets (set via `firebase functions:secrets:set`):
 *   - STRIPE_SECRET_KEY        sk_test_... (server-only, never in the app)
 *   - STRIPE_WEBHOOK_SECRET    whsec_...   (set after the first deploy)
 *   - STRIPE_PRICE_STANDARD    price_...   (Standard tier, $9.99/mo)
 *   - STRIPE_PRICE_CELEBRITY   price_...   (Celebrity tier, $19.99/mo)
 */

import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { onRequest } from "firebase-functions/v2/https";
import { defineSecret } from "firebase-functions/params";
import * as logger from "firebase-functions/logger";
import Stripe from "stripe";

admin.initializeApp();
const db = admin.firestore();

const STRIPE_SECRET_KEY = defineSecret("STRIPE_SECRET_KEY");
const STRIPE_WEBHOOK_SECRET = defineSecret("STRIPE_WEBHOOK_SECRET");
const STRIPE_PRICE_STANDARD = defineSecret("STRIPE_PRICE_STANDARD");
const STRIPE_PRICE_CELEBRITY = defineSecret("STRIPE_PRICE_CELEBRITY");

type Tier = "standard" | "celebrityTrainer";

function priceFor(tier: Tier): string {
  switch (tier) {
    case "standard":
      return STRIPE_PRICE_STANDARD.value();
    case "celebrityTrainer":
      return STRIPE_PRICE_CELEBRITY.value();
  }
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

  const customer = await stripe.customers.create({
    email: email ?? undefined,
    metadata: { firebaseUid: uid },
  });
  await ref.set({ stripeCustomerId: customer.id }, { merge: true });
  return customer.id;
}

/* ------------------------------------------------------------------ */
/* startFreeTrial                                                     */
/* ------------------------------------------------------------------ */

const TRIAL_DAYS = 14;

export const startFreeTrial = onCall(
  { region: "us-central1" },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to start a trial.");
    }
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
    secrets: [
      STRIPE_SECRET_KEY,
      STRIPE_PRICE_STANDARD,
      STRIPE_PRICE_CELEBRITY,
    ],
    region: "us-central1",
  },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to subscribe.");
    }

    const tier = request.data?.tier as Tier | undefined;
    if (tier !== "standard" && tier !== "celebrityTrainer") {
      throw new HttpsError(
        "invalid-argument",
        `Unknown tier: ${String(tier)}`,
      );
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: "2025-02-24.acacia",
    });
    const customerId = await ensureCustomer(
      stripe,
      auth.uid,
      auth.token?.email ?? null,
    );

    const session = await stripe.checkout.sessions.create({
      mode: "subscription",
      customer: customerId,
      line_items: [{ price: priceFor(tier), quantity: 1 }],
      // The deep link is registered on Android via an app-link intent
      // filter (Phase 4B continuation). Until then these resolve to the
      // public Stripe-hosted "thanks" pages, which is fine for the test
      // mode round-trip — the subscription doc updates via webhook.
      success_url: "https://fitnessapp.example.com/checkout-success",
      cancel_url: "https://fitnessapp.example.com/checkout-cancel",
      client_reference_id: auth.uid,
      subscription_data: { metadata: { firebaseUid: auth.uid } },
      allow_promotion_codes: true,
    });

    if (!session.url) {
      throw new HttpsError("internal", "Stripe returned no checkout URL.");
    }
    logger.info("created checkout session", {
      uid: auth.uid,
      tier,
      sessionId: session.id,
    });
    return { url: session.url };
  },
);

/* ------------------------------------------------------------------ */
/* createPortalSession                                                */
/* ------------------------------------------------------------------ */

export const createPortalSession = onCall(
  { secrets: [STRIPE_SECRET_KEY], region: "us-central1" },
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

    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: "2025-02-24.acacia",
    });
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
 * `priceFor()` is the inverse of this map; if a price id isn't known
 * we default to `free` so the user is never silently upgraded.
 */
function tierFromSubscription(s: Stripe.Subscription): string {
  const priceId = s.items.data[0]?.price.id;
  if (priceId === STRIPE_PRICE_STANDARD.value()) return "standard";
  if (priceId === STRIPE_PRICE_CELEBRITY.value()) return "celebrityTrainer";
  return "free";
}

async function applySubscription(s: Stripe.Subscription) {
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

  // Stripe surfaces these timestamps as Unix seconds.
  const periodEnd = s.current_period_end
    ? new Date(s.current_period_end * 1000).toISOString()
    : null;
  const trialEnd = s.trial_end
    ? new Date(s.trial_end * 1000).toISOString()
    : null;

  await db.doc(`users/${uid}/subscription/main`).set(
    {
      tier,
      status,
      currentPeriodEndsAt: periodEnd,
      trialEndsAt: trialEnd,
      stripeCustomerId: s.customer,
      stripeSubscriptionId: s.id,
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    },
    { merge: true },
  );
}

export const stripeWebhook = onRequest(
  {
    secrets: [
      STRIPE_SECRET_KEY,
      STRIPE_WEBHOOK_SECRET,
      STRIPE_PRICE_STANDARD,
      STRIPE_PRICE_CELEBRITY,
    ],
    region: "us-central1",
  },
  async (req, res) => {
    const sig = req.headers["stripe-signature"];
    if (typeof sig !== "string") {
      res.status(400).send("Missing stripe-signature header");
      return;
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: "2025-02-24.acacia",
    });

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
          await applySubscription(event.data.object as Stripe.Subscription);
          break;
        case "invoice.paid":
        case "invoice.payment_failed": {
          // Refresh the subscription state so periodEnd advances.
          const inv = event.data.object as Stripe.Invoice;
          const subId = inv.subscription;
          if (typeof subId === "string") {
            const sub = await stripe.subscriptions.retrieve(subId);
            await applySubscription(sub);
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
