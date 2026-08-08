import type Stripe from "stripe";

import { invoiceSubscriptionId, subscriptionPeriodEnd } from "../index";

/**
 * Stripe moved two fields in API version 2025-03-31 ("Basil"):
 *
 *   subscription.current_period_end -> subscription.items.data[].current_period_end
 *   invoice.subscription            -> invoice.parent.subscription_details.subscription
 *
 * The SDK client pins `2025-02-24.acacia`, so direct calls keep the old shape.
 * **Webhooks do not follow that pin** — Stripe serialises an event at the
 * account's default version, which nothing in this repository can see or
 * control.
 *
 * The failure that mattered was silent: `s.current_period_end` on a Basil
 * payload is `undefined`, the old code wrote `periodEnd: null`, and a paying
 * subscriber lost their renewal date without an error anywhere. So both shapes
 * are accepted, and both are pinned here — a fix that only handled Basil would
 * break the account that is still on Acacia, which is the more likely one
 * today.
 */
describe("subscriptionPeriodEnd", () => {
  const iso = "2026-09-01T00:00:00.000Z";
  const unix = Math.floor(new Date(iso).getTime() / 1000);

  it("reads the Acacia field on the subscription itself", () => {
    const s = { current_period_end: unix } as unknown as Stripe.Subscription;
    expect(subscriptionPeriodEnd(s)).toBe(iso);
  });

  it("reads the Basil field on the subscription's item", () => {
    const s = {
      items: { data: [{ current_period_end: unix }] },
    } as unknown as Stripe.Subscription;
    expect(subscriptionPeriodEnd(s)).toBe(iso);
  });

  it("takes the LATEST item period when a subscription has several", () => {
    // Access runs until the last one ends; taking the first would cut a
    // paying customer off early, which is the same class of harm as writing
    // null.
    const earlier = unix - 60 * 60 * 24 * 30;
    const s = {
      items: {
        data: [
          { current_period_end: earlier },
          { current_period_end: unix },
        ],
      },
    } as unknown as Stripe.Subscription;
    expect(subscriptionPeriodEnd(s)).toBe(iso);
  });

  it("prefers the flat field when a payload carries both", () => {
    // A transitional payload should not depend on which branch is checked
    // first, so the behaviour is pinned rather than left to reading order.
    const s = {
      current_period_end: unix,
      items: { data: [{ current_period_end: unix - 999 }] },
    } as unknown as Stripe.Subscription;
    expect(subscriptionPeriodEnd(s)).toBe(iso);
  });

  it("returns null rather than an invalid date when neither is present", () => {
    expect(
      subscriptionPeriodEnd({} as unknown as Stripe.Subscription),
    ).toBeNull();
    expect(
      subscriptionPeriodEnd({
        items: { data: [] },
      } as unknown as Stripe.Subscription),
    ).toBeNull();
  });
});

describe("invoiceSubscriptionId", () => {
  it("reads the Acacia top-level string", () => {
    const inv = { subscription: "sub_123" } as unknown as Stripe.Invoice;
    expect(invoiceSubscriptionId(inv)).toBe("sub_123");
  });

  it("reads an expanded Acacia object", () => {
    const inv = {
      subscription: { id: "sub_123" },
    } as unknown as Stripe.Invoice;
    expect(invoiceSubscriptionId(inv)).toBe("sub_123");
  });

  it("reads the Basil nested string", () => {
    const inv = {
      parent: { subscription_details: { subscription: "sub_123" } },
    } as unknown as Stripe.Invoice;
    expect(invoiceSubscriptionId(inv)).toBe("sub_123");
  });

  it("reads an expanded Basil object", () => {
    const inv = {
      parent: { subscription_details: { subscription: { id: "sub_123" } } },
    } as unknown as Stripe.Invoice;
    expect(invoiceSubscriptionId(inv)).toBe("sub_123");
  });

  it("returns null for a one-off invoice with no subscription", () => {
    // Not every invoice belongs to a subscription. The webhook only acts when
    // this is a string, so null must mean "nothing to do" and never a crash.
    expect(invoiceSubscriptionId({} as unknown as Stripe.Invoice)).toBeNull();
    expect(
      invoiceSubscriptionId({
        parent: { subscription_details: {} },
      } as unknown as Stripe.Invoice),
    ).toBeNull();
  });
});
