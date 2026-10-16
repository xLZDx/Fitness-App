/**
 * `enforceNonAnonymousForAi` -- MVP1.G4 Step 2's answer to the
 * anonymous-account-rotation exposure the 4 AI callables have that App Check
 * enforcement does not close (App Check attests the client, not the
 * account). Default is restrictive (anonymous callers refused); the flag is
 * an escape hatch to relax that, not an opt-in to enforce it -- the opposite
 * polarity from `scaling.ts`'s `APP_CHECK_ENFORCED*` flags, which default
 * off. Re-imports the module with a fresh environment per case since the
 * flag is read once at module load, same pattern as `scaling.test.ts`.
 *
 * `enforceAiGatewayEnabled` -- MVP1.G4 Step 8's kill switch.
 * `@google-cloud/secret-manager` is mocked file-wide so `accessSecretVersion`
 * can be scripted per case: a normal JSON payload, an empty payload, an
 * unparseable payload, and a call that throws -- the states the function has
 * to tell apart. `enforceNonAnonymousForAi`'s own tests never touch this
 * client, so mocking it file-wide does not affect them. (Round 1 of this
 * step used a Firestore document instead -- GPT-PM's review found
 * `fn-ai-runtime` already holds project-wide `roles/datastore.user`, so that
 * design let the very code being disabled write itself back on. Secret
 * Manager grants IAM per-secret, which is what makes the runtime's access
 * genuinely read-only; see `abuse_guard.ts`'s own doc comment for the full
 * reasoning.)
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

let controlSecret:
  | { payload: string }
  | { payload: undefined }
  | { throws: true };

// Counts real calls through the mocked client -- round 2's bounded cache
// (`CONTROL_CACHE_TTL_MS` in `abuse_guard.ts`) exists specifically to keep
// this at 1 across many `enforceAiGatewayEnabled` calls in quick succession,
// so a test asserts against it directly rather than only against behavior.
let accessSecretVersionCalls = 0;

jest.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion: async () => {
      accessSecretVersionCalls++;
      if ("throws" in controlSecret) throw new Error("simulated Secret Manager outage");
      return [
        {
          payload: {
            data: controlSecret.payload === undefined ? undefined : Buffer.from(controlSecret.payload),
          },
        },
      ];
    },
  })),
}));

// Deliberately NOT importing `HttpsError` from the outer module registry to compare via
// `instanceof`/`toThrow(HttpsError)`: `withEnv` re-requires `abuse_guard` inside
// `jest.isolateModules`, which gives it a fresh copy of `firebase-functions/v2/https` --
// a DIFFERENT `HttpsError` constructor than the one imported at this file's top level,
// so a class-identity check would fail even though the thrown error is correct. Assert
// on the message and the duck-typed `.code` property instead, both of which survive the
// registry split.
const withEnv = (env: Record<string, string | undefined>) => {
  const saved = { ...process.env };
  Object.assign(process.env, env);
  let mod: typeof import("../abuse_guard");
  jest.isolateModules(() => {
    mod = require("../abuse_guard");
  });
  process.env = saved;
  return mod!;
};

describe("enforceNonAnonymousForAi", () => {
  test("refuses an anonymous caller by default (AI_ALLOW_ANONYMOUS unset)", () => {
    const { enforceNonAnonymousForAi } = withEnv({ AI_ALLOW_ANONYMOUS: undefined });
    expect(() => enforceNonAnonymousForAi("anonymous")).toThrow(/real account/i);
  });

  test("refuses an anonymous caller when the flag is any value other than the literal string true", () => {
    const { enforceNonAnonymousForAi } = withEnv({ AI_ALLOW_ANONYMOUS: "TRUE" });
    expect(() => enforceNonAnonymousForAi("anonymous")).toThrow(/real account/i);
  });

  test("allows a non-anonymous caller by default", () => {
    const { enforceNonAnonymousForAi } = withEnv({ AI_ALLOW_ANONYMOUS: undefined });
    expect(() => enforceNonAnonymousForAi("google.com")).not.toThrow();
    expect(() => enforceNonAnonymousForAi(undefined)).not.toThrow();
  });

  test("allows an anonymous caller once AI_ALLOW_ANONYMOUS=true", () => {
    const { enforceNonAnonymousForAi } = withEnv({ AI_ALLOW_ANONYMOUS: "true" });
    expect(() => enforceNonAnonymousForAi("anonymous")).not.toThrow();
  });

  test("the thrown error is permission-denied, not a generic error", () => {
    const { enforceNonAnonymousForAi } = withEnv({ AI_ALLOW_ANONYMOUS: undefined });
    try {
      enforceNonAnonymousForAi("anonymous");
      throw new Error("expected enforceNonAnonymousForAi to throw");
    } catch (e) {
      expect((e as { code?: string }).code).toBe("permission-denied");
    }
  });
});

describe("enforceAiGatewayEnabled", () => {
  const { enforceAiGatewayEnabled, __resetAiGatewayControlCacheForTests } =
    require("../abuse_guard") as typeof import("../abuse_guard");
  const logger = require("firebase-functions/logger");

  beforeEach(() => {
    jest.clearAllMocks();
    // Round 2's short bounded cache (`CONTROL_CACHE_TTL_MS`) is module-scope
    // state -- without this reset, a cache hit from one test would leak its
    // stale `controlSecret` value into the next.
    __resetAiGatewayControlCacheForTests();
    accessSecretVersionCalls = 0;
    controlSecret = { payload: JSON.stringify({ enabled: true, reason: null }) };
  });

  test("resolves without throwing when enabled: true", async () => {
    await expect(enforceAiGatewayEnabled("aiCoachAdvice")).resolves.toBeUndefined();
  });

  test("refuses when enabled: false, and logs the operator's reason", async () => {
    controlSecret = { payload: JSON.stringify({ enabled: false, reason: "cost_abuse" }) };
    await expect(enforceAiGatewayEnabled("aiCoachAdvice")).rejects.toThrow(/temporarily unavailable/i);
    expect(logger.warn).toHaveBeenCalledWith(
      expect.stringMatching(/disabled/i),
      expect.objectContaining({ fn: "aiCoachAdvice", reason: "cost_abuse" }),
    );
  });

  test("the thrown error is unavailable, not a generic error", async () => {
    controlSecret = { payload: JSON.stringify({ enabled: false }) };
    try {
      await enforceAiGatewayEnabled("aiCoachAdvice");
      throw new Error("expected enforceAiGatewayEnabled to throw");
    } catch (e) {
      expect((e as { code?: string }).code).toBe("unavailable");
    }
  });

  test("fails closed -- a non-boolean `enabled` field is treated as disabled, never as enabled", async () => {
    controlSecret = { payload: JSON.stringify({ enabled: "true" }) };
    await expect(enforceAiGatewayEnabled("aiEquipmentRecognition")).rejects.toThrow(/temporarily unavailable/i);
  });

  test("fails closed -- an empty/missing secret payload is treated as disabled, not as enabled", async () => {
    controlSecret = { payload: undefined };
    await expect(enforceAiGatewayEnabled("aiMachineDescription")).rejects.toThrow(/temporarily unavailable/i);
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringMatching(/control read failed/i),
      expect.objectContaining({ fn: "aiMachineDescription" }),
    );
  });

  test("fails closed -- an unparseable secret payload is treated as disabled, not as enabled", async () => {
    controlSecret = { payload: "not valid json {" };
    await expect(enforceAiGatewayEnabled("aiEquipmentRecognition")).rejects.toThrow(/temporarily unavailable/i);
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringMatching(/control read failed/i),
      expect.objectContaining({ fn: "aiEquipmentRecognition" }),
    );
  });

  test("fails closed -- a Secret Manager read failure is treated as disabled, not as enabled", async () => {
    controlSecret = { throws: true };
    await expect(enforceAiGatewayEnabled("aiExerciseGeneration")).rejects.toThrow(/temporarily unavailable/i);
    expect(logger.error).toHaveBeenCalledWith(
      expect.stringMatching(/control read failed/i),
      expect.objectContaining({ fn: "aiExerciseGeneration" }),
    );
  });

  // GPT-PM's round-2 review: without a bound, an already-over-quota or
  // input-invalid caller could generate one real Secret Manager access per
  // retry, since parseInput/enforceDailyQuota both run AFTER this check by
  // design. This is the direct regression test for the fix -- many calls in
  // quick succession must cost at most one real access.
  test("bounds repeated calls in quick succession to a single real Secret Manager access", async () => {
    await Promise.all([
      enforceAiGatewayEnabled("aiCoachAdvice"),
      enforceAiGatewayEnabled("aiCoachAdvice"),
      enforceAiGatewayEnabled("aiCoachAdvice"),
      enforceAiGatewayEnabled("aiCoachAdvice"),
      enforceAiGatewayEnabled("aiCoachAdvice"),
    ]);
    expect(accessSecretVersionCalls).toBe(1);
  });

  // The cache is a bound, not a permanent state: once CONTROL_CACHE_TTL_MS
  // (5_000 ms in abuse_guard.ts) has elapsed, a flipped kill switch must be
  // re-read, otherwise an operator could never disable AI on a warm instance.
  // Only Date is faked; promise/microtask scheduling stays real.
  describe("cache expiry", () => {
    beforeEach(() => {
      jest.useFakeTimers({
        now: new Date("2026-01-01T00:00:00Z"),
        doNotFake: [
          "nextTick",
          "setImmediate",
          "clearImmediate",
          "setTimeout",
          "clearTimeout",
          "setInterval",
          "clearInterval",
          "queueMicrotask",
        ],
      });
    });
    afterEach(() => {
      jest.useRealTimers();
    });

    test("a flipped secret is served from cache before the TTL and re-read after it", async () => {
      await expect(enforceAiGatewayEnabled("aiCoachAdvice")).resolves.toBeUndefined();
      expect(accessSecretVersionCalls).toBe(1);

      controlSecret = { payload: JSON.stringify({ enabled: false, reason: "cost_abuse" }) };

      jest.setSystemTime(new Date("2026-01-01T00:00:04.999Z"));
      await expect(enforceAiGatewayEnabled("aiCoachAdvice")).resolves.toBeUndefined();
      expect(accessSecretVersionCalls).toBe(1);

      jest.setSystemTime(new Date("2026-01-01T00:00:05.000Z"));
      await expect(enforceAiGatewayEnabled("aiCoachAdvice")).rejects.toThrow(/temporarily unavailable/i);
      expect(accessSecretVersionCalls).toBe(2);
    });
  });

  // The cache must still log a distinct event per call -- proof point 5
  // (observability) requires every refused call to be individually visible,
  // not just the one that actually hit Secret Manager.
  test("still logs one event per call even when the underlying access is cached", async () => {
    controlSecret = { payload: JSON.stringify({ enabled: false, reason: "cost_abuse" }) };
    await enforceAiGatewayEnabled("aiCoachAdvice").catch(() => undefined);
    await enforceAiGatewayEnabled("aiCoachAdvice").catch(() => undefined);
    expect(accessSecretVersionCalls).toBe(1);
    expect(logger.warn).toHaveBeenCalledTimes(2);
  });
});

describe("refundQuota", () => {
  test("a failed refund is a named error event, never swallowed silently", async () => {
    // withEnv re-requires the module in an isolated registry, so the mock
    // must be registered with doMock rather than spied on the outer copy.
    jest.doMock("firebase-admin", () => ({
      firestore: () => ({
        doc: () => ({}),
        runTransaction: async () => {
          throw new Error("txn aborted");
        },
      }),
    }));
    const logger = require("firebase-functions/logger");
    logger.error.mockClear();
    const mod = withEnv({});
    await expect(mod.refundQuota("u1", "clipUrl", 2)).resolves.toBeUndefined();
    expect(logger.error).toHaveBeenCalledWith(
      "quota refund failed",
      expect.objectContaining({ event: "quota refund failed", uid: "u1", action: "clipUrl", amount: 2 }),
    );
    jest.dontMock("firebase-admin");
  });
});

/* ------------------------------------------------------------------ */
/* E0 / C02: eight new quotas and uid-free log events (T08)            */
/* ------------------------------------------------------------------ */

describe("Body Scan + Nutrition Coach quotas (C02, FOOD-28, D-67)", () => {
  const NEW_QUOTAS = {
    bodyScanCreate: 30,
    bodyScanEstimate: 14,
    bodyScanDelete: 60,
    bodyScanManage: 30,
    analyzeMealPhoto: 60,
    parseNutritionLabel: 60,
    barcodeLookup: 120,
    foodSearch: 150,
  } as const;
  // S02 unified activity (design 5.4, 8.1): redacted like the Body Scan actions; starting limits, unmeasured.
  const S02_QUOTAS = {
    activitySettingsSet: 20,
    activityDelete: 100,
    activityStreamUpload: 30,
    activityStreamCommit: 60,
    activityDeleteAll: 10,
    activityDownloadUrls: 60,
    debugTelemetrySend: 200,
    debugTelemetryEvents: 5000,
  } as const;
  const FIXTURE_UID = "uid-SECRET-123";

  // The logger mock is shared across isolated registries; start every case clean.
  beforeEach(() => {
    jest.clearAllMocks();
  });

  /** In-memory Firestore: path -> document data, with merge-set transactions. */
  function makeStore(opts: { failWith?: unknown } = {}) {
    const docs = new Map<string, Record<string, unknown>>();
    const firestore = () => ({
      doc: (path: string) => ({ path }),
      runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
        if (opts.failWith !== undefined) throw opts.failWith;
        const tx = {
          get: async (ref: { path: string }) => ({ data: () => docs.get(ref.path) }),
          set: (ref: { path: string }, data: Record<string, unknown>) => {
            docs.set(ref.path, { ...(docs.get(ref.path) ?? {}), ...data });
          },
        };
        await fn(tx);
      },
    });
    return { docs, firestore };
  }

  /** Loads abuse_guard and its logger mock from ONE isolated registry. */
  function load(store: ReturnType<typeof makeStore>) {
    jest.doMock("firebase-admin", () => ({ firestore: store.firestore }));
    let mod!: typeof import("../abuse_guard");
    let log!: { warn: jest.Mock; error: jest.Mock; info: jest.Mock };
    jest.isolateModules(() => {
      mod = require("../abuse_guard");
      log = require("firebase-functions/logger");
    });
    jest.dontMock("firebase-admin");
    return { mod, log };
  }

  const today = () => new Date().toISOString().slice(0, 10);
  const usagePath = (uid: string) => "users/" + uid + "/usage/" + today();

  test("the eight new QUOTAS have exactly the designed daily values", () => {
    const { QUOTAS } = require("../abuse_guard") as typeof import("../abuse_guard");
    for (const [name, value] of Object.entries(NEW_QUOTAS)) {
      expect((QUOTAS as Record<string, number>)[name]).toBe(value);
    }
  });

  test("the eight S02 activity QUOTAS have exactly the designed daily values (F83)", () => {
    const { QUOTAS } = require("../abuse_guard") as typeof import("../abuse_guard");
    for (const [name, value] of Object.entries(S02_QUOTAS)) {
      expect((QUOTAS as Record<string, number>)[name]).toBe(value);
    }
  });

  test("the pre-existing quotas are unchanged", () => {
    const { QUOTAS } = require("../abuse_guard") as typeof import("../abuse_guard");
    expect(QUOTAS.aiCoachAdvice).toBe(40);
    expect(QUOTAS.aiEquipmentRecognition).toBe(60);
    expect(QUOTAS.aiMachineDescription).toBe(60);
    expect(QUOTAS.aiExerciseGeneration).toBe(40);
    expect(QUOTAS.accountExport).toBe(3);
    expect(QUOTAS.equipmentReport).toBe(30);
  });

  test("REDACTED_QUOTA_ACTIONS is the eight new action names, the eight S02 activity names and the two account export counters (D-67, F83)", () => {
    const { REDACTED_QUOTA_ACTIONS } = require("../abuse_guard") as typeof import("../abuse_guard");
    // An exact set, not a superset: dropping or adding any single name fails.
    expect([...REDACTED_QUOTA_ACTIONS].sort()).toEqual(
      [...Object.keys(NEW_QUOTAS), ...Object.keys(S02_QUOTAS), "accountExport", "accountExportPage"].sort(),
    );
    for (const old of ["aiCoachAdvice", "clipUrl", "equipmentReport", "startFreeTrial"]) {
      expect(REDACTED_QUOTA_ACTIONS.has(old)).toBe(false);
    }
    // The camelCase style of design 5.4: no snake_case name of the withdrawn revision 2.
    for (const name of REDACTED_QUOTA_ACTIONS) expect(name).not.toContain("_");
    for (const snake of ["activity_stream_upload", "activity_stream_commit", "activity_delete", "debug_telemetry_send"]) {
      expect(REDACTED_QUOTA_ACTIONS.has(snake)).toBe(false);
    }
  });

  test("anonymous callers get the integer-floor eighth of each new quota, minimum 1", () => {
    const { quotaFor } = require("../abuse_guard") as typeof import("../abuse_guard");
    expect(quotaFor(30, "anonymous")).toBe(3);
    expect(quotaFor(14, "anonymous")).toBe(1);
    expect(quotaFor(60, "anonymous")).toBe(7);
    expect(quotaFor(120, "anonymous")).toBe(15);
    expect(quotaFor(150, "anonymous")).toBe(18);
    expect(quotaFor(150, "google.com")).toBe(150);
  });

  test("a charge on a new action is stored under users/{uid}/usage/{day} and accumulates", async () => {
    const store = makeStore();
    const { mod } = load(store);
    await mod.enforceDailyQuota(FIXTURE_UID, "bodyScanCreate", 30);
    await mod.enforceDailyQuota(FIXTURE_UID, "bodyScanCreate", 30);
    expect(store.docs.get(usagePath(FIXTURE_UID))?.bodyScanCreate).toBe(2);
  });

  test("the 15th bodyScanEstimate charge is refused (limit 14), the 14th is not", async () => {
    const store = makeStore();
    const { mod } = load(store);
    for (let i = 0; i < 14; i++) await mod.enforceDailyQuota("u1", "bodyScanEstimate", 14);
    await expect(mod.enforceDailyQuota("u1", "bodyScanEstimate", 14)).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(store.docs.get(usagePath("u1"))?.bodyScanEstimate).toBe(14);
  });

  test.each([...Object.keys(NEW_QUOTAS), ...Object.keys(S02_QUOTAS)])(
    "%s refusal log carries NO uid anywhere in the payload",
    async (action) => {
      const store = makeStore();
      store.docs.set(usagePath(FIXTURE_UID), { [action]: 5 });
      const { mod, log } = load(store);
      await expect(mod.enforceDailyQuota(FIXTURE_UID, action, 5)).rejects.toMatchObject({
        code: "resource-exhausted",
      });
      expect(log.warn).toHaveBeenCalledTimes(1);
      const [message, payload] = log.warn.mock.calls[0];
      expect(message).toBe("quota exceeded");
      expect(payload).toEqual({ action, used: 5, cost: 1, limit: 5 });
      expect(payload).not.toHaveProperty("uid");
      expect(JSON.stringify(log.warn.mock.calls)).not.toContain(FIXTURE_UID);
    },
  );

  test("a pre-existing action's refusal log KEEPS its uid (monitoring queries still join)", async () => {
    const store = makeStore();
    store.docs.set(usagePath("u-old"), { clipUrl: 3 });
    const { mod, log } = load(store);
    await expect(mod.enforceDailyQuota("u-old", "clipUrl", 3)).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    expect(log.warn.mock.calls[0][1]).toEqual({ uid: "u-old", action: "clipUrl", used: 3, cost: 1, limit: 3 });
  });

  test("a failed quota transaction on a new action logs only the error CODE, no uid, no path text", async () => {
    const firestoreError = Object.assign(
      new Error("10 ABORTED: transaction on users/" + FIXTURE_UID + "/usage/2026-10-15 aborted"),
      { code: 10 },
    );
    const store = makeStore({ failWith: firestoreError });
    const { mod, log } = load(store);
    await expect(mod.enforceDailyQuota(FIXTURE_UID, "foodSearch", 150)).rejects.toMatchObject({
      code: "internal",
    });
    expect(log.error).toHaveBeenCalledTimes(1);
    const [message, payload] = log.error.mock.calls[0];
    expect(message).toBe("quota check failed");
    expect(payload).toEqual({ action: "foodSearch", cost: 1, limit: 150, err: "10" });
    expect(JSON.stringify(log.error.mock.calls)).not.toContain(FIXTURE_UID);
  });

  test("a failure without a usable code is logged as 'unknown', never as String(e)", async () => {
    const store = makeStore({ failWith: new Error("boom users/" + FIXTURE_UID) });
    const { mod, log } = load(store);
    await expect(mod.enforceDailyQuota(FIXTURE_UID, "barcodeLookup", 120)).rejects.toMatchObject({
      code: "internal",
    });
    expect(log.error.mock.calls[0][1].err).toBe("unknown");
    expect(JSON.stringify(log.error.mock.calls)).not.toContain(FIXTURE_UID);
  });

  test("a failed quota transaction on an OLD action keeps uid and String(e) (unchanged shape)", async () => {
    const store = makeStore({ failWith: new Error("txn aborted") });
    const { mod, log } = load(store);
    await expect(mod.enforceDailyQuota("u-old", "clipUrl", 3)).rejects.toMatchObject({ code: "internal" });
    expect(log.error.mock.calls[0][1]).toEqual({
      uid: "u-old",
      action: "clipUrl",
      cost: 1,
      limit: 3,
      err: "Error: txn aborted",
    });
  });

  test("a failed refund on a new action logs no uid and only the code", async () => {
    const store = makeStore({ failWith: Object.assign(new Error("x " + FIXTURE_UID), { code: "unavailable" }) });
    const { mod, log } = load(store);
    await expect(mod.refundQuota(FIXTURE_UID, "analyzeMealPhoto", 1)).resolves.toBeUndefined();
    expect(log.error).toHaveBeenCalledWith("quota refund failed", {
      event: "quota refund failed",
      action: "analyzeMealPhoto",
      amount: 1,
      err: "unavailable",
    });
    expect(JSON.stringify(log.error.mock.calls)).not.toContain(FIXTURE_UID);
  });

  test("refunding a new action never drops the counter below zero and removes the charge", async () => {
    const store = makeStore();
    const { mod } = load(store);
    await mod.enforceDailyQuota("u1", "bodyScanDelete", 60);
    await mod.refundQuota("u1", "bodyScanDelete", 1);
    expect(store.docs.get(usagePath("u1"))?.bodyScanDelete).toBe(0);
    await mod.refundQuota("u1", "bodyScanDelete", 5);
    expect(store.docs.get(usagePath("u1"))?.bodyScanDelete).toBe(0);
  });

  test("bodyScanManage has its own counter: exhausting bodyScanDelete does not block it", async () => {
    const store = makeStore();
    store.docs.set(usagePath("u1"), { bodyScanDelete: 60 });
    const { mod } = load(store);
    await expect(mod.enforceDailyQuota("u1", "bodyScanDelete", 60)).rejects.toMatchObject({
      code: "resource-exhausted",
    });
    await expect(mod.enforceDailyQuota("u1", "bodyScanManage", 30)).resolves.toBeUndefined();
  });
});
