/**
 * T108 lookup_barcode (FOOD-11, FOOD-13, FOOD-31, FOOD-32, FOOD-33): the cache -> Open Food Facts ->
 * USDA `gtinUpc` -> `found:false` chain, TTLs, the breaker (injected clock), the per-uid burst
 * limit, the global shared-IP budget, quota and refund accounting, and the flag-off path.
 *
 * Firestore is the stateful fake in ./body_scan/fakes; the network is an injected `fetchImpl`
 * serving recorded-shape fixtures; time is an injected `now`. Assertions look at what was
 * fetched, stored and charged.
 */
jest.mock("firebase-admin", () => require("./body_scan/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./body_scan/fakes").loggerMock());

const usdaSecret: { key: string | null; reads: number } = { key: "test-usda-key", reads: 0 };
jest.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion: async ({ name }: { name: string }) => {
      if (name.includes("USDA_FDC_API_KEY")) {
        usdaSecret.reads += 1;
        if (usdaSecret.key === null) throw Object.assign(new Error("not found"), { code: 5 });
        return [{ payload: { data: Buffer.from(usdaSecret.key) } }];
      }
      return [{ payload: { data: Buffer.from(JSON.stringify({ enabled: true, reason: null })) } }];
    },
  })),
}));

import * as logger from "firebase-functions/logger";
import { lookupBarcode, lookupBarcodeCore, MISS_BURST_PER_MINUTE } from "../nutrition_lookup";
import { __resetBreakersForTests } from "../nutrition_breaker";
import { __resetUsdaKeyForTests } from "../nutrition_sources/usda_fdc";
import { OFF_PRODUCT_FIELDS } from "../nutrition_sources/open_food_facts";
import { __resetAiGatewayControlCacheForTests, QUOTAS } from "../abuse_guard";
import { gtinCheckDigit } from "../gtin_validator";
import { CACHE_TTL_MS } from "../nutrition_cache";
import { OFF_READS_PER_MINUTE } from "../nutrition_budget";
import { callReq, expectHttpsError, loggedText, resetFakes, store, usageOf } from "./body_scan/fakes";

const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);
const MIN = 60_000;
const DAY = 24 * 60 * MIN;
const UID = "uid_alice_1";
const NUTELLA = "3017620422003";
const quotaDay = (): string => new Date().toISOString().slice(0, 10);

const gtin = (n: number): string => {
  const payload = `40063813${String(n).padStart(4, "0")}`;
  return payload + String(gtinCheckDigit(payload));
};

const NUTELLA_PRODUCT = {
  code: NUTELLA,
  status: 1,
  product: {
    code: NUTELLA,
    product_name: "Nutella",
    brands: "Ferrero",
    quantity: "400 g",
    nutriments: {
      "energy-kcal_100g": 539,
      energy_100g: 2252,
      proteins_100g: 6.3,
      carbohydrates_100g: 57.5,
      fat_100g: 30.9,
      sodium_100g: 0.0428,
    },
  },
};

type Reply = { status: number; body?: unknown; raw?: string };
interface Call {
  url: URL;
  headers: Record<string, string>;
}

let calls: Call[];
let off: (barcode: string) => Reply;
let usda: (query: string) => Reply;
let clock: number;

const respond = (r: Reply): Response => new Response(r.raw ?? (r.body === undefined ? "" : JSON.stringify(r.body)), { status: r.status });

const fetchImpl = jest.fn(async (input: unknown, init?: { headers?: Record<string, string> }) => {
  const url = new URL(String(input));
  calls.push({ url, headers: { ...(init?.headers ?? {}) } });
  if (url.hostname === "world.openfoodfacts.org") {
    const m = /\/api\/v3\/product\/([^/]+)\.json$/.exec(url.pathname);
    return respond(off(m ? decodeURIComponent(m[1]) : ""));
  }
  if (url.hostname === "api.nal.usda.gov") return respond(usda(url.searchParams.get("query") ?? ""));
  throw new Error(`unexpected host ${url.hostname}`);
}) as unknown as typeof fetch;

const offCalls = (): Call[] => calls.filter((c) => c.url.hostname === "world.openfoodfacts.org");
const usdaCalls = (): Call[] => calls.filter((c) => c.url.hostname === "api.nal.usda.gov");

const deps = (o: Record<string, unknown> = {}): any => ({
  fetchImpl,
  now: () => clock,
  takeBudget: async () => true,
  getUsdaKey: async () => usdaSecret.key,
  ...o,
});

const lookup = (barcode: string, uid = UID, d: any = deps()): Promise<any> => lookupBarcodeCore(uid, "password", barcode, d);

beforeEach(() => {
  resetFakes();
  calls = [];
  clock = T0;
  usdaSecret.key = "test-usda-key";
  usdaSecret.reads = 0;
  off = () => ({ status: 404, body: { status: 0, code: "x", status_verbose: "product not found" } });
  usda = () => ({ status: 200, body: { foods: [] } });
  (fetchImpl as unknown as jest.Mock).mockClear();
  __resetBreakersForTests();
  __resetUsdaKeyForTests();
  __resetAiGatewayControlCacheForTests();
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  process.env.OFF_CONTACT = "ops@example.com";
  process.env.APP_VERSION = "1.2";
  delete process.env.FOOD_LOOKUP_ENABLED;
});

describe("FOOD-11 OFF v3 fixture contract", () => {
  test("a found product: fixed host/path/fields, User-Agent, no serving_size, attribution block", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    const res = await lookup(NUTELLA);

    expect(res).toEqual({
      found: true,
      product: { name: "Nutella", brand: "Ferrero", per100g: { kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9 } },
      dataQuality: "complete",
      source: "open_food_facts",
      attribution: {
        source: "Open Food Facts",
        licence: "ODbL 1.0 (database), DbCL 1.0 (contents)",
        url: `https://world.openfoodfacts.org/product/${NUTELLA}`,
      },
    });
    expect("servingG" in res.product).toBe(false);

    expect(offCalls()).toHaveLength(1);
    const { url, headers } = offCalls()[0];
    expect(url.protocol).toBe("https:");
    expect(url.origin).toBe("https://world.openfoodfacts.org");
    expect(url.pathname).toBe(`/api/v3/product/${NUTELLA}.json`);
    expect([...url.searchParams.keys()]).toEqual(["fields"]);
    expect(url.searchParams.get("fields")).toBe(OFF_PRODUCT_FIELDS);
    expect(headers["User-Agent"]).toBe("FitnessApp/1.2 (ops@example.com)");
    expect(headers["User-Agent"]).toMatch(/^FitnessApp\/\S+ \(.+\)$/);
  });

  test("serving_quantity or a 'serving_size' text becomes servingG when present", async () => {
    off = () => ({ status: 200, body: { ...NUTELLA_PRODUCT, product: { ...NUTELLA_PRODUCT.product, serving_size: "15 g" } } });
    expect((await lookup(NUTELLA)).product.servingG).toBe(15);
  });

  test("dataQuality: complete / partial (macro missing) / inconsistent (kcal vs macros)", async () => {
    const withNutriments = (n: Record<string, number>): Reply => ({
      status: 200,
      body: { ...NUTELLA_PRODUCT, product: { ...NUTELLA_PRODUCT.product, nutriments: n } },
    });
    off = () => withNutriments({ "energy-kcal_100g": 120, proteins_100g: 10, carbohydrates_100g: 20 });
    expect((await lookup(gtin(1))).dataQuality).toBe("partial");
    off = () => withNutriments({ "energy-kcal_100g": 100, proteins_100g: 40, carbohydrates_100g: 0, fat_100g: 0 });
    expect((await lookup(gtin(2))).dataQuality).toBe("inconsistent");
    off = () => withNutriments({ "energy-kcal_100g": 165, proteins_100g: 10, carbohydrates_100g: 20, fat_100g: 5 });
    expect((await lookup(gtin(3))).dataQuality).toBe("complete");
  });

  test("a hostile product name is sanitised before it is returned and cached", async () => {
    off = () => ({
      status: 200,
      body: { ...NUTELLA_PRODUCT, product: { ...NUTELLA_PRODUCT.product, product_name: "<b>Nutella</b> https://evil.example/x bob@evil.example", brands: "<i>Ferrero</i>, Other" } },
    });
    const res = await lookup(NUTELLA);
    expect(res.product.name).toBe("Nutella");
    expect(res.product.brand).toBe("Ferrero");
    expect(JSON.stringify([...store.values()])).not.toMatch(/evil|<b>/);
  });

  test("an unreadable (non-JSON) 200 body is treated as 'no such product', never a crash", async () => {
    off = () => ({ status: 200, raw: "<html>oops</html>" });
    expect(await lookup(NUTELLA)).toEqual({ found: false });
  });
});

describe("FOOD-13 cache, fallback, TTL", () => {
  test("miss -> found writes a positive cache entry with expireAt = now + 30 d and charges 1", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    await lookup(NUTELLA);
    const doc = store.get(`nutrition_cache/off_${NUTELLA}`)!;
    expect(doc.found).toBe(true);
    expect(doc.source).toBe("open_food_facts");
    expect((doc.expireAt as Date).getTime() - T0).toBe(CACHE_TTL_MS.positive);
    expect(CACHE_TTL_MS.positive).toBe(30 * DAY);
    expect(usageOf(UID, "barcodeLookup")).toBe(1);
  });

  test("a cache hit makes NO network call, takes NO budget slot and charges NOTHING", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    const first = await lookup(NUTELLA);
    const takeBudget = jest.fn(async () => true);
    calls = [];
    const second = await lookup(NUTELLA, "uid_other", deps({ takeBudget }));
    expect(second).toEqual(first);
    expect(calls).toEqual([]);
    expect(takeBudget).not.toHaveBeenCalled();
    expect(usageOf("uid_other", "barcodeLookup")).toBe(0);
    expect(store.has(`users/uid_other/usage/${new Date(T0).toISOString().slice(0, 10)}`)).toBe(false);
  });

  test("a positive entry serves at day 29 and is refetched at day 30", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    await lookup(NUTELLA);
    calls = [];
    clock = T0 + 29 * DAY;
    await lookup(NUTELLA);
    expect(calls).toHaveLength(0);
    clock = T0 + 30 * DAY;
    await lookup(NUTELLA);
    expect(offCalls()).toHaveLength(1);
  });

  test("OFF miss -> USDA gtinUpc exact match -> found with the USDA source and attribution", async () => {
    usda = () => ({
      status: 200,
      body: {
        foods: [
          { fdcId: 111, description: "OTHER PRODUCT", gtinUpc: "999999999999", foodNutrients: [{ nutrientId: 1008, value: 1, unitName: "KCAL" }] },
          {
            fdcId: 222,
            description: "PEANUT BUTTER",
            brandOwner: "Acme",
            gtinUpc: "036000291452",
            servingSize: 32,
            servingSizeUnit: "g",
            foodNutrients: [
              { nutrientId: 1008, value: 588, unitName: "KCAL" },
              { nutrientId: 1003, value: 25, unitName: "G" },
              { nutrientId: 1005, value: 20, unitName: "G" },
              { nutrientId: 1004, value: 50, unitName: "G" },
            ],
          },
        ],
      },
    });
    const res = await lookup("036000291452");
    expect(res.found).toBe(true);
    expect(res.source).toBe("usda_fdc");
    expect(res.product).toEqual({ name: "PEANUT BUTTER", brand: "Acme", per100g: { kcal: 588, proteinG: 25, carbsG: 20, fatG: 50 }, servingG: 32 });
    expect(res.attribution).toEqual({ source: "USDA FoodData Central", licence: "CC0 1.0", url: "https://fdc.nal.usda.gov/" });
    expect(offCalls()).toHaveLength(1);
    expect(usdaCalls()).toHaveLength(1);
  });

  test("USDA request: key only in X-Api-Key (never the query string), barcode as one encoded value, Branded", async () => {
    await lookup(NUTELLA);
    const { url, headers } = usdaCalls()[0];
    expect(url.origin).toBe("https://api.nal.usda.gov");
    expect(url.pathname).toBe("/fdc/v1/foods/search");
    expect(headers["X-Api-Key"]).toBe("test-usda-key");
    expect(url.toString()).not.toMatch(/test-usda-key|api_key/i);
    expect(url.searchParams.get("query")).toBe(NUTELLA);
    expect(url.searchParams.get("dataType")).toBe("Branded");
  });

  test("USDA leading zeros are not significant between UPC-A and EAN-13", async () => {
    usda = () => ({
      status: 200,
      body: { foods: [{ fdcId: 5, description: "COLA", gtinUpc: "036000291452", foodNutrients: [{ nutrientId: 1008, value: 42, unitName: "KCAL" }, { nutrientId: 1003, value: 0 }, { nutrientId: 1004, value: 0 }, { nutrientId: 1005, value: 10.6 }] }] },
    });
    expect((await lookup("0036000291452")).found).toBe(true);
  });

  test("a USDA row that does not carry the exact gtinUpc is never accepted", async () => {
    usda = () => ({ status: 200, body: { foods: [{ fdcId: 7, description: "SIMILAR", gtinUpc: "3017620422000", foodNutrients: [{ nutrientId: 1008, value: 10, unitName: "KCAL" }, { nutrientId: 1003, value: 1 }, { nutrientId: 1004, value: 0 }, { nutrientId: 1005, value: 1 }] }] } });
    expect(await lookup(NUTELLA)).toEqual({ found: false });
  });

  test("not found everywhere -> found:false, charged, negative-cached for 1 day, then served from cache", async () => {
    expect(await lookup(NUTELLA)).toEqual({ found: false });
    expect(usageOf(UID, "barcodeLookup")).toBe(1);
    const doc = store.get(`nutrition_cache/off_${NUTELLA}`)!;
    expect(doc.found).toBe(false);
    expect((doc.expireAt as Date).getTime() - T0).toBe(CACHE_TTL_MS.negative);
    expect(CACHE_TTL_MS.negative).toBe(DAY);

    calls = [];
    clock = T0 + DAY - 1;
    expect(await lookup(NUTELLA)).toEqual({ found: false });
    expect(calls).toEqual([]);
    expect(usageOf(UID, "barcodeLookup")).toBe(1);

    clock = T0 + DAY;
    await lookup(NUTELLA);
    expect(offCalls()).toHaveLength(1);
    expect(usageOf(UID, "barcodeLookup")).toBe(2);
  });

  test("with no USDA key the USDA step is skipped and found:false results", async () => {
    usdaSecret.key = null;
    expect(await lookup(NUTELLA)).toEqual({ found: false });
    expect(usdaCalls()).toEqual([]);
  });

  test("an OFF product without usable nutrition falls through to USDA", async () => {
    off = () => ({ status: 200, body: { code: NUTELLA, status: 1, product: { product_name: "Empty", nutriments: {} } } });
    await lookup(NUTELLA);
    expect(usdaCalls()).toHaveLength(1);
  });

  test("OFF 5xx and USDA not-found -> upstream-unavailable, quota refunded, NOT negative-cached", async () => {
    off = () => ({ status: 503 });
    await expectHttpsError(lookup(NUTELLA), "unavailable", "upstream-unavailable");
    expect(usageOf(UID, "barcodeLookup")).toBe(0);
    expect(store.has(`nutrition_cache/off_${NUTELLA}`)).toBe(false);
  });

  test("OFF fails but USDA finds it -> found (a failed source does not block another)", async () => {
    off = () => ({ status: 500 });
    usda = () => ({ status: 200, body: { foods: [{ fdcId: 9, description: "FOUND", gtinUpc: NUTELLA, foodNutrients: [{ nutrientId: 1008, value: 100, unitName: "KCAL" }, { nutrientId: 1003, value: 5 }, { nutrientId: 1004, value: 2 }, { nutrientId: 1005, value: 15 }] }] } });
    const res = await lookup(NUTELLA);
    expect(res.source).toBe("usda_fdc");
    expect(usageOf(UID, "barcodeLookup")).toBe(1);
  });

  test("a USDA 403 (bad key) is an upstream failure, never 'no such food'", async () => {
    usda = () => ({ status: 403 });
    await expectHttpsError(lookup(NUTELLA), "unavailable", "upstream-unavailable");
    expect(usageOf(UID, "barcodeLookup")).toBe(0);
    expect(store.has(`nutrition_cache/off_${NUTELLA}`)).toBe(false);
  });

  test("a cache read failure is a miss: the lookup still works", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    const fakes = require("./body_scan/fakes");
    fakes.fx.failOn = (op: string, path: string) => (op === "get" && path.startsWith("nutrition_cache/off_") ? Object.assign(new Error("down"), { code: 14 }) : undefined);
    expect((await lookup(NUTELLA)).found).toBe(true);
  });

  test("a cache write failure does not fail the user", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    const fakes = require("./body_scan/fakes");
    fakes.fx.failOn = (op: string, path: string) => (op === "set" && path.startsWith("nutrition_cache/off_") ? Object.assign(new Error("down"), { code: 14 }) : undefined);
    expect((await lookup(NUTELLA)).found).toBe(true);
  });
});

describe("FOOD-13 breaker with an injected clock", () => {
  test("3 consecutive OFF failures open it: the 4th call touches no network until 5:00 passes", async () => {
    usdaSecret.key = null;
    off = () => ({ status: 503 });
    for (let i = 0; i < 3; i++) await expectHttpsError(lookup(gtin(i)), "unavailable", "upstream-unavailable");
    expect(offCalls()).toHaveLength(3);

    clock = T0 + 4 * MIN + 59_000;
    await expectHttpsError(lookup(gtin(10)), "unavailable", "upstream-unavailable");
    expect(offCalls()).toHaveLength(3); // answered from the open breaker, no fetch

    clock = T0 + 5 * MIN + 1000;
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    expect((await lookup(NUTELLA)).found).toBe(true);
    expect(offCalls()).toHaveLength(4);
  });

  test("a single 429 opens the breaker at once", async () => {
    usdaSecret.key = null;
    off = () => ({ status: 429 });
    await expectHttpsError(lookup(gtin(1)), "unavailable", "upstream-unavailable");
    await expectHttpsError(lookup(gtin(2)), "unavailable", "upstream-unavailable");
    expect(offCalls()).toHaveLength(1);
  });

  test("2 failures then a success keep the breaker closed", async () => {
    usdaSecret.key = null;
    // A new UTC minute per call: this test is about the breaker, not the 5/min burst limit.
    const next = (): any => {
      clock += MIN;
      return deps();
    };
    off = () => ({ status: 503 });
    await lookup(gtin(1), UID, next()).catch(() => undefined);
    await lookup(gtin(2), UID, next()).catch(() => undefined);
    off = () => ({ status: 404 });
    await lookup(gtin(3), UID, next());
    off = () => ({ status: 503 });
    await lookup(gtin(4), UID, next()).catch(() => undefined);
    await lookup(gtin(5), UID, next()).catch(() => undefined);
    off = () => ({ status: 404 });
    calls = [];
    await lookup(gtin(6), UID, next());
    expect(offCalls()).toHaveLength(1);
  });
});

describe("FOOD-13 request validation and flag", () => {
  const call = (data: unknown, uid: string | null = UID, provider = "password"): Promise<any> =>
    (lookupBarcode as any).run(callReq(data, uid, provider));
  let fetchSpy: jest.SpyInstance;

  beforeEach(() => {
    fetchSpy = jest.spyOn(globalThis, "fetch").mockImplementation(fetchImpl as any);
  });
  afterEach(() => fetchSpy.mockRestore());

  test("an unauthenticated call is refused", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expectHttpsError(call({ barcode: NUTELLA }, null), "unauthenticated");
  });

  test("an anonymous caller is refused before anything is charged or fetched", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expect(call({ barcode: NUTELLA }, UID, "anonymous")).rejects.toThrow(/real account/i);
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(usageOf(UID, "barcodeLookup")).toBe(0);
  });

  test("flag off: feature-disabled, quota doc never written, no network, no cache read", async () => {
    await expectHttpsError(call({ barcode: NUTELLA }), "failed-precondition", "feature-disabled");
    process.env.FOOD_LOOKUP_ENABLED = "false";
    await expectHttpsError(call({ barcode: NUTELLA }), "failed-precondition", "feature-disabled");
    process.env.FOOD_LOOKUP_ENABLED = "TRUE";
    await expectHttpsError(call({ barcode: NUTELLA }), "failed-precondition", "feature-disabled");
    expect(fetchSpy).not.toHaveBeenCalled();
    expect([...store.keys()].filter((k) => k.includes("/usage/"))).toEqual([]);
    expect([...store.keys()]).toEqual([]);
  });

  test("flag off beats a bad barcode (flag is checked before parsing)", async () => {
    await expectHttpsError(call({ barcode: "123" }), "failed-precondition", "feature-disabled");
  });

  test.each([
    ["wrong check digit", "3017620422004"],
    ["length 7", "1234567"],
    ["length 11", "03600029145"],
    ["non-digits", "30176204220AB"],
    ["whitespace", " 3017620422003"],
    ["missing", undefined],
    ["number", 3017620422003],
  ])("invalid barcode (%s) is rejected before any fetch, budget or quota", async (_l, barcode) => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expectHttpsError(call({ barcode }), "invalid-argument", "invalid-barcode");
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(store.size).toBe(0);
  });

  test("a bare null data object is rejected the same way", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expectHttpsError(call(null), "invalid-argument", "invalid-barcode");
  });

  test("flag on, valid barcode: the callable returns the product and charges one lookup", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    const res = await call({ barcode: NUTELLA });
    expect(res.found).toBe(true);
    expect(usageOf(UID, "barcodeLookup")).toBe(1);
    expect(fetchSpy).toHaveBeenCalled();
  });

  test("nothing about the uid, barcode or upstream URL is logged", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    off = () => ({ status: 503 });
    await call({ barcode: NUTELLA }).catch(() => undefined);
    const text = loggedText(logger);
    expect(text).not.toContain(UID);
    expect(text).not.toContain(NUTELLA);
    expect(text).not.toMatch(/openfoodfacts|test-usda-key/);
  });
});

describe("FOOD-13 / FOOD-32 quota, burst limit and global budget", () => {
  const seedQuota = (n: number): void => {
    store.set(`users/${UID}/usage/${quotaDay()}`, { barcodeLookup: n });
  };

  test("the 121st lookup of the day is refused with resource-exhausted and nothing is fetched", async () => {
    expect(QUOTAS.barcodeLookup).toBe(120);
    seedQuota(119);
    await lookup(gtin(1)); // 120th: allowed
    expect(usageOf(UID, "barcodeLookup")).toBe(120);
    calls = [];
    await expectHttpsError(lookup(gtin(2)), "resource-exhausted");
    expect(calls).toEqual([]);
    expect(usageOf(UID, "barcodeLookup")).toBe(120);
  });

  test("an upstream failure refunds exactly the one charge", async () => {
    seedQuota(7);
    off = () => ({ status: 503 });
    usdaSecret.key = null;
    await lookup(gtin(1)).catch(() => undefined);
    expect(usageOf(UID, "barcodeLookup")).toBe(7);
  });

  test("per-uid burst: 5 misses per UTC minute, the 6th is 'rate-limited' (retriable) with no fetch; next minute resets", async () => {
    expect(MISS_BURST_PER_MINUTE).toBe(5);
    for (let i = 0; i < 5; i++) await lookup(gtin(i));
    calls = [];
    const err = await expectHttpsError(lookup(gtin(6)), "unavailable", "rate-limited");
    expect(err.code).not.toBe("resource-exhausted");
    expect(calls).toEqual([]);
    expect(usageOf(UID, "barcodeLookup")).toBe(5);

    clock = T0 + MIN;
    await expect(lookup(gtin(7))).resolves.toEqual({ found: false });
  });

  test("burst counters are per uid and live in the usage document", async () => {
    for (let i = 0; i < 5; i++) await lookup(gtin(i));
    await expect(lookup(gtin(20), "uid_bob_2")).resolves.toEqual({ found: false });
    const doc = store.get(`users/${UID}/usage/${new Date(T0).toISOString().slice(0, 10)}`)!;
    expect(doc.offMissCount).toBe(5);
    expect(doc.offMissWindow).toBe(202610151200);
  });

  test("cache hits never consume burst slots", async () => {
    off = () => ({ status: 200, body: NUTELLA_PRODUCT });
    await lookup(NUTELLA);
    for (let i = 0; i < 20; i++) await lookup(NUTELLA);
    const doc = store.get(`users/${UID}/usage/${new Date(T0).toISOString().slice(0, 10)}`)!;
    expect(doc.offMissCount).toBe(1);
  });

  test("an exhausted global budget (injected) answers upstream-unavailable with no network call and a refund", async () => {
    usdaSecret.key = null;
    await expectHttpsError(lookup(NUTELLA, UID, deps({ takeBudget: async () => false })), "unavailable", "upstream-unavailable");
    expect(offCalls()).toEqual([]);
    expect(usageOf(UID, "barcodeLookup")).toBe(0);
    expect(store.has(`nutrition_cache/off_${NUTELLA}`)).toBe(false);
  });

  test("the REAL shared budget: 10 distinct barcodes per UTC minute across uids, the 11th never leaves the process", async () => {
    expect(OFF_READS_PER_MINUTE).toBe(10);
    usdaSecret.key = null;
    const noBudgetOverride = (): any => ({ fetchImpl, now: () => clock, getUsdaKey: async () => null });
    for (let i = 0; i < 10; i++) await lookupBarcodeCore(`uid_${i % 2}`, "password", gtin(i), noBudgetOverride());
    expect(offCalls()).toHaveLength(10);
    expect(store.get("nutrition_cache/budget_off_read_202610151200")?.count).toBe(10);

    await expectHttpsError(lookupBarcodeCore("uid_2", "password", gtin(11), noBudgetOverride()), "unavailable", "upstream-unavailable");
    expect(offCalls()).toHaveLength(10);
    expect(usageOf("uid_2", "barcodeLookup")).toBe(0);

    clock = T0 + MIN;
    await lookupBarcodeCore("uid_2", "password", gtin(12), noBudgetOverride());
    expect(offCalls()).toHaveLength(11);
    expect(store.get("nutrition_cache/budget_off_read_202610151201")?.count).toBe(1);
  });

  test("a Firestore failure on the budget is fail-closed: no fetch, refund", async () => {
    usdaSecret.key = null;
    const fakes = require("./body_scan/fakes");
    fakes.fx.failOn = (op: string, path: string) => (op === "txget" && path.startsWith("nutrition_cache/budget_") ? Object.assign(new Error("down"), { code: 14 }) : undefined);
    await expect(lookupBarcodeCore(UID, "password", NUTELLA, { fetchImpl, now: () => clock, getUsdaKey: async () => null })).rejects.toBeDefined();
    expect(offCalls()).toEqual([]);
    expect(usageOf(UID, "barcodeLookup")).toBe(0);
  });
});
