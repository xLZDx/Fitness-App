/**
 * `enforceNonAnonymousForAi` -- MVP1.G4 Step 2's answer to the
 * anonymous-account-rotation exposure the 4 AI callables have that App Check
 * enforcement does not close (App Check attests the client, not the
 * account). Default is restrictive (anonymous callers refused); the flag is
 * an escape hatch to relax that, not an opt-in to enforce it -- the opposite
 * polarity from `scaling.ts`'s `APP_CHECK_ENFORCED*` flags, which default
 * off. Re-imports the module with a fresh environment per case since the
 * flag is read once at module load, same pattern as `scaling.test.ts`.
 */
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
