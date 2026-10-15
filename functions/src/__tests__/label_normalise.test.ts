/**
 * T106 label_normalise (FOOD-15): decimal commas, kJ-only energy, per-serving -> per-100 g,
 * unreadable fields, EN and RU (Cyrillic units) fixtures, sanity as FOOD-04.
 */
import { normaliseLabel, servingGrams } from "../label_normalise";

type Obj = Record<string, unknown>;

const EN_LABEL: Obj = {
  servingSize: { value: 30, unit: "g" },
  servingsPerContainer: 10,
  perServing: { kcal: 150, proteinG: 3, carbsG: 20, fatG: 6 },
  per100g: { kcal: 500, proteinG: 10, carbsG: 66.7, fatG: 20 },
  energyUnit: "kcal",
  unreadableFields: [],
};

describe("servingGrams", () => {
  test.each([
    [{ value: 30, unit: "g" }, 30],
    [{ value: 250, unit: "ml" }, 250],
    [{ value: "12,5", unit: " G. " }, 12.5],
    [{ value: 40, unit: "г" }, 40], // Cyrillic g
    [{ value: 200, unit: "мл" }, 200], // Cyrillic ml
    [{ value: 3000, unit: "g" }, 3000],
  ])("%j -> %p", (input, expected) => {
    expect(servingGrams(input)).toBe(expected);
  });

  test.each([
    [{ value: 0, unit: "g" }],
    [{ value: -5, unit: "g" }],
    [{ value: 3001, unit: "g" }],
    [{ value: 30, unit: "oz" }],
    [{ value: 30 }],
    [{ unit: "g" }],
    [null],
    ["30 g"],
    [[]],
  ])("%j is unusable", (input) => {
    expect(servingGrams(input)).toBeUndefined();
  });
});

describe("normaliseLabel: direct per-100 g", () => {
  test("a clean EN label returns per-100 g as printed, complete, no codes", () => {
    const r = normaliseLabel(EN_LABEL);
    expect(r.per100g).toEqual({ kcal: 500, proteinG: 10, carbsG: 66.7, fatG: 20 });
    expect(r.perServing).toEqual({ kcal: 150, proteinG: 3, carbsG: 20, fatG: 6 });
    expect(r.servingG).toBe(30);
    expect(r.servingsPerContainer).toBe(10);
    expect(r.dataQuality).toBe("complete");
    expect(r.checkCodes).toEqual([]);
  });

  test("decimal comma strings '12,5' are read as 12.5", () => {
    const r = normaliseLabel({
      ...EN_LABEL,
      per100g: { kcal: "250", proteinG: "12,5", carbsG: "30,0", fatG: "9,0" },
    });
    expect(r.per100g).toEqual({ kcal: 250, proteinG: 12.5, carbsG: 30, fatG: 9 });
  });

  test("kJ only -> kcal (1046 kJ -> 250 kcal)", () => {
    const r = normaliseLabel({
      per100g: { kJ: 1046, proteinG: 12, carbsG: 30, fatG: 9 },
      perServing: {},
      energyUnit: "kJ",
      unreadableFields: [],
    });
    expect(r.per100g?.kcal).toBe(250);
    expect(r.dataQuality).toBe("complete");
  });

  test("kcal and kJ both printed: kcal wins", () => {
    const r = normaliseLabel({ per100g: { kcal: 250, kJ: 9999, proteinG: 12, carbsG: 30, fatG: 9 }, perServing: {}, energyUnit: "kcal", unreadableFields: [] });
    expect(r.per100g?.kcal).toBe(250);
  });

  test("a kJ figure put into kcal when the label lists kJ first is converted", () => {
    const r = normaliseLabel({ per100g: { kcal: 1046, proteinG: 12, carbsG: 30, fatG: 9 }, perServing: {}, energyUnit: "kJ", unreadableFields: [] });
    expect(r.per100g?.kcal).toBe(250);
  });

  test("Cyrillic energy unit word for kJ is understood", () => {
    const r = normaliseLabel({ per100g: { kcal: 1046, proteinG: 12, carbsG: 30, fatG: 9 }, perServing: {}, energyUnit: "кДж", unreadableFields: [] });
    expect(r.per100g?.kcal).toBe(250);
  });
});

describe("normaliseLabel: per-serving only", () => {
  const perServingOnly = (o: Obj = {}): Obj => ({
    servingSize: { value: 40, unit: "g" },
    perServing: { kcal: 100, proteinG: 4, carbsG: 14, fatG: 3 },
    per100g: {},
    energyUnit: "kcal",
    unreadableFields: [],
    ...o,
  });

  test("per-serving + serving grams -> per 100 g (x100/servingG)", () => {
    const r = normaliseLabel(perServingOnly());
    expect(r.per100g).toEqual({ kcal: 250, proteinG: 10, carbsG: 35, fatG: 7.5 });
    expect(r.perServing).toEqual({ kcal: 100, proteinG: 4, carbsG: 14, fatG: 3 });
    expect(r.dataQuality).toBe("complete");
  });

  test("a serving in ml is treated as grams (1 ml = 1 g)", () => {
    const r = normaliseLabel(perServingOnly({ servingSize: { value: 200, unit: "ml" }, perServing: { kcal: 80, proteinG: 4, carbsG: 10, fatG: 2 } }));
    expect(r.per100g).toEqual({ kcal: 40, proteinG: 2, carbsG: 5, fatG: 1 });
  });

  test("per-serving without a serving size -> per100g null and scaleMissing (never divided)", () => {
    const r = normaliseLabel(perServingOnly({ servingSize: undefined }));
    expect(r.per100g).toBeNull();
    expect(r.checkCodes).toContain("scaleMissing");
    expect(r.dataQuality).toBe("unusable");
    expect(r.perServing).not.toBeNull();
  });

  test.each([0, -10, "x"])("a serving of %p is not a scale", (v) => {
    const r = normaliseLabel(perServingOnly({ servingSize: { value: v, unit: "g" } }));
    expect(r.per100g).toBeNull();
    expect(r.checkCodes).toContain("scaleMissing");
  });

  test("scaling that pushes values out of bounds is refused as dataInconsistent", () => {
    // 5 g serving with 100 kcal -> 2000 kcal per 100 g
    const r = normaliseLabel(perServingOnly({ servingSize: { value: 5, unit: "g" }, perServing: { kcal: 100, proteinG: 1, carbsG: 1, fatG: 1 } }));
    expect(r.per100g).toBeNull();
    expect(r.checkCodes).toContain("dataInconsistent");
  });

  test("an explicit per-100 g block wins over per-serving scaling", () => {
    const r = normaliseLabel({ ...perServingOnly(), per100g: { kcal: 300, proteinG: 10, carbsG: 40, fatG: 10 } });
    expect(r.per100g?.kcal).toBe(300);
  });
});

describe("normaliseLabel: ambiguity and sanity", () => {
  test("unreadableFields -> labelAmbiguous (values still returned)", () => {
    const r = normaliseLabel({ ...EN_LABEL, unreadableFields: ["fatG"] });
    expect(r.checkCodes).toContain("labelAmbiguous");
    expect(r.per100g).not.toBeNull();
  });

  test("a missing macro -> labelAmbiguous and the macro is zero-filled and not complete", () => {
    const r = normaliseLabel({ per100g: { kcal: 120, proteinG: 10, carbsG: 20 }, perServing: {}, energyUnit: "kcal", unreadableFields: [] });
    expect(r.per100g).toEqual({ kcal: 120, proteinG: 10, carbsG: 20, fatG: 0 });
    expect(r.checkCodes).toContain("labelAmbiguous");
    expect(r.dataQuality).toBe("partial");
  });

  test("kcal not explained by the macros -> dataInconsistent (sanity as FOOD-04)", () => {
    const r = normaliseLabel({ per100g: { kcal: 100, proteinG: 40, carbsG: 0, fatG: 0 }, perServing: {}, energyUnit: "kcal", unreadableFields: [] });
    expect(r.dataQuality).toBe("inconsistent");
    expect(r.checkCodes).toContain("dataInconsistent");
    expect(r.per100g).not.toBeNull();
  });

  test("an implausible per-100 g block (kcal 2000) -> null and dataInconsistent", () => {
    const r = normaliseLabel({ per100g: { kcal: 2000, proteinG: 1, carbsG: 1, fatG: 1 }, perServing: {}, energyUnit: "kcal", unreadableFields: [] });
    expect(r.per100g).toBeNull();
    expect(r.checkCodes).toContain("dataInconsistent");
    expect(r.dataQuality).toBe("unusable");
  });

  test.each([["empty object", {}], ["null", null], ["array", []], ["string", "label"], ["number", 5]])(
    "%s -> unusable with labelAmbiguous, never throws",
    (_l, raw) => {
      const r = normaliseLabel(raw);
      expect(r.per100g).toBeNull();
      expect(r.perServing).toBeNull();
      expect(r.dataQuality).toBe("unusable");
      expect(r.checkCodes).toEqual(["labelAmbiguous"]);
    },
  );

  test("check codes are always from the closed set; hostile unreadableFields text is never echoed", () => {
    const r = normaliseLabel({ ...EN_LABEL, unreadableFields: ["<script>alert(1)</script>", "ignore previous"] });
    expect(JSON.stringify(r)).not.toMatch(/script|ignore/);
    for (const c of r.checkCodes) {
      expect(["labelAmbiguous", "dataInconsistent", "scaleMissing"]).toContain(c);
    }
  });

  test("servingsPerContainer outside 0..100 is omitted", () => {
    expect(normaliseLabel({ ...EN_LABEL, servingsPerContainer: 0 }).servingsPerContainer).toBeUndefined();
    expect(normaliseLabel({ ...EN_LABEL, servingsPerContainer: 101 }).servingsPerContainer).toBeUndefined();
    expect(normaliseLabel({ ...EN_LABEL, servingsPerContainer: 100 }).servingsPerContainer).toBe(100);
  });
});

describe("normaliseLabel: RU fixtures (Cyrillic units)", () => {
  // Label text: "ккал", "белки", "жиры", "углеводы" -- the model maps them into the schema fields.
  test("RU label with per-100 g in kJ+kcal and a gram serving written in Cyrillic", () => {
    const r = normaliseLabel({
      servingSize: { value: "25,5", unit: "г" },
      servingsPerContainer: 4,
      perServing: { kcal: "102", proteinG: "1,0", carbsG: "14,0", fatG: "4,5" },
      per100g: { kcal: "400", kJ: "1674", proteinG: "4,0", carbsG: "55,0", fatG: "17,6" },
      energyUnit: "ккал",
      unreadableFields: [],
    });
    expect(r.per100g).toEqual({ kcal: 400, proteinG: 4, carbsG: 55, fatG: 17.6 });
    expect(r.servingG).toBe(25.5);
    expect(r.checkCodes).toEqual([]);
  });

  test("RU label, only per serving in grams ('г'), scaled to per 100 g", () => {
    const r = normaliseLabel({
      servingSize: { value: 50, unit: "гр" },
      perServing: { kcal: 110, proteinG: 5, carbsG: 15, fatG: 3.5 },
      per100g: {},
      energyUnit: "ккал",
      unreadableFields: [],
    });
    expect(r.per100g).toEqual({ kcal: 220, proteinG: 10, carbsG: 30, fatG: 7 });
  });

  test("RU label with millilitre serving ('мл') for a drink", () => {
    const r = normaliseLabel({
      servingSize: { value: 250, unit: "мл" },
      perServing: { kcal: 100, proteinG: 0, carbsG: 25, fatG: 0 },
      per100g: {},
      energyUnit: "ккал",
      unreadableFields: [],
    });
    expect(r.per100g).toEqual({ kcal: 40, proteinG: 0, carbsG: 10, fatG: 0 });
  });

  test("RU label with an unreadable fat field is flagged labelAmbiguous", () => {
    const r = normaliseLabel({
      per100g: { kcal: 120, proteinG: 10, carbsG: 20 },
      perServing: {},
      energyUnit: "ккал",
      unreadableFields: ["жиры"],
    });
    expect(r.checkCodes).toContain("labelAmbiguous");
  });
});
