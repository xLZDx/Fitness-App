/**
 * nutrition_sources (FOOD-09, FOOD-11, FOOD-14, FOOD-31): match scoring, OFF/USDA record mapping,
 * the USDA key cache, search ranking and dedupe, enrichment limits (order, concurrency 4, total
 * budget) and the OFF User-Agent configuration.
 */
jest.mock("firebase-admin", () => require("./body_scan/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./body_scan/fakes").loggerMock());

const secret: { key: string | null; reads: number; error: unknown } = { key: "k-1", reads: 0, error: null };
jest.mock("@google-cloud/secret-manager", () => ({
  SecretManagerServiceClient: jest.fn().mockImplementation(() => ({
    accessSecretVersion: async ({ name }: { name: string }) => {
      secret.reads += 1;
      (secret as any).lastName = name;
      if (secret.error) throw secret.error;
      if (secret.key === null) return [{ payload: { data: Buffer.from("  \n") } }];
      return [{ payload: { data: Buffer.from(`  ${secret.key}\n`) } }];
    },
  })),
}));

import * as logger from "firebase-functions/logger";
import { matchRank, scoreMatch, tokens } from "../nutrition_sources/match";
import { mapOffRecord, servingGramsFromText } from "../nutrition_sources/open_food_facts";
import { getUsdaApiKey, mapUsdaFood, __resetUsdaKeyForTests, lookupUsdaByGtin, searchUsda } from "../nutrition_sources/usda_fdc";
import { rankAndCap, needsUsdaKey, MAX_RESULTS } from "../nutrition_sources/search";
import { ENRICH_CONCURRENCY, ENRICH_TOTAL_BUDGET_MS, MATCH_FACTOR, MIN_CALL_MS, enrichItems, entryConfidence } from "../nutrition_sources/enrich";
import { offUserAgent, offContact, appVersion, DEFAULT_OFF_CONTACT, DEFAULT_APP_VERSION, USDA_SECRET_ID } from "../nutrition_config";
import { __resetBreakersForTests } from "../nutrition_breaker";
import { coerceMealAnalysis } from "../coerce_meal_analysis";
import type { FoodCandidate } from "../nutrition_sources/types";
import { resetFakes } from "./body_scan/fakes";

const T0 = Date.UTC(2026, 9, 15, 12, 0, 0);
const MIN = 60_000;

beforeEach(() => {
  resetFakes();
  __resetBreakersForTests();
  __resetUsdaKeyForTests();
  secret.key = "k-1";
  secret.reads = 0;
  secret.error = null;
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  delete process.env.OFF_CONTACT;
  delete process.env.APP_VERSION;
});

describe("match: tokens and scoreMatch", () => {
  test("tokens lower-case, drop 1-char words, singularise long plurals and dedupe", () => {
    expect(tokens("Chicken Breasts, raw & a RAW")).toEqual(["chicken", "breast", "raw"]);
    expect(tokens("peas")).toEqual(["pea"]); // length 4 > 3 and ends in s -> singularised
  });

  test("exact: every query token present and at least half the candidate tokens matched", () => {
    expect(scoreMatch(["chicken breast"], "Chicken breast, raw")).toBe("exact");
    expect(scoreMatch(["chicken breasts"], "Chicken breast")).toBe("exact");
  });

  test("close: >= 2/3 of the query tokens matched but not exact", () => {
    expect(scoreMatch(["grilled chicken breast"], "Chicken breast, raw")).toBe("close");
  });

  test("weak: >= 1/3 matched", () => {
    expect(scoreMatch(["roast chicken sandwich"], "Chicken breast, raw")).toBe("weak");
  });

  test("none: no overlap, empty query, empty candidate", () => {
    expect(scoreMatch(["apple"], "Chicken breast")).toBe("none");
    expect(scoreMatch([""], "Chicken breast")).toBe("none");
    expect(scoreMatch([], "Chicken breast")).toBe("none");
    expect(scoreMatch(["chicken"], "")).toBe("none");
  });

  test("a candidate that is mostly unrelated words is not exact", () => {
    expect(scoreMatch(["rice"], "Beef stew with rice carrots potatoes onions")).toBe("close");
  });

  test("the best of several phrases wins; ranks are ordered", () => {
    expect(scoreMatch(["apple", "chicken breast"], "Chicken breast, raw")).toBe("exact");
    expect(["exact", "close", "weak", "none"].map((q) => matchRank(q as never))).toEqual([3, 2, 1, 0]);
  });
});

describe("mapOffRecord and servingGramsFromText", () => {
  const nutriments = { "energy-kcal_100g": 539, proteins_100g: 6.3, carbohydrates_100g: 57.5, fat_100g: 30.9 };

  test("maps code, name, first brand, per-100 g and quality", () => {
    const c = mapOffRecord({ code: "3017620422003", product_name: "Nutella", brands: "Ferrero,Other", nutriments })!;
    expect(c).toMatchObject({ foodRef: "off:3017620422003", sourceRef: "3017620422003", name: "Nutella", brand: "Ferrero", source: "open_food_facts", completeness: "complete" });
    expect(c.per100g).toEqual({ kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9 });
    expect("servingG" in c).toBe(false);
    expect("derivedEnergy" in c).toBe(false);
  });

  test("a numeric code and an array of brands are accepted", () => {
    expect(mapOffRecord({ code: 3017620422003, brands: ["Ferrero", "X"], product_name: "N", nutriments })?.brand).toBe("Ferrero");
  });

  test.each([["short code", "1234567"], ["long code", "123456789012345"], ["non-digit", "30176204220AB"], ["empty", ""]])("%s is rejected", (_l, code) => {
    expect(mapOffRecord({ code, product_name: "x", nutriments })).toBeNull();
  });

  test("records without nutrition, non-objects and arrays are rejected", () => {
    expect(mapOffRecord({ code: "3017620422003", product_name: "x", nutriments: {} })).toBeNull();
    for (const v of [null, undefined, "x", 5, []]) expect(mapOffRecord(v)).toBeNull();
  });

  test("a missing name falls back to the brand, then to 'Product'", () => {
    expect(mapOffRecord({ code: "3017620422003", brands: "Ferrero", nutriments })?.name).toBe("Ferrero");
    expect(mapOffRecord({ code: "3017620422003", nutriments })?.name).toBe("Product");
  });

  test("serving_quantity wins over serving_size text; out-of-range servings are dropped", () => {
    expect(mapOffRecord({ code: "3017620422003", nutriments, serving_quantity: "25", serving_size: "30 g" })?.servingG).toBe(25);
    expect(mapOffRecord({ code: "3017620422003", nutriments, serving_size: "30 g" })?.servingG).toBe(30);
    expect(mapOffRecord({ code: "3017620422003", nutriments, serving_quantity: 5000 })?.servingG).toBeUndefined();
    expect(mapOffRecord({ code: "3017620422003", nutriments, serving_quantity: 0 })?.servingG).toBeUndefined();
  });

  test("servingGramsFromText: g, ml, comma decimals, Cyrillic units; rubbish and oz are undefined", () => {
    expect(servingGramsFromText("30 g")).toBe(30);
    expect(servingGramsFromText("250,5 ml")).toBe(250.5);
    expect(servingGramsFromText("40г")).toBe(40);
    expect(servingGramsFromText("200 мл")).toBe(200);
    expect(servingGramsFromText("1 cup (240 ml)")).toBe(240);
    expect(servingGramsFromText("3 oz")).toBeUndefined();
    expect(servingGramsFromText("0 g")).toBeUndefined();
    expect(servingGramsFromText("4000 g")).toBeUndefined();
    expect(servingGramsFromText(null)).toBeUndefined();
  });

  test("derived-energy and inconsistent quality propagate", () => {
    const c = mapOffRecord({ code: "3017620422003", product_name: "x", nutriments: { proteins_100g: 10, carbohydrates_100g: 20, fat_100g: 5 } })!;
    expect(c.derivedEnergy).toBe(true);
    expect(c.completeness).toBe("partial");
    expect(mapOffRecord({ code: "3017620422003", product_name: "x", nutriments: { "energy-kcal_100g": 100, proteins_100g: 40, carbohydrates_100g: 0, fat_100g: 0 } })?.completeness).toBe("inconsistent");
  });
});

describe("mapUsdaFood", () => {
  const rows = [
    { nutrientId: 1008, value: 165, unitName: "KCAL" },
    { nutrientId: 1003, value: 31 },
    { nutrientId: 1005, value: 0 },
    { nutrientId: 1004, value: 3.6 },
  ];

  test("maps id, description, brand and per-100 g", () => {
    const c = mapUsdaFood({ fdcId: 171077, description: "Chicken, breast", brandName: "Acme", foodNutrients: rows })!;
    expect(c).toMatchObject({ foodRef: "usda:171077", sourceRef: "171077", name: "Chicken, breast", brand: "Acme", source: "usda_fdc" });
    expect(c.per100g).toEqual({ kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6 });
  });

  test.each([[0], [-5], [1.5], ["abc"], [undefined]])("fdcId %p is rejected", (fdcId) => {
    expect(mapUsdaFood({ fdcId, description: "x", foodNutrients: rows })).toBeNull();
  });

  test("no description or hostile-only description is rejected", () => {
    expect(mapUsdaFood({ fdcId: 1, foodNutrients: rows })).toBeNull();
    expect(mapUsdaFood({ fdcId: 1, description: "<br>", foodNutrients: rows })).toBeNull();
  });

  test("servingSize only counts in g or ml and within 1..3000", () => {
    expect(mapUsdaFood({ fdcId: 1, description: "x", foodNutrients: rows, servingSize: 32, servingSizeUnit: "G" })?.servingG).toBe(32);
    expect(mapUsdaFood({ fdcId: 1, description: "x", foodNutrients: rows, servingSize: 240, servingSizeUnit: "ml" })?.servingG).toBe(240);
    expect(mapUsdaFood({ fdcId: 1, description: "x", foodNutrients: rows, servingSize: 2, servingSizeUnit: "cup" })?.servingG).toBeUndefined();
    expect(mapUsdaFood({ fdcId: 1, description: "x", foodNutrients: rows, servingSize: 9000, servingSizeUnit: "g" })?.servingG).toBeUndefined();
  });

  test("non-objects and foods with no nutrition are rejected", () => {
    for (const v of [null, "x", [], 5]) expect(mapUsdaFood(v)).toBeNull();
    expect(mapUsdaFood({ fdcId: 1, description: "x", foodNutrients: [] })).toBeNull();
  });
});

describe("getUsdaApiKey (Secret Manager, runtime read)", () => {
  test("reads USDA_FDC_API_KEY/versions/latest, trims, caches for 10 minutes", async () => {
    expect(USDA_SECRET_ID).toBe("USDA_FDC_API_KEY");
    expect(await getUsdaApiKey(T0)).toBe("k-1");
    expect((secret as any).lastName).toMatch(/\/secrets\/USDA_FDC_API_KEY\/versions\/latest$/);
    secret.key = "k-2";
    expect(await getUsdaApiKey(T0 + 10 * MIN - 1)).toBe("k-1");
    expect(secret.reads).toBe(1);
    expect(await getUsdaApiKey(T0 + 10 * MIN)).toBe("k-2");
    expect(secret.reads).toBe(2);
  });

  test("an empty secret and a NOT_FOUND secret both resolve null; absent is re-checked after 1 minute", async () => {
    secret.key = null;
    expect(await getUsdaApiKey(T0)).toBeNull();
    secret.key = "late";
    expect(await getUsdaApiKey(T0 + MIN - 1)).toBeNull();
    expect(secret.reads).toBe(1);
    expect(await getUsdaApiKey(T0 + MIN)).toBe("late");
  });

  test("NOT_FOUND (code 5) is silent; another failure logs only the numeric code, never the message", async () => {
    secret.error = Object.assign(new Error("projects/p/secrets/USDA_FDC_API_KEY denied for sa@example.com"), { code: 5 });
    expect(await getUsdaApiKey(T0)).toBeNull();
    expect(logger.warn).not.toHaveBeenCalled();
    __resetUsdaKeyForTests();
    secret.error = Object.assign(new Error("projects/p/secrets/USDA_FDC_API_KEY denied for sa@example.com"), { code: 7 });
    expect(await getUsdaApiKey(T0)).toBeNull();
    expect(logger.warn).toHaveBeenCalledTimes(1);
    expect((logger.warn as jest.Mock).mock.calls[0]).toEqual(["usda_key_unreadable", { code: 7 }]);
    expect(JSON.stringify((logger.warn as jest.Mock).mock.calls)).not.toMatch(/sa@example|projects\/p/);
  });

  test("never throws on a non-error rejection", async () => {
    secret.error = "boom";
    expect(await getUsdaApiKey(T0)).toBeNull();
  });
});

describe("USDA requests", () => {
  const json = (b: unknown, status = 200): typeof fetch => (async () => new Response(JSON.stringify(b), { status })) as any;

  test("searchUsda maps foods and skips unusable ones", async () => {
    const f = json({ foods: [{ fdcId: 1, description: "Rice", foodNutrients: [{ nutrientId: 1008, value: 130, unitName: "KCAL" }, { nutrientId: 1003, value: 2.7 }, { nutrientId: 1005, value: 28 }, { nutrientId: 1004, value: 0.3 }] }, { fdcId: 2 }] });
    const out = await searchUsda("k", "rice", { fetchImpl: f, now: () => T0 });
    expect(out.map((c) => c.foodRef)).toEqual(["usda:1"]);
  });

  test("a non-200 is an upstream failure; a missing foods array is an empty list", async () => {
    await expect(searchUsda("k", "rice", { fetchImpl: json({}, 403), now: () => T0 })).rejects.toMatchObject({ slug: "upstream-unavailable" });
    expect(await searchUsda("k", "rice", { fetchImpl: json({ nope: 1 }), now: () => T0 })).toEqual([]);
    expect(await searchUsda("k", "rice", { fetchImpl: (async () => new Response("<html>", { status: 200 })) as any, now: () => T0 })).toEqual([]);
  });

  test("lookupUsdaByGtin returns null when nothing matches the exact code", async () => {
    expect(await lookupUsdaByGtin("k", "3017620422003", { fetchImpl: json({ foods: [{ fdcId: 1, description: "x", gtinUpc: "123" }] }), now: () => T0 })).toBeNull();
    expect(await lookupUsdaByGtin("k", "3017620422003", { fetchImpl: json({ foods: [{ fdcId: 1, description: "x" }] }), now: () => T0 })).toBeNull();
  });
});

describe("search: rankAndCap and scope", () => {
  const cand = (name: string, o: Partial<FoodCandidate> = {}): FoodCandidate => ({
    foodRef: `usda:${name}`,
    name,
    per100g: { kcal: 100, proteinG: 1, carbsG: 1, fatG: 1 },
    source: "usda_fdc",
    sourceRef: name,
    completeness: "complete",
    ...o,
  });

  test("dedupes by name|brand case-insensitively, keeping the first", () => {
    const out = rankAndCap("rice", [cand("Rice", { sourceRef: "a" }), cand("rice", { sourceRef: "b" }), cand("Rice", { brand: "Acme" })]);
    expect(out.map((c) => c.sourceRef)).toEqual(["a", "Rice"]);
    expect(out).toHaveLength(2);
  });

  test("ranks by match, then completeness, then original order (stable)", () => {
    const out = rankAndCap("chicken breast", [
      cand("Apple"),
      cand("Chicken breast pie with extra words here", { completeness: "inconsistent" }),
      cand("Chicken breast", { completeness: "partial" }),
      cand("Chicken breast raw", { completeness: "complete" }),
    ]);
    expect(out.map((c) => c.name)).toEqual(["Chicken breast raw", "Chicken breast", "Chicken breast pie with extra words here", "Apple"]);
  });

  test("caps at the limit (20 by default)", () => {
    const many = Array.from({ length: 50 }, (_, i) => cand(`Rice ${i}`));
    expect(MAX_RESULTS).toBe(20);
    expect(rankAndCap("rice", many)).toHaveLength(20);
    expect(rankAndCap("rice", many, 3)).toHaveLength(3);
  });

  test("only the generic scope needs the USDA key", () => {
    expect(needsUsdaKey("generic")).toBe(true);
    expect(needsUsdaKey("packaged")).toBe(false);
    expect(needsUsdaKey("both")).toBe(false);
  });
});

describe("enrichment limits (FOOD-09)", () => {
  const items = (n: number) =>
    coerceMealAnalysis(
      JSON.stringify({
        mealName: "m",
        items: Array.from({ length: n }, (_, i) => ({
          name: `Food ${String.fromCharCode(97 + i)}`,
          queryTerms: [`food ${String.fromCharCode(97 + i)}`],
          packaged: false,
          estimatedGrams: { low: 90, mid: 100, high: 110 },
          confidence: 0.8,
          uncertainties: [],
          llmPer100g: { kcal: 100, proteinG: 5, carbsG: 15, fatG: 2 },
        })),
        overallConfidence: 0.8,
        assumptions: [],
      }),
    ).items;

  const usdaBody = (name: string): unknown => ({
    foods: [{ fdcId: 1, description: name, foodNutrients: [{ nutrientId: 1008, value: 50, unitName: "KCAL" }, { nutrientId: 1003, value: 5 }, { nutrientId: 1005, value: 5 }, { nutrientId: 1004, value: 1 }] }],
  });

  test("constants: concurrency 4, total budget 8 s, minimum call 500 ms, factors 1/0.8/0.5/0.35", () => {
    expect(ENRICH_CONCURRENCY).toBe(4);
    expect(ENRICH_TOTAL_BUDGET_MS).toBe(8000);
    expect(MIN_CALL_MS).toBe(500);
    expect(MATCH_FACTOR).toEqual({ exact: 1.0, close: 0.8, weak: 0.5, none: 0.35 });
  });

  test("order is preserved and at most 4 lookups run at once", async () => {
    let active = 0;
    let peak = 0;
    const fetchImpl = (async (input: unknown) => {
      active++;
      peak = Math.max(peak, active);
      await new Promise((r) => setTimeout(r, 15));
      active--;
      const q = new URL(String(input)).searchParams.get("query")!;
      return new Response(JSON.stringify(usdaBody(q)), { status: 200 });
    }) as any;
    const out = await enrichItems(items(9), { fetchImpl, now: () => T0, getUsdaKey: async () => "k", takeBudget: async () => true });
    expect(out.map((i) => i.name)).toEqual(["food a", "food b", "food c", "food d", "food e", "food f", "food g", "food h", "food i"]);
    expect(peak).toBeLessThanOrEqual(4);
    expect(peak).toBeGreaterThan(1);
  });

  test("once the 8 s total budget is spent (under 500 ms left) no further upstream call starts: later items use the model estimate", async () => {
    let t = T0;
    const fetchImpl = jest.fn(async (input: unknown) => {
      t += 7_700; // each call burns most of the 8 s budget
      return new Response(JSON.stringify(usdaBody(new URL(String(input)).searchParams.get("query")!)), { status: 200 });
    });
    const out = await enrichItems(items(5), { fetchImpl: fetchImpl as any, now: () => t, getUsdaKey: async () => "k", takeBudget: async () => true });
    expect(fetchImpl).toHaveBeenCalledTimes(4); // the 4 parallel workers started inside the budget
    expect(out.map((i) => i.source)).toEqual(["usda_fdc", "usda_fdc", "usda_fdc", "usda_fdc", "llm_estimate"]);
    expect(out[4].checkCodes).toContain("lowConfidenceItem");
  });

  test("each upstream call gets at most the time remaining (timeout shrinks)", async () => {
    const aborted: boolean[] = [];
    const fetchImpl = (async (_i: unknown, init: { signal: AbortSignal }) => {
      aborted.push(init.signal.aborted);
      return new Response(JSON.stringify(usdaBody("food a")), { status: 200 });
    }) as any;
    const out = await enrichItems(items(1), { fetchImpl, now: () => T0, getUsdaKey: async () => "k", takeBudget: async () => true });
    expect(out[0].source).toBe("usda_fdc");
    expect(aborted).toEqual([false]);
  });

  test("an item with no query term of 3+ characters makes no upstream call", async () => {
    const fetchImpl = jest.fn();
    const it = items(1);
    it[0] = { ...it[0], name: "ab", queryTerms: ["ab"] };
    const out = await enrichItems(it, { fetchImpl: fetchImpl as any, now: () => T0, getUsdaKey: async () => "k", takeBudget: async () => true });
    expect(fetchImpl).not.toHaveBeenCalled();
    expect(out[0].source).toBe("llm_estimate");
  });

  test("an empty item list resolves to an empty list", async () => {
    expect(await enrichItems([], {})).toEqual([]);
  });
});

describe("entryConfidence", () => {
  const i = (confidence: number, checkCodes: string[] = []) => ({ confidence, checkCodes: checkCodes as never[] });
  test("empty -> low", () => expect(entryConfidence([])).toBe("low"));
  test("high only if every item >= 0.75 and none has a code", () => {
    expect(entryConfidence([i(0.75), i(0.9)])).toBe("high");
    expect(entryConfidence([i(0.74), i(0.9)])).toBe("medium");
    expect(entryConfidence([i(0.9, ["portionUnclear"])])).toBe("medium");
  });
  test("medium at exactly 0.5, low below it", () => {
    expect(entryConfidence([i(0.5), i(0.6)])).toBe("medium");
    expect(entryConfidence([i(0.49), i(0.9)])).toBe("low");
  });
});

describe("nutrition_config (OFF User-Agent)", () => {
  test("defaults when nothing is configured", () => {
    expect(offContact()).toBe(DEFAULT_OFF_CONTACT);
    expect(appVersion()).toBe(DEFAULT_APP_VERSION);
    expect(offUserAgent()).toBe(`FitnessApp/${DEFAULT_APP_VERSION} (${DEFAULT_OFF_CONTACT})`);
  });

  test("configured values are used", () => {
    process.env.OFF_CONTACT = "ops@example.com";
    process.env.APP_VERSION = "2.3.4";
    expect(offUserAgent()).toBe("FitnessApp/2.3.4 (ops@example.com)");
  });

  test("header-unsafe characters are stripped (no CR/LF header injection) and values are bounded", () => {
    process.env.OFF_CONTACT = "ops@example.com\r\nX-Evil: 1";
    process.env.APP_VERSION = "9".repeat(50);
    const ua = offUserAgent();
    expect(ua).not.toMatch(/[\r\n]/);
    expect(appVersion()).toHaveLength(20);
    expect(offContact().length).toBeLessThanOrEqual(80);
    process.env.OFF_CONTACT = "\r\n\u0000";
    expect(offContact()).toBe(DEFAULT_OFF_CONTACT);
  });
});
