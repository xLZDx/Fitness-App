/**
 * Ticket #9 — unit tests for 4 callable Cloud Functions:
 *   startFreeTrial, createCheckoutSession, generateAnnualReceipt,
 *   bookCoachSession.
 *
 * Pure unit tests:
 *   - firebase-admin is jest-mocked (in-memory doc-ref registry, no
 *     Firestore).
 *   - stripe is jest-mocked (no network).
 *   - Secrets come from fake process.env values set in jest.setup.js
 *     (defineSecret().value() reads process.env at runtime).
 *   - Handlers are invoked through the `.run()` property that
 *     firebase-functions v2 `onCall` attaches to every exported
 *     CallableFunction (verified against firebase-functions 6.6.0,
 *     lib/v2/providers/https.js — `func.run = withInit(handler)`).
 *
 * These tests assert CURRENT behavior of src/index.ts, not idealized
 * behavior.
 */

jest.mock("firebase-admin", () => {
  // In-memory registry of doc refs, keyed by Firestore path. Refs are
  // created lazily so tests can both prime reads and assert writes.
  const refs = new Map<string, any>();
  const getRef = (path: string): any => {
    let ref = refs.get(path);
    if (!ref) {
      ref = {
        path,
        get: jest.fn(async () => ({ exists: false, data: () => undefined })),
        set: jest.fn(async () => undefined),
        delete: jest.fn(async () => undefined),
      };
      refs.set(path, ref);
    }
    return ref;
  };
  // Transactions run their body immediately against the same ref registry.
  // Serialisation is not modelled -- these tests assert what a transaction
  // writes, not that Firestore retries it, and pretending otherwise would be
  // a fake with opinions about a database it is not.
  const runTransaction = jest.fn(async (fn: (tx: any) => Promise<any>) =>
    fn({
      get: (ref: any) => ref.get(),
      set: (ref: any, data: any, opts?: any) => ref.set(data, opts),
      delete: (ref: any) => ref.delete(),
    }),
  );
  const firestoreFn: any = jest.fn(() => ({
    doc: jest.fn((path: string) => getRef(path)),
    runTransaction,
  }));
  firestoreFn.FieldValue = {
    serverTimestamp: jest.fn(() => "__SERVER_TIMESTAMP__"),
  };
  // F011. `startFreeTrial` and `createCheckoutSession` now ask Auth whether
  // the uid still exists, so the mock has to answer. Default: it does.
  // `__setUserLookup` lets a case make the account absent (a deleted user
  // whose token has not expired) or make the lookup itself fail (an Auth
  // outage), which are two different requirements.
  const getUser = jest.fn(async (uid: string) => ({ uid }));
  const authFn: any = jest.fn(() => ({ getUser }));
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    auth: authFn,
    __getRef: getRef,
    __getUser: getUser,
    __setUserLookup: (impl: (uid: string) => Promise<any>) =>
      getUser.mockImplementation(impl as any),
    __reset: () => {
      refs.clear();
      getUser.mockReset();
      getUser.mockImplementation(async (uid: string) => ({ uid }));
    },
  };
});

jest.mock("stripe", () => {
  const instance = {
    customers: { create: jest.fn() },
    checkout: { sessions: { create: jest.fn() } },
    invoices: { list: jest.fn() },
    paymentIntents: { create: jest.fn() },
    // A4 — checkout now asks Stripe whether this customer already has a live
    // subscription before creating a second one. Defaulted to "none" in
    // `beforeEach`; the duplicate-guard tests override it.
    subscriptions: { list: jest.fn() },
    // A5 — both of these took a `return_url` pointing at a domain that does
    // not resolve, so the tests below can only see the fix if the mock
    // records what was sent.
    billingPortal: { sessions: { create: jest.fn() } },
    accountLinks: { create: jest.fn() },
    accounts: { create: jest.fn() },
  };
  const ctor: any = jest.fn(() => instance);
  ctor.__instance = instance;
  return ctor;
});

jest.mock("firebase-functions/logger", () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

import { HttpsError } from "firebase-functions/v2/https";
import { QUOTAS } from "../abuse_guard";
import {
  startFreeTrial,
  createCheckoutSession,
  generateAnnualReceipt,
  bookCoachSession,
  createPortalSession,
  startCoachOnboarding,
  optInDonorWall,
  optOutDonorWall,
  reportEquipment,
} from "../index";

const adminMock = jest.requireMock("firebase-admin") as any;
const stripeCtor = jest.requireMock("stripe") as any;
const stripeMock = stripeCtor.__instance;

/**
 * Derived from the source, not restated here.
 *
 * These two assertions were stale for as long as the return origin has been
 * real: the code moved off the `fitnessapp.example.com` placeholder (and the
 * reason is written at `index.ts` above `RETURN_ORIGIN`) and gained
 * `locale: "auto"`, and neither change reached this file. A literal copy of a
 * constant is a test that fails for the one reason that does not matter --
 * the value changing -- while still passing if the URL stops being sent at
 * all. Importing it keeps the shape under test and drops the copy.
 */
// F0·1: derived the same way production derives it, from the deploying
// project, instead of copying the literal. The comment above predicted
// exactly this failure -- the copy broke the moment the value stopped being
// hardcoded, while still not testing anything about the URL's shape. Written
// against `GCLOUD_PROJECT` (set to `demo-fitness-unit-tests` in
// jest.setup.js:17) so the assertion now says "checkout returns to THIS
// project's hosting site", which is the contract that actually matters and
// the one a project split would break.
const RETURN_ORIGIN = `https://${process.env.GCLOUD_PROJECT}.web.app`;

const STRIPE_CTOR_ARGS = [
  "sk_test_fake_unit_test_key_not_real",
  { apiVersion: "2025-02-24.acacia" },
];

/** Primes the mock doc at `path` so `.get()` resolves with `value`. */
function primeDoc(path: string, value: Record<string, unknown> | undefined) {
  const ref = adminMock.__getRef(path);
  ref.get.mockResolvedValue({ exists: value !== undefined, data: () => value });
  return ref;
}

/** Builds the CallableRequest shape the v2 handlers read. */
function req(
  data: unknown,
  auth?: { uid: string; token?: Record<string, unknown> },
): any {
  return { data, auth, rawRequest: {} };
}

/** Asserts `p` rejects with an HttpsError carrying `code`; returns it. */
async function expectHttpsError(
  p: Promise<unknown>,
  code: string,
): Promise<HttpsError> {
  const err = await p.then(
    () => {
      throw new Error(`expected HttpsError("${code}") but the call resolved`);
    },
    (e: unknown) => e,
  );
  expect(err).toBeInstanceOf(HttpsError);
  expect((err as HttpsError).code).toBe(code);
  return err as HttpsError;
}

beforeEach(() => {
  adminMock.__reset();
  stripeCtor.mockClear(); // keeps the () => instance implementation
  stripeMock.customers.create.mockReset();
  stripeMock.checkout.sessions.create.mockReset();
  // No live subscription by default: the ordinary path is a first purchase.
  stripeMock.subscriptions.list.mockReset().mockResolvedValue({ data: [] });
  stripeMock.invoices.list.mockReset();
  stripeMock.paymentIntents.create.mockReset();
});

/* ------------------------------------------------------------------ */
/* F011 — the stale-token window, on the two callables that close it   */
/* ------------------------------------------------------------------ */

/**
 * `deleteAccount` removes the Auth user, but a token minted just before that
 * stays valid for up to ~1 hour and `onCall` does not re-check that the uid
 * still exists. The F011 decision RISK_ACCEPTED seven callables and required
 * remediation for exactly these two, because their eligibility checks read
 * records deletion has just removed: a stale token replays them against
 * absence and gets a fresh trial, or a new paid subscription attached to an
 * account that no longer exists.
 *
 * Each case is written so it FAILS without the guard: every one of them
 * reaches a state the callable would otherwise treat as success.
 */
describe("F011: a deleted account cannot replay a payment operation", () => {
  const deleted = async (_uid: string) => {
    const e: any = new Error("no user record");
    e.code = "auth/user-not-found";
    throw e;
  };

  test("startFreeTrial refuses, and writes nothing", async () => {
    // No subscription doc, which is what deletion leaves behind — so without
    // the guard `trialStartedOnce` is absent and the trial is GRANTED.
    const ref = primeDoc("users/u1/subscription/main", undefined);
    adminMock.__setUserLookup(deleted);

    await expectHttpsError(
      startFreeTrial.run(req({ tier: "standard" }, { uid: "u1" })),
      "unauthenticated",
    );
    expect(ref.set).not.toHaveBeenCalled();
  });

  test("createCheckoutSession refuses, and never reaches Stripe", async () => {
    primeDoc("users/u1/subscription/main", undefined);
    adminMock.__setUserLookup(deleted);

    await expectHttpsError(
      createCheckoutSession.run(
        req({ tier: "standard" }, { uid: "u1", token: { email: "a@b.test" } }),
      ),
      "unauthenticated",
    );
    expect(stripeMock.customers.create).not.toHaveBeenCalled();
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("the check runs before the trial-already-used branch", async () => {
    // Ordering matters: a deleted account must be refused as unauthenticated
    // rather than told "trial already used", which is a different fact and
    // leaks whether that uid ever had one.
    primeDoc("users/u1/subscription/main", { trialStartedOnce: true });
    adminMock.__setUserLookup(deleted);

    await expectHttpsError(
      startFreeTrial.run(req({ tier: "standard" }, { uid: "u1" })),
      "unauthenticated",
    );
  });

  test("an Auth outage refuses rather than granting", async () => {
    // Fail-closed. "We could not check" must never read as "yes" on a payment
    // path, so a lookup failure that is NOT user-not-found propagates.
    const ref = primeDoc("users/u1/subscription/main", undefined);
    adminMock.__setUserLookup(async () => {
      const e: any = new Error("backend unavailable");
      e.code = "auth/internal-error";
      throw e;
    });

    await expect(
      startFreeTrial.run(req({ tier: "standard" }, { uid: "u1" })),
    ).rejects.toThrow("backend unavailable");
    expect(ref.set).not.toHaveBeenCalled();
  });

  test("a live account is unaffected, and is asked about by uid", async () => {
    // The control. Without it the four refusals above are satisfied by a
    // guard that refuses everybody.
    const ref = primeDoc("users/u1/subscription/main", undefined);

    const res = await startFreeTrial.run(
      req({ tier: "standard" }, { uid: "u1" }),
    );

    expect(res.trialEndsAt).toBeTruthy();
    expect(ref.set).toHaveBeenCalledTimes(1);
    expect(adminMock.__getUser).toHaveBeenCalledWith("u1");
  });

  test("an unauthenticated caller is still refused before any lookup", async () => {
    await expectHttpsError(
      startFreeTrial.run(req({ tier: "standard" }, undefined)),
      "unauthenticated",
    );
    expect(adminMock.__getUser).not.toHaveBeenCalled();
  });

  /*
   * N-03. `bookCoachSession` was counted among the callables F011 accepted as
   * "bounded by what deletion already removes". It is not bounded by that: it
   * WRITES. `ensureCustomer` mints a Stripe customer holding the deleted uid
   * and the token's email, and writes the subscription document back into
   * Firestore after the recursive delete and the shared-record sweep have both
   * finished — so nothing ever cleans it up — and then a card is charged for a
   * booking made by an account that cannot sign in.
   *
   * Without the guard this whole sequence succeeds, which is why the
   * assertions below are on the Stripe calls rather than on the thrown code
   * alone.
   */
  test("bookCoachSession refuses, and creates nothing in Stripe", async () => {
    primeDoc("coach_listings/c1", {
      priceCentsPerSession: 5000,
      stripeConnectAccountId: "acct_live",
      currency: "usd",
    });
    const sub = primeDoc("users/u1/subscription/main", undefined);
    adminMock.__setUserLookup(deleted);

    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "c1", startsAt: "2026-09-01T10:00:00Z" },
          { uid: "u1", token: { email: "a@b.test" } },
        ),
      ),
      "unauthenticated",
    );

    expect(stripeMock.customers.create).not.toHaveBeenCalled();
    expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
    expect(sub.set).not.toHaveBeenCalled();
  });

  test("the booking guard runs before the coach listing is even read", async () => {
    // Ordering. A deleted account must not be told whether a coach exists,
    // and must not spend a read finding out.
    const listing = primeDoc("coach_listings/c1", undefined);
    adminMock.__setUserLookup(deleted);

    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "c1", startsAt: "2026-09-01T10:00:00Z" },
          { uid: "u1", token: { email: "a@b.test" } },
        ),
      ),
      "unauthenticated",
    );
    expect(listing.get).not.toHaveBeenCalled();
  });

  test("a live account still reaches the coach listing", async () => {
    // The control. Without it, both refusals above are satisfied by a guard
    // that refuses everybody.
    const listing = primeDoc("coach_listings/c1", undefined);

    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "c1", startsAt: "2026-09-01T10:00:00Z" },
          { uid: "u1", token: { email: "a@b.test" } },
        ),
      ),
      "not-found",
    );
    expect(listing.get).toHaveBeenCalled();
    expect(adminMock.__getUser).toHaveBeenCalledWith("u1");
  });
});

/* ------------------------------------------------------------------ */
/* startFreeTrial                                                     */
/* ------------------------------------------------------------------ */

describe("startFreeTrial", () => {
  const SUB_PATH = "users/u1/subscription/main";
  const FOURTEEN_DAYS_MS = 14 * 24 * 60 * 60 * 1000;

  test("happy path: writes 14-day trial state and returns trialEndsAt", async () => {
    const ref = primeDoc(SUB_PATH, undefined);

    const before = Date.now();
    const res = await startFreeTrial.run(req({ tier: "standard" }, { uid: "u1" }));
    const after = Date.now();

    const ends = Date.parse(res.trialEndsAt);
    expect(ends).toBeGreaterThanOrEqual(before + FOURTEEN_DAYS_MS);
    expect(ends).toBeLessThanOrEqual(after + FOURTEEN_DAYS_MS);

    expect(ref.set).toHaveBeenCalledTimes(1);
    expect(ref.set).toHaveBeenCalledWith(
      {
        tier: "standard",
        status: "trial",
        trialEndsAt: res.trialEndsAt,
        trialStartedOnce: true,
        currentPeriodEndsAt: null,
        updatedAt: "__SERVER_TIMESTAMP__",
      },
      { merge: true },
    );
  });

  test("unauthenticated request throws unauthenticated", async () => {
    await expectHttpsError(
      startFreeTrial.run(req({ tier: "standard" }, undefined)),
      "unauthenticated",
    );
  });

  test("unknown tier throws invalid-argument and writes nothing", async () => {
    const ref = primeDoc(SUB_PATH, undefined);
    await expectHttpsError(
      startFreeTrial.run(req({ tier: "gold" }, { uid: "u1" })),
      "invalid-argument",
    );
    expect(ref.set).not.toHaveBeenCalled();
  });

  test("an anonymous account cannot start a trial", async () => {
    // A6-full. `trialStartedOnce` is per-uid and an anonymous uid costs
    // nothing to replace: sign out, sign in anonymously, new uid, new trial,
    // forever. The flag was guarding a door in a wall the caller walks around.
    const ref = primeDoc(SUB_PATH, undefined);

    await expectHttpsError(
      startFreeTrial.run(
        req(
          { tier: "standard" },
          { uid: "anon1", token: { firebase: { sign_in_provider: "anonymous" } } },
        ),
      ),
      "failed-precondition",
    );
    expect(ref.set).not.toHaveBeenCalled();
  });

  test("a Google account still can", async () => {
    // The guard must bind rotation, not block the product. Signing in again
    // with the same Google account returns the same uid, so the once-only flag
    // is still there to do its job.
    primeDoc(SUB_PATH, undefined);

    const res = await startFreeTrial.run(
      req(
        { tier: "standard" },
        { uid: "u1", token: { firebase: { sign_in_provider: "google.com" } } },
      ),
    );

    expect(res.trialEndsAt).toBeTruthy();
  });

  test("second trial attempt throws failed-precondition and writes nothing", async () => {
    const ref = primeDoc(SUB_PATH, { trialStartedOnce: true });
    await expectHttpsError(
      startFreeTrial.run(req({ tier: "standard" }, { uid: "u1" })),
      "failed-precondition",
    );
    expect(ref.set).not.toHaveBeenCalled();
  });
});

/* ------------------------------------------------------------------ */
/* createCheckoutSession                                              */
/* ------------------------------------------------------------------ */

describe("createCheckoutSession", () => {
  const SUB_PATH = "users/u1/subscription/main";

  test("happy path: existing customer, standard monthly subscription", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    stripeMock.checkout.sessions.create.mockResolvedValue({
      id: "cs_test_1",
      url: "https://checkout.stripe.test/cs_test_1",
    });

    const res = await createCheckoutSession.run(
      req(
        { tier: "standard", period: "monthly" },
        { uid: "u1", token: { email: "u1@example.com" } },
      ),
    );

    expect(res).toEqual({ url: "https://checkout.stripe.test/cs_test_1" });
    expect(stripeCtor).toHaveBeenCalledWith(...STRIPE_CTOR_ARGS);
    expect(stripeMock.customers.create).not.toHaveBeenCalled();
    expect(stripeMock.checkout.sessions.create).toHaveBeenCalledTimes(1);
    expect(stripeMock.checkout.sessions.create).toHaveBeenCalledWith({
      mode: "subscription",
      customer: "cus_existing",
      line_items: [{ price: "price_fake_std_monthly", quantity: 1 }],
      locale: "auto",
      success_url: `${RETURN_ORIGIN}/checkout-success`,
      cancel_url: `${RETURN_ORIGIN}/checkout-cancel`,
      client_reference_id: "u1",
      subscription_data: {
        metadata: { firebaseUid: "u1", tier: "standard", period: "monthly" },
      },
      allow_promotion_codes: true,
    },
    {
      // A4 — a double-tap on Subscribe must not open two payable sessions.
      idempotencyKey: "checkout_u1_standard_monthly_auto",
    });
  });

  test("first-time customer: creates Stripe customer, persists id, lifetime uses payment mode", async () => {
    const subRef = primeDoc("users/u2/subscription/main", undefined);
    stripeMock.customers.create.mockResolvedValue({ id: "cus_new_1" });
    stripeMock.checkout.sessions.create.mockResolvedValue({
      id: "cs_test_2",
      url: "https://checkout.stripe.test/cs_test_2",
    });

    const res = await createCheckoutSession.run(
      req(
        { tier: "celebrityTrainer", period: "lifetime" },
        { uid: "u2", token: { email: "u2@example.com" } },
      ),
    );

    expect(res).toEqual({ url: "https://checkout.stripe.test/cs_test_2" });
    expect(stripeMock.customers.create).toHaveBeenCalledWith(
      {
        email: "u2@example.com",
        metadata: { firebaseUid: "u2" },
      },
      // The second argument is the point: two concurrent calls for one uid
      // both read no customer and both create one, and a repeated key makes
      // Stripe return the same customer rather than a second. The loser of
      // that race used to leave an orphan holding invoices that then vanished
      // from the user's annual tax receipt.
      { idempotencyKey: "customer_u2" },
    );
    expect(subRef.set).toHaveBeenCalledWith(
      { stripeCustomerId: "cus_new_1" },
      { merge: true },
    );
    expect(stripeMock.checkout.sessions.create).toHaveBeenCalledWith({
      mode: "payment",
      customer: "cus_new_1",
      line_items: [{ price: "price_fake_celeb_lifetime", quantity: 1 }],
      locale: "auto",
      success_url: `${RETURN_ORIGIN}/checkout-success`,
      cancel_url: `${RETURN_ORIGIN}/checkout-cancel`,
      client_reference_id: "u2",
      payment_intent_data: {
        metadata: {
          firebaseUid: "u2",
          tier: "celebrityTrainer",
          period: "lifetime",
        },
      },
      allow_promotion_codes: true,
    },
    { idempotencyKey: "checkout_u2_celebrityTrainer_lifetime_auto" });
  });

  test("a one-time purchase never asks whether a subscription exists",
    async () => {
      // Buying lifetime or donating is not mutually exclusive with holding a
      // subscription, so the duplicate guard must not reach these at all.
      primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
      stripeMock.checkout.sessions.create.mockResolvedValue({
        id: "cs_1",
        url: "https://checkout.stripe.test/cs_1",
      });

      await createCheckoutSession.run(
        req(
          { tier: "celebrityTrainer", period: "lifetime" },
          { uid: "u1", token: { email: "u1@example.com" } },
        ),
      );

      expect(stripeMock.subscriptions.list).not.toHaveBeenCalled();
    });

  test("refuses a second subscription while a live one exists", async () => {
    // The audit's scenario: two Checkout sessions, two recurring
    // subscriptions, one stored id, and the account-deletion path cancelling
    // only the id it remembers while the other keeps billing.
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    stripeMock.subscriptions.list.mockResolvedValue({
      data: [{ id: "sub_live", status: "active" }],
    });

    const err = await expectHttpsError(
      createCheckoutSession.run(
        req(
          { tier: "standard", period: "monthly" },
          { uid: "u1", token: { email: "u1@example.com" } },
        ),
      ),
      "failed-precondition",
    );

    expect(err.message).toMatch(/already have an active subscription/i);
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("past_due counts as live -- it still bills", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    stripeMock.subscriptions.list.mockResolvedValue({
      data: [{ id: "sub_late", status: "past_due" }],
    });

    await expectHttpsError(
      createCheckoutSession.run(
        req(
          { tier: "standard", period: "monthly" },
          { uid: "u1", token: { email: "u1@example.com" } },
        ),
      ),
      "failed-precondition",
    );
  });

  test("a canceled subscription does not block a new one", async () => {
    // Someone who cancelled and came back must be able to subscribe again.
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    stripeMock.subscriptions.list.mockResolvedValue({
      data: [{ id: "sub_old", status: "canceled" }],
    });
    stripeMock.checkout.sessions.create.mockResolvedValue({
      id: "cs_2",
      url: "https://checkout.stripe.test/cs_2",
    });

    const res = await createCheckoutSession.run(
      req(
        { tier: "standard", period: "monthly" },
        { uid: "u1", token: { email: "u1@example.com" } },
      ),
    );

    expect(res).toEqual({ url: "https://checkout.stripe.test/cs_2" });
  });

  test("unauthenticated request throws unauthenticated", async () => {
    await expectHttpsError(
      createCheckoutSession.run(req({ tier: "standard" }, undefined)),
      "unauthenticated",
    );
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("unknown tier throws invalid-argument", async () => {
    await expectHttpsError(
      createCheckoutSession.run(req({ tier: "premium" }, { uid: "u1" })),
      "invalid-argument",
    );
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("unknown period throws invalid-argument", async () => {
    await expectHttpsError(
      createCheckoutSession.run(
        req({ tier: "standard", period: "weekly" }, { uid: "u1" }),
      ),
      "invalid-argument",
    );
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("standard + lifetime combination throws invalid-argument", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    const err = await expectHttpsError(
      createCheckoutSession.run(
        req({ tier: "standard", period: "lifetime" }, { uid: "u1" }),
      ),
      "invalid-argument",
    );
    expect(err.message).toBe("Standard does not offer a lifetime plan.");
    expect(stripeMock.checkout.sessions.create).not.toHaveBeenCalled();
  });

  test("Stripe session without url throws internal", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_existing" });
    stripeMock.checkout.sessions.create.mockResolvedValue({
      id: "cs_test_nourl",
      url: null,
    });
    await expectHttpsError(
      createCheckoutSession.run(
        req({ tier: "standard", period: "monthly" }, { uid: "u1" }),
      ),
      "internal",
    );
  });
});

/* ------------------------------------------------------------------ */
/* generateAnnualReceipt                                              */
/* ------------------------------------------------------------------ */

describe("generateAnnualReceipt", () => {
  const SUB_PATH = "users/u1/subscription/main";
  const RECEIPT_PATH = "users/u1/receipts/2025";

  test("happy path: sums paid invoices for the year and persists the receipt", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_1" });
    stripeMock.invoices.list.mockResolvedValue({
      data: [
        {
          id: "in_1",
          amount_paid: 999,
          created: 1735689600, // 2025-01-01T00:00:00Z
          currency: "usd",
          number: "INV-001",
          lines: { data: [{ description: "Standard plan" }] },
        },
        {
          id: "in_2",
          amount_paid: 501,
          created: 1749945600, // 2025-06-15T00:00:00Z
          currency: "usd",
          number: null,
          lines: { data: [] },
        },
      ],
      has_more: false,
    });

    const res = await generateAnnualReceipt.run(
      req({ year: 2025 }, { uid: "u1", token: { name: "Ivan Tester", email: "i@example.com" } }),
    );

    expect(res).toMatchObject({
      year: 2025,
      currency: "USD",
      totalCents: 1500,
      invoiceCount: 2,
      payerName: "Ivan Tester",
      payerUid: "u1",
      issuedBy: "Fitness App",
    });
    expect(res.items).toEqual([
      {
        created: "2025-01-01T00:00:00.000Z",
        amountCents: 999,
        currency: "usd",
        number: "INV-001",
        description: "Standard plan",
      },
      {
        created: "2025-06-15T00:00:00.000Z",
        amountCents: 501,
        currency: "usd",
        number: null,
        description: "Subscription",
      },
    ]);

    expect(stripeCtor).toHaveBeenCalledWith(...STRIPE_CTOR_ARGS);
    expect(stripeMock.invoices.list).toHaveBeenCalledTimes(1);
    expect(stripeMock.invoices.list).toHaveBeenCalledWith({
      customer: "cus_1",
      status: "paid",
      created: { gte: 1735689600, lt: 1767225600 }, // [2025-01-01, 2026-01-01)
      limit: 100,
    });

    const receiptRef = adminMock.__getRef(RECEIPT_PATH);
    expect(receiptRef.set).toHaveBeenCalledTimes(1);
    expect(receiptRef.set).toHaveBeenCalledWith(res, { merge: true });
  });

  test("paginates with starting_after until has_more is false", async () => {
    primeDoc(SUB_PATH, { stripeCustomerId: "cus_1" });
    stripeMock.invoices.list
      .mockResolvedValueOnce({
        data: [
          {
            id: "in_1",
            amount_paid: 1000,
            created: 1735689600,
            currency: "usd",
            number: "INV-001",
            lines: { data: [{ description: "Donation" }] },
          },
        ],
        has_more: true,
      })
      .mockResolvedValueOnce({
        data: [
          {
            id: "in_2",
            amount_paid: 200,
            created: 1749945600,
            currency: "usd",
            number: "INV-002",
            lines: { data: [{ description: "Donation" }] },
          },
        ],
        has_more: false,
      });

    const res = await generateAnnualReceipt.run(
      req({ year: 2025 }, { uid: "u1", token: {} }),
    );

    expect(res.totalCents).toBe(1200);
    expect(res.invoiceCount).toBe(2);
    expect(stripeMock.invoices.list).toHaveBeenCalledTimes(2);
    expect(stripeMock.invoices.list).toHaveBeenNthCalledWith(2, {
      customer: "cus_1",
      status: "paid",
      created: { gte: 1735689600, lt: 1767225600 },
      limit: 100,
      starting_after: "in_1",
    });
  });

  test("user with no Stripe customer gets a zero receipt without calling Stripe", async () => {
    primeDoc(SUB_PATH, undefined);

    const res = await generateAnnualReceipt.run(
      req({ year: 2025 }, { uid: "u1", token: { email: "u1@example.com" } }),
    );

    expect(res).toEqual({
      year: 2025,
      currency: "USD",
      totalCents: 0,
      invoiceCount: 0,
      items: [],
      payerName: "u1@example.com",
      payerUid: "u1",
      issuedBy: "Fitness App",
      notice: "No payments were recorded under your account in this year.",
    });
    expect(stripeCtor).not.toHaveBeenCalled();
    expect(stripeMock.invoices.list).not.toHaveBeenCalled();
    // Current behavior: the zero-receipt path does NOT persist a copy.
    expect(adminMock.__getRef(RECEIPT_PATH).set).not.toHaveBeenCalled();
  });

  test("claims no charitable status, on either path", async () => {
    // The regression this replaces was not a bug in the arithmetic. Until
    // P0 this function returned `orgName: "Fitness App (501(c)(3) pending)"`
    // and a notice promising that "prior-year donations made under our
    // fiscal sponsor are retroactively deductible" -- on a document a user
    // could hand to a tax authority -- and persisted it to
    // `users/{uid}/receipts/{year}`. There is no 501(c)(3), no pending
    // application and no fiscal sponsor. S0b removed the same framing from
    // every Flutter surface and never grepped the backend, which is exactly
    // why the assertion belongs here rather than in a doc comment.
    //
    // Asserted over the serialised payload rather than field by field: the
    // failure mode was a claim living in a field nobody thought to check, so
    // naming the fields would rebuild the original blind spot.
    //
    // `notice` is excluded from the scan and pinned separately, because the
    // corrective sentence has to USE the forbidden words to negate them
    // ("not charitable donations", "not tax-deductible"). A pattern scan
    // cannot tell an assertion from its denial; two assertions can.
    const forbidden = [/501\(c\)/i, /deductib/i, /donation/i, /donor/i,
      /fiscal sponsor/i, /charit/i];
    const withoutNotice = (r: Record<string, unknown>) => {
      const {notice: _drop, ...rest} = r;
      return rest;
    };

    primeDoc(SUB_PATH, undefined);
    const zero = await generateAnnualReceipt.run(
      req({ year: 2025 }, { uid: "u1", token: {} }),
    );

    primeDoc(SUB_PATH, { stripeCustomerId: "cus_1" });
    stripeMock.invoices.list.mockResolvedValue({
      data: [{
        id: "in_1", amount_paid: 999, created: 1735689600,
        currency: "usd", number: "INV-001", lines: { data: [] },
      }],
      has_more: false,
    });
    const paid = await generateAnnualReceipt.run(
      req({ year: 2025 }, { uid: "u1", token: {} }),
    );

    for (const payload of [zero, paid]) {
      const text = JSON.stringify(withoutNotice(payload));
      for (const pattern of forbidden) {
        expect(text).not.toMatch(pattern);
      }
    }

    // The notices, pinned exactly. The paid one states the correction the
    // published Terms state ("These payments are not tax-deductible
    // donations"); the zero one simply has nothing to correct.
    expect(paid.notice).toBe(
      "Keep this summary for your records. These are subscription payments, " +
      "not charitable donations, and they are not tax-deductible.",
    );
    expect(zero.notice).toBe(
      "No payments were recorded under your account in this year.",
    );
  });

  test("unauthenticated request throws unauthenticated", async () => {
    await expectHttpsError(
      generateAnnualReceipt.run(req({ year: 2025 }, undefined)),
      "unauthenticated",
    );
  });

  test("out-of-range year throws invalid-argument", async () => {
    await expectHttpsError(
      generateAnnualReceipt.run(req({ year: 1999 }, { uid: "u1" })),
      "invalid-argument",
    );
    await expectHttpsError(
      generateAnnualReceipt.run(req({ year: "not-a-year" }, { uid: "u1" })),
      "invalid-argument",
    );
  });
});

/* ------------------------------------------------------------------ */
/* bookCoachSession                                                   */
/* ------------------------------------------------------------------ */

describe("bookCoachSession", () => {
  const CLIENT_SUB_PATH = "users/client1/subscription/main";

  test("happy path: PaymentIntent with 15% platform fee + pending booking doc", async () => {
    primeDoc("coach_listings/coach1", {
      priceCentsPerSession: 10000,
      stripeConnectAccountId: "acct_c1",
      currency: "eur",
    });
    primeDoc(CLIENT_SUB_PATH, { stripeCustomerId: "cus_cl1" });
    stripeMock.paymentIntents.create.mockResolvedValue({
      id: "pi_1",
      client_secret: "pi_1_secret_x",
    });

    const res = await bookCoachSession.run(
      req(
        {
          coachUid: "coach1",
          startsAt: "2026-08-01T10:00:00.000Z",
          durationMinutes: 45,
        },
        { uid: "client1", token: { email: "client1@example.com" } },
      ),
    );

    expect(res.bookingId).toMatch(/^bk_\d+_client1$/);
    expect(res.clientSecret).toBe("pi_1_secret_x");
    expect(res.amountCents).toBe(10000);

    expect(stripeCtor).toHaveBeenCalledWith(...STRIPE_CTOR_ARGS);
    expect(stripeMock.paymentIntents.create).toHaveBeenCalledTimes(1);
    expect(stripeMock.paymentIntents.create).toHaveBeenCalledWith({
      amount: 10000,
      currency: "eur",
      customer: "cus_cl1",
      application_fee_amount: 1500, // 15% of 10000
      transfer_data: { destination: "acct_c1" },
      metadata: {
        firebaseUid: "client1",
        coachUid: "coach1",
        bookingId: res.bookingId,
        kind: "coach_booking",
      },
    });

    const bookingRef = adminMock.__getRef(`coach_bookings/${res.bookingId}`);
    expect(bookingRef.set).toHaveBeenCalledTimes(1);
    expect(bookingRef.set).toHaveBeenCalledWith({
      coachUid: "coach1",
      clientUid: "client1",
      startsAt: "2026-08-01T10:00:00.000Z",
      durationMinutes: 45,
      priceCents: 10000,
      platformFeeCents: 1500,
      status: "pending",
      stripePaymentIntentId: "pi_1",
      createdAt: "__SERVER_TIMESTAMP__",
    });
  });

  /**
   * Found while tracing the export path, not while looking at payments.
   *
   * Every field below is written verbatim into `coach_bookings/{id}` and read
   * back out by `exportAccountData`. None was bounded: N-04 applied `bounded`
   * to `reportEquipment` and stopped there, so the callable that also charges
   * a card took a string of any length.
   *
   * Refused rather than truncated, and nothing may reach Stripe first -- a
   * rejected booking that has already created a PaymentIntent is worse than
   * the unbounded write it replaced.
   */
  describe("client input is bounded before anything is charged", () => {
    beforeEach(() => {
      primeDoc("coach_listings/coach1", {
        priceCentsPerSession: 10000,
        stripeConnectAccountId: "acct_c1",
      });
      primeDoc(CLIENT_SUB_PATH, { stripeCustomerId: "cus_cl1" });
    });

    const bad: [string, Record<string, unknown>][] = [
      ["an oversized startsAt", { coachUid: "coach1", startsAt: "x".repeat(65) }],
      ["a non-string startsAt", { coachUid: "coach1", startsAt: 12345 }],
      ["an oversized coachUid", { coachUid: "c".repeat(129), startsAt: "2026-08-01T10:00:00.000Z" }],
      ["a fractional duration", { coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z", durationMinutes: 45.5 }],
      ["a negative duration", { coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z", durationMinutes: -60 }],
      ["a zero duration", { coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z", durationMinutes: 0 }],
      ["an absurd duration", { coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z", durationMinutes: 100000 }],
      ["a duration that is not a number", { coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z", durationMinutes: "60" }],
    ];

    for (const [name, payload] of bad) {
      test(`${name} is refused, and nothing is charged`, async () => {
        await expect(
          bookCoachSession.run(req(payload, { uid: "client1", token: {} })),
        ).rejects.toMatchObject({ code: "invalid-argument" });
        expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
      });
    }

    test("the control: a well-formed booking still goes through", async () => {
      // Without this the group above would pass just as happily against a
      // callable that refuses everything.
      stripeMock.paymentIntents.create.mockResolvedValue({
        id: "pi_ok",
        client_secret: "pi_ok_secret",
      });
      const res = await bookCoachSession.run(
        req(
          {
            coachUid: "coach1",
            startsAt: "2026-08-01T10:00:00.000Z",
            durationMinutes: 480,
          },
          { uid: "client1", token: {} },
        ),
      );
      expect(res.bookingId).toMatch(/^bk_\d+_client1$/);
    });
  });

  test("defaults durationMinutes to 60 and rounds the platform fee", async () => {
    primeDoc("coach_listings/coach2", {
      priceCentsPerSession: 3333,
      stripeConnectAccountId: "acct_c2",
    });
    primeDoc(CLIENT_SUB_PATH, { stripeCustomerId: "cus_cl1" });
    stripeMock.paymentIntents.create.mockResolvedValue({
      id: "pi_2",
      client_secret: "pi_2_secret",
    });

    const res = await bookCoachSession.run(
      req(
        { coachUid: "coach2", startsAt: "2026-08-02T09:00:00.000Z" },
        { uid: "client1", token: {} },
      ),
    );

    expect(stripeMock.paymentIntents.create).toHaveBeenCalledWith(
      expect.objectContaining({
        amount: 3333,
        currency: "usd", // coach doc has no currency -> default
        application_fee_amount: 500, // Math.round(3333 * 0.15) = 500
      }),
    );
    const bookingRef = adminMock.__getRef(`coach_bookings/${res.bookingId}`);
    expect(bookingRef.set).toHaveBeenCalledWith(
      expect.objectContaining({ durationMinutes: 60, platformFeeCents: 500 }),
    );
  });

  test("unauthenticated request throws unauthenticated", async () => {
    await expectHttpsError(
      bookCoachSession.run(
        req({ coachUid: "coach1", startsAt: "2026-08-01T10:00:00.000Z" }, undefined),
      ),
      "unauthenticated",
    );
    expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
  });

  test("missing coachUid or startsAt throws invalid-argument", async () => {
    await expectHttpsError(
      bookCoachSession.run(
        req({ startsAt: "2026-08-01T10:00:00.000Z" }, { uid: "client1" }),
      ),
      "invalid-argument",
    );
    await expectHttpsError(
      bookCoachSession.run(req({ coachUid: "coach1" }, { uid: "client1" })),
      "invalid-argument",
    );
    expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
  });

  test("unknown coach throws not-found", async () => {
    primeDoc("coach_listings/ghost", undefined);
    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "ghost", startsAt: "2026-08-01T10:00:00.000Z" },
          { uid: "client1" },
        ),
      ),
      "not-found",
    );
    expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
  });

  test("coach without Connect account or price throws failed-precondition", async () => {
    primeDoc("coach_listings/no-account", { priceCentsPerSession: 5000 });
    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "no-account", startsAt: "2026-08-01T10:00:00.000Z" },
          { uid: "client1" },
        ),
      ),
      "failed-precondition",
    );

    primeDoc("coach_listings/no-price", {
      stripeConnectAccountId: "acct_x",
      priceCentsPerSession: 0,
    });
    await expectHttpsError(
      bookCoachSession.run(
        req(
          { coachUid: "no-price", startsAt: "2026-08-01T10:00:00.000Z" },
          { uid: "client1" },
        ),
      ),
      "failed-precondition",
    );
    expect(stripeMock.paymentIntents.create).not.toHaveBeenCalled();
  });
});

/* ------------------------------------------------------------------ */
/* A5 — every Stripe redirect goes somewhere that exists              */
/* ------------------------------------------------------------------ */

describe("Stripe return URLs", () => {
  /** The dead placeholder these three URLs used to carry. */
  const DEAD = "fitnessapp.example.com";

  test("the billing portal returns to a page that resolves", async () => {
    // The portal is where a user CANCELS. A dead redirect landed them on a
    // browser error immediately after asking to stop paying -- the single
    // worst place in the product to look broken.
    primeDoc("users/u1/subscription/main", { stripeCustomerId: "cus_1" });
    stripeMock.billingPortal.sessions.create.mockResolvedValue({
      url: "https://billing.stripe.com/session/x",
    });

    await createPortalSession.run(req({}, { uid: "u1" }));

    const [args] = stripeMock.billingPortal.sessions.create.mock.calls[0];
    expect(args.return_url).toBe(`${RETURN_ORIGIN}/portal-return`);
    expect(args.return_url).not.toContain(DEAD);
  });

  test("coach onboarding returns to pages that resolve, on both paths",
    async () => {
      // Connect sends the coach back on BOTH links, so a dead domain
      // stranded them mid-onboarding with a half-created account.
      // Both branches reach the same `accountLinks.create`, so the account is
      // left to be created rather than primed -- that is the first-time
      // onboarding path, which is the one a new coach actually walks.
      stripeMock.accounts.create.mockResolvedValue({ id: "acct_new" });
      stripeMock.accountLinks.create.mockResolvedValue({
        url: "https://connect.stripe.com/setup/x",
      });

      await startCoachOnboarding.run(req({}, { uid: "c1" }));

      const [args] = stripeMock.accountLinks.create.mock.calls[0];
      expect(args.return_url).toBe(`${RETURN_ORIGIN}/coach/onboarding-done`);
      expect(args.refresh_url).toBe(
        `${RETURN_ORIGIN}/coach/onboarding-refresh`,
      );
      expect(JSON.stringify(args)).not.toContain(DEAD);
    });
});


/* ------------------------------------------------------------------ */
/* P7 — the three callables that had no behavioural test at all        */
/* ------------------------------------------------------------------ */

/**
 * All three appeared only in `scaling.test.ts`, which asserts the scaling
 * configuration of every export and calls none of them. A function listed there
 * is covered in the sense that its `maxInstances` is pinned, and in no other
 * sense — the scope row that listed these as "no tests" was right about them and
 * wrong about the three it grouped them with.
 *
 * Two of the three write to shared collections that `deleteAccount` has to sweep
 * (`donor_wall`, `equipment_reports`), and the third is the only endpoint that
 * calls out to a third party. Those are the properties asserted below: what
 * lands in Firestore, and what happens when the gym's endpoint misbehaves.
 */
describe("optInDonorWall", () => {
  it("refuses an unauthenticated caller", async () => {
    await expectHttpsError(optInDonorWall.run(req({})), "unauthenticated");
  });

  it("refuses a caller with no active subscription", async () => {
    // The wall is a list of people who are currently supporting the project.
    // Without this the endpoint is an open write to a world-readable
    // collection.
    primeDoc("users/u1/subscription/main", { status: "expired" });
    await expectHttpsError(
      optInDonorWall.run(req({ displayName: "Sam" }, { uid: "u1" })),
      "failed-precondition",
    );
    expect(adminMock.__getRef("donor_wall/u1").set).not.toHaveBeenCalled();
  });

  it("accepts a cancelled subscription, which is still paid up", async () => {
    primeDoc("users/u1/subscription/main", { status: "cancelled" });
    await optInDonorWall.run(req({ displayName: "Sam" }, { uid: "u1" }));
    expect(adminMock.__getRef("donor_wall/u1").set).toHaveBeenCalled();
  });

  it("writes an anonymous entry when the name is blank", async () => {
    // Blank is a deliberate choice in the UI, not a missing field: the privacy
    // policy tells the user that leaving the name empty shows the entry as
    // anonymous.
    primeDoc("users/u1/subscription/main", { status: "active" });
    await optInDonorWall.run(req({ displayName: "   " }, { uid: "u1" }));
    const [written] = adminMock.__getRef("donor_wall/u1").set.mock.calls[0];
    expect(written.displayName).toBe("Anonymous donor");
    expect(written).not.toHaveProperty("message");
  });

  it("enforces the published limits on both fields", async () => {
    // 60 and 200 are the numbers the privacy policy states out loud, so they
    // are a promise rather than an implementation detail.
    primeDoc("users/u1/subscription/main", { status: "active" });
    await expectHttpsError(
      optInDonorWall.run(req({ displayName: "x".repeat(61) }, { uid: "u1" })),
      "invalid-argument",
    );
    await expectHttpsError(
      optInDonorWall.run(req({ message: "x".repeat(201) }, { uid: "u1" })),
      "invalid-argument",
    );
    expect(adminMock.__getRef("donor_wall/u1").set).not.toHaveBeenCalled();
  });

  it("derives the tier from the subscription, not from the request", async () => {
    // A client-supplied tier would let any supporter list themselves as a
    // sustainer on a public page.
    primeDoc("users/u1/subscription/main", {
      status: "active",
      tier: "celebrityTrainer",
    });
    await optInDonorWall.run(
      req({ displayName: "Sam", tier: "sustainer" }, { uid: "u1" }),
    );
    const [written] = adminMock.__getRef("donor_wall/u1").set.mock.calls[0];
    expect(written.tier).toBe("sustainer");

    adminMock.__reset();
    primeDoc("users/u2/subscription/main", { status: "active", tier: "x" });
    await optInDonorWall.run(
      req({ displayName: "Sam", tier: "sustainer" }, { uid: "u2" }),
    );
    const [second] = adminMock.__getRef("donor_wall/u2").set.mock.calls[0];
    expect(second.tier).toBe("supporter");
  });
});

describe("optOutDonorWall", () => {
  it("refuses an unauthenticated caller", async () => {
    await expectHttpsError(optOutDonorWall.run(req({})), "unauthenticated");
  });

  it("deletes only the caller's own entry", async () => {
    // The uid comes from the auth context and there is no client field for it.
    // A request body naming somebody else must not reach their row.
    await optOutDonorWall.run(req({ uid: "victim" }, { uid: "u1" }));
    expect(adminMock.__getRef("donor_wall/u1").delete).toHaveBeenCalled();
    expect(adminMock.__getRef("donor_wall/victim").delete).not.toHaveBeenCalled();
  });
});

describe("reportEquipment", () => {
  const originalFetch = global.fetch;
  afterEach(() => {
    global.fetch = originalFetch;
  });

  it("refuses an unauthenticated caller", async () => {
    await expectHttpsError(reportEquipment.run(req({})), "unauthenticated");
  });

  it("requires an equipmentId", async () => {
    await expectHttpsError(
      reportEquipment.run(req({ gymId: "g1" }, { uid: "u1" })),
      "invalid-argument",
    );
  });

  it("stamps the report with the caller's own uid and opens it", async () => {
    // `reporterUid` is what `deleteAccount` later replaces with
    // `deleted_user`, so it has to be the authenticated uid rather than
    // anything the client sent.
    global.fetch = jest.fn() as any;
    await reportEquipment.run(
      req(
        { id: "r1", equipmentId: "cable_machine", reporterUid: "someone_else" },
        { uid: "u1" },
      ),
    );
    const [written] = adminMock.__getRef("equipment_reports/r1").set.mock.calls[0];
    expect(written.reporterUid).toBe("u1");
    expect(written.status).toBe("open");
    expect(written.gymId).toBe("unknown");
    expect(written.fault).toBe("other");
  });

  it("posts to a gym's webhook when one is registered", async () => {
    const fetchMock = jest.fn().mockResolvedValue({ ok: true });
    global.fetch = fetchMock as any;
    primeDoc("gyms/g1", { maintenanceWebhookUrl: "https://gym.example/hook" });
    await reportEquipment.run(
      req(
        { id: "r2", equipmentId: "leg_press", gymId: "g1", fault: "broken" },
        { uid: "u1" },
      ),
    );
    expect(fetchMock).toHaveBeenCalledTimes(1);
    const [url, init] = fetchMock.mock.calls[0];
    expect(url).toBe("https://gym.example/hook");
    expect(JSON.parse(init.body).equipmentId).toBe("leg_press");
    // Bounded on purpose: one gym whose endpoint accepts and never answers
    // would otherwise hold the instance until the platform kills it, with the
    // user watching a spinner and nobody else able to file a report.
    expect(init.signal).toBeDefined();
  });

  it("does not call out when the gym registered no webhook", async () => {
    const fetchMock = jest.fn();
    global.fetch = fetchMock as any;
    primeDoc("gyms/g1", {});
    await reportEquipment.run(
      req({ id: "r3", equipmentId: "leg_press", gymId: "g1" }, { uid: "u1" }),
    );
    expect(fetchMock).not.toHaveBeenCalled();
  });

  it("still stores the report when the gym's endpoint fails", async () => {
    // The ordering is the whole point: the write happens first, so a dead
    // third-party endpoint cannot cost the user their report. Swallowing the
    // error is only defensible because of that, and this is what pins it.
    global.fetch = jest.fn().mockRejectedValue(new Error("gym is down")) as any;
    primeDoc("gyms/g1", { maintenanceWebhookUrl: "https://gym.example/hook" });
    await expect(
      reportEquipment.run(
        req({ id: "r4", equipmentId: "leg_press", gymId: "g1" }, { uid: "u1" }),
      ),
    ).resolves.toBeDefined();
    expect(adminMock.__getRef("equipment_reports/r4").set).toHaveBeenCalled();
  });

  /*
   * N-04. This callable had no quota, took its document id from the client and
   * wrote it with `set()`, accepted an unbounded note, and relayed that note
   * verbatim into a webhook belonging to a gym the client also named. The
   * Admin SDK bypasses firestore.rules, so the `if false` on
   * `equipment_reports` protected none of it.
   */
  it("refuses a note longer than the bound, rather than truncating it", async () => {
    global.fetch = jest.fn() as any;
    await expectHttpsError(
      reportEquipment.run(
        req(
          { id: "n1", equipmentId: "bench", note: "x".repeat(501) },
          { uid: "u1" },
        ),
      ),
      "invalid-argument",
    );
    // Refused, not stored short. Silently keeping half of what someone typed
    // is a data bug wearing a limit's clothes.
    expect(adminMock.__getRef("equipment_reports/n1").set).not.toHaveBeenCalled();
  });

  it("refuses a non-string note instead of stringifying it", async () => {
    global.fetch = jest.fn() as any;
    await expectHttpsError(
      reportEquipment.run(
        req({ id: "n2", equipmentId: "bench", note: { a: 1 } }, { uid: "u1" }),
      ),
      "invalid-argument",
    );
  });

  it("refuses an id containing a path separator", async () => {
    // `equipment_reports/${id}` with a slash writes into an arbitrary
    // subcollection under the prefix.
    global.fetch = jest.fn() as any;
    await expectHttpsError(
      reportEquipment.run(
        req({ id: "a/b/c", equipmentId: "bench" }, { uid: "u1" }),
      ),
      "invalid-argument",
    );
  });

  it("will not let one user overwrite another user's report", async () => {
    global.fetch = jest.fn() as any;
    primeDoc("equipment_reports/shared", { reporterUid: "someone_else" });
    await expectHttpsError(
      reportEquipment.run(
        req({ id: "shared", equipmentId: "bench" }, { uid: "u1" }),
      ),
      "already-exists",
    );
    expect(adminMock.__getRef("equipment_reports/shared").set)
      .not.toHaveBeenCalled();
  });

  it("still lets the same reporter re-file the same report", async () => {
    // The client generates the id so an offline retry does not file twice.
    // That has to keep working, or the overwrite guard has broken the feature
    // it was protecting.
    global.fetch = jest.fn() as any;
    primeDoc("equipment_reports/mine", { reporterUid: "u1" });
    await expect(
      reportEquipment.run(
        req({ id: "mine", equipmentId: "bench" }, { uid: "u1" }),
      ),
    ).resolves.toBeDefined();
  });

  it("strips newlines from the note before relaying it to a gym", async () => {
    // The note lands in a Slack-shaped `text` alongside lines the platform
    // writes itself, so a newline lets an attacker forge those lines.
    const fetchMock = jest.fn().mockResolvedValue({ ok: true });
    global.fetch = fetchMock as any;
    primeDoc("gyms/g9", { maintenanceWebhookUrl: "https://gym.example/hook" });
    await reportEquipment.run(
      req(
        {
          id: "r9",
          equipmentId: "bench",
          gymId: "g9",
          note: "broken\nReporter: admin",
        },
        { uid: "u1" },
      ),
    );
    const body = JSON.parse(fetchMock.mock.calls[0][1].body);
    expect(body.text).toContain("broken Reporter: admin");
    expect(body.text).not.toContain("broken\nReporter: admin");
  });

  it("is rate-limited per caller", async () => {
    global.fetch = jest.fn() as any;
    // The shared doc-ref fake does not read back what it was written, and the
    // quota is a read-modify-write — so the counter has to accumulate for this
    // assertion to mean anything. Wired here rather than in the shared fake,
    // because other cases rely on `set` being inert.
    const day = new Date().toISOString().slice(0, 10);
    const usage = adminMock.__getRef(`users/u1/usage/${day}`);
    let stored: Record<string, unknown> = {};
    usage.get.mockImplementation(async () => ({
      exists: true,
      data: () => stored,
    }));
    usage.set.mockImplementation(async (data: Record<string, unknown>) => {
      stored = { ...stored, ...data };
    });

    for (let i = 0; i < QUOTAS.equipmentReport; i++) {
      await reportEquipment.run(
        req({ id: `q${i}`, equipmentId: "bench" }, { uid: "u1" }),
      );
    }
    expect(stored.equipmentReport).toBe(QUOTAS.equipmentReport);

    await expectHttpsError(
      reportEquipment.run(
        req({ id: "over", equipmentId: "bench" }, { uid: "u1" }),
      ),
      "resource-exhausted",
    );
    // And the refused call wrote nothing.
    expect(adminMock.__getRef("equipment_reports/over").set)
      .not.toHaveBeenCalled();
  });
});
