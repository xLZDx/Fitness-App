/**
 * C25 / D-61 (PRIV-25, PRIV-12) - newest-first paging of the body-scan and
 * nutrition collections in `exportAccountData`.
 *
 * The in-memory Firestore double implements `orderBy(field, "desc")`,
 * `startAfter(snapshot)` and `limit(n)` over seeded rows, so the assertions
 * below are about WHICH rows come back in WHAT order, not about call shapes.
 * Document ids are deliberately NOT correlated with `loggedAt` for
 * `food_entries` (real ids are random UUIDs), so a read that falls back to
 * document-id order returns a visibly wrong subset.
 */

const docs = new Map<string, any>();
const collections = new Map<string, Array<{ id: string; data: any }>>();
const logged: unknown[][] = [];

const snapOf = (rows: Array<{ id: string; data: any }>) => ({
  docs: rows.map((r) => ({ id: r.id, data: () => r.data })),
});

const orderedRef = (name: string, field: string, after?: { id: string }): any => {
  const sorted = () => {
    const rows = [...(collections.get(name) ?? [])].sort((a, b) => {
      const av = field === "__name__" ? a.id : a.data[field];
      const bv = field === "__name__" ? b.id : b.data[field];
      return av < bv ? 1 : av > bv ? -1 : 0;
    });
    if (!after) return rows;
    return rows.slice(rows.findIndex((r) => r.id === after.id) + 1);
  };
  return {
    startAfter: (snap: { id: string }) => orderedRef(name, field, snap),
    limit: (n: number) => ({ get: async () => snapOf(sorted().slice(0, n)) }),
  };
};

const collectionRef = (name: string): any => ({
  orderBy: (field: string) => orderedRef(name, field),
  get: async () => snapOf(collections.get(name) ?? []),
  limit: (n: number) => ({
    get: async () => snapOf((collections.get(name) ?? []).slice(0, n)),
  }),
  where: () => ({ limit: () => ({ get: async () => snapOf([]) }) }),
});

let usage: Record<string, number> = {};

jest.mock("firebase-admin", () => ({
  firestore: jest.fn(() => ({
    doc: jest.fn((path: string) => {
      if (path.includes("/usage/")) return { path };
      return {
        get: async () => {
          const stored = docs.get(path);
          if (stored !== undefined) {
            return { exists: true, id: path.split("/").pop(), data: () => stored };
          }
          // A collection member addressed by path (cursor lookup).
          const parts = path.split("/");
          const id = parts.pop()!;
          const row = (collections.get(parts.join("/")) ?? []).find(
            (r) => r.id === id,
          );
          return { exists: row !== undefined, id, data: () => row?.data };
        },
      };
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
  info: (...a: unknown[]) => logged.push(a),
  warn: (...a: unknown[]) => logged.push(a),
  error: (...a: unknown[]) => logged.push(a),
}));

import { exportAccountData } from "../account_export";
import { QUOTAS } from "../abuse_guard";

const run = (data: unknown = {}): Promise<any> =>
  exportAccountData.run({
    data,
    auth: { uid: "u1", token: {} },
    rawRequest: {},
  } as any);

beforeEach(() => {
  docs.clear();
  collections.clear();
  logged.length = 0;
  usage = {};
});

/** 2500 food rows; ids are a permutation unrelated to loggedAt (newest = 2499). */
const foodIds = Array.from({ length: 2500 }, (_, i) => `e${((i * 7919) % 2500).toString(36)}x${i}`);
const seedFood = (n = 2500): void => {
  collections.set(
    "users/u1/food_entries",
    Array.from({ length: n }, (_, i) => ({
      id: foodIds[i],
      data: { loggedAt: i, name: `meal ${i}` },
    })),
  );
};
/** Expected newest-first id list for the first `n` seeded food rows. */
const expectedFood = (n = 2500): string[] =>
  Array.from({ length: n }, (_, k) => foodIds[n - 1 - k]);

/** 800 consecutive days; ids are ISO dates so id order == date order. */
const weightIds = Array.from({ length: 800 }, (_, i) =>
  new Date(Date.UTC(2023, 0, 1 + i)).toISOString().slice(0, 10),
);
const seedWeight = (): void => {
  collections.set(
    "users/u1/weight_entries",
    weightIds.map((id, i) => ({ id, data: { kg: 80 + (i % 5) } })),
  );
};

test("first call returns the newest 500 of each section, with exact paging state", async () => {
  seedFood();
  seedWeight();
  const res = await run();
  expect(res.foodEntries.map((r: any) => r.id)).toEqual(expectedFood().slice(0, 500));
  expect(res.paging.foodEntries).toEqual({
    returned: 500,
    hasMore: true,
    nextCursor: expectedFood()[499],
  });
  expect(res.weightEntries.map((r: any) => r.id)).toEqual(
    [...weightIds].reverse().slice(0, 500),
  );
  expect(res.paging.weightEntries).toEqual({
    returned: 500,
    hasMore: true,
    nextCursor: [...weightIds].reverse()[499],
  });
  // Empty sections are present, empty and final.
  expect(res.bodyScans).toEqual([]);
  expect(res.paging.bodyScans).toEqual({ returned: 0, hasMore: false, nextCursor: null });
  // The legacy `truncated` string array is untouched by paged sections.
  expect(res.truncated).toEqual([]);
});

test("PRIV-25: 2500 food + 800 weight entries are exported completely, newest first, no gaps or duplicates", async () => {
  seedFood();
  seedWeight();
  const first = await run();
  const food: string[] = first.foodEntries.map((r: any) => r.id);
  const weight: string[] = first.weightEntries.map((r: any) => r.id);
  let paging = first.paging;
  let calls = 1;
  while (paging.foodEntries.hasMore || paging.weightEntries.hasMore) {
    const cursors: Record<string, string> = {};
    if (paging.foodEntries.hasMore) cursors.foodEntries = paging.foodEntries.nextCursor;
    if (paging.weightEntries.hasMore) cursors.weightEntries = paging.weightEntries.nextCursor;
    const res = await run({ cursors });
    calls++;
    // A continuation reads only the named sections.
    expect(res.profile).toBeUndefined();
    if (cursors.foodEntries) food.push(...res.foodEntries.map((r: any) => r.id));
    else expect(res.foodEntries).toBeUndefined();
    if (cursors.weightEntries) weight.push(...res.weightEntries.map((r: any) => r.id));
    else expect(res.weightEntries).toBeUndefined();
    paging = { ...paging, ...res.paging };
    expect(calls).toBeLessThan(20);
  }
  expect(calls).toBe(5); // 1 full + 4 continuations (2500 / 500)
  expect(food).toEqual(expectedFood());
  expect(new Set(food).size).toBe(2500);
  expect(weight).toEqual([...weightIds].reverse());
  expect(paging.foodEntries).toEqual({ returned: 500, hasMore: false, nextCursor: null });
  expect(paging.weightEntries).toEqual({ returned: 300, hasMore: false, nextCursor: null });
});

test("page boundary: exactly 500 rows is final, 501 rows has a cursor at the 500th", async () => {
  seedFood(500);
  let res = await run();
  expect(res.paging.foodEntries).toEqual({ returned: 500, hasMore: false, nextCursor: null });

  seedFood(501);
  res = await run();
  expect(res.paging.foodEntries.hasMore).toBe(true);
  expect(res.paging.foodEntries.nextCursor).toBe(expectedFood(501)[499]);
  const next = await run({ cursors: { foodEntries: res.paging.foodEntries.nextCursor } });
  expect(next.foodEntries.map((r: any) => r.id)).toEqual([expectedFood(501)[500]]);
  expect(next.paging.foodEntries).toEqual({ returned: 1, hasMore: false, nextCursor: null });
});

test("continuations are charged to accountExportPage (150/day), not the 3/day export quota", async () => {
  seedFood();
  await run(); // full export: 1 of 3
  await run({ cursors: { foodEntries: expectedFood()[499] } });
  await run({ cursors: { foodEntries: expectedFood()[999] } });
  expect(usage.accountExport).toBe(1);
  expect(usage.accountExportPage).toBe(2);
  expect(QUOTAS.accountExport).toBe(3);

  // The full-export quota exhausted does not block paging ...
  usage = { accountExport: 3, accountExportPage: 10 };
  const res = await run({ cursors: { foodEntries: expectedFood()[499] } });
  expect(res.foodEntries).toHaveLength(500);
  expect(usage.accountExport).toBe(3);
  expect(usage.accountExportPage).toBe(11);
  // ... but a fresh full export is refused.
  await expect(run()).rejects.toMatchObject({ code: "resource-exhausted" });
});

test("the page counter is bounded at 150/day and a refusal reads nothing", async () => {
  seedFood();
  usage = { accountExportPage: 149 };
  await run({ cursors: { foodEntries: expectedFood()[499] } });
  expect(usage.accountExportPage).toBe(150);
  await expect(
    run({ cursors: { foodEntries: expectedFood()[499] } }),
  ).rejects.toMatchObject({ code: "resource-exhausted" });
  expect(usage.accountExportPage).toBe(150);
  // A full export is still possible: separate counter.
  const full = await run();
  expect(full.foodEntries).toHaveLength(500);
});

test("scan rows are newest first by takenAt, carry photoLinksAvailable and never a link or path field", async () => {
  collections.set("users/u1/body_scans", [
    {
      id: "a-old",
      data: {
        takenAt: 1,
        photosState: "stored",
        signedUrl: "https://example.invalid/x?sig=1",
        downloadUrl: "https://example.invalid/y?sig=2",
        photoLink: "https://example.invalid/z",
        objectPath: "users/u1/scans/s1/front.jpg",
        storagePath: "users/u1/scans/s1/side.jpg",
        weightKg: 80,
      },
    },
    { id: "z-mid", data: { takenAt: 2, photosState: "deleted" } },
    { id: "m-new", data: { takenAt: 3, photosState: "none" } },
  ]);
  const res = await run();
  expect(res.bodyScans.map((r: any) => r.id)).toEqual(["m-new", "z-mid", "a-old"]);
  const old = res.bodyScans[2];
  expect(old.photoLinksAvailable).toBe(true);
  expect(old.weightKg).toBe(80);
  expect(Object.keys(old).sort()).toEqual(
    ["id", "photoLinksAvailable", "photosState", "takenAt", "weightKg"],
  );
  expect(res.bodyScans[0].photoLinksAvailable).toBeUndefined();
  expect(res.bodyScans[1].photoLinksAvailable).toBeUndefined();
  expect(JSON.stringify(res)).not.toMatch(/sig=|example\.invalid|objectPath|front\.jpg|side\.jpg/);
});

test("D-67: single-document sections and the response notes contain no signed URL, and nothing photo-related is logged", async () => {
  docs.set("users/u1/body_scan_settings/main", { retentionDays: 0 });
  docs.set("users/u1/nutrition_plan/main", { status: "active" });
  collections.set("users/u1/body_scans", [
    { id: "s1", data: { takenAt: 1, photosState: "stored", signedUrl: "https://x.invalid/?sig=1" } },
  ]);
  const res = await run();
  expect(res.bodyScanSettings).toMatchObject({ id: "main", retentionDays: 0 });
  expect(res.nutritionPlan).toMatchObject({ id: "main", status: "active" });
  expect(res.notes.join(" ")).toMatch(/no photo links/i);
  expect(JSON.stringify(res)).not.toContain("sig=1");
  expect(JSON.stringify(logged)).not.toContain("sig=1");
});

test("a stale cursor is refused with failed-precondition and consumes no full-export quota", async () => {
  seedFood(10);
  await expect(run({ cursors: { foodEntries: "deleted-since" } })).rejects.toMatchObject({
    code: "failed-precondition",
  });
  expect(usage.accountExport).toBeUndefined();
});

test.each([
  ["unknown section", { nope: "x" }],
  ["slash in cursor", { foodEntries: "a/b" }],
  ["empty cursor", { foodEntries: "" }],
  ["non-string cursor", { foodEntries: 5 }],
  ["over-long cursor", { foodEntries: "x".repeat(201) }],
])("malformed cursor (%s) is invalid-argument", async (_n, cursors) => {
  await expect(run({ cursors })).rejects.toMatchObject({ code: "invalid-argument" });
});

test.each([["a string", "foodEntries"], ["an array", ["x"]]])(
  "cursors given as %s is invalid-argument",
  async (_n, cursors) => {
    await expect(run({ cursors })).rejects.toMatchObject({ code: "invalid-argument" });
  },
);

test("saved_foods and nutrition_plan_reviews page by document id descending", async () => {
  collections.set("users/u1/saved_foods", [
    { id: "b", data: {} },
    { id: "a", data: {} },
    { id: "c", data: { createdAt: 1 } },
  ]);
  collections.set("users/u1/nutrition_plan_reviews", [
    { id: "2026-W02", data: { decision: "keep" } },
    { id: "2026-W10", data: { decision: "keep" } },
  ]);
  const res = await run();
  // The row lacking createdAt is not dropped: ordering does not depend on it.
  expect(res.savedFoods.map((r: any) => r.id)).toEqual(["c", "b", "a"]);
  expect(res.nutritionPlanReviews.map((r: any) => r.id)).toEqual(["2026-W10", "2026-W02"]);
});
