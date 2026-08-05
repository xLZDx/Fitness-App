/**
 * Every deployed function has a scaling ceiling.
 *
 * The state this locks out is the one the repo shipped with: `grep -E
 * "maxInstances|minInstances|concurrency|memory" src/` returned nothing, so
 * all twelve entrypoints ran on the same platform default and any one of them
 * could consume the regional pool — including starving `stripeWebhook`, the
 * only function here whose failure loses money.
 *
 * The assertion is on `__endpoint`, the deployment descriptor
 * `firebase-functions` builds from the options object, rather than on the
 * options object itself. That is deliberate: `__endpoint` is what the deploy
 * actually reads, so a profile that is defined but wired to nothing still
 * fails here.
 */
import * as admin from "firebase-admin";

jest.mock("firebase-admin", () => ({
  initializeApp: jest.fn(),
  firestore: Object.assign(
    jest.fn(() => ({ doc: jest.fn() })),
    { FieldValue: { serverTimestamp: jest.fn() } },
  ),
}));

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

import * as index from "../index";
import { clipUrl, clipUrls } from "../video_urls";
import { INTERACTIVE, RARE, VIDEO_BATCH, VIDEO_HOT, WEBHOOK } from "../scaling";

/** `__endpoint` is internal to firebase-functions and untyped for consumers. */
const endpointOf = (fn: unknown): any => (fn as any).__endpoint;

/** Every entrypoint this backend deploys, by the name it deploys under. */
const ENTRYPOINTS: Record<string, unknown> = {
  clipUrl,
  clipUrls,
  startFreeTrial: index.startFreeTrial,
  createCheckoutSession: index.createCheckoutSession,
  createPortalSession: index.createPortalSession,
  stripeWebhook: index.stripeWebhook,
  optInDonorWall: index.optInDonorWall,
  optOutDonorWall: index.optOutDonorWall,
  generateAnnualReceipt: index.generateAnnualReceipt,
  startCoachOnboarding: index.startCoachOnboarding,
  bookCoachSession: index.bookCoachSession,
  reportEquipment: index.reportEquipment,
  deleteAccount: index.deleteAccount,
};

describe("scaling ceilings", () => {
  test("admin is only initialised once, at module load", () => {
    // Guards the mock itself: if firebase-admin stopped being mocked, the
    // rest of this file would be asserting against a real SDK.
    expect(admin.initializeApp).toHaveBeenCalledTimes(1);
  });

  test("the deployed surface is exactly these twelve", () => {
    // A thirteenth function added without a ceiling is the regression this
    // whole file exists to catch, and it can only be caught by noticing the
    // count moved.
    const exported = Object.keys(index).filter(
      (k) => typeof endpointOf((index as any)[k])?.platform === "string",
    );
    expect(exported.sort()).toEqual(
      Object.keys(ENTRYPOINTS)
        .filter((n) => n !== "clipUrl" && n !== "clipUrls")
        .concat(["clipUrl", "clipUrls"])
        .sort(),
    );
  });

  test.each(Object.keys(ENTRYPOINTS))("%s declares maxInstances", (name) => {
    const max = endpointOf(ENTRYPOINTS[name]).maxInstances;
    expect(typeof max).toBe("number");
    expect(max).toBeGreaterThan(0);
  });

  test.each(Object.keys(ENTRYPOINTS))("%s deploys to one region", (name) => {
    expect(endpointOf(ENTRYPOINTS[name]).region).toEqual(["us-central1"]);
  });

  test("clipUrl keeps an instance warm; nothing else pays to", () => {
    // Cold start on this one function is a black rectangle rather than a slow
    // response — the player awaits the signature before it builds the video
    // controller. Everywhere else a cold start is invisible, and idle billing
    // for it would be waste.
    expect(endpointOf(clipUrl).minInstances).toBe(1);
    for (const [name, fn] of Object.entries(ENTRYPOINTS)) {
      if (name === "clipUrl") continue;
      expect(endpointOf(fn).minInstances).not.toBe(1);
    }
  });

  test("the batch signer is capped below the single signer", () => {
    // One clipUrls call signs up to 60 objects, so its instance ceiling buys
    // 60x the IAM work of a clipUrl instance. Ordering these the other way
    // round is the mistake this catches.
    expect(VIDEO_BATCH.maxInstances).toBeLessThan(VIDEO_HOT.maxInstances);
  });

  test("the webhook has a ceiling of its own", () => {
    // Not shared with the video path: no amount of clip traffic may crowd out
    // the function whose failure Stripe responds to by retrying.
    expect(endpointOf(index.stripeWebhook).maxInstances).toBe(
      WEBHOOK.maxInstances,
    );
    expect(WEBHOOK.maxInstances).not.toBe(VIDEO_HOT.maxInstances);
  });

  test("rare actions are capped below interactive ones", () => {
    expect(RARE.maxInstances).toBeLessThan(INTERACTIVE.maxInstances);
  });

  test("concurrency is left at the platform default on purpose", () => {
    // The default is 80 (options.d.ts: "80 when CPU >= 1", and CPU defaults
    // to 1 at <= 2GB RAM). Setting it here would restate a default and invite
    // someone to lower it, which is the change that would actually hurt.
    for (const fn of Object.values(ENTRYPOINTS)) {
      expect(endpointOf(fn).concurrency).not.toEqual(expect.any(Number));
    }
  });
});
