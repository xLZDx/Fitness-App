jest.mock("firebase-admin", () => ({
  firestore: jest.fn(),
}));

import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { enforceDailyQuota } from "../quota";

describe("enforceDailyQuota -- transaction failure fails closed", () => {
  test("a non-HttpsError thrown inside the transaction becomes HttpsError('internal', ...), never a silent pass", async () => {
    (admin.firestore as unknown as jest.Mock).mockReturnValue({
      doc: () => ({}),
      runTransaction: async () => {
        throw new Error("simulated Firestore outage");
      },
    });

    await expect(enforceDailyQuota("uid1", "identityTextLookup", 10)).rejects.toThrow(HttpsError);
    try {
      await enforceDailyQuota("uid1", "identityTextLookup", 10);
      throw new Error("expected enforceDailyQuota to throw");
    } catch (e) {
      expect(e).toBeInstanceOf(HttpsError);
      expect((e as HttpsError).code).toBe("internal");
    }
  });

  test("a genuine resource-exhausted HttpsError passes through unchanged, not wrapped as internal", async () => {
    (admin.firestore as unknown as jest.Mock).mockReturnValue({
      doc: () => ({}),
      runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
        const tx = {
          get: async () => ({ data: () => ({ identityTextLookup: 10 }) }),
        };
        // Delegate to the real callback so the real over-limit branch throws
        // the real HttpsError('resource-exhausted', ...) -- proves the catch
        // block distinguishes it from a generic failure rather than
        // re-wrapping every thrown error as 'internal'.
        await fn(tx);
      },
    });

    try {
      await enforceDailyQuota("uid1", "identityTextLookup", 10);
      throw new Error("expected enforceDailyQuota to throw");
    } catch (e) {
      expect(e).toBeInstanceOf(HttpsError);
      expect((e as HttpsError).code).toBe("resource-exhausted");
    }
  });
});

describe("enforceDailyQuota -- logging (restored to match abuse_guard.ts's own catch block)", () => {
  test("a non-HttpsError transaction failure is logged with the real underlying error before being rewrapped", async () => {
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
    (admin.firestore as unknown as jest.Mock).mockReturnValue({
      doc: () => ({}),
      runTransaction: async () => {
        throw new Error("simulated Firestore outage");
      },
    });

    await expect(enforceDailyQuota("uid1", "identityTextLookup", 10)).rejects.toThrow(HttpsError);

    expect(errorSpy).toHaveBeenCalledWith(
      "equipment_identity_quota_check_failed",
      expect.objectContaining({
        uid: "uid1",
        action: "identityTextLookup",
        err: expect.stringContaining("simulated Firestore outage"),
      }),
    );
    errorSpy.mockRestore();
  });

  test("a genuine over-limit rejection is logged as a warning, not an error", async () => {
    const logger = await import("firebase-functions/logger");
    const warnSpy = jest.spyOn(logger, "warn").mockImplementation(() => undefined);
    (admin.firestore as unknown as jest.Mock).mockReturnValue({
      doc: () => ({}),
      runTransaction: async (fn: (tx: unknown) => Promise<void>) => {
        const tx = { get: async () => ({ data: () => ({ identityTextLookup: 10 }) }) };
        await fn(tx);
      },
    });

    await expect(enforceDailyQuota("uid1", "identityTextLookup", 10)).rejects.toThrow(HttpsError);

    expect(warnSpy).toHaveBeenCalledWith(
      "equipment_identity_quota_exceeded",
      expect.objectContaining({ uid: "uid1", action: "identityTextLookup", used: 10, limit: 10 }),
    );
    warnSpy.mockRestore();
  });
});
