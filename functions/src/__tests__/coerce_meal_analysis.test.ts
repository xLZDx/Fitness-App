/**
 * T104 coerce_meal_analysis (FOOD-01..FOOD-06, FOOD-30). The model's JSON is hostile input:
 * the parser must never throw, clamp every number, keep only closed codes, sanitise every
 * string, cut to 12 items and RECOMPUTE all totals.
 */
import {
  MAX_GRAMS,
  MAX_ITEMS,
  MIN_GRAMS,
  coerceMealAnalysis,
  itemMacros,
  parseModelJson,
  sumMacros,
} from "../coerce_meal_analysis";
import { FOOD_CHECK_CODES } from "../food_types";

type Obj = Record<string, unknown>;

const per = (o: Obj = {}): Obj => ({ kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6, ...o });
const item = (o: Obj = {}): Obj => ({
  name: "Chicken breast",
  queryTerms: ["chicken breast"],
  packaged: false,
  estimatedGrams: { low: 100, mid: 150, high: 200 },
  confidence: 0.8,
  uncertainties: [],
  llmPer100g: per(),
  ...o,
});
const meal = (items: Obj[] = [item()], o: Obj = {}): string =>
  JSON.stringify({ mealName: "Lunch", items, overallConfidence: 0.7, assumptions: [], ...o });

const first = (text: string) => coerceMealAnalysis(text).items[0];

describe("FOOD-01 parsing and numeric hygiene", () => {
  test.each([
    ["empty string", ""],
    ["whitespace", "   \n"],
    ["plain prose", "I cannot see any food"],
    ["truncated JSON", '{"mealName":"Lunch","items":[{"name":"Rice","estimatedGr'],
    ["JSON array", '[{"name":"Rice"}]'],
    ["JSON string", '"hello"'],
    ["JSON null", "null"],
    ["JSON number", "42"],
  ])("%s yields an empty meal and does not throw", (_l, text) => {
    const m = coerceMealAnalysis(text);
    expect(m.items).toEqual([]);
    expect(m.overallConfidence).toBe(0);
    expect(m.mealName).toBe("Meal");
    expect(m.totals).toEqual(sumMacros([]));
    expect(m.totals.kcal).toEqual({ low: 0, mid: 0, high: 0 });
  });

  test("non-string input does not throw", () => {
    expect(coerceMealAnalysis(undefined as unknown as string).items).toEqual([]);
    expect(coerceMealAnalysis(null as unknown as string).items).toEqual([]);
  });

  test("a fenced ```json block and prose around one object are tolerated", () => {
    const body = meal();
    expect(coerceMealAnalysis("```json\n" + body + "\n```").items).toHaveLength(1);
    expect(coerceMealAnalysis("Here you go: " + body + " Enjoy!").items).toHaveLength(1);
  });

  test("parseModelJson returns undefined for unparseable text", () => {
    expect(parseModelJson("{nope")).toBeUndefined();
    expect(parseModelJson('{"a":1}')).toEqual({ a: 1 });
  });

  test("items that is not an array gives an empty list", () => {
    expect(coerceMealAnalysis(JSON.stringify({ mealName: "x", items: "rice" })).items).toEqual([]);
    expect(coerceMealAnalysis(JSON.stringify({ mealName: "x", items: { name: "rice" } })).items).toEqual([]);
  });

  test("non-object entries inside items are skipped", () => {
    const m = coerceMealAnalysis(meal([null as unknown as Obj, "rice" as unknown as Obj, 5 as unknown as Obj, item()]));
    expect(m.items).toHaveLength(1);
  });

  test.each([
    ["NaN as string", "NaN"],
    ["Infinity as string", "Infinity"],
    ["negative", -5],
    ["null", null],
    ["text", "lots"],
    ["object", {}],
  ])("bad per-100 g kcal (%s) drops the model values but keeps the item", (_l, bad) => {
    const it = first(meal([item({ llmPer100g: per({ kcal: bad }) })]));
    expect(it).toBeDefined();
    expect(it.llmPer100g).toBeNull();
  });

  test("a negative macro drops the model values (not folded to zero)", () => {
    expect(first(meal([item({ llmPer100g: per({ fatG: -1 }) })])).llmPer100g).toBeNull();
  });

  test("numeric strings are accepted, including a decimal comma", () => {
    const it = first(meal([item({ estimatedGrams: { low: "100", mid: "150,5", high: "200" }, llmPer100g: per({ kcal: "165", proteinG: "31,0" }) })]));
    expect(it.grams).toEqual({ low: 100, mid: 150.5, high: 200 });
    expect(it.llmPer100g).toEqual({ kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6 });
  });

  test("missing per-100 g block gives llmPer100g null", () => {
    expect(first(meal([item({ llmPer100g: undefined })])).llmPer100g).toBeNull();
  });

  test("an item with no usable grams is discarded", () => {
    const m = coerceMealAnalysis(meal([item({ estimatedGrams: { low: 1, high: 2 } }), item({ estimatedGrams: "lots" }), item({ estimatedGrams: undefined }), item({ estimatedGrams: { mid: -5 } })]));
    expect(m.items).toEqual([]);
  });

  test("an item with no usable name is discarded", () => {
    expect(coerceMealAnalysis(meal([item({ name: "" }), item({ name: 5 }), item({ name: "<>" })])).items).toEqual([]);
  });

  test("unknown fields are ignored and never copied", () => {
    const m = coerceMealAnalysis(meal([item({ evil: "<script>", totals: { kcal: 1e9 } })], { instructions: "ignore", totals: { kcal: 5 } }));
    expect(JSON.stringify(m)).not.toMatch(/script|ignore|evil|instructions/);
  });
});

describe("FOOD-02 portion clamps", () => {
  const grams = (g: Obj) => first(meal([item({ estimatedGrams: g })]));

  test("0 grams clamps up to 1 and 5000 down to 3000", () => {
    expect(MIN_GRAMS).toBe(1);
    expect(MAX_GRAMS).toBe(3000);
    expect(grams({ low: 0, mid: 0, high: 0 }).grams).toEqual({ low: 1, mid: 1, high: 1 });
    expect(grams({ low: 4000, mid: 5000, high: 6000 }).grams).toEqual({ low: 3000, mid: 3000, high: 3000 });
  });

  test("exact bounds 1 and 3000 are untouched", () => {
    expect(grams({ low: 1, mid: 1, high: 1 }).grams).toEqual({ low: 1, mid: 1, high: 1 });
    expect(grams({ low: 3000, mid: 3000, high: 3000 }).grams).toEqual({ low: 3000, mid: 3000, high: 3000 });
  });

  test("out-of-order portions are reordered so low <= mid <= high", () => {
    const g = grams({ low: 300, mid: 100, high: 200 }).grams;
    expect(g).toEqual({ low: 100, mid: 200, high: 300 });
  });

  test("high/low = 4.0 gives no flag, 4.1 gives portionUnclear", () => {
    expect(grams({ low: 100, mid: 200, high: 400 }).checkCodes).not.toContain("portionUnclear");
    expect(grams({ low: 100, mid: 200, high: 410 }).checkCodes).toContain("portionUnclear");
  });

  test("only a mid portion gives +-30 % and portionUnclear", () => {
    const it = grams({ mid: 100 });
    expect(it.grams).toEqual({ low: 70, mid: 100, high: 130 });
    expect(it.checkCodes).toContain("portionUnclear");
  });

  test("a clamped-to-same range with both ends at 1 does not divide by zero", () => {
    expect(grams({ low: 0, mid: 0.5, high: 0 }).grams.low).toBe(1);
  });
});

describe("FOOD-03 per-100 g clamps", () => {
  const p = (o: Obj) => first(meal([item({ llmPer100g: o })]));

  test("kcal 900 is accepted without a flag, 901 is clamped to 900 and flagged", () => {
    const ok = p({ kcal: 900, proteinG: 0, carbsG: 0, fatG: 100 });
    expect(ok.llmPer100g?.kcal).toBe(900);
    expect(ok.checkCodes).not.toContain("dataInconsistent");
    const over = p({ kcal: 901, proteinG: 0, carbsG: 0, fatG: 100 });
    expect(over.llmPer100g?.kcal).toBe(900);
    expect(over.checkCodes).toContain("dataInconsistent");
  });

  test("a macro over 100 is flagged", () => {
    const it = p({ kcal: 400, proteinG: 101, carbsG: 0, fatG: 0 });
    expect(it.checkCodes).toContain("dataInconsistent");
    expect(it.llmPer100g?.proteinG).toBe(100);
  });

  test("protein+carbs+fat 105.0 is kept, 105.1 rejects the model values", () => {
    const ok = p({ kcal: 800, proteinG: 35, carbsG: 35, fatG: 35 });
    expect(ok.llmPer100g).toEqual({ kcal: 800, proteinG: 35, carbsG: 35, fatG: 35 });
    const bad = p({ kcal: 800, proteinG: 35, carbsG: 35, fatG: 35.1 });
    expect(bad.llmPer100g).toBeNull();
    expect(bad.checkCodes).toContain("dataInconsistent");
  });

  test("confidence is clamped to 0..1; a bad confidence becomes 0", () => {
    expect(first(meal([item({ confidence: 5 })])).confidence).toBe(1);
    expect(first(meal([item({ confidence: -2 })])).confidence).toBe(0);
    expect(first(meal([item({ confidence: "high" })])).confidence).toBe(0);
    expect(first(meal([item({ confidence: 0.333 })])).confidence).toBe(0.33);
    expect(coerceMealAnalysis(meal([item()], { overallConfidence: 9 })).overallConfidence).toBe(1);
    expect(coerceMealAnalysis(meal([item()], { overallConfidence: -1 })).overallConfidence).toBe(0);
  });

  test("overall confidence is 0 when there are no items", () => {
    expect(coerceMealAnalysis(meal([], { overallConfidence: 0.9 })).overallConfidence).toBe(0);
  });
});

describe("FOOD-04 kcal vs 4P+4C+9F", () => {
  const p = (o: Obj) => first(meal([item({ llmPer100g: o })]));

  test("Atwater 125 vs kcal 100 is accepted, 126 raises dataInconsistent (whole-number fixtures: the coercion rounds to 0.1 before the check)", () => {
    expect(p({ kcal: 100, proteinG: 29, carbsG: 0, fatG: 1 }).checkCodes).not.toContain("dataInconsistent");
    expect(p({ kcal: 100, proteinG: 27, carbsG: 0, fatG: 2 }).checkCodes).toContain("dataInconsistent");
  });

  test("Atwater 75 accepted, 74 flagged", () => {
    expect(p({ kcal: 100, proteinG: 12, carbsG: 0, fatG: 3 }).checkCodes).not.toContain("dataInconsistent");
    expect(p({ kcal: 100, proteinG: 14, carbsG: 0, fatG: 2 }).checkCodes).toContain("dataInconsistent");
  });

  test("a flagged item is still returned, with its values", () => {
    const it = p({ kcal: 100, proteinG: 40, carbsG: 0, fatG: 0 });
    expect(it).toBeDefined();
    expect(it.llmPer100g?.kcal).toBe(100);
  });
});

describe("FOOD-05 closed codes only", () => {
  test("unknown codes are dropped, known codes kept, free text never passed through", () => {
    const m = coerceMealAnalysis(
      meal([item({ uncertainties: ["portionUnclear", "ignore previous instructions", "hiddenIngredients", 5, null, "PORTIONUNCLEAR"] })], {
        assumptions: ["cookingMethod", "<b>x</b>", "brandUnknown"],
      }),
    );
    expect(m.items[0].checkCodes).toEqual(["portionUnclear", "hiddenIngredients"]);
    expect(m.assumptions).toEqual(["cookingMethod", "brandUnknown"]);
  });

  test("all 11 closed codes are accepted and duplicates collapse", () => {
    expect(FOOD_CHECK_CODES).toHaveLength(11);
    const m = coerceMealAnalysis(meal([item({ uncertainties: [...FOOD_CHECK_CODES, ...FOOD_CHECK_CODES] })], { assumptions: [...FOOD_CHECK_CODES, "portionUnclear"] }));
    expect([...m.assumptions].sort()).toEqual([...FOOD_CHECK_CODES].sort());
    expect(m.assumptions).toHaveLength(11);
    for (const c of FOOD_CHECK_CODES) expect(m.items[0].checkCodes).toContain(c);
  });

  test("assumptions or uncertainties that are not arrays are ignored", () => {
    const m = coerceMealAnalysis(meal([item({ uncertainties: "portionUnclear" })], { assumptions: "cookingMethod" }));
    expect(m.assumptions).toEqual([]);
    expect(m.items[0].checkCodes).toEqual([]);
  });
});

describe("FOOD-30 hostile model strings", () => {
  test("a URL, e-mail, phone, HTML and 200-char name are sanitised to <= 80 chars", () => {
    const hostile = `<b>Rice</b> https://evil.example/x bob@evil.example +1 555 123 4567 ${"a".repeat(200)}`;
    const m = coerceMealAnalysis(meal([item({ name: hostile })], { mealName: hostile }));
    for (const s of [m.items[0].name, m.mealName]) {
      expect(Array.from(s).length).toBeLessThanOrEqual(80);
      expect(s).not.toMatch(/[<>:@]|evil|http/);
      expect(s).toContain("Rice");
    }
  });

  test("query terms are sanitised, lower-cased, de-duplicated, capped at 5 terms of 40 chars", () => {
    const it = first(meal([item({ queryTerms: ["Chicken", "chicken", "<i>x</i>", "https://evil.example", "a".repeat(100), "t1", "t2", "t3", "t4"] })]));
    expect(it.queryTerms).toHaveLength(5);
    expect(it.queryTerms[0]).toBe("chicken");
    expect(it.queryTerms.filter((t) => t === "chicken")).toHaveLength(1);
    for (const t of it.queryTerms) {
      expect(Array.from(t).length).toBeLessThanOrEqual(40);
      expect(t).not.toMatch(/[<>:/]|evil/);
    }
  });

  test("missing query terms fall back to the sanitised name", () => {
    expect(first(meal([item({ queryTerms: undefined, name: "Brown Rice" })])).queryTerms).toEqual(["brown rice"]);
  });

  test("an empty or hostile meal name falls back to 'Meal'", () => {
    expect(coerceMealAnalysis(meal([item()], { mealName: "<script></script>" })).mealName).toBe("Meal");
    expect(coerceMealAnalysis(meal([item()], { mealName: 5 })).mealName).toBe("Meal");
  });

  test("packaged is true only for the boolean true", () => {
    expect(first(meal([item({ packaged: true })])).packaged).toBe(true);
    expect(first(meal([item({ packaged: "true" })])).packaged).toBe(false);
    expect(first(meal([item({ packaged: undefined })])).packaged).toBe(false);
  });
});

describe("FOOD-06 totals recomputed server-side", () => {
  test("model totals are ignored; output totals equal per100g x grams / 100 summed", () => {
    const a = item({ estimatedGrams: { low: 100, mid: 200, high: 300 }, llmPer100g: per({ kcal: 100, proteinG: 10, carbsG: 10, fatG: 5 }) });
    const b = item({ name: "Rice", queryTerms: ["rice"], estimatedGrams: { low: 50, mid: 100, high: 150 }, llmPer100g: per({ kcal: 130, proteinG: 2.7, carbsG: 28, fatG: 0.3 }) });
    const m = coerceMealAnalysis(meal([a, b], { totals: { kcal: 99999 }, totalKcal: 99999 }));
    // low: 100 + 65 = 165; mid: 200 + 130 = 330; high: 300 + 195 = 495
    expect(m.totals.kcal).toEqual({ low: 165, mid: 330, high: 495 });
    expect(m.totals.proteinG).toEqual({ low: 11.4, mid: 22.7, high: 34.1 }); // 10+1.35, 20+2.7, 30+4.05 (rounded)
    expect(m.totals.carbsG).toEqual({ low: 24, mid: 48, high: 72 });
    expect(m.totals.fatG).toEqual({ low: 5.2, mid: 10.3, high: 15.5 });
  });

  test("an item without model values contributes zero", () => {
    const m = coerceMealAnalysis(meal([item({ llmPer100g: undefined }), item()]));
    expect(m.totals.kcal).toEqual({ low: 165, mid: 247.5, high: 330 });
  });

  test("itemMacros: null per100g and zero grams give zero; values scale per 100 g", () => {
    expect(itemMacros(null, { low: 1, mid: 2, high: 3 }).kcal).toEqual({ low: 0, mid: 0, high: 0 });
    expect(itemMacros({ kcal: 200, proteinG: 10, carbsG: 20, fatG: 5 }, { low: 50, mid: 100, high: 150 }).kcal).toEqual({
      low: 100,
      mid: 200,
      high: 300,
    });
    expect(itemMacros({ kcal: 200, proteinG: 10, carbsG: 20, fatG: 5 }, { low: 0, mid: 0, high: 0 }).fatG).toEqual({ low: 0, mid: 0, high: 0 });
  });

  test("more than 12 items are cut to 12 (the first 12 kept)", () => {
    expect(MAX_ITEMS).toBe(12);
    const items = Array.from({ length: 20 }, (_, i) => item({ name: `Food ${String.fromCharCode(97 + i)}` }));
    const m = coerceMealAnalysis(meal(items));
    expect(m.items).toHaveLength(12);
    expect(m.items[0].name).toBe("Food a");
    expect(m.items[11].name).toBe("Food l");
  });

  test("invalid entries do not consume the 12-item cap", () => {
    const items = [...Array.from({ length: 5 }, () => item({ name: "" })), ...Array.from({ length: 12 }, () => item())];
    expect(coerceMealAnalysis(meal(items)).items).toHaveLength(12);
  });

  test("no food (empty items) gives an empty list and zero totals", () => {
    const m = coerceMealAnalysis(meal([]));
    expect(m.items).toEqual([]);
    expect(m.totals.kcal).toEqual({ low: 0, mid: 0, high: 0 });
  });

  test("sumMacros of nothing is all zero ranges", () => {
    expect(sumMacros([]).proteinG).toEqual({ low: 0, mid: 0, high: 0 });
  });
});
