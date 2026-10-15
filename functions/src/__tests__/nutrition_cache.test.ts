/**
 * nutrition_cache (FOOD-13, FOOD-14): TTLs (positive 30 d, negative 1 d, search 7 d), `expireAt`
 * compared in code (TTL deletion lags), a failed read is a miss, a failed write is swallowed,
 * keys are `off_<barcode>`, `usda_<id>`, `q_<sha1(lang|query|scope)>`.
 */
jest.mock("firebase-admin", () => require("./body_scan/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./body_scan/fakes").loggerMock());

import { createHash } from "crypto";
import {
  CACHE_COLLECTION,
  CACHE_SCHEMA,
  CACHE_TTL_MS,
  offCacheKey,
  readCache,
  searchCacheKey,
  usdaCacheKey,
  writeCache,
} from "../nutrition_cache";
import { firestoreError, fx, resetFakes, store, ts, writes } from "./body_scan/fakes";

const DAY = 24 * 60 * 60 * 1000;
const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);

beforeEach(() => resetFakes());

describe("keys", () => {
  test("off and usda keys", () => {
    expect(offCacheKey("3017620422003")).toBe("off_3017620422003");
    expect(usdaCacheKey(171077)).toBe("usda_171077");
    expect(usdaCacheKey("171077")).toBe("usda_171077");
  });

  test("search key is q_<sha1(lang|query|scope)> over the trimmed lower-cased query", () => {
    const expected = "q_" + createHash("sha1").update("en|chicken breast|both").digest("hex");
    expect(searchCacheKey("en", "chicken breast", "both")).toBe(expected);
    expect(searchCacheKey("en", "  Chicken Breast ", "both")).toBe(expected);
  });

  test("language and scope are part of the key", () => {
    const base = searchCacheKey("en", "rice", "both");
    expect(searchCacheKey("ru", "rice", "both")).not.toBe(base);
    expect(searchCacheKey("en", "rice", "generic")).not.toBe(base);
    expect(searchCacheKey("en", "rice", "packaged")).not.toBe(base);
    expect(searchCacheKey("en", "rice", "both")).toBe(base);
  });
});

describe("TTL constants", () => {
  test("positive 30 d, negative 1 d, search 7 d", () => {
    expect(CACHE_TTL_MS.positive).toBe(30 * DAY);
    expect(CACHE_TTL_MS.negative).toBe(1 * DAY);
    expect(CACHE_TTL_MS.search).toBe(7 * DAY);
  });
});

describe("writeCache", () => {
  test("writes schema, fetchedAt, expireAt = now + ttl, found, source and a JSON-cloned payload", async () => {
    await writeCache("off_1", { found: true, source: "open_food_facts", payload: { a: 1, b: undefined } }, CACHE_TTL_MS.positive, T0);
    const doc = store.get(`${CACHE_COLLECTION}/off_1`)!;
    expect(doc.schema).toBe(CACHE_SCHEMA);
    expect((doc.fetchedAt as Date).getTime()).toBe(T0);
    expect((doc.expireAt as Date).getTime()).toBe(T0 + 30 * DAY);
    expect(doc.found).toBe(true);
    expect(doc.source).toBe("open_food_facts");
    expect(doc.payload).toEqual({ a: 1 });
    expect("b" in doc.payload).toBe(false);
  });

  test("a negative entry has no payload and expires in 1 day", async () => {
    await writeCache("off_2", { found: false, source: "none" }, CACHE_TTL_MS.negative, T0);
    const doc = store.get(`${CACHE_COLLECTION}/off_2`)!;
    expect("payload" in doc).toBe(false);
    expect((doc.expireAt as Date).getTime()).toBe(T0 + DAY);
  });

  test("a write failure is swallowed (never fails the user)", async () => {
    fx.failOn = (op) => (op === "set" ? firestoreError("unavailable", 14) : undefined);
    await expect(writeCache("off_3", { found: true, source: "x", payload: 1 }, DAY, T0)).resolves.toBeUndefined();
    expect(store.has(`${CACHE_COLLECTION}/off_3`)).toBe(false);
  });

  test("an unserialisable payload (circular) is swallowed too", async () => {
    const circ: Record<string, unknown> = {};
    circ.self = circ;
    await expect(writeCache("off_4", { found: true, source: "x", payload: circ }, DAY, T0)).resolves.toBeUndefined();
    expect(writes).toEqual([]);
  });
});

describe("readCache", () => {
  const seed = (key: string, o: Record<string, unknown>): void => {
    store.set(`${CACHE_COLLECTION}/${key}`, { found: true, source: "s", ...o });
  };

  test("missing document is a miss", async () => {
    expect(await readCache("off_none", T0)).toBeNull();
  });

  test("round trip returns found, source, payload, fetchedAtMs and expireAtMs", async () => {
    await writeCache("off_5", { found: true, source: "open_food_facts", payload: { n: 1 } }, CACHE_TTL_MS.positive, T0);
    const hit = await readCache<{ n: number }>("off_5", T0 + 1000);
    expect(hit).toEqual({ found: true, source: "open_food_facts", payload: { n: 1 }, fetchedAtMs: T0, expireAtMs: T0 + 30 * DAY });
  });

  test("expireAt is compared in code: one ms before is a hit, exactly at and after is a miss", async () => {
    seed("k", { expireAt: new Date(T0 + 1000) });
    expect(await readCache("k", T0 + 999)).not.toBeNull();
    expect(await readCache("k", T0 + 1000)).toBeNull();
    expect(await readCache("k", T0 + 5000)).toBeNull();
  });

  test("a 30-day positive entry is live at day 29 and dead at day 30; a negative entry dies after 1 day", async () => {
    await writeCache("pos", { found: true, source: "s", payload: 1 }, CACHE_TTL_MS.positive, T0);
    await writeCache("neg", { found: false, source: "none" }, CACHE_TTL_MS.negative, T0);
    expect(await readCache("pos", T0 + 29 * DAY)).not.toBeNull();
    expect(await readCache("pos", T0 + 30 * DAY)).toBeNull();
    expect(await readCache("neg", T0 + DAY - 1)).not.toBeNull();
    expect(await readCache("neg", T0 + DAY)).toBeNull();
  });

  test("a search entry is live at day 6 and dead at day 7", async () => {
    await writeCache("q", { found: true, source: "search", payload: [] }, CACHE_TTL_MS.search, T0);
    expect(await readCache("q", T0 + 6 * DAY)).not.toBeNull();
    expect(await readCache("q", T0 + 7 * DAY)).toBeNull();
  });

  test("expireAt as a Firestore Timestamp (toMillis) or a plain number is understood", async () => {
    seed("ts", { expireAt: ts(T0 + 5000) });
    seed("num", { expireAt: T0 + 5000 });
    expect(await readCache("ts", T0)).not.toBeNull();
    expect(await readCache("num", T0)).not.toBeNull();
  });

  test.each([
    ["missing expireAt", { expireAt: undefined }],
    ["string expireAt", { expireAt: "tomorrow" }],
    ["NaN expireAt", { expireAt: NaN }],
    ["non-boolean found", { expireAt: new Date(T0 + DAY), found: "yes" }],
    ["non-string source", { expireAt: new Date(T0 + DAY), source: 5 }],
  ])("a malformed entry (%s) is a miss", async (_l, o) => {
    seed("bad", o as Record<string, unknown>);
    expect(await readCache("bad", T0)).toBeNull();
  });

  test("a failed read is a miss, not an error", async () => {
    await writeCache("off_6", { found: true, source: "s", payload: 1 }, DAY, T0);
    fx.failOn = (op) => (op === "get" ? firestoreError("unavailable", 14) : undefined);
    await expect(readCache("off_6", T0)).resolves.toBeNull();
  });
});
