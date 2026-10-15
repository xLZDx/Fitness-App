/**
 * T109 search_foods (FOOD-14, FOOD-31, FOOD-32, FOOD-33): query bounds, limit clamp, cache key
 * `q_<sha1(lang|query|scope)>` 7 d, the USDA key from the secret (never DEMO_KEY), Search-a-licious
 * -> legacy fallback, Atwater-derived energy, dedupe and cap, quota 151st, burst and global budget.
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

import { createHash } from "crypto";
import * as logger from "firebase-functions/logger";
import { parseSearchRequest, searchFoods, searchFoodsCore, MISS_BURST_PER_MINUTE } from "../nutrition_lookup";
import { __resetBreakersForTests } from "../nutrition_breaker";
import { __resetUsdaKeyForTests } from "../nutrition_sources/usda_fdc";
import { __resetAiGatewayControlCacheForTests, QUOTAS } from "../abuse_guard";
import { CACHE_TTL_MS, searchCacheKey } from "../nutrition_cache";
import { OFF_SEARCHES_PER_MINUTE } from "../nutrition_budget";
import { callReq, expectHttpsError, loggedText, resetFakes, store, usageOf, fx } from "./body_scan/fakes";

const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);
const MIN = 60_000;
const DAY = 24 * 60 * MIN;
const UID = "uid_alice_1";
const quotaDay = (): string => new Date().toISOString().slice(0, 10);

type Reply = { status: number; body?: unknown };
interface Call {
  url: URL;
  headers: Record<string, string>;
}
let calls: Call[];
let clock: number;
let usda: (u: URL) => Reply;
let salicious: (u: URL) => Reply;
let legacy: (u: URL) => Reply;

const usdaFood = (fdcId: number, description: string, o: { kcal?: number; p?: number; c?: number; f?: number } = {}): unknown => ({
  fdcId,
  description,
  foodNutrients: [
    ...(o.kcal === undefined ? [] : [{ nutrientId: 1008, value: o.kcal, unitName: "KCAL" }]),
    { nutrientId: 1003, value: o.p ?? 10, unitName: "G" },
    { nutrientId: 1005, value: o.c ?? 20, unitName: "G" },
    { nutrientId: 1004, value: o.f ?? 5, unitName: "G" },
  ],
});
const offHit = (code: string, name: string, brand = "Brand"): unknown => ({
  code,
  product_name: name,
  brands: brand,
  nutriments: { "energy-kcal_100g": 165, proteins_100g: 10, carbohydrates_100g: 20, fat_100g: 5 },
});

const fetchImpl = jest.fn(async (input: unknown, init?: { headers?: Record<string, string> }) => {
  const url = new URL(String(input));
  calls.push({ url, headers: { ...(init?.headers ?? {}) } });
  let r: Reply;
  if (url.hostname === "api.nal.usda.gov") r = usda(url);
  else if (url.hostname === "search.openfoodfacts.org") r = salicious(url);
  else if (url.hostname === "world.openfoodfacts.org" && url.pathname === "/cgi/search.pl") r = legacy(url);
  else throw new Error(`unexpected request ${url.origin}${url.pathname}`);
  return new Response(r.body === undefined ? "" : JSON.stringify(r.body), { status: r.status });
}) as unknown as typeof fetch;

const hostCalls = (host: string): Call[] => calls.filter((c) => c.url.hostname === host);
const usdaCalls = (): Call[] => hostCalls("api.nal.usda.gov");
const saliciousCalls = (): Call[] => hostCalls("search.openfoodfacts.org");
const legacyCalls = (): Call[] => calls.filter((c) => c.url.pathname === "/cgi/search.pl");

const deps = (o: Record<string, unknown> = {}): any => ({
  fetchImpl,
  now: () => clock,
  takeBudget: async () => true,
  getUsdaKey: async () => usdaSecret.key,
  ...o,
});

const req = (o: Record<string, unknown> = {}): any => ({ query: "chicken breast", languageCode: "en", scope: "both", limit: 20, ...o });
const search = (r: any = req(), uid = UID, d: any = deps()): Promise<any> => searchFoodsCore(uid, "password", r, d);

beforeEach(() => {
  resetFakes();
  calls = [];
  clock = T0;
  usdaSecret.key = "test-usda-key";
  usdaSecret.reads = 0;
  usda = () => ({ status: 200, body: { foods: [] } });
  salicious = () => ({ status: 200, body: { hits: [] } });
  legacy = () => ({ status: 200, body: { products: [] } });
  (fetchImpl as unknown as jest.Mock).mockClear();
  __resetBreakersForTests();
  __resetUsdaKeyForTests();
  __resetAiGatewayControlCacheForTests();
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  process.env.OFF_CONTACT = "ops@example.com";
  delete process.env.FOOD_LOOKUP_ENABLED;
});

describe("FOOD-14 request parsing", () => {
  const bad = (data: unknown): void => {
    try {
      parseSearchRequest(data);
    } catch (e: any) {
      expect(e.code).toBe("invalid-argument");
      return;
    }
    throw new Error("expected a refusal");
  };

  test("query of 2 characters is refused, 3 accepted, 60 accepted, 61 refused", () => {
    bad({ query: "ab" });
    expect(parseSearchRequest({ query: "abc" }).query).toBe("abc");
    expect(parseSearchRequest({ query: "a".repeat(60) }).query).toHaveLength(60);
    bad({ query: "a".repeat(61) });
  });

  test("query is trimmed before the bounds apply; non-strings and missing are refused", () => {
    bad({ query: "  ab  " });
    expect(parseSearchRequest({ query: "  abc  " }).query).toBe("abc");
    bad({});
    bad(null);
    bad({ query: 123 });
    bad({ query: ["rice"] });
  });

  test("the query is lower-cased and stripped of markup, URLs and noise (it is what is searched and cache-keyed)", () => {
    expect(parseSearchRequest({ query: "Chicken BREAST" }).query).toBe("chicken breast");
    expect(parseSearchRequest({ query: "<b>rice</b> https://evil.example" }).query).toBe("rice");
    bad({ query: "<b>a</b>" }); // nothing left after sanitising
    bad({ query: "!!!???" });
  });

  test("limit defaults to 20, clamps to 1..20, floors fractions and ignores non-numbers", () => {
    expect(parseSearchRequest({ query: "rice" }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: 50 }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: 21 }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: 20 }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: 5 }).limit).toBe(5);
    expect(parseSearchRequest({ query: "rice", limit: 5.9 }).limit).toBe(5);
    expect(parseSearchRequest({ query: "rice", limit: 0 }).limit).toBe(1);
    expect(parseSearchRequest({ query: "rice", limit: -4 }).limit).toBe(1);
    expect(parseSearchRequest({ query: "rice", limit: "3" }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: NaN }).limit).toBe(20);
    expect(parseSearchRequest({ query: "rice", limit: Infinity }).limit).toBe(20);
  });

  test("scope defaults to both; unknown scope and language are refused", () => {
    expect(parseSearchRequest({ query: "rice" }).scope).toBe("both");
    for (const s of ["generic", "packaged", "both"]) expect(parseSearchRequest({ query: "rice", scope: s }).scope).toBe(s);
    bad({ query: "rice", scope: "everything" });
    bad({ query: "rice", scope: 1 });
    bad({ query: "rice", languageCode: "de" });
    expect(parseSearchRequest({ query: "rice", languageCode: "ru" }).languageCode).toBe("ru");
    expect(parseSearchRequest({ query: "rice" }).languageCode).toBe("en");
  });

  test("a Cyrillic query is kept", () => {
    expect(parseSearchRequest({ query: "гречка", languageCode: "ru" }).query).toBe("гречка");
  });
});

describe("FOOD-14 cache", () => {
  test("a miss writes q_<sha1(lang|query|scope)> with expireAt = now + 7 d and charges 1", async () => {
    usda = () => ({ status: 200, body: { foods: [usdaFood(1, "Chicken breast, raw", { kcal: 120 })] } });
    await search(req({ scope: "generic" }));
    const key = "q_" + createHash("sha1").update("en|chicken breast|generic").digest("hex");
    expect(searchCacheKey("en", "chicken breast", "generic")).toBe(key);
    const doc = store.get(`nutrition_cache/${key}`)!;
    expect(doc.found).toBe(true);
    expect((doc.expireAt as Date).getTime() - T0).toBe(CACHE_TTL_MS.search);
    expect(CACHE_TTL_MS.search).toBe(7 * DAY);
    expect(usageOf(UID, "foodSearch")).toBe(1);
  });

  test("a hit within 7 days makes no network call, takes no budget, no burst slot and charges nothing", async () => {
    usda = () => ({ status: 200, body: { foods: [usdaFood(1, "Chicken breast, raw", { kcal: 120 })] } });
    const first = await search(req({ scope: "generic" }));
    calls = [];
    const takeBudget = jest.fn(async () => true);
    clock = T0 + 7 * DAY - 1;
    const second = await search(req({ scope: "generic" }), "uid_other", deps({ takeBudget }));
    expect(second).toEqual(first);
    expect(calls).toEqual([]);
    expect(takeBudget).not.toHaveBeenCalled();
    expect(usageOf("uid_other", "foodSearch")).toBe(0);
    clock = T0 + 7 * DAY;
    await search(req({ scope: "generic" }));
    expect(usdaCalls()).toHaveLength(1);
  });

  test("scope and language are part of the cache identity", async () => {
    await search(req({ scope: "generic" }));
    await search(req({ scope: "packaged" }));
    await search(req({ scope: "generic", languageCode: "ru" }));
    expect(usdaCalls()).toHaveLength(2);
    expect(saliciousCalls()).toHaveLength(1);
  });

  test("an empty result is cached as not-found for 1 day and still charged", async () => {
    await search(req({ scope: "generic" }));
    const doc = store.get(`nutrition_cache/${searchCacheKey("en", "chicken breast", "generic")}`)!;
    expect(doc.found).toBe(false);
    expect((doc.expireAt as Date).getTime() - T0).toBe(CACHE_TTL_MS.negative);
    expect(usageOf(UID, "foodSearch")).toBe(1);
  });

  test("a cached list is re-sliced to the caller's limit", async () => {
    usda = () => ({ status: 200, body: { foods: Array.from({ length: 10 }, (_, i) => usdaFood(i + 1, `Chicken breast variant ${i}`, { kcal: 120 })) } });
    await search(req({ scope: "generic", limit: 20 }));
    const res = await search(req({ scope: "generic", limit: 3 }));
    expect(res.results).toHaveLength(3);
  });
});

describe("FOOD-14 USDA key and generic scope", () => {
  test("generic scope with no key -> failed-precondition source-not-configured BEFORE any charge, budget or fetch", async () => {
    usdaSecret.key = null;
    await expectHttpsError(search(req({ scope: "generic" }), UID, deps({ getUsdaKey: undefined })), "failed-precondition", "source-not-configured");
    expect(calls).toEqual([]);
    expect(store.size).toBe(0);
  });

  test("the key is read from the secret (X-Api-Key) and the public DEMO_KEY is never sent", async () => {
    usdaSecret.key = "registered-key-123";
    await search(req({ scope: "generic" }), UID, deps({ getUsdaKey: undefined }));
    expect(usdaSecret.reads).toBe(1);
    const { headers, url } = usdaCalls()[0];
    expect(headers["X-Api-Key"]).toBe("registered-key-123");
    expect(JSON.stringify(calls.map((c) => [c.url.toString(), c.headers]))).not.toMatch(/DEMO_KEY/);
    expect(url.search).not.toMatch(/registered-key|api_key/i);
  });

  test("the secret is cached between calls (no read per request)", async () => {
    usdaSecret.key = "k1";
    await search(req({ query: "rice" }), UID, deps({ getUsdaKey: undefined }));
    await search(req({ query: "beans" }), UID, deps({ getUsdaKey: undefined }));
    expect(usdaSecret.reads).toBe(1);
  });

  test("the USDA request is Foundation and SR Legacy, page size 10, over api.nal.usda.gov /fdc/v1/foods/search", async () => {
    await search(req({ scope: "generic" }));
    const { url } = usdaCalls()[0];
    expect(url.origin + url.pathname).toBe("https://api.nal.usda.gov/fdc/v1/foods/search");
    expect(url.searchParams.get("query")).toBe("chicken breast");
    expect(url.searchParams.get("dataType")).toBe("Foundation,SR Legacy");
    expect(url.searchParams.get("pageSize")).toBe("10");
  });

  test("scope generic never touches Open Food Facts; scope packaged never touches USDA", async () => {
    await search(req({ scope: "generic" }));
    expect(calls.filter((c) => c.url.hostname.includes("openfoodfacts"))).toEqual([]);
    calls = [];
    await search(req({ scope: "packaged", query: "nutella" }));
    expect(usdaCalls()).toEqual([]);
    expect(saliciousCalls()).toHaveLength(1);
  });

  test("scope both with no key skips USDA and answers from Open Food Facts (no refusal)", async () => {
    usdaSecret.key = null;
    salicious = () => ({ status: 200, body: { hits: [offHit("3017620422003", "Chicken breast slices")] } });
    const res = await search(req({ scope: "both" }), UID, deps({ getUsdaKey: undefined }));
    expect(res.results).toHaveLength(1);
    expect(usdaCalls()).toEqual([]);
  });

  test("a USDA food without an energy nutrient gets Atwater energy and derivedEnergy", async () => {
    usda = () => ({ status: 200, body: { foods: [usdaFood(11, "Chicken breast, raw", { p: 10, c: 20, f: 5 })] } });
    const res = await search(req({ scope: "generic" }));
    expect(res.results[0].per100g).toEqual({ kcal: 165, proteinG: 10, carbsG: 20, fatG: 5 });
    expect(res.results[0].derivedEnergy).toBe(true);
    expect(res.results[0].completeness).toBe("partial");
    expect(res.results[0].foodRef).toBe("usda:11");
    expect(res.results[0].source).toBe("usda_fdc");
  });

  test("a USDA food with no usable nutrition or name is skipped", async () => {
    usda = () => ({
      status: 200,
      body: { foods: [{ fdcId: 1, description: "No nutrients", foodNutrients: [] }, { fdcId: 2, description: "<>", foodNutrients: [] }, usdaFood(3, "Chicken breast", { kcal: 120 }), null, "x"] },
    });
    const res = await search(req({ scope: "generic" }));
    expect(res.results.map((r: any) => r.foodRef)).toEqual(["usda:3"]);
  });
});

describe("FOOD-14 / FOOD-31 Open Food Facts search and fallback", () => {
  test("Search-a-licious is primary: fixed host/path, q and langs, User-Agent", async () => {
    salicious = () => ({ status: 200, body: { hits: [offHit("3017620422003", "Chicken breast slices")] } });
    const res = await search(req({ scope: "packaged", languageCode: "ru" }));
    const { url, headers } = saliciousCalls()[0];
    expect(url.origin + url.pathname).toBe("https://search.openfoodfacts.org/search");
    expect(url.searchParams.get("q")).toBe("chicken breast");
    expect(url.searchParams.get("langs")).toBe("ru,en");
    expect(url.searchParams.get("page_size")).toBe("20");
    expect(headers["User-Agent"]).toMatch(/^FitnessApp\/\S+ \(ops@example\.com\)$/);
    expect(res.results[0]).toMatchObject({ foodRef: "off:3017620422003", source: "open_food_facts", sourceRef: "3017620422003", brand: "Brand" });
    expect(legacyCalls()).toEqual([]);
  });

  test("Search-a-licious 503 -> the legacy endpoint answers", async () => {
    salicious = () => ({ status: 503 });
    legacy = () => ({ status: 200, body: { products: [offHit("3017620422003", "Chicken breast slices")] } });
    const res = await search(req({ scope: "packaged" }));
    expect(res.results.map((r: any) => r.foodRef)).toEqual(["off:3017620422003"]);
    const { url } = legacyCalls()[0];
    expect(url.origin + url.pathname).toBe("https://world.openfoodfacts.org/cgi/search.pl");
    expect(url.searchParams.get("search_terms")).toBe("chicken breast");
    expect(url.searchParams.get("json")).toBe("1");
    expect(url.searchParams.get("action")).toBe("process");
  });

  test("Search-a-licious 429 stops the chain: legacy is NOT called, and the call fails calmly with a refund", async () => {
    salicious = () => ({ status: 429 });
    await expectHttpsError(search(req({ scope: "packaged" })), "unavailable", "upstream-unavailable");
    expect(legacyCalls()).toEqual([]);
    expect(usageOf(UID, "foodSearch")).toBe(0);
  });

  test("both Open Food Facts endpoints down -> upstream-unavailable, refund, nothing cached", async () => {
    salicious = () => ({ status: 500 });
    legacy = () => ({ status: 500 });
    await expectHttpsError(search(req({ scope: "packaged" })), "unavailable", "upstream-unavailable");
    expect(usageOf(UID, "foodSearch")).toBe(0);
    expect([...store.keys()].some((k) => k.startsWith("nutrition_cache/q_"))).toBe(false);
  });

  test("a hostile query is one encoded value: 'x&api_key=evil' never becomes a parameter", async () => {
    await search(req({ query: "x&api_key=evil", scope: "both" }));
    for (const c of calls) {
      expect(c.url.searchParams.has("api_key")).toBe(false);
      expect(c.url.searchParams.has("evil")).toBe(false);
    }
    expect(saliciousCalls()[0].url.searchParams.get("q")).toBe("x&api_key=evil");
    expect(saliciousCalls()[0].url.search).toContain("x%26api_key%3Devil");
    expect(usdaCalls()[0].url.searchParams.get("query")).toBe("x&api_key=evil");
  });

  test("hostile product names from upstream are sanitised in the response and the cache", async () => {
    salicious = () => ({ status: 200, body: { hits: [offHit("3017620422003", "<script>alert(1)</script>Chicken breast https://evil.example", "<b>Evil</b> bob@evil.example")] } });
    const res = await search(req({ scope: "packaged" }));
    expect(res.results[0].name).toBe("alert(1) Chicken breast");
    expect(JSON.stringify(res)).not.toMatch(/evil|<|>|script/i);
    expect(JSON.stringify([...store.values()])).not.toMatch(/evil|<script/i);
  });

  test("OFF hits with a bad code or without nutrition are dropped", async () => {
    salicious = () => ({
      status: 200,
      body: { hits: [offHit("12", "Short code chicken"), { code: "3017620422003", product_name: "No nutrients chicken", nutriments: {} }, offHit("3017620422010", "Good chicken")] },
    });
    const res = await search(req({ scope: "packaged" }));
    expect(res.results.map((r: any) => r.name)).toEqual(["Good chicken"]);
  });
});

describe("FOOD-14 merge, dedupe, cap, attribution", () => {
  test("duplicates by name|brand are collapsed and the list is capped at 20", async () => {
    usda = () => ({
      status: 200,
      body: { foods: [usdaFood(1, "Chicken breast", { kcal: 120 }), usdaFood(2, "chicken breast", { kcal: 121 }), ...Array.from({ length: 12 }, (_, i) => usdaFood(10 + i, `Chicken breast ${i}`, { kcal: 120 }))] },
    });
    salicious = () => ({
      status: 200,
      body: { hits: Array.from({ length: 20 }, (_, i) => offHit(String(3000000000000 + i), `Chicken breast pack ${i}`, `B${i}`)) },
    });
    const res = await search(req({ scope: "both" }));
    expect(res.results.length).toBeLessThanOrEqual(20);
    expect(res.results).toHaveLength(20);
    const names = res.results.map((r: any) => `${r.name.toLowerCase()}|${(r.brand ?? "").toLowerCase()}`);
    expect(new Set(names).size).toBe(names.length);
    expect(res.results.filter((r: any) => r.foodRef === "usda:2")).toEqual([]);
  });

  test("results are ranked by name match against the query, then completeness", async () => {
    usda = () => ({
      status: 200,
      body: { foods: [usdaFood(1, "Beef soup with chicken noodles and many other words", { kcal: 100 }), usdaFood(2, "Chicken breast", { kcal: 120 }), usdaFood(3, "Apple", { kcal: 52 })] },
    });
    const res = await search(req({ scope: "generic" }));
    expect(res.results[0].foodRef).toBe("usda:2");
    expect(res.results[res.results.length - 1].foodRef).toBe("usda:3");
  });

  test("attributions list exactly the sources present in the (capped) answer", async () => {
    usda = () => ({ status: 200, body: { foods: [usdaFood(1, "Chicken breast", { kcal: 120 })] } });
    let res = await search(req({ scope: "generic" }));
    expect(res.attributions).toEqual([{ source: "USDA FoodData Central", licence: "CC0 1.0", url: "https://fdc.nal.usda.gov/" }]);
    salicious = () => ({ status: 200, body: { hits: [offHit("3017620422003", "Chicken breast pack")] } });
    res = await search(req({ query: "chicken breast pack", scope: "both" }));
    expect(res.attributions.map((a: any) => a.source).sort()).toEqual(["Open Food Facts", "USDA FoodData Central"]);
    res = await search(req({ query: "chicken breast pack", scope: "both", limit: 1 }));
    expect(res.results).toHaveLength(1);
  });

  test("partial failure (USDA ok, OFF down) returns the partial list but does NOT cache it", async () => {
    usda = () => ({ status: 200, body: { foods: [usdaFood(1, "Chicken breast", { kcal: 120 })] } });
    salicious = () => ({ status: 429 });
    const res = await search(req({ scope: "both" }));
    expect(res.results.map((r: any) => r.foodRef)).toEqual(["usda:1"]);
    expect([...store.keys()].some((k) => k.startsWith("nutrition_cache/q_"))).toBe(false);
    expect(usageOf(UID, "foodSearch")).toBe(1);
  });

  test("USDA down alone in generic scope -> upstream-unavailable with refund", async () => {
    usda = () => ({ status: 500 });
    await expectHttpsError(search(req({ scope: "generic" })), "unavailable", "upstream-unavailable");
    expect(usageOf(UID, "foodSearch")).toBe(0);
  });
});

describe("FOOD-14 / FOOD-32 quota, burst and global budget", () => {
  test("the 151st search of the day is refused (resource-exhausted) with no fetch", async () => {
    expect(QUOTAS.foodSearch).toBe(150);
    store.set(`users/${UID}/usage/${quotaDay()}`, { foodSearch: 149 });
    await search(req({ query: "rice" }));
    expect(usageOf(UID, "foodSearch")).toBe(150);
    calls = [];
    await expectHttpsError(search(req({ query: "beans" })), "resource-exhausted");
    expect(calls).toEqual([]);
    expect(usageOf(UID, "foodSearch")).toBe(150);
  });

  test("5 misses per UTC minute per uid; the 6th is rate-limited (retriable) with no fetch", async () => {
    for (let i = 0; i < MISS_BURST_PER_MINUTE; i++) await search(req({ query: `query number ${i}` }));
    calls = [];
    await expectHttpsError(search(req({ query: "query number 9" })), "unavailable", "rate-limited");
    expect(calls).toEqual([]);
    clock = T0 + MIN;
    await expect(search(req({ query: "query number 9" }))).resolves.toBeDefined();
  });

  test("the REAL shared search budget (6 per minute) stops the 7th distinct search before any fetch", async () => {
    expect(OFF_SEARCHES_PER_MINUTE).toBe(6);
    const real = (): any => ({ fetchImpl, now: () => clock, getUsdaKey: async () => null });
    for (let i = 0; i < 6; i++) await searchFoodsCore(`uid_${i % 3}`, "password", req({ query: `packaged item ${i}`, scope: "packaged" }), real());
    expect(saliciousCalls()).toHaveLength(6);
    await expectHttpsError(searchFoodsCore("uid_9", "password", req({ query: "packaged item 7", scope: "packaged" }), real()), "unavailable", "upstream-unavailable");
    expect(saliciousCalls()).toHaveLength(6);
    expect(legacyCalls()).toEqual([]);
    expect(usageOf("uid_9", "foodSearch")).toBe(0);
  });

  test("Firestore failure on the budget is fail-closed", async () => {
    fx.failOn = (op, path) => (op === "txget" && path.startsWith("nutrition_cache/budget_") ? Object.assign(new Error("down"), { code: 14 }) : undefined);
    await expect(searchFoodsCore(UID, "password", req({ scope: "packaged" }), { fetchImpl, now: () => clock, getUsdaKey: async () => null })).rejects.toBeDefined();
    expect(saliciousCalls()).toEqual([]);
    expect(usageOf(UID, "foodSearch")).toBe(0);
  });
});

describe("FOOD-33 callable", () => {
  const call = (data: unknown, uid: string | null = UID, provider = "password"): Promise<any> => (searchFoods as any).run(callReq(data, uid, provider));
  let fetchSpy: jest.SpyInstance;
  beforeEach(() => {
    fetchSpy = jest.spyOn(globalThis, "fetch").mockImplementation(fetchImpl as any);
  });
  afterEach(() => fetchSpy.mockRestore());

  test("unauthenticated and anonymous callers are refused", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expectHttpsError(call({ query: "rice" }, null), "unauthenticated");
    await expect(call({ query: "rice" }, UID, "anonymous")).rejects.toThrow(/real account/i);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("flag off: feature-disabled, no usage doc, no cache doc, no network (also for a bad query)", async () => {
    await expectHttpsError(call({ query: "rice" }), "failed-precondition", "feature-disabled");
    await expectHttpsError(call({ query: "x" }), "failed-precondition", "feature-disabled");
    process.env.FOOD_LOOKUP_ENABLED = "1";
    await expectHttpsError(call({ query: "rice" }), "failed-precondition", "feature-disabled");
    expect(fetchSpy).not.toHaveBeenCalled();
    expect(store.size).toBe(0);
  });

  test("flag on: a bad query is rejected as invalid-query before quota", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    await expectHttpsError(call({ query: "ab" }), "invalid-argument", "invalid-query");
    expect(usageOf(UID, "foodSearch")).toBe(0);
    expect(fetchSpy).not.toHaveBeenCalled();
  });

  test("flag on: a valid packaged search goes through safeFetch to the fixed host and is charged once", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    salicious = () => ({ status: 200, body: { hits: [offHit("3017620422003", "Chicken breast slices")] } });
    const res = await call({ query: "Chicken Breast", scope: "packaged" });
    expect(res.results).toHaveLength(1);
    expect(usageOf(UID, "foodSearch")).toBe(1);
    expect(saliciousCalls()[0].url.searchParams.get("q")).toBe("chicken breast");
  });

  test("nothing about the uid, query or upstream URL is logged", async () => {
    process.env.FOOD_LOOKUP_ENABLED = "true";
    salicious = () => ({ status: 500 });
    legacy = () => ({ status: 500 });
    await call({ query: "secret snack", scope: "packaged" }).catch(() => undefined);
    const text = loggedText(logger);
    expect(text).not.toContain(UID);
    expect(text).not.toContain("secret snack");
    expect(text).not.toMatch(/openfoodfacts|test-usda-key/);
  });
});
