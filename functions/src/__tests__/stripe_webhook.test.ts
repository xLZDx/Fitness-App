/**
 * The webhook, which had no test at all.
 *
 * `index.test.ts` covers `startFreeTrial`, `createCheckoutSession`,
 * `generateAnnualReceipt` and `bookCoachSession`. The one entrypoint whose
 * failure takes money and gives nothing back had none, which is how it shipped
 * reading four price secrets it was never granted.
 */
const refs = new Map<string, any>();
const getRef = (path: string): any => {
  let ref = refs.get(path);
  if (!ref) {
    let stored: any = undefined;
    ref = {
      path,
      get: jest.fn(async () => ({
        exists: stored !== undefined,
        data: () => stored,
      })),
      set: jest.fn(async (data: any, opts?: any) => {
        stored = opts?.merge ? { ...(stored ?? {}), ...data } : data;
      }),
      delete: jest.fn(async () => {
        stored = undefined;
      }),
      __read: () => stored,
    };
    refs.set(path, ref);
  }
  return ref;
};

jest.mock("firebase-admin", () => {
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
  return { initializeApp: jest.fn(), firestore: firestoreFn };
});

const constructEvent = jest.fn();
jest.mock("stripe", () => {
  const instance = {
    webhooks: { constructEvent },
    // P1e reconciles duplicates on every subscription event, so the mock has
    // to answer `list` and record `cancel` or the handler cannot be observed.
    subscriptions: {
      retrieve: jest.fn(),
      list: jest.fn(async () => ({ data: [], has_more: false })),
      cancel: jest.fn(async () => ({})),
    },
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

import { stripeWebhook } from "../index";

const SUB_DOC = "users/u1/subscription/main";

/** A subscription event as Stripe delivers it. */
const subscriptionEvent = (opts: {
  created: number;
  status: string;
  priceId: string;
  period?: string;
}) => ({
  type: "customer.subscription.updated",
  created: opts.created,
  data: {
    object: {
      id: "sub_1",
      status: opts.status,
      customer: "cus_1",
      current_period_end: 1800000000,
      trial_end: null,
      metadata: { firebaseUid: "u1", period: opts.period ?? "monthly" },
      items: { data: [{ price: { id: opts.priceId } }] },
    },
  },
});

/** `onRequest` hands the handler an express req/res pair. */
const deliver = async (event: unknown) => {
  constructEvent.mockReturnValue(event);
  const res: any = {
    status: jest.fn(() => res),
    send: jest.fn(() => res),
  };
  // `onRequest` returns the express handler itself -- unlike `onCall`, which
  // wraps its body in `.run`.
  await (stripeWebhook as unknown as (req: any, res: any) => Promise<void>)(
    { headers: { "stripe-signature": "sig" }, rawBody: Buffer.from("{}") },
    res,
  );
  return res;
};

beforeEach(() => {
  refs.clear();
  jest.clearAllMocks();
});

describe("the price secrets the webhook is granted", () => {
  test("cover every price the tier mapping reads", () => {
    // The invariant, and the only one a unit test can hold: the two lists are
    // in different places and nothing but this keeps them in step. When they
    // drifted, an unbound secret resolved to "" rather than throwing, `known()`
    // discarded the blank, and every annual and family subscriber was written
    // back as `free` -- on purchase and again on every renewal.
    const endpoint = (stripeWebhook as any).__endpoint;
    const granted: string[] = endpoint.secretEnvironmentVariables.map(
      (s: { key: string }) => s.key,
    );
    for (const secret of [
      "STRIPE_PRICE_STANDARD",
      "STRIPE_PRICE_STANDARD_ANNUAL",
      "STRIPE_PRICE_STANDARD_FAMILY2",
      "STRIPE_PRICE_STANDARD_FAMILY4",
      "STRIPE_PRICE_CELEBRITY",
      "STRIPE_PRICE_CELEBRITY_ANNUAL",
    ]) {
      expect(granted).toContain(secret);
    }
  });
});

describe("tier resolution end to end", () => {
  test("an annual subscriber is written as standard, not free", async () => {
    // jest.setup.js sets STRIPE_PRICE_STANDARD_ANNUAL. Before the secret was
    // bound this same event produced tier "free" in production while passing
    // every test, because the tests read the env directly.
    await deliver(
      subscriptionEvent({
        created: 1000,
        status: "active",
        priceId: process.env.STRIPE_PRICE_STANDARD_ANNUAL!,
        period: "annual",
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      tier: "standard",
      status: "active",
      period: "annual",
    });
  });

  test("a family price resolves and carries its seat count", async () => {
    await deliver(
      subscriptionEvent({
        created: 1000,
        status: "active",
        priceId: process.env.STRIPE_PRICE_STANDARD_FAMILY4!,
        period: "family4",
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      tier: "standard",
      seatCount: 4,
    });
  });

  test("an unknown price still falls back to free", async () => {
    // Failing closed is correct and stays. The bug was never this branch, it
    // was arriving here with a price that should have matched.
    await deliver(
      subscriptionEvent({
        created: 1000,
        status: "active",
        priceId: "price_never_seen",
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({ tier: "free" });
  });
});

describe("delivery order", () => {
  test("a cancellation is not undone by a delayed earlier event", async () => {
    // The failure this prevents: Stripe does not guarantee order, and the
    // write overwrites `status` unconditionally, so an `active` event
    // delivered late restored premium to a cancelled account permanently --
    // nothing re-reconciles it.
    await deliver(
      subscriptionEvent({
        created: 2000,
        status: "canceled",
        priceId: process.env.STRIPE_PRICE_STANDARD!,
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "cancelled" });

    await deliver(
      subscriptionEvent({
        created: 1000,
        status: "active",
        priceId: process.env.STRIPE_PRICE_STANDARD!,
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "cancelled" });
  });

  test("a newer event still applies", async () => {
    await deliver(
      subscriptionEvent({
        created: 1000,
        status: "active",
        priceId: process.env.STRIPE_PRICE_STANDARD!,
      }),
    );
    await deliver(
      subscriptionEvent({
        created: 2000,
        status: "canceled",
        priceId: process.env.STRIPE_PRICE_STANDARD!,
      }),
    );
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "cancelled" });
  });

  test("a redelivery of the same event is applied, not rejected", async () => {
    // Equal timestamps must pass: Stripe redelivers on any non-2xx, and every
    // write is deterministic from the event body, so a replay rewriting the
    // same fields is harmless. Rejecting it would turn a retry into a
    // permanently missed update.
    const event = subscriptionEvent({
      created: 1000,
      status: "active",
      priceId: process.env.STRIPE_PRICE_STANDARD!,
    });
    await deliver(event);
    getRef(SUB_DOC).set({ tier: "scribbled" }, { merge: true });
    await deliver(event);
    expect(getRef(SUB_DOC).__read()).toMatchObject({ tier: "standard" });
  });

  test("the ordering clock is persisted, not held in memory", async () => {
    // A cold start between two events must not lose the comparison.
    await deliver(
      subscriptionEvent({
        created: 5000,
        status: "active",
        priceId: process.env.STRIPE_PRICE_STANDARD!,
      }),
    );
    expect(getRef(SUB_DOC).__read().lastStripeEventCreated).toBe(5000);
  });
});

describe("signature verification", () => {
  test("a bad signature is rejected before anything is written", async () => {
    constructEvent.mockImplementation(() => {
      throw new Error("no");
    });
    const res: any = { status: jest.fn(() => res), send: jest.fn(() => res) };
    await (stripeWebhook as unknown as (req: any, res: any) => Promise<void>)(
      { headers: { "stripe-signature": "sig" }, rawBody: Buffer.from("{}") },
      res,
    );
    expect(res.status).toHaveBeenCalledWith(400);
    expect(refs.has(SUB_DOC)).toBe(false);
  });
});

/* ------------------------------------------------------------------ */
/* P1e -- duplicate subscription reconciliation                       */
/* ------------------------------------------------------------------ */

describe("duplicate subscriptions", () => {
  const stripeMock = (jest.requireMock("stripe") as any).__instance;

  /** A subscription as `subscriptions.list` returns it. */
  const live = (id: string, created: number, extra: object = {}) => ({
    id,
    created,
    status: "active",
    customer: "cus_1",
    cancel_at_period_end: false,
    ...extra,
  });

  const listReturns = (subs: object[]) =>
    stripeMock.subscriptions.list.mockResolvedValue({
      data: subs,
      has_more: false,
    });

  const anEvent = () =>
    subscriptionEvent({ created: 1700000000, status: "active", priceId: "price_standard_monthly" });

  test("a single subscription is left alone", async () => {
    listReturns([live("sub_1", 100)]);
    await deliver(anEvent());
    expect(stripeMock.subscriptions.cancel).not.toHaveBeenCalled();
  });

  test("the oldest survives and the newer duplicate is cancelled", async () => {
    // The oldest is what the customer believes they bought. Cancelling it
    // would end the plan they have been using and leave one they never
    // knowingly started.
    listReturns([live("sub_new", 200), live("sub_old", 100)]);

    await deliver(anEvent());

    expect(stripeMock.subscriptions.cancel).toHaveBeenCalledTimes(1);
    expect(stripeMock.subscriptions.cancel).toHaveBeenCalledWith("sub_new", {
      prorate: true,
    });
  });

  test("three duplicates leave exactly one", async () => {
    listReturns([live("sub_c", 300), live("sub_a", 100), live("sub_b", 200)]);

    await deliver(anEvent());

    const cancelled = stripeMock.subscriptions.cancel.mock.calls.map(
      (c: unknown[]) => c[0],
    );
    expect(cancelled.sort()).toEqual(["sub_b", "sub_c"]);
  });

  test("one failed cancel does not stop the others", async () => {
    // A customer with three duplicates must end up with one, not two.
    listReturns([live("sub_c", 300), live("sub_a", 100), live("sub_b", 200)]);
    stripeMock.subscriptions.cancel
      .mockRejectedValueOnce(new Error("stripe down"))
      .mockResolvedValue({});

    await deliver(anEvent());

    expect(stripeMock.subscriptions.cancel).toHaveBeenCalledTimes(2);
  });

  test("subscriptions already ending are not touched", async () => {
    // The customer has already asked for that; re-cancelling is a no-op that
    // muddies the audit trail.
    listReturns([
      live("sub_old", 100),
      live("sub_leaving", 200, { cancel_at_period_end: true }),
    ]);

    await deliver(anEvent());

    expect(stripeMock.subscriptions.cancel).not.toHaveBeenCalled();
  });

  test("non-billing statuses are not duplicates", async () => {
    listReturns([
      live("sub_old", 100),
      live("sub_dead", 200, { status: "canceled" }),
      live("sub_gone", 300, { status: "incomplete_expired" }),
    ]);

    await deliver(anEvent());

    expect(stripeMock.subscriptions.cancel).not.toHaveBeenCalled();
  });

  test("a reconciliation failure still returns 200 to Stripe", async () => {
    // This runs inside the webhook. A non-2xx makes Stripe retry the whole
    // event, replaying applySubscription forever over a problem that is not
    // the entitlement write.
    stripeMock.subscriptions.list.mockRejectedValue(new Error("stripe down"));

    const res = await deliver(anEvent());

    expect(res.status).not.toHaveBeenCalledWith(500);
  });
});
