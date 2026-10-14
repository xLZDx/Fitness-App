/**
 * Webhook paths `stripe_webhook.test.ts` does not reach: the money-moving
 * `payment_intent.succeeded` branches (lifetime purchase, coach booking
 * confirmation), the invoice refresh path, the transport-level refusals, and
 * the 500-so-Stripe-retries contract.
 *
 * Each assertion names an outcome that changes if the guarded branch breaks:
 * a lifetime buyer left on free, a paid booking left pending, a failed write
 * answered with 200 (so Stripe never retries and the payment is lost), or a
 * stale invoice event restoring premium to a cancelled account.
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
      update: jest.fn(async (data: any) => {
        if (stored === undefined) {
          throw Object.assign(new Error("NOT_FOUND"), { code: 5 });
        }
        stored = { ...stored, ...data };
      }),
      __read: () => stored,
    };
    refs.set(path, ref);
  }
  return ref;
};

const getUser = jest.fn(async (_uid?: string) => ({}));

jest.mock("firebase-admin", () => {
  const runTransaction = jest.fn(async (fn: (tx: any) => Promise<any>) =>
    fn({
      get: (ref: any) => ref.get(),
      set: (ref: any, data: any, opts?: any) => ref.set(data, opts),
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
    auth: jest.fn(() => ({ getUser })),
  };
});

const constructEvent = jest.fn();
jest.mock("stripe", () => {
  const instance = {
    webhooks: { constructEvent },
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

import * as logger from "firebase-functions/logger";
import { stripeWebhook } from "../index";

const stripeMock = (jest.requireMock("stripe") as any).__instance;
const SUB_DOC = "users/u1/subscription/main";

type Handler = (req: any, res: any) => Promise<void>;
const makeRes = (): any => {
  const res: any = {
    status: jest.fn(() => res),
    send: jest.fn(() => res),
  };
  return res;
};

const deliver = async (event: unknown, headers: any = { "stripe-signature": "sig" }) => {
  constructEvent.mockReturnValue(event);
  const res = makeRes();
  await (stripeWebhook as unknown as Handler)(
    { headers, rawBody: Buffer.from("{}") },
    res,
  );
  return res;
};

const subscriptionObject = (
  status: string,
  extra: { metadata?: any } = {},
): any => ({
  id: "sub_1",
  status,
  customer: "cus_1",
  current_period_end: 1800000000,
  trial_end: null,
  metadata: extra.metadata ?? { firebaseUid: "u1", period: "monthly" },
  items: { data: [{ price: { id: process.env.STRIPE_PRICE_STANDARD! } }] },
});

const invoiceEvent = (type: string, created: number, withSub = true) => ({
  type,
  created,
  data: {
    object: withSub ? { id: "in_1", subscription: "sub_1" } : { id: "in_2" },
  },
});

beforeEach(() => {
  refs.clear();
  jest.clearAllMocks();
  getUser.mockReset().mockResolvedValue({});
  stripeMock.subscriptions.list.mockResolvedValue({ data: [], has_more: false });
  // `clearAllMocks` keeps implementations, so a `retrieve` result set by one
  // test used to leak into the next. A same-second tie now calls `retrieve`
  // from the subscription-event path, so the leak would decide outcomes.
  stripeMock.subscriptions.retrieve.mockReset();
});

describe("transport-level refusals", () => {
  test("a request with no stripe-signature header is refused and never verified", async () => {
    const res = await deliver({ type: "x" }, {});
    expect(res.status).toHaveBeenCalledWith(400);
    expect(constructEvent).not.toHaveBeenCalled();
    expect(refs.size).toBe(0);
  });

  test("an event type the app does not handle is acknowledged and writes nothing", async () => {
    // Anything but 200 makes Stripe retry an event we will never act on.
    const res = await deliver({ type: "charge.dispute.created", created: 1, data: { object: {} } });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.size).toBe(0);
  });
});

describe("a failed handler answers 500 so Stripe redelivers", () => {
  test("a Stripe lookup failure on invoice.paid is a 500, with nothing written", async () => {
    stripeMock.subscriptions.retrieve.mockRejectedValue(new Error("stripe 503"));
    const res = await deliver(invoiceEvent("invoice.paid", 1000));
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.status).not.toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
  });

  test("a Firestore failure while granting a lifetime purchase is a 500, not a lost 200", async () => {
    getRef(SUB_DOC).set.mockRejectedValueOnce(new Error("firestore unavailable"));
    const res = await deliver({
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_1",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    });
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.status).not.toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toBeUndefined();
  });
});

describe("payment_intent.succeeded: lifetime purchase", () => {
  const lifetime = (metadata: any) => ({
    type: "payment_intent.succeeded",
    created: 1000,
    data: { object: { id: "pi_life", customer: "cus_1", metadata } },
  });

  test("grants the purchased tier forever, marked lifetime", async () => {
    const res = await deliver(
      lifetime({ firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" }),
    );
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      tier: "celebrityTrainer",
      status: "active",
      period: "lifetime",
      isLifetime: true,
      seatCount: 1,
      currentPeriodEndsAt: "9999-12-31T23:59:59.000Z",
      trialEndsAt: null,
      stripeCustomerId: "cus_1",
      stripePaymentIntentId: "pi_life",
    });
  });

  test("a redelivery converges on the same document", async () => {
    const event = lifetime({ firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" });
    await deliver(event);
    const first = { ...getRef(SUB_DOC).__read() };
    const res = await deliver(event);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toEqual(first);
  });

  test("a payment naming no tier grants nothing, and says so in the log", async () => {
    const res = await deliver(lifetime({ firebaseUid: "u1", period: "lifetime" }));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(logger.error).toHaveBeenCalledWith(
      "lifetime payment without uid/tier",
      expect.objectContaining({ paymentIntentId: "pi_life" }),
    );
  });

  test("a payment naming no user grants nothing", async () => {
    await deliver(lifetime({ tier: "celebrityTrainer", period: "lifetime" }));
    expect(refs.size).toBe(0);
  });
});

describe("payment_intent.succeeded: coach booking confirmation", () => {
  const booking = (metadata: any) => ({
    type: "payment_intent.succeeded",
    created: 1000,
    data: { object: { id: "pi_bk", metadata } },
  });

  test("confirms the booking and keeps every other field on it", async () => {
    await getRef("coach_bookings/bk_1").set({
      clientUid: "c1",
      coachUid: "k1",
      status: "pending",
      stripePaymentIntentId: "pi_bk",
    });
    const res = await deliver(booking({ kind: "coach_booking", bookingId: "bk_1" }));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef("coach_bookings/bk_1").__read()).toEqual({
      clientUid: "c1",
      coachUid: "k1",
      status: "confirmed",
      stripePaymentIntentId: "pi_bk",
      confirmedAt: "__SERVER_TIMESTAMP__",
    });
  });

  test("a booking intent with no booking id writes nothing and logs a named error", async () => {
    const res = await deliver(booking({ kind: "coach_booking" }));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.size).toBe(0);
    expect(logger.error).toHaveBeenCalledWith(
      "webhook_booking_confirm_missing_booking_id",
      expect.objectContaining({ paymentIntentId: "pi_bk" }),
    );
  });

  test("a missing booking doc is not recreated as a stub; named error, still 200", async () => {
    const res = await deliver(booking({ kind: "coach_booking", bookingId: "bk_gone" }));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef("coach_bookings/bk_gone").__read()).toBeUndefined();
    expect(logger.error).toHaveBeenCalledWith(
      "webhook_booking_confirm_booking_doc_missing",
      expect.objectContaining({ bookingId: "bk_gone" }),
    );
  });

  test("a non-NOT_FOUND failure confirming the booking is a 500 so Stripe retries", async () => {
    getRef("coach_bookings/bk_1").update.mockRejectedValueOnce(
      Object.assign(new Error("unavailable"), { code: 14 }),
    );
    const res = await deliver(booking({ kind: "coach_booking", bookingId: "bk_1" }));
    expect(res.status).toHaveBeenCalledWith(500);
  });

  test("an unrelated payment intent confirms no booking and grants nothing", async () => {
    const res = await deliver(booking({ bookingId: "bk_1", firebaseUid: "u1" }));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.size).toBe(0);
  });
});

describe("invoice events refresh the subscription from Stripe", () => {
  test("invoice.paid re-reads the subscription and applies it with the event clock", async () => {
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("active"));
    const res = await deliver(invoiceEvent("invoice.paid", 4000));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).toHaveBeenCalledWith("sub_1");
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "active",
      tier: "standard",
      lastStripeEventCreated: 4000,
    });
  });

  test("invoice.payment_failed on a past_due subscription removes access", async () => {
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("past_due"));
    await deliver(invoiceEvent("invoice.payment_failed", 4000));
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "expired" });
  });

  test("an invoice with no subscription (a one-off charge) touches nothing", async () => {
    const res = await deliver(invoiceEvent("invoice.paid", 4000, false));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(refs.size).toBe(0);
  });

  test("a stale invoice event cannot resurrect a cancelled subscription", async () => {
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("canceled"));
    await deliver(invoiceEvent("invoice.paid", 9000));
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "cancelled" });

    // A delayed earlier invoice event whose re-read still says "active".
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("active"));
    const res = await deliver(invoiceEvent("invoice.paid", 100));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "cancelled",
      lastStripeEventCreated: 9000,
    });
  });
});

describe("events for a deleted account never recreate user data", () => {
  const gone = () =>
    getUser.mockRejectedValue(
      Object.assign(new Error("no user"), { code: "auth/user-not-found" }),
    );
  const named = "webhook_event_for_deleted_account";

  test("a subscription event is acknowledged with a named log and writes nothing", async () => {
    gone();
    const res = await deliver({
      type: "customer.subscription.updated",
      created: 1000,
      data: { object: subscriptionObject("active") },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(logger.warn).toHaveBeenCalledWith(named, expect.objectContaining({ uid: "u1" }));
  });

  test("invoice.paid is acknowledged and writes nothing", async () => {
    gone();
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("active"));
    const res = await deliver(invoiceEvent("invoice.paid", 4000));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
  });

  test("a lifetime payment is acknowledged and grants nothing", async () => {
    gone();
    const res = await deliver({
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_life",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(logger.warn).toHaveBeenCalledWith(named, expect.objectContaining({ uid: "u1" }));
  });

  test("any other Auth lookup failure is a 500 so Stripe retries, with nothing written", async () => {
    getUser.mockRejectedValue(Object.assign(new Error("auth down"), { code: "auth/internal-error" }));
    const res = await deliver({
      type: "customer.subscription.updated",
      created: 1000,
      data: { object: subscriptionObject("active") },
    });
    expect(res.status).toHaveBeenCalledWith(500);
    expect(refs.has(SUB_DOC)).toBe(false);
  });

  test("an existing account is still written", async () => {
    const res = await deliver({
      type: "customer.subscription.updated",
      created: 1000,
      data: { object: subscriptionObject("active") },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getUser).toHaveBeenCalledWith("u1");
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "active" });
  });
});

describe("a subscription event that cannot be attributed", () => {
  test("without a firebaseUid it is logged, acknowledged, and writes no user document", async () => {
    const res = await deliver({
      type: "customer.subscription.updated",
      created: 1000,
      data: { object: subscriptionObject("active", { metadata: {} }) },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(logger.error).toHaveBeenCalledWith(
      "subscription event without firebaseUid",
      expect.objectContaining({ subscriptionId: "sub_1" }),
    );
  });
});

describe("a write that races the Auth deletion does not survive", () => {
  const notFound = () =>
    Object.assign(new Error("no user"), { code: "auth/user-not-found" });
  // The shared ref mock has no delete(); give this document one that removes it.
  const armDelete = () => {
    const del = jest.fn(async () => {
      refs.delete(SUB_DOC);
    });
    getRef(SUB_DOC).delete = del;
    return del;
  };
  const subEvent = {
    type: "customer.subscription.deleted",
    created: 1000,
    data: { object: subscriptionObject("canceled") },
  };

  test("user exists before the write and is gone after it: the written document is deleted", async () => {
    getUser.mockResolvedValueOnce({}).mockRejectedValue(notFound());
    const del = armDelete();
    const res = await deliver(subEvent);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getUser).toHaveBeenCalledTimes(2);
    expect(del).toHaveBeenCalledTimes(1);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(logger.warn).toHaveBeenCalledWith(
      "webhook_write_for_deleted_account_removed",
      expect.objectContaining({ uid: "u1" }),
    );
    // The recheck itself must not emit the "ignored" event.
    expect(logger.warn).not.toHaveBeenCalledWith(
      "webhook_event_for_deleted_account",
      expect.anything(),
    );
  });

  test("a lifetime payment that raced the deletion is deleted too", async () => {
    getUser.mockResolvedValueOnce({}).mockRejectedValue(notFound());
    const del = armDelete();
    const res = await deliver({
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_life",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    expect(del).toHaveBeenCalledTimes(1);
    expect(refs.has(SUB_DOC)).toBe(false);
  });

  test("user exists both times: the document is kept", async () => {
    const del = armDelete();
    const res = await deliver(subEvent);
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getUser).toHaveBeenCalledTimes(2);
    expect(del).not.toHaveBeenCalled();
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "cancelled" });
  });

  test("a non-not-found lookup error on the recheck is a 500 so Stripe retries", async () => {
    getUser
      .mockResolvedValueOnce({})
      .mockRejectedValue(Object.assign(new Error("auth down"), { code: "auth/internal-error" }));
    const del = armDelete();
    const res = await deliver(subEvent);
    expect(res.status).toHaveBeenCalledWith(500);
    expect(del).not.toHaveBeenCalled();
  });
});

describe("deleted-account guard: remaining event paths", () => {
  const gone = () =>
    getUser.mockRejectedValue(
      Object.assign(new Error("no user"), { code: "auth/user-not-found" }),
    );
  const userRefs = () => [...refs.keys()].filter((p) => p.startsWith("users/"));

  test("a coach booking confirmation for a deleted client creates no users/* document", async () => {
    gone();
    await getRef("coach_bookings/bk_1").set({
      clientUid: "u1",
      coachUid: "k1",
      status: "pending",
    });
    const res = await deliver({
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_bk",
          metadata: { kind: "coach_booking", bookingId: "bk_1", firebaseUid: "u1" },
        },
      },
    });
    expect(res.status).toHaveBeenCalledWith(200);
    // The booking is a shared coach_bookings row (not user-owned data), so it is
    // confirmed in place; what must never happen is a ghost users/{uid} write.
    expect(userRefs()).toEqual([]);
    expect(getRef("coach_bookings/bk_1").__read()).toMatchObject({
      clientUid: "u1",
      status: "confirmed",
    });
  });

  test("invoice.payment_failed for a deleted account is acknowledged and writes nothing", async () => {
    gone();
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("past_due"));
    const res = await deliver(invoiceEvent("invoice.payment_failed", 4000));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(userRefs()).toEqual([]);
    expect(logger.warn).toHaveBeenCalledWith(
      "webhook_event_for_deleted_account",
      expect.objectContaining({ uid: "u1" }),
    );
  });

  test("an Auth lookup error other than user-not-found on a lifetime payment is a 500 with nothing written", async () => {
    getUser.mockRejectedValue(
      Object.assign(new Error("auth down"), { code: "auth/internal-error" }),
    );
    const res = await deliver({
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_life",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    });
    expect(res.status).toHaveBeenCalledWith(500);
    expect(res.status).not.toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);
    expect(userRefs()).toEqual([]);
  });
});

describe("webhook replay journey: redelivery of the same event converges on one document", () => {
  const notFound = () =>
    Object.assign(new Error("no user"), { code: "auth/user-not-found" });
  const authDown = () =>
    Object.assign(new Error("auth down"), { code: "auth/internal-error" });
  const subEvent = (created: number, status: string) => ({
    id: `evt_${created}_${status}`,
    type: "customer.subscription.updated",
    created,
    data: { object: subscriptionObject(status) },
  });
  const userRefs = () => [...refs.keys()].filter((p) => p.startsWith("users/"));

  test("a write that landed but whose recheck failed (500) is replayed to the same single document", async () => {
    const event = subEvent(2000, "active");
    // First lookup (pre-write guard) succeeds, the post-write recheck fails.
    getUser.mockResolvedValueOnce({}).mockRejectedValueOnce(authDown());

    const first = await deliver(event);
    expect(first.status).toHaveBeenCalledWith(500);
    const afterPartial = { ...getRef(SUB_DOC).__read() };
    expect(afterPartial).toMatchObject({ status: "active", lastStripeEventCreated: 2000 });

    // Stripe redelivers the same event id: lookups now succeed. The redelivery
    // is a same-second tie (OLD behaviour: plain re-apply), so it re-reads the
    // subscription; Stripe's current state is the one the event described.
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("active"));
    const second = await deliver(event);
    expect(second.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toEqual(afterPartial);
    expect(userRefs()).toEqual([SUB_DOC]);

    // A third delivery after success is a no-op as well.
    const third = await deliver(event);
    expect(third.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toEqual(afterPartial);
  });

  test("a lifetime write that failed outright (500, nothing stored) is completed by the redelivery", async () => {
    // The transaction mock does not await tx.set, so the outright-failure case
    // is exercised through the direct-write lifetime path.
    const event = {
      id: "evt_life",
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_life",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    };
    getRef(SUB_DOC).set.mockRejectedValueOnce(new Error("firestore unavailable"));

    const first = await deliver(event);
    expect(first.status).toHaveBeenCalledWith(500);
    expect(getRef(SUB_DOC).__read()).toBeUndefined();

    const second = await deliver(event);
    expect(second.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      tier: "celebrityTrainer",
      status: "active",
      isLifetime: true,
      stripeCustomerId: "cus_1",
      stripePaymentIntentId: "pi_life",
    });
    expect(userRefs()).toEqual([SUB_DOC]);
  });

  test("an older event delivered after a newer one is ignored by the event-order guard, also when replayed", async () => {
    await deliver(subEvent(3000, "canceled"));
    const settled = { ...getRef(SUB_DOC).__read() };
    expect(settled).toMatchObject({ status: "cancelled", lastStripeEventCreated: 3000 });

    const older = await deliver(subEvent(2000, "active"));
    const olderReplay = await deliver(subEvent(2000, "active"));

    expect(older.status).toHaveBeenCalledWith(200);
    expect(olderReplay.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toEqual(settled);
    expect(logger.info).toHaveBeenCalledWith(
      "ignoring out-of-order stripe event",
      expect.objectContaining({ eventCreated: 2000, alreadyApplied: 3000 }),
    );
  });

  test("the same event id redelivered after deletion answers 200 and writes nothing, even after a raced write was removed", async () => {
    const event = subEvent(2000, "active");
    // First delivery races the deletion: the user is there before the write, gone after.
    getUser.mockResolvedValueOnce({}).mockRejectedValue(notFound());
    getRef(SUB_DOC).delete = jest.fn(async () => {
      refs.delete(SUB_DOC);
    });

    const first = await deliver(event);
    expect(first.status).toHaveBeenCalledWith(200);
    expect(refs.has(SUB_DOC)).toBe(false);

    const replay = await deliver(event);
    expect(replay.status).toHaveBeenCalledWith(200);
    expect(userRefs()).toEqual([]);
    expect(logger.warn).toHaveBeenCalledWith(
      "webhook_event_for_deleted_account",
      expect.objectContaining({ uid: "u1" }),
    );
  });

  test("a lifetime payment replayed after the account was deleted grants nothing", async () => {
    getUser.mockRejectedValue(notFound());
    const event = {
      id: "evt_life",
      type: "payment_intent.succeeded",
      created: 1000,
      data: {
        object: {
          id: "pi_life",
          customer: "cus_1",
          metadata: { firebaseUid: "u1", tier: "celebrityTrainer", period: "lifetime" },
        },
      },
    };
    await deliver(event);
    const replay = await deliver(event);
    expect(replay.status).toHaveBeenCalledWith(200);
    expect(userRefs()).toEqual([]);
  });
});

describe("same-second event ties are settled by re-reading the subscription (F13)", () => {
  const subEvent = (created: number, status: string, id = "sub_1") => ({
    id: `evt_${created}_${status}`,
    type: "customer.subscription.updated",
    created,
    data: { object: { ...subscriptionObject(status), id } },
  });
  /** Lands the first event of the second `created`, so the next one can tie or not. */
  const seed2000 = async () => {
    const res = await deliver(subEvent(2000, "trialing"));
    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({ lastStripeEventCreated: 2000 });
    // The very first event for a subscription has nothing to tie with.
    expect(stripeMock.subscriptions.retrieve).not.toHaveBeenCalled();
  };

  test("a tie triggers exactly one retrieve and the stored doc reflects the FRESH object, not the event", async () => {
    await seed2000();
    const fresh = subscriptionObject("canceled");
    stripeMock.subscriptions.retrieve.mockResolvedValue(fresh);

    // Same second, but this event says "active"; Stripe's current state is canceled.
    const res = await deliver(subEvent(2000, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).toHaveBeenCalledTimes(1);
    expect(stripeMock.subscriptions.retrieve).toHaveBeenCalledWith("sub_1");
    const stored = getRef(SUB_DOC).__read();
    expect(stored).toMatchObject({ status: "cancelled", stripeSubscriptionId: "sub_1" });
    // Applied without an event clock: the ordering marker did not move.
    expect(stored.lastStripeEventCreated).toBe(2000);
    // Both writes happened, tie-applied first and the fresh state last.
    const statuses = getRef(SUB_DOC).set.mock.calls.map((c: any[]) => c[0].status);
    // (`mapStatus` stores Stripe "trialing" as "trial".)
    expect(statuses).toEqual(["trial", "active", "cancelled"]);
  });

  /** A `retrieve` that settles only when the test says so (a slow Stripe round trip). */
  const deferredRetrieve = () => {
    let resolve!: (v: unknown) => void;
    stripeMock.subscriptions.retrieve.mockReturnValue(
      new Promise((r) => {
        resolve = r;
      }),
    );
    return resolve;
  };
  const untilRetrieveCalled = async () => {
    while (stripeMock.subscriptions.retrieve.mock.calls.length === 0) {
      await new Promise((r) => setImmediate(r));
    }
  };

  test("the settle write goes through one transaction that re-reads the marker", async () => {
    await seed2000();
    const txRunner = (jest.requireMock("firebase-admin").firestore() as any).runTransaction;
    txRunner.mockClear();
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("canceled"));

    await deliver(subEvent(2000, "active"));

    // One transaction for the tie-applied event, one for the settle.
    expect(txRunner).toHaveBeenCalledTimes(2);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "cancelled",
      lastStripeEventCreated: 2000,
    });
  });

  test("a newer event applied while retrieve is in flight wins: the older fresh state is NOT written", async () => {
    await seed2000();
    const resolveRetrieve = deferredRetrieve();

    // The tie event is delivered; its settle blocks inside `retrieve`.
    const tie = deliver(subEvent(2000, "active"));
    await untilRetrieveCalled();
    expect(getRef(SUB_DOC).__read()).toMatchObject({ status: "active", lastStripeEventCreated: 2000 });

    // A strictly newer event lands and is applied meanwhile.
    const newer = await deliver(subEvent(2001, "canceled"));
    expect(newer.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "cancelled",
      lastStripeEventCreated: 2001,
    });

    // Stripe's (older) answer finally arrives and says "active".
    resolveRetrieve(subscriptionObject("active"));
    const tieRes = await tie;

    expect(tieRes.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "cancelled",
      lastStripeEventCreated: 2001,
    });
    const statuses = getRef(SUB_DOC).set.mock.calls.map((c: any[]) => c[0].status);
    expect(statuses).toEqual(["trial", "active", "cancelled"]); // no later "active"
    expect(logger.info).toHaveBeenCalledWith(
      "same-second stripe tie: a newer event already applied",
      expect.objectContaining({ uid: "u1", marker: 2001, settleIfMarkerIs: 2000 }),
    );
  });

  test("when the marker is unchanged after a slow retrieve, the fresh state is written", async () => {
    await seed2000();
    const resolveRetrieve = deferredRetrieve();

    const tie = deliver(subEvent(2000, "active"));
    await untilRetrieveCalled();
    resolveRetrieve(subscriptionObject("canceled"));
    const tieRes = await tie;

    expect(tieRes.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "cancelled",
      lastStripeEventCreated: 2000,
    });
    expect(logger.info).not.toHaveBeenCalledWith(
      "same-second stripe tie: a newer event already applied",
      expect.anything(),
    );
  });

  test("a strictly newer event is applied without any retrieve", async () => {
    await seed2000();
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("canceled"));

    const res = await deliver(subEvent(2001, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "active",
      lastStripeEventCreated: 2001,
    });
  });

  test("an older event is ignored and does not retrieve", async () => {
    await seed2000();
    stripeMock.subscriptions.retrieve.mockResolvedValue(subscriptionObject("canceled"));
    const before = { ...getRef(SUB_DOC).__read() };

    const res = await deliver(subEvent(1999, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(getRef(SUB_DOC).__read()).toEqual(before);
    expect(logger.info).toHaveBeenCalledWith(
      "ignoring out-of-order stripe event",
      expect.objectContaining({ eventCreated: 1999, alreadyApplied: 2000 }),
    );
  });

  test("a retrieve rejection keeps the tie-applied event, logs a warning and does not fail the webhook", async () => {
    await seed2000();
    stripeMock.subscriptions.retrieve.mockRejectedValue(new Error("stripe 503"));

    const res = await deliver(subEvent(2000, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(res.status).not.toHaveBeenCalledWith(500);
    expect(stripeMock.subscriptions.retrieve).toHaveBeenCalledTimes(1);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "active",
      lastStripeEventCreated: 2000,
    });
    expect(logger.warn).toHaveBeenCalledWith(
      "same-second stripe tie: could not re-read the subscription",
      expect.objectContaining({ uid: "u1", subscriptionId: "sub_1" }),
    );
  });

  test("a re-read that returns a different subscription id is not applied", async () => {
    await seed2000();
    stripeMock.subscriptions.retrieve.mockResolvedValue({
      ...subscriptionObject("canceled"),
      id: "sub_other",
    });

    const res = await deliver(subEvent(2000, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(getRef(SUB_DOC).__read()).toMatchObject({
      status: "active",
      stripeSubscriptionId: "sub_1",
    });
  });

  test("a tie for an account whose Auth user is gone writes nothing and never retrieves", async () => {
    getUser.mockRejectedValue(
      Object.assign(new Error("no user"), { code: "auth/user-not-found" }),
    );

    const res = await deliver(subEvent(2000, "active"));

    expect(res.status).toHaveBeenCalledWith(200);
    expect(stripeMock.subscriptions.retrieve).not.toHaveBeenCalled();
    expect(refs.has(SUB_DOC)).toBe(false);
  });
});

describe("coach booking confirmation journey with deleted accounts", () => {
  const confirmEvent = {
    id: "evt_bk",
    type: "payment_intent.succeeded",
    created: 1000,
    data: {
      object: {
        id: "pi_bk",
        metadata: { kind: "coach_booking", bookingId: "bk_1", firebaseUid: "u1" },
      },
    },
  };
  const gone = () =>
    getUser.mockRejectedValue(
      Object.assign(new Error("no user"), { code: "auth/user-not-found" }),
    );
  const userRefs = () => [...refs.keys()].filter((p) => p.startsWith("users/"));

  test("a booking anonymised by the client's deletion is confirmed once; a replay changes nothing and no user document appears", async () => {
    gone();
    await getRef("coach_bookings/bk_1").set({
      clientUid: "deleted_user",
      coachUid: "k1",
      status: "pending",
    });

    const first = await deliver(confirmEvent);
    expect(first.status).toHaveBeenCalledWith(200);
    const confirmed = { ...getRef("coach_bookings/bk_1").__read() };
    expect(confirmed).toMatchObject({
      clientUid: "deleted_user",
      coachUid: "k1",
      status: "confirmed",
    });

    const replay = await deliver(confirmEvent);
    expect(replay.status).toHaveBeenCalledWith(200);
    expect(getRef("coach_bookings/bk_1").__read()).toEqual(confirmed);
    expect(userRefs()).toEqual([]);
  });

  test("a booking removed by the deletion sweep is not recreated, on the first delivery or on a replay", async () => {
    gone();
    const first = await deliver(confirmEvent);
    const replay = await deliver(confirmEvent);

    expect(first.status).toHaveBeenCalledWith(200);
    expect(replay.status).toHaveBeenCalledWith(200);
    expect(getRef("coach_bookings/bk_1").__read()).toBeUndefined();
    expect(userRefs()).toEqual([]);
    expect(logger.error).toHaveBeenCalledWith(
      "webhook_booking_confirm_booking_doc_missing",
      expect.objectContaining({ bookingId: "bk_1" }),
    );
  });
});
