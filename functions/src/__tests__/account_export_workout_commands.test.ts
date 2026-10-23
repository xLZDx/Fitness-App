/**
 * V0 offline command protocol - export of `workout_typed_sessions` and
 * `workout_command_receipts` through `exportAccountData`.
 *
 * Same in-memory Firestore double as account_export_paging.test.ts: it honours
 * orderBy(desc)/startAfter/limit over per-path seeded rows, so the assertions
 * are about WHICH rows leave in WHAT order and with WHICH fields. Rows of
 * another account live under a different `users/<uid>/...` path: if the code
 * ever read a wrong or unscoped path they would show up in the output.
 */
import * as fs from "fs";
import * as path from "path";

const docs = new Map<string, any>();
const collections = new Map<string, Array<{ id: string; data: any }>>();
const readPaths: string[] = [];

const snapOf = (rows: Array<{ id: string; data: any }>) => ({
  docs: rows.map((r) => ({ id: r.id, data: () => r.data })),
});

const orderedRef = (name: string, field: string, after?: { id: string }): any => {
  const sorted = () => {
    readPaths.push(name);
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
    doc: jest.fn((p: string) => {
      if (p.includes("/usage/")) return { path: p };
      return {
        get: async () => {
          const stored = docs.get(p);
          if (stored !== undefined) {
            return { exists: true, id: p.split("/").pop(), data: () => stored };
          }
          const parts = p.split("/");
          const id = parts.pop()!;
          const row = (collections.get(parts.join("/")) ?? []).find((r) => r.id === id);
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
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

import { exportAccountData, MAX_EXPORT_BYTES } from "../account_export";

const run = (data: unknown = {}, uid = "u1"): Promise<any> =>
  exportAccountData.run({ data, auth: { uid, token: {} }, rawRequest: {} } as any);

beforeEach(() => {
  docs.clear();
  collections.clear();
  readPaths.length = 0;
  usage = {};
});

const TYPED = "users/u1/workout_typed_sessions";
const RECEIPTS = "users/u1/workout_command_receipts";
const HASH = "sha256:deadbeefcafe0123456789";

/** Sortable ids ("s0001"...): the export orders by document id, descending. */
const ids = (n: number, prefix: string): string[] =>
  Array.from({ length: n }, (_, i) => `${prefix}${String(i + 1).padStart(4, "0")}`);

const seedTyped = (name: string, n: number, extra: Record<string, unknown> = {}): string[] => {
  const list = ids(n, "s");
  collections.set(
    name,
    list.map((id, i) => ({
      id,
      data: { exercises: [{ name: "squat", sets: i }], revision: i, writerTokenHash: HASH, ...extra },
    })),
  );
  return list;
};

const seedReceipts = (name: string, n: number, extra: Record<string, unknown> = {}): string[] => {
  const list = ids(n, "op");
  collections.set(
    name,
    list.map((id, i) => ({ id, data: { result: "applied", setSeq: i, ...extra } })),
  );
  return list;
};

describe("workoutTypedSessions", () => {
  test("owner sessions are exported newest id first, with content and bookkeeping intact", async () => {
    const list = seedTyped(TYPED, 3);
    const res = await run();
    expect(res.workoutTypedSessions.map((r: any) => r.id)).toEqual([...list].reverse());
    expect(res.workoutTypedSessions[0]).toMatchObject({
      id: "s0003",
      revision: 2,
      exercises: [{ name: "squat", sets: 2 }],
    });
    expect(res.paging.workoutTypedSessions).toEqual({ returned: 3, hasMore: false, nextCursor: null });
  });

  test("writerTokenHash is withheld from every row, first page and continuation, wherever it sits", async () => {
    seedTyped(TYPED, 700); // every stored doc carries writerTokenHash
    const first = await run();
    expect(first.workoutTypedSessions).toHaveLength(500);
    for (const r of first.workoutTypedSessions) expect(r).not.toHaveProperty("writerTokenHash");
    const next = await run({
      cursors: { workoutTypedSessions: first.paging.workoutTypedSessions.nextCursor },
    });
    expect(next.workoutTypedSessions).toHaveLength(200);
    for (const r of next.workoutTypedSessions) expect(r).not.toHaveProperty("writerTokenHash");
    // Strongest form: the secret-derived value appears nowhere in either response.
    expect(JSON.stringify(first)).not.toContain(HASH);
    expect(JSON.stringify(first)).not.toContain("writerTokenHash");
    expect(JSON.stringify(next)).not.toContain(HASH);
    // Only the withheld field is removed: the other server-side keys stay.
    expect(Object.keys(first.workoutTypedSessions[0]).sort()).toEqual(["exercises", "id", "revision"]);
  });

  test("a stored writerTokenHash with a null/odd value is still dropped", async () => {
    collections.set(TYPED, [
      { id: "a", data: { writerTokenHash: null, n: 1 } },
      { id: "b", data: { writerTokenHash: { nested: HASH }, n: 2 } },
      { id: "c", data: { n: 3 } },
    ]);
    const res = await run();
    expect(res.workoutTypedSessions.map((r: any) => r.id)).toEqual(["c", "b", "a"]);
    expect(JSON.stringify(res)).not.toMatch(/writerTokenHash|deadbeef/);
  });

  test("paging: 1200 rows come back as 500+500+200, no gaps or duplicates, exact cursors", async () => {
    const list = seedTyped(TYPED, 1200);
    const expected = [...list].reverse();
    const first = await run();
    expect(first.paging.workoutTypedSessions).toEqual({
      returned: 500,
      hasMore: true,
      nextCursor: expected[499],
    });
    const got: string[] = first.workoutTypedSessions.map((r: any) => r.id);
    let cursor: string | null = first.paging.workoutTypedSessions.nextCursor;
    let calls = 1;
    while (cursor) {
      const res = await run({ cursors: { workoutTypedSessions: cursor } });
      calls++;
      expect(res.profile).toBeUndefined();
      expect(res.workoutCommandReceipts).toBeUndefined(); // only the named section
      got.push(...res.workoutTypedSessions.map((r: any) => r.id));
      cursor = res.paging.workoutTypedSessions.nextCursor;
      expect(calls).toBeLessThan(10);
    }
    expect(calls).toBe(3);
    expect(got).toEqual(expected);
    expect(new Set(got).size).toBe(1200);
  });

  test("boundary: exactly 500 rows is final, 501 has a cursor at the 500th", async () => {
    seedTyped(TYPED, 500);
    let res = await run();
    expect(res.paging.workoutTypedSessions).toEqual({ returned: 500, hasMore: false, nextCursor: null });
    const list = seedTyped(TYPED, 501);
    res = await run();
    expect(res.paging.workoutTypedSessions.hasMore).toBe(true);
    expect(res.paging.workoutTypedSessions.nextCursor).toBe([...list].reverse()[499]);
  });

  test("tenant isolation: another account's typed sessions never appear", async () => {
    seedTyped(TYPED, 2);
    collections.set("users/u2/workout_typed_sessions", [
      { id: "zzz-other", data: { exercises: [], writerTokenHash: "OTHER-HASH", marker: "OTHER-ACCOUNT" } },
    ]);
    const res = await run();
    expect(res.workoutTypedSessions.map((r: any) => r.id)).toEqual(["s0002", "s0001"]);
    expect(JSON.stringify(res)).not.toMatch(/OTHER-ACCOUNT|zzz-other|OTHER-HASH/);
    // The other account asking sees only its own row.
    const other = await run({}, "u2");
    expect(other.workoutTypedSessions.map((r: any) => r.id)).toEqual(["zzz-other"]);
    expect(JSON.stringify(other)).not.toMatch(/"s000[12]"/);
    // Every paged read stayed inside a users/<caller>/ path.
    expect(readPaths.filter((p) => p.includes("workout_typed_sessions"))).toEqual([
      TYPED,
      "users/u2/workout_typed_sessions",
    ]);
  });

  test("cursor naming another account's session id (not in caller's collection) is a stale-position refusal", async () => {
    seedTyped(TYPED, 2);
    collections.set("users/u2/workout_typed_sessions", [{ id: "theirs", data: {} }]);
    await expect(run({ cursors: { workoutTypedSessions: "theirs" } })).rejects.toMatchObject({
      code: "failed-precondition",
    });
  });

  test("empty collection yields an empty, final section", async () => {
    const res = await run();
    expect(res.workoutTypedSessions).toEqual([]);
    expect(res.paging.workoutTypedSessions).toEqual({ returned: 0, hasMore: false, nextCursor: null });
  });
});

describe("workoutCommandReceipts", () => {
  test("owner receipts are exported newest id first with all fields", async () => {
    const list = seedReceipts(RECEIPTS, 3);
    const res = await run();
    expect(res.workoutCommandReceipts.map((r: any) => r.id)).toEqual([...list].reverse());
    expect(res.workoutCommandReceipts[0]).toEqual({ id: "op0003", result: "applied", setSeq: 2 });
    expect(res.paging.workoutCommandReceipts).toEqual({ returned: 3, hasMore: false, nextCursor: null });
  });

  test("paging: 1100 receipts come back as 500+500+100 with no gaps or duplicates", async () => {
    const list = seedReceipts(RECEIPTS, 1100);
    const first = await run();
    const got: string[] = first.workoutCommandReceipts.map((r: any) => r.id);
    let cursor: string | null = first.paging.workoutCommandReceipts.nextCursor;
    expect(cursor).toBe([...list].reverse()[499]);
    let calls = 1;
    while (cursor) {
      const res = await run({ cursors: { workoutCommandReceipts: cursor } });
      calls++;
      expect(res.workoutTypedSessions).toBeUndefined();
      got.push(...res.workoutCommandReceipts.map((r: any) => r.id));
      cursor = res.paging.workoutCommandReceipts.nextCursor;
      expect(calls).toBeLessThan(10);
    }
    expect(calls).toBe(3);
    expect(got).toEqual([...list].reverse());
  });

  test("tenant isolation: another account's receipts never appear", async () => {
    seedReceipts(RECEIPTS, 2);
    collections.set("users/u2/workout_command_receipts", [
      { id: "op9999", data: { marker: "OTHER-RECEIPT" } },
    ]);
    const res = await run();
    expect(res.workoutCommandReceipts.map((r: any) => r.id)).toEqual(["op0002", "op0001"]);
    expect(JSON.stringify(res)).not.toMatch(/OTHER-RECEIPT|op9999/);
  });

  test("empty collection yields an empty, final section", async () => {
    const res = await run();
    expect(res.workoutCommandReceipts).toEqual([]);
    expect(res.paging.workoutCommandReceipts).toEqual({ returned: 0, hasMore: false, nextCursor: null });
  });

  test("fence, policy and counters collections are not exported", async () => {
    seedReceipts(RECEIPTS, 1);
    collections.set("users/u1/workout_command_fence", [{ id: "f0", data: { marker: "FENCE-DIGEST" } }]);
    collections.set("users/u1/workout_command_policy", [{ id: "current", data: { marker: "POLICY-X" } }]);
    collections.set("users/u1/workout_command_counters", [{ id: "2026-10-23", data: { marker: "COUNTER-X" } }]);
    const res = await run();
    expect(JSON.stringify(res)).not.toMatch(/FENCE-DIGEST|POLICY-X|COUNTER-X/);
    expect(Object.keys(res)).not.toEqual(
      expect.arrayContaining(["workoutCommandFence"]),
    );
  });
});

describe("byte budget with the new sections present", () => {
  const big = "x".repeat(10_000);

  test("oversized new sections are trimmed to fit, keep a valid cursor, and the rest arrives by continuation", async () => {
    // 500 x ~10 KB per section = ~10 MB > MAX_EXPORT_BYTES (8 MiB).
    const typedIds = seedTyped(TYPED, 500, { blob: big });
    const recIds = seedReceipts(RECEIPTS, 500, { blob: big });
    const res = await run();
    const body = JSON.stringify(res);
    expect(Buffer.byteLength(body, "utf8")).toBeLessThanOrEqual(MAX_EXPORT_BYTES);

    for (const [key, all] of [
      ["workoutTypedSessions", [...typedIds].reverse()],
      ["workoutCommandReceipts", [...recIds].reverse()],
    ] as const) {
      const rows: any[] = res[key];
      const p = res.paging[key];
      expect(rows.length).toBeGreaterThan(0);
      // Trimmed rows are a prefix of the newest-first list, never a random subset.
      expect(rows.map((r) => r.id)).toEqual(all.slice(0, rows.length));
      if (rows.length < 500) {
        expect(p).toEqual({ returned: rows.length, hasMore: true, nextCursor: rows[rows.length - 1].id });
        const cont = await run({ cursors: { [key]: p.nextCursor } });
        expect(cont[key][0].id).toBe(all[rows.length]); // exactly the next row: nothing lost
      }
    }
    // At least one section really was trimmed (otherwise the test proves nothing).
    expect(
      res.workoutTypedSessions.length < 500 || res.workoutCommandReceipts.length < 500,
    ).toBe(true);
    expect(body).not.toContain("writerTokenHash");
    expect(body).not.toContain(HASH);
  });

  test("small new sections do not disturb the legacy sections or other paged sections", async () => {
    seedTyped(TYPED, 2);
    seedReceipts(RECEIPTS, 2);
    collections.set("users/u1/food_entries", [{ id: "f1", data: { loggedAt: 1, name: "m" } }]);
    const res = await run();
    expect(res.foodEntries.map((r: any) => r.id)).toEqual(["f1"]);
    expect(res.truncated).toEqual([]);
    expect(res.paging.workoutTypedSessions.hasMore).toBe(false);
    expect(res.paging.workoutCommandReceipts.hasMore).toBe(false);
  });
});

describe("lifecycle policy matches the export code", () => {
  const repo = path.resolve(__dirname, "../../..");
  const policy = JSON.parse(
    fs.readFileSync(path.join(repo, "scripts/ci/data_lifecycle_policy.json"), "utf8"),
  );
  const entries: Record<string, { classification: string }> =
    policy.collections ?? policy.entries ?? policy;
  const src = fs.readFileSync(path.join(__dirname, "../account_export.ts"), "utf8");
  const exportedPaths = new Set(
    [...src.matchAll(/path:\s*"([a-z_]+)"/g)].map((m) => m[1]),
  );

  test.each(["workout_typed_sessions", "workout_command_receipts"])(
    "%s is a paged export section in code and BOTH in policy",
    (c) => {
      expect(exportedPaths.has(c)).toBe(true);
      expect(entries[c].classification).toBe("BOTH");
    },
  );

  test.each(["workout_command_fence", "workout_command_policy", "workout_command_counters"])(
    "%s is not exported by code and is DELETE (not export-classified) in policy",
    (c) => {
      expect(exportedPaths.has(c)).toBe(false);
      expect(src).not.toContain(c);
      expect(entries[c].classification).toBe("DELETE");
    },
  );

  test("the code withholds writerTokenHash by declaration", () => {
    expect(src).toMatch(/TYPED_SESSION_WITHHELD_FIELDS\s*=\s*\[\s*"writerTokenHash"/);
  });
});
