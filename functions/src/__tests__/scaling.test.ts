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
  // A3. Added here in the same change that exported it -- this list IS the
  // registration, and the count test below is what refuses a function that
  // ships without a ceiling.
  exportAccountData: index.exportAccountData,
};

describe("scaling ceilings", () => {
  test("admin is only initialised once, at module load", () => {
    // Guards the mock itself: if firebase-admin stopped being mocked, the
    // rest of this file would be asserting against a real SDK.
    expect(admin.initializeApp).toHaveBeenCalledTimes(1);
  });

  test("the deployed surface is exactly these thirteen", () => {
    // A fourteenth function added without a ceiling is the regression this
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
    // europe-west1 is inside eur3, where this project's Firestore lives, so
    // a function's reads stay on the same continent as the data. The value
    // is asserted literally on purpose: the client has to name the same
    // region (`kFunctionsRegion` in mobile/lib/core/firebase/
    // functions_region.dart), and a silent drift between the two surfaces as
    // NOT_FOUND on every callable at runtime rather than at build time.
    expect(endpointOf(ENTRYPOINTS[name]).region).toEqual(["europe-west1"]);
  });

  test("no function pays for an idle warm instance", () => {
    // Not a temporary state: `clipUrl` used to keep one warm on the grounds
    // that a cold start showed "a black rectangle", but the player has always
    // painted a bundled poster first (workout_player_page.dart:160, :413) and
    // fades the video in over it. The warm instance billed 24/7 to hide
    // latency that shipping 3.6 MB of posters already hides. See VIDEO_HOT.
    //
    // If this test ever fails because someone set minInstances back to 1,
    // read that comment before changing the expectation: the cost is
    // continuous and the benefit was measured to be nil.
    // Normalised through `typeof === "number"` rather than `?? 0`, which is
    // wrong here and quietly so: a function that never sets minInstances gets
    // firebase-functions' ResetValue sentinel, which is an OBJECT that merely
    // serialises to null. `??` only substitutes real null/undefined, so the
    // sentinel sails through it and the assertion compares an object to 0.
    // Anything non-numeric means "no explicit warm floor", i.e. zero.
    for (const fn of Object.values(ENTRYPOINTS)) {
      const min = endpointOf(fn).minInstances;
      expect(typeof min === "number" ? min : 0).toBe(0);
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

/* ------------------------------------------------------------------ */
/* A6-full — App Check enforcement is staged, and OFF until staged on  */
/* ------------------------------------------------------------------ */

describe("App Check enforcement flags", () => {
  /** Re-imports `scaling` with a fresh environment, since the flags are
   * read once at module load. */
  const withEnv = (env: Record<string, string | undefined>) => {
    const saved = { ...process.env };
    Object.assign(process.env, env);
    let mod: typeof import("../scaling");
    jest.isolateModules(() => {
      mod = require("../scaling");
    });
    process.env = saved;
    return mod!;
  };

  test("every callable profile is unenforced by default", () => {
    // Enforcing today locks out the operator's own phone: Play Integrity only
    // attests builds distributed through Google Play, and this project ships
    // testers through Firebase App Distribution. Default-on would be a silent
    // lockout, not a visible error.
    const s = withEnv({
      APP_CHECK_ENFORCED: undefined,
      APP_CHECK_ENFORCED_VIDEO: undefined,
    });
    expect(s.APP_CHECK_ENFORCED).toBe(false);
    expect(s.APP_CHECK_ENFORCED_VIDEO).toBe(false);
    expect(s.VIDEO_HOT.enforceAppCheck).toBe(false);
    expect(s.RARE.enforceAppCheck).toBe(false);
  });

  test("stage 1 enforces the clip-signing pair and nothing else", () => {
    const s = withEnv({
      APP_CHECK_ENFORCED: undefined,
      APP_CHECK_ENFORCED_VIDEO: "true",
    });
    expect(s.VIDEO_HOT.enforceAppCheck).toBe(true);
    expect(s.VIDEO_BATCH.enforceAppCheck).toBe(true);
    // Not `deleteAccount`, not checkout. Video going green is not evidence
    // that gating an account operation behind attestation is safe.
    expect(s.INTERACTIVE.enforceAppCheck).toBe(false);
    expect(s.RARE.enforceAppCheck).toBe(false);
  });

  test("stage 2 implies stage 1", () => {
    // There must be no flag combination where the cheap functions are
    // enforced and the expensive, per-call-billed ones are not.
    const s = withEnv({
      APP_CHECK_ENFORCED: "true",
      APP_CHECK_ENFORCED_VIDEO: undefined,
    });
    expect(s.VIDEO_HOT.enforceAppCheck).toBe(true);
    expect(s.INTERACTIVE.enforceAppCheck).toBe(true);
  });

  test("anything other than the exact string 'true' fails safe", () => {
    // A typo in a deploy environment must not lock the product.
    for (const value of ["1", "TRUE", "yes", "", "false"]) {
      const s = withEnv({
        APP_CHECK_ENFORCED: value,
        APP_CHECK_ENFORCED_VIDEO: value,
      });
      expect(s.APP_CHECK_ENFORCED).toBe(false);
      expect(s.APP_CHECK_ENFORCED_VIDEO).toBe(false);
    }
  });
});
