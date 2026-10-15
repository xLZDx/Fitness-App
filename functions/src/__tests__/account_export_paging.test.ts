/**
 * C25 / D-61 — newest-first paging of the body-scan and nutrition collections.
 */

const docs = new Map<string, any>();
const collections = new Map<string, Array<{ id: string; data: any }>>();

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

const usage: Record<string, Record<string, number>> = {};

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
          return {
            exists: row !== undefined,
            id,
            data: () => row?.data,
          };
        },
      };
    }),
    collection: jest.fn((name: string) => collectionRef(name)),
    runTransaction: jest.fn(async (fn: (tx: any) => Promise<void>) =>
      fn({
        get: async () => ({ data: () => ({ ...(usage.u1 ?? {}) }) }),
        set: (_ref: any, data: Record<string, number>) => {
          usage.u1 = { ...(usage.u1 ?? {}), ...data };
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

import { exportAccountData } from "../account_export";

const req = (data: unknown = {}): any => ({
  data,
  auth: { uid: "u1", token: {} },
  rawRequest: {},
});

beforeEach(() => {
  docs.clear();
  collections.clear();
  delete usage.u1;
});

const seed = (): void => {
  collections.set(
    "users/u1/food_entries",
    Array.from({ length: 1200 }, (_, i) => ({
      id: `f${String(i).padStart(4, "0")}`,
      data: { loggedAt: i, name: `meal ${i}` },
    })),
  );
  collections.set(
    "users/u1/weight_entries",
    Array.from({ length: 800 }, (_, i) => ({
      id: `2024-01-${String(i).padStart(4, "0")}`,
      data: { kg: 80 },
    })),
  );
};

test("food_entries and weight_entries come newest first with per-section paging", async () => {
  seed();
  const res: any = await exportAccountData.run(req());
  expect(res.foodEntries[0].id).toBe("f1199");
  expect(res.foodEntries).toHaveLength(500);
  expect(res.paging.foodEntries).toEqual({
    returned: 500,
    hasMore: true,
    nextCursor: "f0700",
  });
  expect(res.weightEntries[0].id).toBe("2024-01-0799");
  expect(res.paging.weightEntries.hasMore).toBe(true);
  expect(res.paging.bodyScans).toEqual({
    returned: 0,
    hasMore: false,
    nextCursor: null,
  });
});

test("a continuation page resumes after the cursor, reads only named sections and ends", async () => {
  seed();
  let cursor = "f0700";
  const ids: string[] = [];
  let pages = 0;
  for (;;) {
    const res: any = await exportAccountData.run(
      req({ cursors: { foodEntries: cursor } }),
    );
    pages++;
    expect(res.weightEntries).toBeUndefined();
    expect(res.profile).toBeUndefined();
    ids.push(...res.foodEntries.map((r: any) => r.id));
    if (!res.paging.foodEntries.hasMore) break;
    cursor = res.paging.foodEntries.nextCursor;
  }
  expect(pages).toBe(2);
  expect(ids).toHaveLength(700);
  expect(ids[0]).toBe("f0699");
  expect(ids[ids.length - 1]).toBe("f0000");
  // Continuations do not spend the 3/day full-export quota.
  expect(usage.u1.accountExport).toBeUndefined();
  expect(usage.u1.accountExportPage).toBe(2);
});

test("scan rows carry photoLinksAvailable and never a link or path field", async () => {
  collections.set("users/u1/body_scans", [
    {
      id: "s1",
      data: {
        takenAt: 1,
        photosState: "stored",
        signedUrl: "https://example.invalid/x?sig=1",
        objectPath: "users/u1/scans/s1/front.jpg",
      },
    },
    { id: "s2", data: { takenAt: 2, photosState: "deleted" } },
  ]);
  const res: any = await exportAccountData.run(req());
  expect(res.bodyScans.map((r: any) => r.id)).toEqual(["s2", "s1"]);
  expect(res.bodyScans[1].photoLinksAvailable).toBe(true);
  expect(res.bodyScans[0].photoLinksAvailable).toBeUndefined();
  expect(JSON.stringify(res)).not.toMatch(/sig=1|objectPath|front\.jpg/);
});

test("a stale cursor is refused with failed-precondition, malformed ones with invalid-argument", async () => {
  await expect(
    exportAccountData.run(req({ cursors: { foodEntries: "gone" } })),
  ).rejects.toMatchObject({ code: "failed-precondition" });
  await expect(
    exportAccountData.run(req({ cursors: { nope: "x" } })),
  ).rejects.toMatchObject({ code: "invalid-argument" });
  await expect(
    exportAccountData.run(req({ cursors: { foodEntries: "a/b" } })),
  ).rejects.toMatchObject({ code: "invalid-argument" });
});
