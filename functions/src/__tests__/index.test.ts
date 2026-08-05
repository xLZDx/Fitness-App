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
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    __getRef: getRef,
    __reset: () => refs.clear(),
  };
});

jest.mock("stripe", () => {
  const instance = {
    customers: { create: jest.fn() },
    checkout: { sessions: { create: jest.fn() } },
    invoices: { list: jest.fn() },
    paymentIntents: { create: jest.fn() },
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
import {
  startFreeTrial,
  createCheckoutSession,
  generateAnnualReceipt,
  bookCoachSession,
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
  stripeMock.invoices.list.mockReset();
  stripeMock.paymentIntents.create.mockReset();
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
    });
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
          lines: { data: [{ description: "Standard plan donation" }] },
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
      donorName: "Ivan Tester",
      donorUid: "u1",
      orgName: "Fitness App (501(c)(3) pending)",
    });
    expect(res.items).toEqual([
      {
        created: "2025-01-01T00:00:00.000Z",
        amountCents: 999,
        currency: "usd",
        number: "INV-001",
        description: "Standard plan donation",
      },
      {
        created: "2025-06-15T00:00:00.000Z",
        amountCents: 501,
        currency: "usd",
        number: null,
        description: "Recurring donation",
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
      donorName: "u1@example.com",
      donorUid: "u1",
      orgName: "Fitness App (501(c)(3) pending)",
      notice: "No donations were recorded under your account in this year.",
    });
    expect(stripeCtor).not.toHaveBeenCalled();
    expect(stripeMock.invoices.list).not.toHaveBeenCalled();
    // Current behavior: the zero-receipt path does NOT persist a copy.
    expect(adminMock.__getRef(RECEIPT_PATH).set).not.toHaveBeenCalled();
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
