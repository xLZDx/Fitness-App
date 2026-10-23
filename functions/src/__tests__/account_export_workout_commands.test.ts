/**
 * V0 offline command protocol - export of `workout_typed_sessions` and the
 * replay fence (section workoutCommandOutcomes) through `exportAccountData`.
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
/** One entry per server read: collection, requested limit, documents returned. */
const reads: Array<{ name: string; limit: number; returned: number }> = [];

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
    limit: (n: number) => ({
      get: async () => {
        const out = sorted().slice(0, n);
        reads.push({ name, limit: n, returned: out.length });
        return snapOf(out);
      },
    }),
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
  reads.length = 0;
  usage = {};
});

const TYPED = "users/u1/workout_typed_sessions";
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
      expect(res.workoutCommandOutcomes).toBeUndefined(); // only the named section
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


const FENCE = "users/u1/workout_command_fence";
const PAYLOAD = "HASHPREFIX1"; // 11 chars: the withheld payload-hash prefix
const key22 = (shard: string, i: number): string =>
  `k${shard}${String(i).padStart(5, "0")}`.padEnd(22, "_");
const fenceValue = (code: string, digest: string): string => code + digest + PAYLOAD;
const digestOf = (shard: string, i: number): string =>
  `d${shard}${i}`.padEnd(11, "x").slice(0, 11);
const shardIds = (n: number): string[] =>
  Array.from({ length: n }, (_, i) => i.toString(16).padStart(2, "0"));

/** Seeds `shards` fence docs with `per` entries each; returns every operationKey. */
const seedFence = (name: string, shards: number, per: number): string[] => {
  const all: string[] = [];
  collections.set(
    name,
    shardIds(shards).map((sh) => {
      const e: Record<string, string> = {};
      for (let i = 0; i < per; i++) {
        const k = key22(sh, i);
        e[k] = fenceValue("CRS"[i % 3], digestOf(sh, i));
        all.push(k);
      }
      return { id: sh, data: { e } };
    }),
  );
  return all;
};

/** Client-style loop: first full call, then follow cursors until nothing has more. */
const exportAll = async (
  key: "workoutTypedSessions" | "workoutCommandOutcomes",
): Promise<{ rows: any[]; calls: number; responses: any[] }> => {
  const first = await run();
  const responses = [first];
  const rows: any[] = [...first[key]];
  let cursor: string | null = first.paging[key].nextCursor;
  let calls = 1;
  while (cursor) {
    const res = await run({ cursors: { [key]: cursor } });
    responses.push(res);
    calls++;
    rows.push(...res[key]);
    cursor = res.paging[key].nextCursor;
    if (calls > 50) throw new Error("client 50-page cap exceeded");
  }
  return { rows, calls, responses };
};

describe("workoutCommandOutcomes (fence)", () => {
  test("row shape: shard id, entries sorted by operationKey, code and session digest only", async () => {
    collections.set(FENCE, [
      {
        id: "0a",
        data: {
          e: {
            zzz: fenceValue("S", "SESSIONDIG2"),
            aaa: fenceValue("C", "SESSIONDIG1"),
            mmm: fenceValue("R", "SESSIONDIG3"),
          },
        },
      },
    ]);
    const res = await run();
    expect(res.workoutCommandOutcomes).toEqual([
      {
        id: "0a",
        entries: [
          { operationKey: "aaa", code: "C", sessionDigest: "SESSIONDIG1" },
          { operationKey: "mmm", code: "R", sessionDigest: "SESSIONDIG3" },
          { operationKey: "zzz", code: "S", sessionDigest: "SESSIONDIG2" },
        ],
      },
    ]);
    expect(res.paging.workoutCommandOutcomes).toEqual({ returned: 1, hasMore: false, nextCursor: null });
    expect(JSON.stringify(res)).not.toContain(PAYLOAD);
  });

  test("256 populated shards: every owner entry exactly once, payload hash never present, pages far below 50", async () => {
    const keys = seedFence(FENCE, 256, 40); // 10240 entries
    const { rows, calls, responses } = await exportAll("workoutCommandOutcomes");
    expect(calls).toBeLessThan(10);
    expect(rows.map((r) => r.id)).toEqual(shardIds(256).reverse());
    const seen = rows.flatMap((r) => r.entries.map((e: any) => e.operationKey));
    expect(seen).toHaveLength(keys.length);
    expect(new Set(seen).size).toBe(keys.length);
    expect([...seen].sort()).toEqual([...keys].sort());
    for (const r of rows) {
      const ks = r.entries.map((e: any) => e.operationKey);
      expect(ks).toEqual([...ks].sort());
      for (const e of r.entries) {
        expect(["C", "R", "S"]).toContain(e.code);
        expect(Object.keys(e).sort()).toEqual(["code", "operationKey", "sessionDigest"]);
      }
    }
    const sh00 = rows.find((r) => r.id === "00");
    expect(sh00.entries.slice(0, 3).map((e: any) => e.code)).toEqual(["C", "R", "S"]);
    for (const res of responses) expect(JSON.stringify(res)).not.toContain(PAYLOAD);
  });

  test("outcomes follow the shared paging contract: cursor is the last included shard, continuation reads only that section", async () => {
    seedFence(FENCE, 256, 400);
    const first = await run();
    const p = first.paging.workoutCommandOutcomes;
    expect(p.returned).toBe(first.workoutCommandOutcomes.length);
    if (p.hasMore) {
      expect(p.nextCursor).toBe(first.workoutCommandOutcomes[p.returned - 1].id);
      const cont = await run({ cursors: { workoutCommandOutcomes: p.nextCursor } });
      expect(cont.profile).toBeUndefined();
      expect(cont.workoutTypedSessions).toBeUndefined();
      expect(cont.workoutCommandOutcomes[0].id).toBe(shardIds(256).reverse()[p.returned]);
    }
    const { rows, calls } = await exportAll("workoutCommandOutcomes");
    expect(calls).toBeLessThan(50);
    expect(rows).toHaveLength(256);
    expect(rows.reduce((n, r) => n + r.entries.length, 0)).toBe(256 * 400);
  });

  test("a malformed stored value is listed with null code and digest, never dropped or leaked", async () => {
    collections.set(FENCE, [
      {
        id: "01",
        data: {
          e: {
            ok: fenceValue("C", "GOODDIGEST1"),
            short: "Cabc",
            badcode: "X" + "d".repeat(11) + PAYLOAD,
            num: 42,
            nul: null,
            long: "C" + "d".repeat(40),
          },
        },
      },
      { id: "02", data: { e: "not-a-map" } },
      { id: "03", data: {} },
    ]);
    const res = await run();
    const byId = Object.fromEntries(res.workoutCommandOutcomes.map((r: any) => [r.id, r.entries]));
    const entry = (k: string) => byId["01"].find((e: any) => e.operationKey === k);
    expect(entry("ok")).toEqual({ operationKey: "ok", code: "C", sessionDigest: "GOODDIGEST1" });
    for (const k of ["short", "badcode", "num", "nul", "long"]) {
      expect(entry(k)).toEqual({ operationKey: k, code: null, sessionDigest: null });
    }
    expect(byId["02"]).toEqual([]);
    expect(byId["03"]).toEqual([]);
    expect(JSON.stringify(res)).not.toContain(PAYLOAD);
  });

  test("tenant isolation: another account's fence never appears", async () => {
    seedFence(FENCE, 2, 2);
    collections.set("users/u2/workout_command_fence", [
      { id: "ff", data: { e: { OTHERKEY: fenceValue("C", "OTHERDIGEST") } } },
    ]);
    const res = await run();
    expect(res.workoutCommandOutcomes.map((r: any) => r.id)).toEqual(["01", "00"]);
    expect(JSON.stringify(res)).not.toMatch(/OTHERKEY|OTHERDIGEST|"ff"/);
    const other = await run({}, "u2");
    expect(other.workoutCommandOutcomes.map((r: any) => r.id)).toEqual(["ff"]);
    expect(JSON.stringify(other)).not.toMatch(/k00|k01/);
    expect(readPaths.filter((x) => x.includes("workout_command_fence"))).toEqual([
      FENCE,
      "users/u2/workout_command_fence",
    ]);
  });

  test("empty fence yields an empty, final section", async () => {
    const res = await run();
    expect(res.workoutCommandOutcomes).toEqual([]);
    expect(res.paging.workoutCommandOutcomes).toEqual({ returned: 0, hasMore: false, nextCursor: null });
  });

  test("receipts are no longer an export section", async () => {
    collections.set("users/u1/workout_command_receipts", [{ id: "op1", data: { marker: "RECEIPT-X" } }]);
    const res = await run();
    expect(res.workoutCommandReceipts).toBeUndefined();
    expect(res.paging.workoutCommandReceipts).toBeUndefined();
    expect(JSON.stringify(res)).not.toContain("RECEIPT-X");
    await expect(run({ cursors: { workoutCommandReceipts: "op1" } })).rejects.toMatchObject({
      code: "invalid-argument",
    });
  });
});

describe("bounded reads of large documents", () => {
  const BLOB = "x".repeat(400_000);
  const bigSessions = (n: number, blob = BLOB): string[] => {
    const list = ids(n, "s");
    collections.set(
      TYPED,
      list.map((id, i) => ({
        id,
        data: { exercises: [{ name: "squat", sets: i }], revision: i, writerTokenHash: HASH, blob },
      })),
    );
    return list;
  };

  test("40 sessions of ~400 KB with populated outcomes: every session and every entry exactly once, no hash anywhere", async () => {
    const list = bigSessions(40);
    const keys = seedFence(FENCE, 256, 10);
    const sessions = await exportAll("workoutTypedSessions");
    expect(sessions.rows.map((r) => r.id)).toEqual([...list].reverse());
    expect(new Set(sessions.rows.map((r) => r.id)).size).toBe(40);
    expect(sessions.calls).toBeGreaterThan(1);
    expect(sessions.calls).toBeLessThan(50);
    for (const res of sessions.responses) {
      expect(Buffer.byteLength(JSON.stringify(res), "utf8")).toBeLessThanOrEqual(MAX_EXPORT_BYTES);
      expect(JSON.stringify(res)).not.toMatch(/writerTokenHash|deadbeef/);
    }
    const outcomes = await exportAll("workoutCommandOutcomes");
    const seen = outcomes.rows.flatMap((r) => r.entries.map((e: any) => e.operationKey));
    expect([...seen].sort()).toEqual([...keys].sort());
  });

  test("a read never asks for more than 20 documents and stops materialising once the byte budget is reached", async () => {
    const list = bigSessions(60);
    reads.length = 0;
    const res = await run({ cursors: { workoutTypedSessions: list[59] } });
    const mine = reads.filter((r) => r.name === TYPED);
    expect(mine.length).toBeGreaterThan(1);
    expect(Math.max(...mine.map((r) => r.limit))).toBeLessThanOrEqual(20);
    const included = res.workoutTypedSessions.length;
    const materialised = mine.reduce((n, r) => n + r.returned, 0);
    expect(included).toBeGreaterThanOrEqual(15);
    expect(included).toBeLessThan(25);
    expect(res.paging.workoutTypedSessions).toEqual({
      returned: included,
      hasMore: true,
      nextCursor: res.workoutTypedSessions[included - 1].id,
    });
    expect(materialised).toBeLessThanOrEqual(included + 20);
    expect(materialised).toBeLessThan(59);
    expect(Buffer.byteLength(JSON.stringify(res.workoutTypedSessions), "utf8")).toBeLessThanOrEqual(
      MAX_EXPORT_BYTES,
    );
  });

  test("small rows still read in batches of at most 20 and stop at the 500-row limit", async () => {
    seedTyped(TYPED, 700);
    reads.length = 0;
    const res = await run({ cursors: { workoutTypedSessions: "s0700" } });
    const mine = reads.filter((r) => r.name === TYPED);
    expect(res.workoutTypedSessions).toHaveLength(500);
    expect(Math.max(...mine.map((r) => r.limit))).toBeLessThanOrEqual(20);
    expect(mine.reduce((n, r) => n + r.returned, 0)).toBeLessThanOrEqual(501 + 20);
  });

  test("a single document larger than the whole budget is emitted alone and paging advances past it", async () => {
    collections.set(TYPED, [
      { id: "s0001", data: { n: 1, writerTokenHash: HASH } },
      { id: "s0002", data: { n: 2, writerTokenHash: HASH } },
      { id: "s0003", data: { n: 3, writerTokenHash: HASH, blob: "y".repeat(MAX_EXPORT_BYTES + 100_000) } },
    ]);
    await expect(run({ cursors: { workoutTypedSessions: "s0004-missing" } })).rejects.toMatchObject({
      code: "failed-precondition",
    });
    const full = await run();
    expect(full.workoutTypedSessions.map((r: any) => r.id)).toEqual(["s0003"]);
    expect(full.paging.workoutTypedSessions).toEqual({ returned: 1, hasMore: true, nextCursor: "s0003" });
    const next = await run({ cursors: { workoutTypedSessions: "s0003" } });
    expect(next.workoutTypedSessions.map((r: any) => r.id)).toEqual(["s0002", "s0001"]);
    expect(next.paging.workoutTypedSessions).toEqual({ returned: 2, hasMore: false, nextCursor: null });
    for (const r of [full, next]) expect(JSON.stringify(r)).not.toMatch(/writerTokenHash|deadbeef/);
  });
});

describe("byte budget with the new sections present", () => {
  const big = "x".repeat(20_000);

  test("oversized new sections are trimmed to fit, keep a valid cursor, and the rest arrives by continuation", async () => {
    // 500 x ~20 KB = ~10 MB > MAX_EXPORT_BYTES (8 MiB).
    const typedIds = seedTyped(TYPED, 500, { blob: big });
    const res = await run();
    const body = JSON.stringify(res);
    expect(Buffer.byteLength(body, "utf8")).toBeLessThanOrEqual(MAX_EXPORT_BYTES);

    for (const [key, all] of [
      ["workoutTypedSessions", [...typedIds].reverse()],
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
    // The section really was trimmed (otherwise the test proves nothing).
    expect(res.workoutTypedSessions.length).toBeLessThan(500);
    expect(body).not.toContain("writerTokenHash");
    expect(body).not.toContain(HASH);
  });

  test("small new sections do not disturb the legacy sections or other paged sections", async () => {
    seedTyped(TYPED, 2);
    collections.set("users/u1/food_entries", [{ id: "f1", data: { loggedAt: 1, name: "m" } }]);
    const res = await run();
    expect(res.foodEntries.map((r: any) => r.id)).toEqual(["f1"]);
    expect(res.truncated).toEqual([]);
    expect(res.paging.workoutTypedSessions.hasMore).toBe(false);
    expect(res.paging.workoutCommandOutcomes.hasMore).toBe(false);
    expect(res.paging.workoutCommandReceipts).toBeUndefined();
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

  test.each(["workout_typed_sessions", "workout_command_fence"])(
    "%s is a paged export section in code and BOTH in policy",
    (c) => {
      expect(exportedPaths.has(c)).toBe(true);
      expect(entries[c].classification).toBe("BOTH");
    },
  );

  test.each(["workout_command_receipts", "workout_command_policy", "workout_command_counters"])(
    "%s is not exported by code and is DELETE (not export-classified) in policy",
    (c) => {
      expect(exportedPaths.has(c)).toBe(false);
      expect(entries[c].classification).toBe("DELETE");
    },
  );

  test("the code withholds writerTokenHash by declaration", () => {
    expect(src).toMatch(/TYPED_SESSION_WITHHELD_FIELDS\s*=\s*\[\s*"writerTokenHash"/);
  });
});
