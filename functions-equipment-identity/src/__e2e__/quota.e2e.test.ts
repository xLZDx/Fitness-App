/**
 * P2.G3 T2 -- the ported quota primitive against a real Firestore emulator.
 * Proves the SAME atomic-store properties `abuse_guard.ts`'s
 * `enforceDailyQuota` already has, at the SAME Firestore path.
 *
 *     npm run test:e2e
 */
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import { enforceDailyQuota, usageDocRef } from "../p2/quota";

function randomUid(): string {
  return `e2e-quota-uid-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

const TODAY = new Date().toISOString().slice(0, 10);

afterAll(async () => {
  await admin.app().delete();
});

describe("enforceDailyQuota -- real transactional behavior", () => {
  test("under-limit calls succeed and increment the counter", async () => {
    const uid = randomUid();
    await enforceDailyQuota(uid, "identityTextLookup", 5);
    await enforceDailyQuota(uid, "identityTextLookup", 5);

    const snap = await usageDocRef(uid, TODAY).get();
    expect(snap.data()?.identityTextLookup).toBe(2);
  });

  test("a call landing exactly on the limit succeeds", async () => {
    const uid = randomUid();
    for (let i = 0; i < 5; i++) {
      await enforceDailyQuota(uid, "identityTextLookup", 5);
    }
    const snap = await usageDocRef(uid, TODAY).get();
    expect(snap.data()?.identityTextLookup).toBe(5);
  });

  test("the call exceeding the limit throws resource-exhausted and does NOT increment", async () => {
    const uid = randomUid();
    for (let i = 0; i < 5; i++) {
      await enforceDailyQuota(uid, "identityTextLookup", 5);
    }
    await expect(enforceDailyQuota(uid, "identityTextLookup", 5)).rejects.toMatchObject({
      code: "resource-exhausted",
    });

    const snap = await usageDocRef(uid, TODAY).get();
    // Still 5 -- the refused 6th call charged nothing.
    expect(snap.data()?.identityTextLookup).toBe(5);
  });

  test("concurrent near-limit calls never let the counter exceed the limit", async () => {
    const uid = randomUid();
    const limit = 5;
    // Seed to 3 used, then fire 5 concurrent calls at a limit of 5 -- at
    // most 2 can legitimately succeed; the transaction must serialize the
    // rest into resource-exhausted rather than letting a race push the
    // counter past 5.
    for (let i = 0; i < 3; i++) {
      await enforceDailyQuota(uid, "identityTextLookup", limit);
    }

    const attempts = await Promise.allSettled(
      Array.from({ length: 5 }, () => enforceDailyQuota(uid, "identityTextLookup", limit)),
    );
    const succeeded = attempts.filter((a) => a.status === "fulfilled").length;
    const rejected = attempts.filter((a) => a.status === "rejected").length;

    expect(succeeded).toBe(2);
    expect(rejected).toBe(3);
    for (const a of attempts) {
      if (a.status === "rejected") {
        expect(a.reason).toBeInstanceOf(HttpsError);
        expect((a.reason as HttpsError).code).toBe("resource-exhausted");
      }
    }

    const snap = await usageDocRef(uid, TODAY).get();
    expect(snap.data()?.identityTextLookup).toBe(limit);
  });

  test("merge preserves an unrelated counter already on the same day document", async () => {
    const uid = randomUid();
    await usageDocRef(uid, TODAY).set({ someOtherAction: 42 }, { merge: true });

    await enforceDailyQuota(uid, "identityTextLookup", 10);

    const snap = await usageDocRef(uid, TODAY).get();
    expect(snap.data()?.someOtherAction).toBe(42);
    expect(snap.data()?.identityTextLookup).toBe(1);
  });

  test("uses the exact same document path shape as abuse_guard.ts: users/{uid}/usage/{yyyy-mm-dd}", async () => {
    const uid = randomUid();
    await enforceDailyQuota(uid, "identityTextLookup", 10);

    const directRef = admin.firestore().doc(`users/${uid}/usage/${TODAY}`);
    const snap = await directRef.get();
    expect(snap.exists).toBe(true);
    expect(snap.data()?.identityTextLookup).toBe(1);
  });
});
