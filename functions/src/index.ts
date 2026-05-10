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
 *   - generateAnnualReceipt  (callable) — tax-deductible donation receipt
 *                                         for the requested year.
 *   - reportEquipment        (callable) — TX.7. Stores a broken-equipment
 *                                         report and dispatches to the gym's
 *                                         registered webhook.
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
  { region: "us-central1" },
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
  { region: "us-central1" },
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
 * Returns a tax-deductible receipt for the calling user for the given
 * year. The receipt is a JSON document the app can render or email; we
 * intentionally don't attach a PDF here (lower attack surface, easier
 * to localise client-side).
 *
 * The amount is derived from Stripe invoices marked `paid` between
 * Jan 1 and Dec 31 of the requested year. No client field accepted.
 */
export const generateAnnualReceipt = onCall(
  {
    secrets: [STRIPE_SECRET_KEY],
    region: "us-central1",
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
      // Trial-only / never-donated user — return a zero receipt rather
      // than 4xx so the client can show "no donations recorded" instead
      // of an error.
      return {
        year,
        currency: "USD",
        totalCents: 0,
        invoiceCount: 0,
        items: [],
        donorName: auth.token?.name ?? auth.token?.email ?? "Anonymous",
        donorUid: auth.uid,
        orgName: "Fitness App (501(c)(3) pending)",
        notice:
          "No donations were recorded under your account in this year.",
      };
    }

    const stripe = new Stripe(STRIPE_SECRET_KEY.value(), {
      apiVersion: "2025-02-24.acacia",
    });

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
          description: inv.lines?.data?.[0]?.description ?? "Recurring donation",
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
      donorName: auth.token?.name ?? auth.token?.email ?? "Anonymous",
      donorUid: auth.uid,
      orgName: "Fitness App (501(c)(3) pending)",
      generatedAt: new Date().toISOString(),
      notice: totalCents > 0
        ? "Keep this receipt for your records. " +
          "501(c)(3) status pending — once approved, prior-year donations " +
          "made under our fiscal sponsor are retroactively deductible."
        : "No donations were recorded under your account in this year.",
    };

    // Persist a copy so the year-end batch job has a known address.
    await db
      .doc(`users/${auth.uid}/receipts/${year}`)
      .set(receipt, { merge: true });

    return receipt;
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
  { region: "us-central1" },
  async (request) => {
    const auth = request.auth;
    if (!auth) {
      throw new HttpsError("unauthenticated", "Sign in to file a report.");
    }
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
        await fetch(webhookUrl, {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify(payload),
        });
      }
    } catch (err) {
      logger.warn("equipment report webhook failed", { err, gymId });
      // We swallow the error — the Firestore write succeeded.
    }

    return { reportId };
  },
);
