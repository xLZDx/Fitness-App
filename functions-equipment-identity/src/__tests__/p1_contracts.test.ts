import { z } from "zod";
import {
  EquipmentModelSchema,
  EquipmentBrandSchema,
  ProductLineSchema,
  StagedEquipmentModelCandidateSchema,
  ProvenanceRefSchema,
  RecognitionAuthorityTupleSchema,
  SlugSchema,
  CatalogVersionSchema,
  EntityIdSchema,
} from "../p1/contracts";

const VALID_PROVENANCE = {
  sourceId: "technogym_interior_design",
  sourceUrl: "https://www.technogym.com/product/selection-leg-press",
  retrievedAt: "2026-08-22T00:00:00Z",
  fixtureSha256: "a".repeat(64),
  adapterId: "technogym-adapter",
  adapterVersion: "1.0.0",
  fields: ["canonicalName", "modelCode"],
} as const;

function validModel(overrides: Record<string, unknown> = {}): unknown {
  return {
    schemaVersion: 1,
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    brandId: "technogym",
    productLineId: "technogym-selection",
    canonicalName: "Selection Leg Press",
    modelCode: "SEL-LEGPRESS-500",
    skuAliases: [],
    primaryTypeId: "leg_press_machine",
    supportedTypeIds: ["leg_press_machine"],
    generation: undefined,
    aliases: [],
    catalogStatus: "ACTIVE",
    textSupportStatus: "EXPERIMENTAL",
    visionSupportStatus: "NONE",
    sourceConfidence: "OFFICIAL",
    catalogVersion: "catalog-v1-test",
    provenance: [VALID_PROVENANCE],
    ...overrides,
  };
}

describe("ProvenanceRefSchema", () => {
  test("accepts a valid provenance ref without sourceContentSha256", () => {
    expect(() => ProvenanceRefSchema.parse(VALID_PROVENANCE)).not.toThrow();
  });

  test("rejects a fixtureSha256 that is not 64 lowercase hex chars", () => {
    expect(() =>
      ProvenanceRefSchema.parse({ ...VALID_PROVENANCE, fixtureSha256: "not-a-hash" }),
    ).toThrow(z.ZodError);
  });

  test("rejects an empty fields array (must be non-empty)", () => {
    expect(() => ProvenanceRefSchema.parse({ ...VALID_PROVENANCE, fields: [] })).toThrow(
      z.ZodError,
    );
  });
});

describe("EquipmentModelSchema", () => {
  test("accepts a valid single-function model", () => {
    expect(() => EquipmentModelSchema.parse(validModel())).not.toThrow();
  });

  test("accepts a valid multi-function model", () => {
    const model = validModel({
      primaryTypeId: "leg_press_machine",
      supportedTypeIds: ["leg_press_machine", "hack_squat_machine"],
    });
    expect(() => EquipmentModelSchema.parse(model)).not.toThrow();
  });

  test("rejects primaryTypeId absent from supportedTypeIds", () => {
    const model = validModel({
      primaryTypeId: "leg_press_machine",
      supportedTypeIds: ["hack_squat_machine"],
    });
    expect(() => EquipmentModelSchema.parse(model)).toThrow(/primaryTypeId/);
  });

  test("rejects duplicate ids inside supportedTypeIds", () => {
    const model = validModel({
      supportedTypeIds: ["leg_press_machine", "leg_press_machine"],
    });
    expect(() => EquipmentModelSchema.parse(model)).toThrow(/duplicate/);
  });

  test("rejects a non-UUID modelId", () => {
    expect(() => EquipmentModelSchema.parse(validModel({ modelId: "not-a-uuid" }))).toThrow(
      z.ZodError,
    );
  });

  test("rejects an unknown extra field (strict schema)", () => {
    const model = validModel() as Record<string, unknown>;
    model.unexpectedField = "should not be here";
    expect(() => EquipmentModelSchema.parse(model)).toThrow(z.ZodError);
  });

  test("rejects empty provenance", () => {
    expect(() => EquipmentModelSchema.parse(validModel({ provenance: [] }))).toThrow(
      z.ZodError,
    );
  });

  test("rejects empty supportedTypeIds", () => {
    expect(() => EquipmentModelSchema.parse(validModel({ supportedTypeIds: [] }))).toThrow(
      z.ZodError,
    );
  });
});

describe("StagedEquipmentModelCandidateSchema", () => {
  test("accepts a valid candidate with only typeHints (no primaryTypeId field at all)", () => {
    const candidate = {
      schemaVersion: 1,
      candidateId: "cand-1",
      brandId: "technogym",
      canonicalNameCandidate: "Selection Leg Press",
      modelCode: "SEL-LEGPRESS-500",
      skuAliases: [],
      aliases: [],
      catalogStatusCandidate: "UNKNOWN",
      sourceConfidence: "OFFICIAL",
      provenance: [VALID_PROVENANCE],
      typeHints: ["leg_press_machine"],
      sourceStableKey: "SEL-LEGPRESS-500",
    };
    expect(() => StagedEquipmentModelCandidateSchema.parse(candidate)).not.toThrow();
  });

  test("rejects a candidate that smuggles in a primaryTypeId (strict schema)", () => {
    const candidate = {
      schemaVersion: 1,
      candidateId: "cand-1",
      brandId: "technogym",
      canonicalNameCandidate: "Selection Leg Press",
      skuAliases: [],
      aliases: [],
      catalogStatusCandidate: "UNKNOWN",
      sourceConfidence: "OFFICIAL",
      provenance: [VALID_PROVENANCE],
      typeHints: ["leg_press_machine"],
      sourceStableKey: "SEL-LEGPRESS-500",
      primaryTypeId: "leg_press_machine",
    };
    expect(() => StagedEquipmentModelCandidateSchema.parse(candidate)).toThrow(z.ZodError);
  });
});

describe("RecognitionAuthorityTupleSchema", () => {
  test("accepts the minimum required fields", () => {
    const tuple = {
      catalogVersion: "catalog-v1-test",
      ocrVersion: "ocr-1",
      textPolicyVersion: "text-1",
      fusionPolicyVersion: "fusion-1",
      identityPolicyVersion: "identity-1",
    };
    expect(() => RecognitionAuthorityTupleSchema.parse(tuple)).not.toThrow();
  });

  test("rejects an unknown extra field (strict schema)", () => {
    const tuple = {
      catalogVersion: "catalog-v1-test",
      ocrVersion: "ocr-1",
      textPolicyVersion: "text-1",
      fusionPolicyVersion: "fusion-1",
      identityPolicyVersion: "identity-1",
      unexpectedField: "nope",
    };
    expect(() => RecognitionAuthorityTupleSchema.parse(tuple)).toThrow(z.ZodError);
  });
});

// Reviewer-found gap (P1.G1 type-design review, 2026-08-22): EquipmentBrandSchema
// and ProductLineSchema were the only two contracts in this file missing
// `.strict()`, inconsistent with every other schema here.
describe("EquipmentBrandSchema / ProductLineSchema strictness", () => {
  const validBrand = {
    schemaVersion: 1,
    brandId: "technogym",
    displayName: "Technogym",
    catalogVersion: "catalog-v1-test",
    provenance: [VALID_PROVENANCE],
  };
  const validLine = {
    schemaVersion: 1,
    productLineId: "technogym-selection",
    brandId: "technogym",
    displayName: "Selection",
    catalogVersion: "catalog-v1-test",
    provenance: [VALID_PROVENANCE],
  };

  test("EquipmentBrandSchema accepts a valid brand", () => {
    expect(() => EquipmentBrandSchema.parse(validBrand)).not.toThrow();
  });

  test("EquipmentBrandSchema rejects an unknown extra field", () => {
    expect(() =>
      EquipmentBrandSchema.parse({ ...validBrand, unexpectedField: "nope" }),
    ).toThrow(z.ZodError);
  });

  test("ProductLineSchema accepts a valid product line", () => {
    expect(() => ProductLineSchema.parse(validLine)).not.toThrow();
  });

  test("ProductLineSchema rejects an unknown extra field", () => {
    expect(() =>
      ProductLineSchema.parse({ ...validLine, unexpectedField: "nope" }),
    ).toThrow(z.ZodError);
  });
});

describe("EquipmentModelSchema: productLineId/generation are optional-only, not nullable", () => {
  // Reviewer-found gap (P1.G1 type-design review, 2026-08-22): admitting
  // both `null` and `undefined` for the same "no value" meaning let two
  // otherwise-identical models serialize differently, which would break
  // deterministic content hashing once P1.G6 needs it. Only `.optional()`
  // (field omitted) is accepted now; `null` is a type error.
  test("productLineId: null is rejected (must be omitted, not null)", () => {
    expect(() =>
      EquipmentModelSchema.parse(validModel({ productLineId: null })),
    ).toThrow(z.ZodError);
  });

  test("generation: null is rejected (must be omitted, not null)", () => {
    expect(() => EquipmentModelSchema.parse(validModel({ generation: null }))).toThrow(
      z.ZodError,
    );
  });

  test("omitting productLineId/generation entirely is accepted", () => {
    const model = validModel() as Record<string, unknown>;
    delete model.productLineId;
    delete model.generation;
    expect(() => EquipmentModelSchema.parse(model)).not.toThrow();
  });
});

describe("SlugSchema / CatalogVersionSchema / EntityIdSchema Firestore-docId safety", () => {
  // Reviewer-found gap (P1.G1 database review, 2026-08-22): these ids feed
  // a raw `{catalogVersion}--{entityId}` Firestore docId join
  // (firestore_paths.ts); a `--` inside either half would make a future
  // documentId() prefix-range read ambiguous, and `/` would nest an
  // unintended subcollection.
  test("SlugSchema accepts an ordinary slug", () => {
    expect(() => SlugSchema.parse("technogym-selection")).not.toThrow();
  });

  test("SlugSchema rejects a slug containing '--'", () => {
    expect(() => SlugSchema.parse("ab--cd")).toThrow(z.ZodError);
  });

  test("CatalogVersionSchema accepts a normal version string, including spaces", () => {
    expect(() => CatalogVersionSchema.parse("catalog-v1-abc123")).not.toThrow();
  });

  test("CatalogVersionSchema rejects a value containing '/'", () => {
    expect(() => CatalogVersionSchema.parse("catalog/v1")).toThrow(z.ZodError);
  });

  test("CatalogVersionSchema rejects a value containing '--'", () => {
    expect(() => CatalogVersionSchema.parse("catalog--v1")).toThrow(z.ZodError);
  });

  test("EntityIdSchema accepts an arbitrary external identifier", () => {
    expect(() => EntityIdSchema.parse("wger-exercise-1234")).not.toThrow();
  });

  test("EntityIdSchema rejects '/'", () => {
    expect(() => EntityIdSchema.parse("a/b")).toThrow(z.ZodError);
  });

  test("EntityIdSchema rejects '--'", () => {
    expect(() => EntityIdSchema.parse("a--b")).toThrow(z.ZodError);
  });

  test("EntityIdSchema rejects '.' and '..'", () => {
    expect(() => EntityIdSchema.parse(".")).toThrow(z.ZodError);
    expect(() => EntityIdSchema.parse("..")).toThrow(z.ZodError);
  });

  test("EntityIdSchema rejects the reserved __...__ pattern", () => {
    expect(() => EntityIdSchema.parse("__reserved__")).toThrow(z.ZodError);
  });
});
