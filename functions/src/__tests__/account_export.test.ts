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

// C25: `orderBy(field, "desc")` + `startAfter(snapshot)` + `limit` over the same
// in-memory rows. "__name__" orders by document id.
const orderedRef = (
  name: string,
  field: string,
  after?: { id: string },
): any => {
  const sorted = () => {
    const rows = [...(collections.get(name) ?? [])].sort((a, b) => {
      const av = field === "__name__" ? a.id : a.data[field];
      const bv = field === "__name__" ? b.id : b.data[field];
      return av < bv ? 1 : av > bv ? -1 : 0;
    });
    if (!after) return rows;
    const i = rows.findIndex((r) => r.id === after.id);
    return rows.slice(i + 1);
  };
  return {
    startAfter: (snap: { id: string }) => orderedRef(name, field, snap),
    limit: (n: number) => ({ get: async () => snapOf(sorted().slice(0, n)) }),
  };
};

const collectionRef = (name: string): any => ({
  orderBy: (field: string, _dir: string) => orderedRef(name, field),
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
import {
  exportAccountData,
  HARD_RESPONSE_BYTES,
  MAX_EXPORT_BYTES,
} from "../account_export";
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
  docs.set("users/u1/stats/workout_sessions", { longestStreakDays: 5 });
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
  expect(res.workoutSessionStats).toMatchObject({ longestStreakDays: 5 });
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
  expect(res.coachBookings.map((b: any) => b.yourRole).sort()).toEqual([
    "client",
    "coach",
  ]);
  // The client keeps their own booking id; the coach's row carries none.
  const asClient: any = res.coachBookings.find(
    (b: any) => b.yourRole === "client",
  );
  const asCoach: any = res.coachBookings.find(
    (b: any) => b.yourRole === "coach",
  );
  expect(asClient.id).toBe("b1");
  expect(asCoach).not.toHaveProperty("id");
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
        // Legacy id shape: the client's uid is embedded in the doc id itself.
        id: "bk_1_client_7",
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
    expect(booking).not.toHaveProperty("id");
    // What is theirs stays: when it was, what it cost, which side they were on.
    expect(booking.startsAt).toBe("2026-08-01T10:00:00Z");
    expect(booking.priceCents).toBe(5000);
    expect(booking.yourRole).toBe("coach");
  });

test("a self-booking matched by both queries is exported once, as the client's own row",
  async () => {
    // One session must not be counted twice in someone's data export, and a
    // row that is the user's own as client keeps its id (the client's own
    // reference) and is not relabelled as the coach side.
    collections.set("coach_bookings", [
      {
        id: "bk_self",
        data: { clientUid: "u1", coachUid: "u1", priceCents: 4000, stripePaymentIntentId: "pi_x" },
      },
    ]);

    const res = await exportAccountData.run(req());

    expect(res.coachBookings).toHaveLength(1);
    expect(res.coachBookings[0]).toMatchObject({
      id: "bk_self",
      yourRole: "client",
      priceCents: 4000,
    });
    expect(JSON.stringify(res)).not.toContain("pi_x");
  });

test("bookings where the user is client and where the user is coach are both listed, each with its own role",
  async () => {
    collections.set("coach_bookings", [
      { id: "asClient", data: { clientUid: "u1", coachUid: "c9" } },
      { id: "asCoach", data: { clientUid: "c8", coachUid: "u1" } },
    ]);

    const res = await exportAccountData.run(req());

    const byRole = Object.fromEntries(
      res.coachBookings.map((b: any) => [b.yourRole, b]),
    );
    expect(res.coachBookings).toHaveLength(2);
    expect(byRole.client.id).toBe("asClient");
    expect(byRole.coach).not.toHaveProperty("id");
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

test("an export over the byte ceiling is trimmed and named, never silently short",
  async () => {
    // 1500 rows is under MAX_ROWS, but ~15 MB serialized is over the ceiling.
    const blob = "x".repeat(10_000);
    collections.set(
      "debug_sessions",
      Array.from({ length: 1500 }, (_, i) => ({
        id: `d${i}`,
        data: { uid: "u1", blob },
      })),
    );

    const res = await exportAccountData.run(req());

    expect(res.truncated).toContain("debugSessions");
    expect(res.debugSessions.length).toBeLessThan(1500);
    expect(Buffer.byteLength(JSON.stringify(res), "utf8")).toBeLessThanOrEqual(
      MAX_EXPORT_BYTES + 4096,
    );
    expect((res.notes as string[]).join(" ")).toContain("bytes");
  });

test("an export under the byte ceiling is returned untouched, with no truncated entry",
  async () => {
    // ~7 MB serialized: large, but below MAX_EXPORT_BYTES (8 MiB).
    const blob = "x".repeat(10_000);
    collections.set(
      "debug_sessions",
      Array.from({ length: 700 }, (_, i) => ({
        id: `d${i}`,
        data: { uid: "u1", blob },
      })),
    );

    const res = await exportAccountData.run(req());

    expect(res.debugSessions).toHaveLength(700);
    expect(res.truncated).toEqual([]);
    expect((res.notes as string[]).join(" ")).not.toContain("bytes");
  });

test("F-03: a single oversized non-array section over the hard ceiling is rejected, no data",
  async () => {
    // The byte guard only trims array sections; a 10 MiB profile document
    // cannot be trimmed and must not be returned as a success.
    docs.set("users/u1/profile/main", {
      blob: "x".repeat(HARD_RESPONSE_BYTES + 1024),
    });

    let caught: any;
    let res: any;
    try {
      res = await exportAccountData.run(req());
    } catch (e) {
      caught = e;
    }

    expect(res).toBeUndefined();
    expect(caught).toBeInstanceOf(HttpsError);
    expect(caught.code).toBe("resource-exhausted");
    expect(String(caught.message)).not.toContain("xxxx");
  });

test("F-03: a non-array response between the soft and hard ceilings still succeeds",
  async () => {
    // ~8.5 MiB: over MAX_EXPORT_BYTES (nothing to trim), under the hard ceiling.
    const size = MAX_EXPORT_BYTES + 512 * 1024;
    expect(size).toBeLessThan(HARD_RESPONSE_BYTES);
    docs.set("users/u1/profile/main", { blob: "x".repeat(size) });

    const res = await exportAccountData.run(req());

    expect((res.profile as { blob: string }).blob).toHaveLength(size);
    const bytes = Buffer.byteLength(JSON.stringify(res), "utf8");
    expect(bytes).toBeGreaterThan(MAX_EXPORT_BYTES);
    expect(bytes).toBeLessThanOrEqual(HARD_RESPONSE_BYTES);
  });

test("every section trimmed for size is named, once, and keeps its leading rows",
  async () => {
    // Two sections of ~6 MB each: ~12 MB total, so BOTH must be trimmed.
    const blob = "x".repeat(10_000);
    collections.set(
      "users/u1/workout_logs",
      Array.from({ length: 600 }, (_, i) => ({ id: `l${i}`, data: { blob } })),
    );
    collections.set(
      "debug_sessions",
      Array.from({ length: 600 }, (_, i) => ({
        id: `d${i}`,
        data: { uid: "u1", blob },
      })),
    );

    const res = await exportAccountData.run(req());

    expect(res.truncated).toContain("workoutLogs");
    expect(res.truncated).toContain("debugSessions");
    expect(new Set(res.truncated).size).toBe(res.truncated.length);
    expect(res.workoutLogs.length).toBeLessThan(600);
    expect(res.debugSessions.length).toBeLessThan(600);
    // Trailing rows are dropped; the leading rows survive in order.
    expect(res.workoutLogs[0]).toMatchObject({ id: "l0" });
    expect(res.debugSessions[0]).toMatchObject({ id: "d0" });
    expect(Buffer.byteLength(JSON.stringify(res), "utf8")).toBeLessThanOrEqual(
      MAX_EXPORT_BYTES + 4096,
    );
  });

test("a section that hit the row cap and the byte ceiling is named once",
  async () => {
    // 2100 rows hits MAX_ROWS (named "debug_sessions.uid"); 2000 kept rows of
    // 10 KB is ~20 MB, so the byte guard trims it as well ("debugSessions").
    const blob = "x".repeat(10_000);
    collections.set(
      "debug_sessions",
      Array.from({ length: 2100 }, (_, i) => ({
        id: `d${i}`,
        data: { uid: "u1", blob },
      })),
    );

    const res = await exportAccountData.run(req());

    expect(res.truncated).toContain("debug_sessions.uid");
    expect(res.truncated).toContain("debugSessions");
    expect(res.truncated.filter((n: string) => n === "debugSessions")).toHaveLength(1);
    expect(Buffer.byteLength(JSON.stringify(res), "utf8")).toBeLessThanOrEqual(
      MAX_EXPORT_BYTES + 4096,
    );
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
