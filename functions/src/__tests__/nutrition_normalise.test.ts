/**
 * T105 nutrition_normalise (FOOD-04 Atwater sanity, FOOD-10 kJ/salt/per-100 g rules).
 * Exact expected values; boundaries on both sides of every threshold.
 */
import {
  atwaterKcal,
  buildPer100g,
  isEnergyConsistent,
  isWithinBounds,
  kjToKcal,
  normaliseOffNutriments,
  normaliseUsdaNutrients,
  round1,
  toFiniteNumber,
} from "../nutrition_normalise";

describe("toFiniteNumber", () => {
  test("numbers and numeric strings, decimal comma included", () => {
    expect(toFiniteNumber(12.5)).toBe(12.5);
    expect(toFiniteNumber("12,5")).toBe(12.5);
    expect(toFiniteNumber(" 7 ")).toBe(7);
    expect(toFiniteNumber(".5")).toBe(0.5);
    expect(toFiniteNumber("-3")).toBe(-3);
  });

  test.each([NaN, Infinity, -Infinity, "", "  ", "abc", "1e5", "12 g", "1.2.3", null, undefined, {}, [], true])(
    "%p is not a finite number",
    (v) => {
      expect(toFiniteNumber(v)).toBeUndefined();
    },
  );
});

describe("energy helpers", () => {
  test("kJ to kcal uses 4.184 and one decimal (2252 kJ -> 538.2)", () => {
    expect(kjToKcal(2252)).toBe(538.2);
    expect(kjToKcal(0)).toBe(0);
    expect(kjToKcal(4.184)).toBe(1);
  });

  test("Atwater is 4P + 4C + 9F", () => {
    expect(atwaterKcal({ proteinG: 10, carbsG: 20, fatG: 5 })).toBe(165);
  });

  test("round1 rounds half up to one decimal", () => {
    expect(round1(1.25)).toBe(1.3);
    expect(round1(1.24)).toBe(1.2);
  });
});

describe("isEnergyConsistent (FOOD-04 V-ATWATER)", () => {
  // kcal 100: Atwater 125 is a gap of exactly 25 (25 %), accepted; 126 is flagged.
  test("Atwater 125 vs kcal 100 is accepted, 126 is flagged", () => {
    expect(isEnergyConsistent({ kcal: 100, proteinG: 31.25, carbsG: 0, fatG: 0 })).toBe(true); // 125
    expect(isEnergyConsistent({ kcal: 100, proteinG: 31.5, carbsG: 0, fatG: 0 })).toBe(false); // 126
  });

  test("Atwater 75 vs kcal 100 is accepted, 74 is flagged", () => {
    expect(isEnergyConsistent({ kcal: 100, proteinG: 18.75, carbsG: 0, fatG: 0 })).toBe(true); // 75
    expect(isEnergyConsistent({ kcal: 100, proteinG: 18.5, carbsG: 0, fatG: 0 })).toBe(false); // 74
  });

  test("the 10 kcal floor protects very low energy foods", () => {
    // Diet drink: kcal 1, Atwater 10 -> gap 9 <= 10 accepted; Atwater 12 -> gap 11 flagged.
    expect(isEnergyConsistent({ kcal: 1, proteinG: 2.5, carbsG: 0, fatG: 0 })).toBe(true);
    expect(isEnergyConsistent({ kcal: 1, proteinG: 3, carbsG: 0, fatG: 0 })).toBe(false);
    expect(isEnergyConsistent({ kcal: 0, proteinG: 0, carbsG: 0, fatG: 0 })).toBe(true);
  });

  test("a realistic consistent food passes", () => {
    // Chicken breast 165 kcal, 31 P, 0 C, 3.6 F -> Atwater 156.4
    expect(isEnergyConsistent({ kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6 })).toBe(true);
  });
});

describe("isWithinBounds", () => {
  const ok = { kcal: 900, proteinG: 35, carbsG: 35, fatG: 35 };
  test("900 kcal and a 105 g macro sum are accepted", () => {
    expect(isWithinBounds(ok)).toBe(true);
  });
  test("901 kcal is rejected", () => {
    expect(isWithinBounds({ ...ok, kcal: 901 })).toBe(false);
  });
  test("macro sum 105.1 is rejected", () => {
    expect(isWithinBounds({ ...ok, fatG: 35.1 })).toBe(false);
  });
  test("a single macro of 100.1 is rejected, 100 accepted", () => {
    expect(isWithinBounds({ kcal: 400, proteinG: 100, carbsG: 0, fatG: 0 })).toBe(true);
    expect(isWithinBounds({ kcal: 400, proteinG: 100.1, carbsG: 0, fatG: 0 })).toBe(false);
  });
  test("negative, NaN and Infinity are rejected", () => {
    expect(isWithinBounds({ ...ok, kcal: -1 })).toBe(false);
    expect(isWithinBounds({ ...ok, proteinG: NaN })).toBe(false);
    expect(isWithinBounds({ ...ok, carbsG: Infinity })).toBe(false);
  });
});

describe("buildPer100g", () => {
  test("nothing usable -> null (no energy and no macro)", () => {
    expect(buildPer100g({})).toBeNull();
  });

  test("no energy and fewer than three macros -> null (cannot derive honestly)", () => {
    expect(buildPer100g({ proteinG: 5, carbsG: 5 })).toBeNull();
  });

  test("energy alone with no macros is kept as partial and lists all macros missing", () => {
    const r = buildPer100g({ kcal: 100 });
    expect(r?.per100g).toEqual({ kcal: 100, proteinG: 0, carbsG: 0, fatG: 0 });
    expect(r?.missing).toEqual(["proteinG", "carbsG", "fatG"]);
    expect(r?.dataQuality).toBe("inconsistent"); // 0 Atwater vs 100 kcal
  });

  test("no energy, three macros -> Atwater energy, partial, derivedEnergy", () => {
    const r = buildPer100g({ proteinG: 10, carbsG: 20, fatG: 5 });
    expect(r).toEqual({
      per100g: { kcal: 165, proteinG: 10, carbsG: 20, fatG: 5 },
      dataQuality: "partial",
      derivedEnergy: true,
      missing: [],
    });
  });

  test("complete and consistent -> complete", () => {
    const r = buildPer100g({ kcal: 165, proteinG: 10, carbsG: 20, fatG: 5 });
    expect(r?.dataQuality).toBe("complete");
    expect(r?.derivedEnergy).toBe(false);
  });

  test("complete but kcal far from the macros -> inconsistent, still returned", () => {
    const r = buildPer100g({ kcal: 400, proteinG: 10, carbsG: 20, fatG: 5 });
    expect(r?.dataQuality).toBe("inconsistent");
    expect(r?.per100g.kcal).toBe(400);
  });

  test("a missing macro with consistent energy -> partial", () => {
    const r = buildPer100g({ kcal: 120, proteinG: 10, carbsG: 20 });
    expect(r?.missing).toEqual(["fatG"]);
    expect(r?.dataQuality).toBe("partial");
  });

  test("out-of-bounds values -> null", () => {
    expect(buildPer100g({ kcal: 901, proteinG: 1, carbsG: 1, fatG: 1 })).toBeNull();
    expect(buildPer100g({ kcal: 500, proteinG: 60, carbsG: 50, fatG: 0 })).toBeNull();
  });

  test("salt is rounded to two decimals and negative salt is dropped", () => {
    expect(buildPer100g({ kcal: 100, proteinG: 5, carbsG: 15, fatG: 2, saltG: 1.2345 })?.saltG).toBe(1.23);
    expect(buildPer100g({ kcal: 100, proteinG: 5, carbsG: 15, fatG: 2, saltG: -1 })?.saltG).toBeUndefined();
  });
});

describe("normaliseOffNutriments (FOOD-10)", () => {
  const macros = { proteins_100g: 6.3, carbohydrates_100g: 57.5, fat_100g: 30.9 };

  test("kcal absent -> kJ / 4.184 (2252 kJ -> 538.2)", () => {
    const r = normaliseOffNutriments({ ...macros, "energy_100g": 2252 });
    expect(r?.per100g.kcal).toBe(538.2);
    expect(r?.derivedEnergy).toBe(false);
  });

  test("energy-kj_100g is used when energy_100g is absent", () => {
    expect(normaliseOffNutriments({ ...macros, "energy-kj_100g": 2252 })?.per100g.kcal).toBe(538.2);
  });

  test("kcal present wins over kJ (539 not 538.2)", () => {
    const r = normaliseOffNutriments({ ...macros, "energy-kcal_100g": 539, energy_100g: 2252 });
    expect(r?.per100g.kcal).toBe(539);
  });

  test("the recorded Nutella fixture (539 kcal) is complete", () => {
    const r = normaliseOffNutriments({
      "energy-kcal_100g": 539,
      energy_100g: 2252,
      proteins_100g: 6.3,
      carbohydrates_100g: 57.5,
      fat_100g: 30.9,
      sodium_100g: 0.0428,
    });
    expect(r?.per100g).toEqual({ kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9 });
    expect(r?.dataQuality).toBe("complete");
  });

  test("sodium 0.4 g -> salt 1.0 g (x2.5); explicit salt wins", () => {
    expect(normaliseOffNutriments({ ...macros, "energy-kcal_100g": 539, sodium_100g: 0.4 })?.saltG).toBe(1);
    expect(normaliseOffNutriments({ ...macros, "energy-kcal_100g": 539, sodium_100g: 0.4, salt_100g: 0.7 })?.saltG).toBe(0.7);
  });

  test("numeric strings with decimal comma are accepted", () => {
    const r = normaliseOffNutriments({ "energy-kcal_100g": "539", proteins_100g: "6,3", carbohydrates_100g: "57,5", fat_100g: "30,9" });
    expect(r?.per100g).toEqual({ kcal: 539, proteinG: 6.3, carbsG: 57.5, fatG: 30.9 });
  });

  test("per-serving values are never mistaken for per-100 g", () => {
    const r = normaliseOffNutriments({
      "energy-kcal_serving": 150,
      proteins_serving: 2,
      carbohydrates_serving: 20,
      fat_serving: 8,
      "energy-kcal": 150,
      proteins: 2,
    });
    expect(r).toBeNull();
  });

  test("a per-serving value next to missing per-100 g does not leak in", () => {
    const r = normaliseOffNutriments({ "energy-kcal_100g": 100, proteins_100g: 5, carbohydrates_serving: 99, fat_100g: 2 });
    expect(r?.per100g.carbsG).toBe(0);
    expect(r?.missing).toEqual(["carbsG"]);
  });

  test("missing energy and macros -> unusable (null)", () => {
    expect(normaliseOffNutriments({})).toBeNull();
    expect(normaliseOffNutriments({ salt_100g: 1 })).toBeNull();
  });

  test.each([null, undefined, "x", 5, []])("non-object %p -> null", (v) => {
    expect(normaliseOffNutriments(v)).toBeNull();
  });

  test("an implausible record (kcal 2000 per 100 g) is refused", () => {
    expect(normaliseOffNutriments({ "energy-kcal_100g": 2000, proteins_100g: 1, carbohydrates_100g: 1, fat_100g: 1 })).toBeNull();
  });
});

describe("normaliseUsdaNutrients", () => {
  const rows = (o: Record<number, number>, unit = "KCAL"): unknown[] =>
    Object.entries(o).map(([id, value]) => ({ nutrientId: Number(id), value, unitName: Number(id) === 1008 ? unit : "G" }));

  test("maps 1008/1003/1004/1005", () => {
    const r = normaliseUsdaNutrients(rows({ 1008: 165, 1003: 31, 1004: 3.6, 1005: 0 }));
    expect(r?.per100g).toEqual({ kcal: 165, proteinG: 31, carbsG: 0, fatG: 3.6 });
    expect(r?.derivedEnergy).toBe(false);
  });

  test("energy absent -> derived by Atwater and flagged derivedEnergy", () => {
    const r = normaliseUsdaNutrients(rows({ 1003: 10, 1004: 5, 1005: 20 }));
    expect(r?.per100g.kcal).toBe(165);
    expect(r?.derivedEnergy).toBe(true);
    expect(r?.dataQuality).toBe("partial");
  });

  test("a 1008 row reported in kJ is NOT read as kcal", () => {
    const r = normaliseUsdaNutrients(rows({ 1008: 2252, 1003: 10, 1004: 5, 1005: 20 }, "kJ"));
    expect(r?.per100g.kcal).toBe(165); // derived, not 2252
    expect(r?.derivedEnergy).toBe(true);
  });

  test("first occurrence of a nutrient id wins", () => {
    const r = normaliseUsdaNutrients([
      { nutrientId: 1008, value: 100, unitName: "KCAL" },
      { nutrientId: 1008, value: 999, unitName: "KCAL" },
      { nutrientId: 1003, value: 5 },
      { nutrientId: 1004, value: 2 },
      { nutrientId: 1005, value: 15 },
    ]);
    expect(r?.per100g.kcal).toBe(100);
  });

  test("junk rows are skipped and a non-array is null", () => {
    const r = normaliseUsdaNutrients([null, "x", { nutrientId: "abc", value: 1 }, { nutrientId: 1008, value: "n/a" }, ...rows({ 1008: 100, 1003: 5, 1004: 2, 1005: 15 })]);
    expect(r?.per100g.kcal).toBe(100);
    expect(normaliseUsdaNutrients(undefined)).toBeNull();
    expect(normaliseUsdaNutrients({})).toBeNull();
    expect(normaliseUsdaNutrients([])).toBeNull();
  });
});
