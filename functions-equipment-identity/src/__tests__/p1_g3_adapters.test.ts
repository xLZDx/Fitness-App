import { runPrecorAdapter } from "../p1/adapters/precor_adapter";
import { runPanattaAdapter } from "../p1/adapters/panatta_adapter";
import { StagedEquipmentModelCandidateSchema } from "../p1/contracts";

describe("Precor adapter -- real committed fixture (official spec-table PDF)", () => {
  test("emits 14 candidates, all brandId=precor, all DIRECT_FETCH, no drift", () => {
    const result = runPrecorAdapter();
    expect(result.candidates).toHaveLength(14);
    expect(result.candidates.every((c) => c.brandId === "precor")).toBe(true);
    expect(
      result.candidates.every((c) =>
        c.provenance.every((p) => p.retrievalMethod === "DIRECT_FETCH"),
      ),
    ).toBe(true);
    expect(
      result.candidates.every((c) =>
        c.provenance.every((p) => p.sourceUrl === "https://static.precor.com/spec-tables/en-us/Precor-2022-NA-Spec-Tables.pdf"),
      ),
    ).toBe(true);
    expect(result.driftIssues).toEqual([]);
  });

  test("every candidate re-validates against the P1.G1 staged-candidate schema and never carries primaryTypeId", () => {
    const result = runPrecorAdapter();
    for (const candidate of result.candidates) {
      expect("primaryTypeId" in (candidate as Record<string, unknown>)).toBe(false);
      expect(() => StagedEquipmentModelCandidateSchema.parse(candidate)).not.toThrow();
    }
  });
});

describe("Panatta adapter -- real committed fixture (search-index discovery only)", () => {
  test("emits 12 candidates, all brandId=panatta, all SEARCH_INDEX_SNIPPET, no drift", () => {
    const result = runPanattaAdapter();
    expect(result.candidates).toHaveLength(12);
    expect(result.candidates.every((c) => c.brandId === "panatta")).toBe(true);
    expect(
      result.candidates.every((c) =>
        c.provenance.every((p) => p.retrievalMethod === "SEARCH_INDEX_SNIPPET"),
      ),
    ).toBe(true);
    expect(
      result.candidates.every((c) =>
        c.provenance.every((p) => p.sourceUrl.includes("panattasport.com")),
      ),
    ).toBe(true);
    expect(result.driftIssues).toEqual([]);
  });

  test("every candidate has a distinct sourceUrl pointing at its own real product page (model code visible in the URL)", () => {
    const result = runPanattaAdapter();
    for (const candidate of result.candidates) {
      const url = candidate.provenance[0].sourceUrl;
      expect(candidate.modelCode).toBeDefined();
      expect(url.toUpperCase()).toContain((candidate.modelCode as string).toUpperCase());
    }
  });

  test("every candidate re-validates against the P1.G1 staged-candidate schema and never carries primaryTypeId", () => {
    const result = runPanattaAdapter();
    for (const candidate of result.candidates) {
      expect("primaryTypeId" in (candidate as Record<string, unknown>)).toBe(false);
      expect(() => StagedEquipmentModelCandidateSchema.parse(candidate)).not.toThrow();
    }
  });
});
