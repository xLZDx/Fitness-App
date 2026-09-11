import {
  normalizeModelCodeLookupKey,
  materializeEquipmentModelTextKeys,
} from "../text_key_index";
import { textKeyDocId } from "../firestore_paths";
import type { EquipmentModel } from "../../p1/contracts";

function makeProvenance(): EquipmentModel["provenance"][number] {
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

function makeModel(overrides: Partial<EquipmentModel> = {}): EquipmentModel {
  return {
    schemaVersion: 1,
    modelId: "11111111-1111-4111-8111-111111111111",
    canonicalSlug: "technogym-selection-leg-press",
    brandId: "technogym",
    productLineId: "technogym-selection",
    canonicalName: "Selection Leg Press",
    modelCode: "SEL-LEGPRESS-500",
    skuAliases: [],
    primaryTypeId: "some-type",
    supportedTypeIds: ["some-type"],
    aliases: [],
    catalogStatus: "ACTIVE",
    textSupportStatus: "EXPERIMENTAL",
    visionSupportStatus: "NONE",
    sourceConfidence: "OFFICIAL",
    catalogVersion: "catalog-v1-test",
    provenance: [makeProvenance()],
    ...overrides,
  } as EquipmentModel;
}

describe("normalizeModelCodeLookupKey", () => {
  test("uppercases and preserves internal delimiters, matching P2.G2's convention", () => {
    expect(normalizeModelCodeLookupKey("8trx")).toBe("8TRX");
    expect(normalizeModelCodeLookupKey("abc/123")).toBe("ABC/123");
    expect(normalizeModelCodeLookupKey("a-b-123")).toBe("A-B-123");
  });

  test("strips only leading/trailing punctuation, never internal", () => {
    expect(normalizeModelCodeLookupKey("  (8trx)  ")).toBe("8TRX");
    expect(normalizeModelCodeLookupKey("--A/B--")).toBe("A/B");
  });

  test("a code containing '--' internally is preserved through normalization", () => {
    expect(normalizeModelCodeLookupKey("A--B123")).toBe("A--B123");
  });

  test("a degenerate all-punctuation input normalizes to the empty string", () => {
    expect(normalizeModelCodeLookupKey("---")).toBe("");
    expect(normalizeModelCodeLookupKey("   ")).toBe("");
  });
});

describe("materializeEquipmentModelTextKeys -- dedup by (catalogVersion, lookupKey, modelId)", () => {
  test("modelCode and an alias that normalize to the same key produce ONE record with both keyKinds", () => {
    const model = makeModel({ modelCode: "8TRx", aliases: ["8trx"] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records).toHaveLength(1);
    expect(records[0]).toEqual({
      catalogVersion: "catalog-v1-test",
      lookupKey: "8TRX",
      modelId: model.modelId,
      keyKinds: ["ALIAS", "MODEL_CODE"],
    });
  });

  test("modelCode + SKU + alias all collapsing to one key still produce ONE record", () => {
    const model = makeModel({
      modelCode: "8TRX",
      skuAliases: ["8trx", " 8TRX "],
      aliases: ["8Trx"],
    });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records).toHaveLength(1);
    expect(records[0].lookupKey).toBe("8TRX");
    expect(records[0].keyKinds).toEqual(["ALIAS", "MODEL_CODE", "SKU_ALIAS"]);
  });

  test("distinct sources that do NOT collapse produce separate records", () => {
    const model = makeModel({ modelCode: "8TRX", aliases: ["9WAY"] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records.map((r) => r.lookupKey).sort()).toEqual(["8TRX", "9WAY"]);
  });

  test("a slash-containing model code is preserved end to end", () => {
    const model = makeModel({ modelCode: "ABC/123", aliases: [] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records).toHaveLength(1);
    expect(records[0].lookupKey).toBe("ABC/123");
  });

  test("a '--'-containing model code is preserved end to end", () => {
    const model = makeModel({ modelCode: "A--B123", aliases: [] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records).toHaveLength(1);
    expect(records[0].lookupKey).toBe("A--B123");
  });

  test("a degenerate all-punctuation source is skipped, never emitted as an empty key", () => {
    const model = makeModel({ modelCode: "8TRX", aliases: ["---", "   "] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records).toHaveLength(1);
    expect(records[0].lookupKey).toBe("8TRX");
  });

  test("output is deterministically sorted by lookupKey", () => {
    const model = makeModel({ modelCode: "ZZZ", aliases: ["AAA", "MMM"] });
    const records = materializeEquipmentModelTextKeys(model);
    expect(records.map((r) => r.lookupKey)).toEqual(["AAA", "MMM", "ZZZ"]);
  });
});

describe("textKeyDocId -- collision-freedom over a real fixture corpus", () => {
  test("the doc id does NOT embed lookupKey as a raw path-joinable component", () => {
    const id = textKeyDocId("catalog-v1", "ABC/123", "11111111-1111-4111-8111-111111111111");
    expect(id).not.toContain("/");
    expect(id).toMatch(/^[0-9a-f]{64}$/);
  });

  test("a '--'-containing lookupKey does not collide with an unrelated tuple", () => {
    const idA = textKeyDocId("catalog-v1", "A--B", "11111111-1111-4111-8111-111111111111");
    const idB = textKeyDocId("catalog-v1", "A", "B-11111111-1111-4111-8111-111111111111");
    expect(idA).not.toBe(idB);
  });

  test("no two distinct real tuples in a realistic fixture corpus collide", () => {
    const catalogVersions = ["catalog-v1", "catalog-v2"];
    const lookupKeys = ["8TRX", "ABC/123", "A--B123", "9WAY", "SEL-LEGPRESS-500"];
    const modelIds = [
      "11111111-1111-4111-8111-111111111111",
      "22222222-2222-4222-8222-222222222222",
      "33333333-3333-4333-8333-333333333333",
    ];
    const seen = new Set<string>();
    for (const cv of catalogVersions) {
      for (const lk of lookupKeys) {
        for (const mid of modelIds) {
          const id = textKeyDocId(cv, lk, mid);
          expect(seen.has(id)).toBe(false);
          seen.add(id);
        }
      }
    }
    expect(seen.size).toBe(catalogVersions.length * lookupKeys.length * modelIds.length);
  });

  test("the id is deterministic -- same tuple always hashes to the same id", () => {
    const a = textKeyDocId("catalog-v1", "8TRX", "11111111-1111-4111-8111-111111111111");
    const b = textKeyDocId("catalog-v1", "8TRX", "11111111-1111-4111-8111-111111111111");
    expect(a).toBe(b);
  });
});
