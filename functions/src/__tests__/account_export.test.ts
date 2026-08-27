/**
 * A3 — the server-side export.
 *
 * The assertion that matters is COVERAGE: every store `core/DATA_INVENTORY_2026-08-11.md`
 * lists against this uid has to appear. A test that checked three collections
 * would pass for exactly the reason the gate exists to fix.
 */

const docs = new Map<string, any>();
const collections = new Map<string, Array<{ id: string; data: any }>>();

const docRef = (path: string) => ({
  get: async () => {
    const stored = docs.get(path);
    return {
      exists: stored !== undefined,
      id: path.split("/").pop(),
      data: () => stored,
    };
  },
});

const snapOf = (rows: Array<{ id: string; data: any }>) => ({
  docs: rows.map((r) => ({ id: r.id, data: () => r.data })),
});

const collectionRef = (name: string): any => ({
  get: async () => snapOf(collections.get(name) ?? []),
  limit: (n: number) => ({
    get: async () => snapOf((collections.get(name) ?? []).slice(0, n)),
  }),
  where: (field: string, _op: string, value: unknown) => ({
    limit: (n: number) => ({
      get: async () =>
        snapOf(
          (collections.get(name) ?? [])
            .filter((r) => r.data[field] === value)
            .slice(0, n),
        ),
    }),
  }),
});

// N-06. The export now spends a daily quota before it reads anything, and the
// quota is a transaction against `users/{uid}/usage/{day}`. Held here rather
// than in the shared docRef store so a test can read the count back.
let usage: Record<string, number> = {};
const usagePaths: string[] = [];

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({
    doc: jest.fn((path: string) => {
      if (path.includes("/usage/")) {
        usagePaths.push(path);
        return { path };
      }
      return docRef(path);
    }),
    collection: jest.fn((name: string) => collectionRef(name)),
    runTransaction: jest.fn(async (fn: (tx: any) => Promise<void>) =>
      fn({
        get: async () => ({ data: () => ({ ...usage }) }),
        set: (_ref: any, data: Record<string, number>) => {
          usage = { ...usage, ...data };
        },
      }),
    ),
  })),
}));

jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

import { HttpsError } from "firebase-functions/v2/https";
import { exportAccountData } from "../account_export";
import { QUOTAS } from "../abuse_guard";

const req = (uid: string | null = "u1"): any => ({
  data: {},
  auth: uid ? { uid, token: {} } : undefined,
  rawRequest: {},
});

beforeEach(() => {
  docs.clear();
  collections.clear();
  usage = {};
  usagePaths.length = 0;
});

test("refuses when signed out", async () => {
  await expect(exportAccountData.run(req(null))).rejects.toBeInstanceOf(
    HttpsError,
  );
});

test("carries every store the inventory lists for this user", async () => {
  docs.set("users/u1/profile/main", { goal: "strength", injuries: ["knee"] });
  docs.set("users/u1/subscription/main", { tier: "standard" });
  docs.set("users/u1/stats/workouts", { total: 12 });
  docs.set("donor_wall/u1", { name: "Ivan" });
  docs.set("coach_listings/u1", { bio: "coach" });
  collections.set("users/u1/workout_logs", [{ id: "l1", data: { reps: 8 } }]);
  collections.set("users/u1/workout_sessions", [{ id: "s1", data: {} }]);
  collections.set("users/u1/scheduled_sessions", [{ id: "sc1", data: {} }]);
  collections.set("users/u1/programmes", [{ id: "p1", data: {} }]);
  collections.set("users/u1/machine_cards", [
    { id: "m1", data: { note: "seat 4" } },
  ]);
  collections.set("users/u1/recognised_equipment", [{ id: "r1", data: {} }]);
  collections.set("users/u1/generated_exercises", [{ id: "g1", data: {} }]);
  collections.set("users/u1/equipment_setup_notes", [
    { id: "n1", data: { note: "seat height 4" } },
  ]);
  collections.set("users/u1/receipts", [
    { id: "2026", data: { totalCents: 4999 } },
  ]);
  collections.set("coach_bookings", [
    { id: "b1", data: { clientUid: "u1", coachUid: "c9" } },
    { id: "b2", data: { clientUid: "c8", coachUid: "u1" } },
  ]);
  collections.set("equipment_reports", [
    { id: "e1", data: { reporterUid: "u1", fault: "cable" } },
  ]);
  collections.set("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);

  const res = await exportAccountData.run(req());

  expect(res.profile).toMatchObject({ injuries: ["knee"] });
  expect(res.subscription).toMatchObject({ tier: "standard" });
  expect(res.stats).toMatchObject({ total: 12 });
  expect(res.workoutLogs).toHaveLength(1);
  expect(res.workoutSessions).toHaveLength(1);
  expect(res.scheduledSessions).toHaveLength(1);
  expect(res.programmes).toHaveLength(1);
  expect(res.machineCards[0]).toMatchObject({ note: "seat 4" });
  expect(res.recognisedEquipment).toHaveLength(1);
  expect(res.generatedExercises).toHaveLength(1);
  expect(res.equipmentSetupNotes[0]).toMatchObject({ note: "seat height 4" });
  expect(res.receipts[0]).toMatchObject({ totalCents: 4999 });
  expect(res.donorWall).toMatchObject({ name: "Ivan" });
  expect(res.coachListing).toMatchObject({ bio: "coach" });
  // Both ends of the marketplace, in one list.
  expect(res.coachBookings.map((b: any) => b.id).sort()).toEqual(["b1", "b2"]);
  expect(res.equipmentReports[0]).toMatchObject({ fault: "cable" });
  expect(res.debugSessions).toHaveLength(1);
});

test("reaches the three collections a phone cannot read at all", async () => {
  // The whole reason A3 is a server function: `firestore.rules:82-87` denies
  // the client every read of `debug_sessions`, and `coach_bookings` /
  // `equipment_reports` have no "all of mine" client query either.
  collections.set("coach_bookings", [
    { id: "b1", data: { clientUid: "u1", coachUid: "c9" } },
  ]);
  collections.set("equipment_reports", [
    { id: "e1", data: { reporterUid: "u1" } },
  ]);
  collections.set("debug_sessions", [{ id: "d1", data: { uid: "u1" } }]);

  const res = await exportAccountData.run(req());

  expect(res.coachBookings).toHaveLength(1);
  expect(res.equipmentReports).toHaveLength(1);
  expect(res.debugSessions).toHaveLength(1);
});

test("never exports another user's rows", async () => {
  collections.set("coach_bookings", [
    { id: "mine", data: { clientUid: "u1", coachUid: "c9" } },
    { id: "theirs", data: { clientUid: "u2", coachUid: "c9" } },
  ]);
  collections.set("equipment_reports", [
    { id: "theirs", data: { reporterUid: "u2" } },
  ]);
  collections.set("debug_sessions", [{ id: "theirs", data: { uid: "u2" } }]);

  const res = await exportAccountData.run(req());

  expect(res.coachBookings.map((b: any) => b.id)).toEqual(["mine"]);
  expect(res.equipmentReports).toEqual([]);
  expect(res.debugSessions).toEqual([]);
});

test("a uid in the request body is ignored", async () => {
  docs.set("users/u1/profile/main", { goal: "mine" });
  docs.set("users/victim/profile/main", { goal: "theirs" });

  const res = await exportAccountData.run({
    data: { uid: "victim" },
    auth: { uid: "u1", token: {} },
    rawRequest: {},
  } as any);

  expect(res.uid).toBe("u1");
  expect(res.profile).toMatchObject({ goal: "mine" });
});

test("a coach's export does not carry their clients' uids or payment ids",
  async () => {
    // Third-party personal data in a file the recipient can forward anywhere.
    collections.set("coach_bookings", [
      {
        id: "b1",
        data: {
          clientUid: "client_7",
          coachUid: "u1",
          priceCents: 5000,
          stripePaymentIntentId: "pi_secret",
          startsAt: "2026-08-01T10:00:00Z",
        },
      },
    ]);

    const res = await exportAccountData.run(req());
    const booking = res.coachBookings[0] as any;

    expect(JSON.stringify(res)).not.toContain("client_7");
    expect(JSON.stringify(res)).not.toContain("pi_secret");
    // What is theirs stays: when it was, what it cost, which side they were on.
    expect(booking.startsAt).toBe("2026-08-01T10:00:00Z");
    expect(booking.priceCents).toBe(5000);
    expect(booking.yourRole).toBe("coach");
  });

test("a capped section is named, never silently short", async () => {
  // A cap that drops rows without saying so is the same lie as a partial
  // export claiming to be whole.
  collections.set(
    "debug_sessions",
    Array.from({ length: 2100 }, (_, i) => ({
      id: `d${i}`,
      data: { uid: "u1" },
    })),
  );

  const res = await exportAccountData.run(req());

  expect(res.debugSessions).toHaveLength(2000);
  expect(res.truncated).toContain("debug_sessions.uid");
  expect((res.notes as string[]).join(" ")).toContain("capped at 2000");
});

test("exactly at the cap is not reported as truncated", async () => {
  collections.set(
    "users/u1/workout_logs",
    Array.from({ length: 2000 }, (_, i) => ({ id: `l${i}`, data: {} })),
  );

  const res = await exportAccountData.run(req());

  expect(res.workoutLogs).toHaveLength(2000);
  expect(res.truncated).toEqual([]);
});

test("absent documents export as null, not as missing keys", async () => {
  // A reader must be able to tell "you have no subscription" from "this export
  // forgot about subscriptions".
  const res = await exportAccountData.run(req());

  expect(res.subscription).toBeNull();
  expect(res.donorWall).toBeNull();
  expect(res.workoutLogs).toEqual([]);
});

test("one failed read fails the whole export instead of shipping it short",
  async () => {
    collections.set("users/u1/workout_logs", [{ id: "l1", data: {} }]);
    const admin = jest.requireMock("firebase-admin");
    // Two `once`s, and a working `runTransaction` on both. The export now
    // spends its N-06 quota before it reads anything, and the quota calls
    // `admin.firestore()` too -- a single `once` was consumed by the quota, so
    // the failing-read mock never reached the code under test and this
    // assertion silently stopped testing anything.
    const failingReads = () => ({
      doc: jest.fn(() => ({
        get: async () => {
          throw new Error("firestore unavailable");
        },
      })),
      collection: jest.fn((name: string) => collectionRef(name)),
      runTransaction: jest.fn(async (fn: (tx: any) => Promise<void>) =>
        fn({ get: async () => ({ data: () => ({}) }), set: () => {} }),
      ),
    });
    // Persistent for the duration, then restored. `once` cannot work here:
    // `db()` is called afresh by every one of the sixteen concurrent reads, so
    // which read receives the failing handle depends on scheduling order --
    // and the quota now takes one before any of them.
    const original = admin.firestore.getMockImplementation();
    admin.firestore.mockImplementation(failingReads);
    try {
      await expect(exportAccountData.run(req())).rejects.toThrow(
        /Could not assemble/,
      );
    } finally {
      admin.firestore.mockImplementation(original);
    }
  });

  test("the export is rate-limited, because it is the heaviest read path",
    async () => {
      // N-06. Sixteen collection reads per call over collections the client
      // may fill itself. The mechanism existed and was pointed at the video
      // endpoints only.
      for (let i = 0; i < QUOTAS.accountExport; i++) {
        await exportAccountData.run(req());
      }
      await expect(exportAccountData.run(req())).rejects.toThrow(
        /resource-exhausted|quota|limit/i,
      );
      expect(usagePaths.some((p) => p.includes("/usage/"))).toBe(true);
    });
