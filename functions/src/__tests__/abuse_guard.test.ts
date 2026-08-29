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
