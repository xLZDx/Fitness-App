import { runAdapter } from "../p1/adapters/adapter_runner";
import { detectRecordDrift } from "../p1/adapters/source_drift";
import { RawCaptureRecord } from "../p1/adapters/contracts";

const SOURCE_ID = "life_fitness_hammer_strength_product_catalog"; // real, registered OFFICIAL_MANUFACTURER

function record(overrides: Partial<RawCaptureRecord> = {}): RawCaptureRecord {
  return {
    brandNameRaw: "Life Fitness",
    productNameRaw: "Test Product",
    modelCodeRaw: "TP-1",
    typeHintsRaw: [],
    sourceUrl: "https://www.lifefitness.com/en-us/catalog/strength-training",
    retrievalMethod: "DIRECT_FETCH",
    ...overrides,
  };
}

function fixtureWith(records: RawCaptureRecord[]) {
  return {
    schemaVersion: 1,
    sourceId: SOURCE_ID,
    capturedAt: "2026-08-22T00:00:00Z",
    records,
  };
}

const BRAND_MAP = { "Life Fitness": "life-fitness", "Hammer Strength": "hammer-strength" };

describe("runAdapter: brand-scoped duplicate detection (P1.G2 review fix)", () => {
  test("two DIFFERENT brands sharing a modelCode within one fixture does NOT throw", () => {
    const rawFixture = fixtureWith([
      record({ brandNameRaw: "Life Fitness", modelCodeRaw: "SHARED-1" }),
      record({ brandNameRaw: "Hammer Strength", modelCodeRaw: "SHARED-1" }),
    ]);
    const result = runAdapter({
      sourceId: SOURCE_ID,
      adapterId: "test-adapter",
      adapterVersion: "1.0.0",
      rawFixture,
      brandIdByRawName: BRAND_MAP,
    });
    expect(result.candidates).toHaveLength(2);
    expect(result.candidates[0].candidateId).not.toBe(result.candidates[1].candidateId);
  });

  test("the SAME brand repeating a modelCode within one fixture still throws", () => {
    const rawFixture = fixtureWith([
      record({ brandNameRaw: "Life Fitness", modelCodeRaw: "DUPE-1" }),
      record({ brandNameRaw: "Life Fitness", modelCodeRaw: "DUPE-1" }),
    ]);
    expect(() =>
      runAdapter({
        sourceId: SOURCE_ID,
        adapterId: "test-adapter",
        adapterVersion: "1.0.0",
        rawFixture,
        brandIdByRawName: BRAND_MAP,
      }),
    ).toThrow(/duplicate modelCodeRaw/);
  });

  test("the SAME brand with a case/whitespace-only variant of a modelCode still throws (matches conflicts.ts normalization)", () => {
    const rawFixture = fixtureWith([
      record({ brandNameRaw: "Life Fitness", modelCodeRaw: "dupe-2" }),
      record({ brandNameRaw: "Life Fitness", modelCodeRaw: " DUPE-2 " }),
    ]);
    expect(() =>
      runAdapter({
        sourceId: SOURCE_ID,
        adapterId: "test-adapter",
        adapterVersion: "1.0.0",
        rawFixture,
        brandIdByRawName: BRAND_MAP,
      }),
    ).toThrow(/duplicate modelCodeRaw/);
  });
});

describe("detectRecordDrift: lifecycle status (P1.G2 review fix)", () => {
  test("flags an unrecognized lifecycleStatusRaw as drift", () => {
    const issues = detectRecordDrift(record({ lifecycleStatusRaw: "Coming Soon" }));
    expect(issues).toEqual(
      expect.arrayContaining([expect.objectContaining({ field: "lifecycleStatusRaw" })]),
    );
  });

  test("does not flag a recognized lifecycleStatusRaw", () => {
    const issues = detectRecordDrift(record({ lifecycleStatusRaw: "Active" }));
    expect(issues.filter((i) => i.field === "lifecycleStatusRaw")).toEqual([]);
  });

  test("does not flag an absent lifecycleStatusRaw (no status given is not drift)", () => {
    const issues = detectRecordDrift(record({}));
    expect(issues.filter((i) => i.field === "lifecycleStatusRaw")).toEqual([]);
  });
});
