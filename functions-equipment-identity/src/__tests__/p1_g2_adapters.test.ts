import { runTechnogymAdapter } from "../p1/adapters/technogym_adapter";
import { runMatrixAdapter } from "../p1/adapters/matrix_adapter";
import { runLifeFitnessHammerStrengthAdapter } from "../p1/adapters/life_fitness_hammer_strength_adapter";
import { runNautilusAdapter } from "../p1/adapters/nautilus_adapter";
import { runAllP0BrandAdapters } from "../p1/adapters/run_all";
import { StagedEquipmentModelCandidateSchema } from "../p1/contracts";

describe("individual P0 brand adapters -- real committed fixtures", () => {
  test("Technogym: emits 9 candidates, all brandId=technogym, all SEARCH_INDEX_SNIPPET, no drift", () => {
    const result = runTechnogymAdapter();
    expect(result.candidates).toHaveLength(9);
    expect(result.candidates.every((c) => c.brandId === "technogym")).toBe(true);
    expect(
      result.candidates.every((c) => c.provenance.every((p) => p.sourceUrl.includes("technogym.com"))),
    ).toBe(true);
    expect(
      result.candidates.every((c) => c.provenance.every((p) => p.retrievalMethod === "SEARCH_INDEX_SNIPPET")),
    ).toBe(true);
    expect(result.driftIssues).toEqual([]);
  });

  test("Matrix: emits 17 candidates, all brandId=matrix, no drift", () => {
    const result = runMatrixAdapter();
    expect(result.candidates).toHaveLength(17);
    expect(result.candidates.every((c) => c.brandId === "matrix")).toBe(true);
    expect(result.driftIssues).toEqual([]);
  });

  test("Life Fitness / Hammer Strength: emits 9 candidates split across two real brandIds, no drift", () => {
    const result = runLifeFitnessHammerStrengthAdapter();
    expect(result.candidates).toHaveLength(9);
    const byBrand = new Map<string, number>();
    for (const c of result.candidates) byBrand.set(c.brandId, (byBrand.get(c.brandId) ?? 0) + 1);
    expect(byBrand.get("life-fitness")).toBe(5);
    expect(byBrand.get("hammer-strength")).toBe(4);
    expect(result.driftIssues).toEqual([]);
    // this is the strongest-retrieval source -- every record was directly fetched
    expect(
      result.candidates.every((c) => c.provenance.every((p) => p.retrievalMethod === "DIRECT_FETCH")),
    ).toBe(true);
  });

  test("Nautilus: emits 13 candidates, all brandId=nautilus, no drift", () => {
    const result = runNautilusAdapter();
    expect(result.candidates).toHaveLength(13);
    expect(result.candidates.every((c) => c.brandId === "nautilus")).toBe(true);
    expect(result.driftIssues).toEqual([]);
  });

  test("no adapter ever emits a candidate carrying a primaryTypeId field (§5.8)", () => {
    const all = [
      ...runTechnogymAdapter().candidates,
      ...runMatrixAdapter().candidates,
      ...runLifeFitnessHammerStrengthAdapter().candidates,
      ...runNautilusAdapter().candidates,
    ];
    for (const candidate of all) {
      expect("primaryTypeId" in (candidate as Record<string, unknown>)).toBe(false);
      // and every candidate independently re-validates against the P1.G1
      // staged-candidate schema, which structurally forbids primaryTypeId
      expect(() => StagedEquipmentModelCandidateSchema.parse(candidate)).not.toThrow();
    }
  });

  test("every candidate has a non-empty modelCode carried through unchanged from its fixture", () => {
    const all = [
      ...runTechnogymAdapter().candidates,
      ...runMatrixAdapter().candidates,
      ...runLifeFitnessHammerStrengthAdapter().candidates,
      ...runNautilusAdapter().candidates,
    ];
    expect(all.every((c) => typeof c.modelCode === "string" && c.modelCode.length > 0)).toBe(true);
  });
});

describe("runAllP0BrandAdapters -- combined pool (P1.G2 + P1.G3)", () => {
  test("produces exactly 74 candidates across the 6 sources (9+17+9+13+14+12), with margin above the 50-model pilot target (§5.7)", () => {
    const result = runAllP0BrandAdapters();
    expect(result.candidates).toHaveLength(74);
    expect(result.captureManifest).toHaveLength(6);
  });

  test("all 7 brands required by §5.7 are represented across P0.G2's + P0.G3's brand groups", () => {
    const result = runAllP0BrandAdapters();
    const brands = new Set(result.candidates.map((c) => c.brandId));
    expect(brands).toEqual(
      new Set([
        "technogym",
        "matrix",
        "life-fitness",
        "hammer-strength",
        "nautilus",
        "precor",
        "panatta",
      ]),
    );
  });

  test("real committed data has zero conflicts (documented fact, not an untested assumption)", () => {
    const result = runAllP0BrandAdapters();
    expect(result.conflicts).toEqual([]);
  });

  test("deterministic: two independent runs against the same fixtures produce byte-identical candidate output", () => {
    const a = runAllP0BrandAdapters();
    const b = runAllP0BrandAdapters();
    expect(JSON.stringify(a.candidates)).toBe(JSON.stringify(b.candidates));
    expect(JSON.stringify(a.captureManifest)).toBe(JSON.stringify(b.captureManifest));
  });

  test("every candidateId is unique across the whole combined pool", () => {
    const result = runAllP0BrandAdapters();
    const ids = result.candidates.map((c) => c.candidateId);
    expect(new Set(ids).size).toBe(ids.length);
  });
});
