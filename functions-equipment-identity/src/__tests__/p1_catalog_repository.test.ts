import {
  validateEquipmentModelWrite,
  validateP1PilotStatusRestrictions,
  validateCatalogUniqueness,
  writeEquipmentModel,
  CatalogValidationError,
  type EquipmentModelStore,
} from "../p1/catalog_repository";
import { loadGeneratedSnapshot } from "../p1/type_snapshot";
import type { EquipmentBrand, EquipmentModel, ProductLine } from "../p1/contracts";

const SNAPSHOT = loadGeneratedSnapshot();
const REAL_TYPE_A = SNAPSHOT.types[0].id;
const REAL_TYPE_B = SNAPSHOT.types[1].id;

function makeProvenance(): EquipmentBrand["provenance"][number] {
  return {
    sourceId: "technogym_interior_design",
    sourceUrl: "https://www.technogym.com/product/selection-leg-press",
    retrievedAt: "2026-08-22T00:00:00Z",
    fixtureSha256: "a".repeat(64),
    adapterId: "technogym-adapter",
    adapterVersion: "1.0.0",
    fields: ["canonicalName", "modelCode"],
  };
}

function makeModel(overrides: Record<string, unknown> = {}): unknown {
  return {
    schemaVersion: 1,
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    brandId: "technogym",
    productLineId: "technogym-selection",
    canonicalName: "Selection Leg Press",
    modelCode: "SEL-LEGPRESS-500",
    skuAliases: [],
    primaryTypeId: REAL_TYPE_A,
    supportedTypeIds: [REAL_TYPE_A],
    generation: undefined,
    aliases: [],
    catalogStatus: "ACTIVE",
    textSupportStatus: "EXPERIMENTAL",
    visionSupportStatus: "NONE",
    sourceConfidence: "OFFICIAL",
    catalogVersion: "catalog-v1-test",
    provenance: [makeProvenance()],
    ...overrides,
  };
}

describe("validateEquipmentModelWrite", () => {
  test("accepts a structurally valid model with a real type reference", () => {
    expect(() => validateEquipmentModelWrite(makeModel())).not.toThrow();
  });

  test("rejects a schema-invalid candidate (CatalogValidationError, not a raw ZodError)", () => {
    expect(() => validateEquipmentModelWrite(makeModel({ modelId: "not-a-uuid" }))).toThrow(
      CatalogValidationError,
    );
  });

  test("rejects a primaryTypeId that does not exist in the P0 snapshot", () => {
    expect(() =>
      validateEquipmentModelWrite(
        makeModel({ primaryTypeId: "does_not_exist_in_snapshot", supportedTypeIds: ["does_not_exist_in_snapshot"] }),
      ),
    ).toThrow(CatalogValidationError);
  });

  test("accepts a multi-function model referencing two real types", () => {
    const model = makeModel({ primaryTypeId: REAL_TYPE_A, supportedTypeIds: [REAL_TYPE_A, REAL_TYPE_B] });
    expect(() => validateEquipmentModelWrite(model)).not.toThrow();
  });
});

describe("validateP1PilotStatusRestrictions", () => {
  test("accepts EXPERIMENTAL/NONE", () => {
    const model = validateEquipmentModelWrite(makeModel());
    expect(() => validateP1PilotStatusRestrictions(model)).not.toThrow();
  });

  test("rejects textSupportStatus=VERIFIED for a P1-created record", () => {
    const model = validateEquipmentModelWrite(makeModel({ textSupportStatus: "VERIFIED" }));
    expect(() => validateP1PilotStatusRestrictions(model)).toThrow(CatalogValidationError);
  });

  test("rejects visionSupportStatus other than NONE for a P1-created record", () => {
    const model = validateEquipmentModelWrite(makeModel({ visionSupportStatus: "EXPERIMENTAL" }));
    expect(() => validateP1PilotStatusRestrictions(model)).toThrow(CatalogValidationError);
  });
});

// P1.G1 T5's mutation proof: an invalid type reference must stop the write
// path before store.write is ever called -- store.write is spied on, not
// just checked for absence of a thrown error.
describe("writeEquipmentModel — fake-store mutation proof", () => {
  function makeFakeStore(): EquipmentModelStore & { writes: EquipmentModel[] } {
    const writes: EquipmentModel[] = [];
    return {
      writes,
      async write(model: EquipmentModel) {
        writes.push(model);
      },
    };
  }

  test("a valid model reaches store.write exactly once", async () => {
    const store = makeFakeStore();
    await writeEquipmentModel(makeModel(), store);
    expect(store.writes).toHaveLength(1);
    expect(store.writes[0].modelId).toBe("11111111-1111-4111-8111-111111111111");
  });

  test("an invalid primaryTypeId throws and store.write is NEVER called", async () => {
    const store = makeFakeStore();
    await expect(
      writeEquipmentModel(
        makeModel({ primaryTypeId: "does_not_exist_in_snapshot", supportedTypeIds: ["does_not_exist_in_snapshot"] }),
        store,
      ),
    ).rejects.toThrow(CatalogValidationError);
    expect(store.writes).toHaveLength(0);
  });

  test("a schema-invalid candidate throws and store.write is NEVER called", async () => {
    const store = makeFakeStore();
    await expect(writeEquipmentModel(makeModel({ modelId: "not-a-uuid" }), store)).rejects.toThrow(
      CatalogValidationError,
    );
    expect(store.writes).toHaveLength(0);
  });

  test("enforceP1PilotRestrictions=true rejects VERIFIED and store.write is NEVER called", async () => {
    const store = makeFakeStore();
    await expect(
      writeEquipmentModel(makeModel({ textSupportStatus: "VERIFIED" }), store, {
        enforceP1PilotRestrictions: true,
      }),
    ).rejects.toThrow(CatalogValidationError);
    expect(store.writes).toHaveLength(0);
  });
});

describe("validateCatalogUniqueness", () => {
  const brand: EquipmentBrand = {
    schemaVersion: 1,
    brandId: "technogym",
    displayName: "Technogym",
    catalogVersion: "catalog-v1-test",
    provenance: [makeProvenance()],
  };
  const line: ProductLine = {
    schemaVersion: 1,
    productLineId: "technogym-selection",
    brandId: "technogym",
    displayName: "Selection",
    catalogVersion: "catalog-v1-test",
    provenance: [makeProvenance()],
  };

  test("a clean catalog has zero violations", () => {
    const model = validateEquipmentModelWrite(makeModel());
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [model] });
    expect(result).toEqual({ valid: true, violations: [] });
  });

  test("detects a duplicate modelId", () => {
    const m1 = validateEquipmentModelWrite(makeModel());
    const m2 = validateEquipmentModelWrite(makeModel({ canonicalSlug: "technogym-selection-leg-press-2" }));
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [m1, m2] });
    expect(result.valid).toBe(false);
    expect(result.violations.some((v) => v.type === "DUPLICATE_MODEL_ID")).toBe(true);
  });

  test("detects a duplicate canonicalSlug within the same catalogVersion", () => {
    const m1 = validateEquipmentModelWrite(makeModel());
    const m2 = validateEquipmentModelWrite(
      makeModel({ modelId: "22222222-2222-4222-8222-222222222222", modelCode: "SEL-LEGPRESS-501" }),
    );
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [m1, m2] });
    expect(result.violations.some((v) => v.type === "DUPLICATE_CANONICAL_SLUG")).toBe(true);
  });

  test("detects a model referencing an absent brand", () => {
    const model = validateEquipmentModelWrite(makeModel({ brandId: "matrix" }));
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [model] });
    expect(
      result.violations.some((v) => v.type === "MODEL_REFERS_TO_ABSENT_BRAND"),
    ).toBe(true);
  });

  test("detects a model referencing an absent product line", () => {
    const model = validateEquipmentModelWrite(makeModel({ productLineId: "technogym-nonexistent-line" }));
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [model] });
    expect(
      result.violations.some((v) => v.type === "MODEL_REFERS_TO_ABSENT_PRODUCT_LINE"),
    ).toBe(true);
  });

  test("detects a duplicate modelCode within the same brand+line", () => {
    const m1 = validateEquipmentModelWrite(makeModel());
    const m2 = validateEquipmentModelWrite(
      makeModel({
        modelId: "22222222-2222-4222-8222-222222222222",
        canonicalSlug: "technogym-selection-leg-press-alt",
      }),
    );
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [m1, m2] });
    expect(
      result.violations.some((v) => v.type === "DUPLICATE_MODEL_CODE_SAME_BRAND_LINE"),
    ).toBe(true);
  });

  test("does not silently rename or drop a collision -- every violation is reported", () => {
    const m1 = validateEquipmentModelWrite(makeModel());
    const m2 = validateEquipmentModelWrite(makeModel()); // fully identical -> multiple violation types
    const result = validateCatalogUniqueness({ brands: [brand], productLines: [line], models: [m1, m2] });
    const types = new Set(result.violations.map((v) => v.type));
    expect(types.has("DUPLICATE_MODEL_ID")).toBe(true);
    expect(types.has("DUPLICATE_CANONICAL_SLUG")).toBe(true);
    expect(types.has("DUPLICATE_MODEL_CODE_SAME_BRAND_LINE")).toBe(true);
  });

  test("detects a duplicate brandId within the same catalogVersion", () => {
    const brand2 = { ...brand };
    const result = validateCatalogUniqueness({
      brands: [brand, brand2],
      productLines: [line],
      models: [],
    });
    expect(result.violations.some((v) => v.type === "DUPLICATE_BRAND_ID")).toBe(true);
  });

  test("detects a duplicate productLineId within the same catalogVersion", () => {
    const line2 = { ...line };
    const result = validateCatalogUniqueness({
      brands: [brand],
      productLines: [line, line2],
      models: [],
    });
    expect(result.violations.some((v) => v.type === "DUPLICATE_PRODUCT_LINE_ID")).toBe(true);
  });

  // Regression test for a reviewer-found MAJOR (P1.G1 database review,
  // 2026-08-22): DUPLICATE_MODEL_CODE_SAME_BRAND_LINE used to build its
  // grouping key by joining `${catalogVersion} ${brandId} ${productLineId}
  // ${modelCode}` with spaces. catalogVersion and modelCode are free text
  // and can themselves contain spaces, so two structurally DIFFERENT
  // 4-tuples could join to the identical string and be misreported as one
  // false "duplicate." This constructs exactly that word-boundary shift:
  //   tuple A: (cv="cat one two",   brand="three", pl="four", mc="five six")
  //   tuple B: (cv="cat one",       brand="two",   pl="three", mc="four five six")
  // both join (space-delimited) to "cat one two three four five six", but
  // brand/pl differ between A and B -- they must NOT be reported as a
  // duplicate modelCode within the same brand+line, because they are not
  // actually the same brand+line.
  test("does not false-positive DUPLICATE_MODEL_CODE_SAME_BRAND_LINE when catalogVersion/modelCode contain spaces that could realign the old joined key", () => {
    const modelA = validateEquipmentModelWrite(
      makeModel({
        modelId: "33333333-3333-4333-8333-333333333333",
        canonicalSlug: "regression-a",
        catalogVersion: "cat one two",
        brandId: "three",
        productLineId: "four",
        modelCode: "five six",
      }),
    );
    const modelB = validateEquipmentModelWrite(
      makeModel({
        modelId: "44444444-4444-4444-8444-444444444444",
        canonicalSlug: "regression-b",
        catalogVersion: "cat one",
        brandId: "two",
        productLineId: "three",
        modelCode: "four five six",
      }),
    );
    const result = validateCatalogUniqueness({
      brands: [],
      productLines: [],
      models: [modelA, modelB],
    });
    expect(
      result.violations.some((v) => v.type === "DUPLICATE_MODEL_CODE_SAME_BRAND_LINE"),
    ).toBe(false);
  });

  test("DUPLICATE_MODEL_CODE_SAME_BRAND_LINE still fires for an actual same-key duplicate with a space-containing catalogVersion", () => {
    const modelA = validateEquipmentModelWrite(
      makeModel({
        modelId: "55555555-5555-4555-8555-555555555555",
        canonicalSlug: "real-dup-a",
        catalogVersion: "cat one two",
        brandId: "three",
        productLineId: "four",
        modelCode: "five six",
      }),
    );
    const modelB = validateEquipmentModelWrite(
      makeModel({
        modelId: "66666666-6666-4666-8666-666666666666",
        canonicalSlug: "real-dup-b",
        catalogVersion: "cat one two",
        brandId: "three",
        productLineId: "four",
        modelCode: "five six",
      }),
    );
    const result = validateCatalogUniqueness({
      brands: [],
      productLines: [],
      models: [modelA, modelB],
    });
    expect(
      result.violations.some((v) => v.type === "DUPLICATE_MODEL_CODE_SAME_BRAND_LINE"),
    ).toBe(true);
  });
});

// P1.G1 §6.7: prove the schema/repository handles a catalog at pilot scale
// (50 records) and multi-function models. These are TEST FIXTURES ONLY --
// never to be mixed into the actual pilot catalog (P1.G5 owns that).
describe("50-model capacity", () => {
  function syntheticCatalog(count: number): {
    brands: EquipmentBrand[];
    productLines: ProductLine[];
    models: EquipmentModel[];
  } {
    const brand: EquipmentBrand = {
      schemaVersion: 1,
      brandId: "synthetic-brand",
      displayName: "Synthetic Brand (test fixture only)",
      catalogVersion: "catalog-v1-capacity-test",
      provenance: [makeProvenance()],
    };
    const models: EquipmentModel[] = [];
    for (let i = 0; i < count; i++) {
      const modelId = `00000000-0000-4000-8000-${i.toString(16).padStart(12, "0")}`;
      const multiFunction = i % 5 === 0;
      models.push(
        validateEquipmentModelWrite(
          makeModel({
            modelId,
            canonicalSlug: `synthetic-brand-fixture-model-${i}`,
            modelCode: `FIXTURE-${i}`,
            brandId: "synthetic-brand",
            productLineId: undefined,
            primaryTypeId: REAL_TYPE_A,
            supportedTypeIds: multiFunction ? [REAL_TYPE_A, REAL_TYPE_B] : [REAL_TYPE_A],
            catalogVersion: "catalog-v1-capacity-test",
          }),
        ),
      );
    }
    return { brands: [brand], productLines: [], models };
  }

  test("50 synthetic models all pass schema + type validation with zero uniqueness violations", () => {
    const catalog = syntheticCatalog(50);
    expect(catalog.models).toHaveLength(50);
    const result = validateCatalogUniqueness(catalog);
    expect(result).toEqual({ valid: true, violations: [] });
  });

  test("multi-function synthetic models are present and pass validateP1PilotStatusRestrictions", () => {
    const catalog = syntheticCatalog(50);
    const multiFunction = catalog.models.filter((m) => m.supportedTypeIds.length > 1);
    expect(multiFunction.length).toBeGreaterThan(0);
    for (const model of catalog.models) {
      expect(() => validateP1PilotStatusRestrictions(model)).not.toThrow();
    }
  });
});
