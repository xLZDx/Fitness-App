import { detectConflicts } from "../p1/adapters/conflicts";
import { mapRecordToCandidate } from "../p1/adapters/candidate_mapper";
import { RawCaptureRecord } from "../p1/adapters/contracts";

function makeCandidate(brandId: string, modelCode: string, sourceId = "src-a") {
  const record: RawCaptureRecord = {
    brandNameRaw: "Brand",
    productNameRaw: `Product ${modelCode}`,
    modelCodeRaw: modelCode,
    typeHintsRaw: [],
    sourceUrl: "https://example.com/p",
    retrievalMethod: "DIRECT_FETCH",
  };
  return mapRecordToCandidate(record, {
    sourceId,
    brandId,
    adapterId: "test-adapter",
    adapterVersion: "1.0.0",
    fixtureSha256: "a".repeat(64),
    capturedAt: "2026-08-22T00:00:00Z",
  });
}

describe("detectConflicts", () => {
  test("reports no conflicts for a pool with all-distinct modelCodes", () => {
    const candidates = [makeCandidate("brand-a", "AAA"), makeCandidate("brand-a", "BBB")];
    expect(detectConflicts(candidates)).toEqual([]);
  });

  test("flags a same-brand duplicate modelCode", () => {
    const candidates = [
      makeCandidate("brand-a", "DUPE-1", "src-a"),
      makeCandidate("brand-a", "DUPE-1", "src-b"),
    ];
    const conflicts = detectConflicts(candidates);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0].kind).toBe("DUPLICATE_MODEL_CODE_SAME_BRAND");
    expect(conflicts[0].brandIds).toEqual(["brand-a"]);
  });

  test("flags a cross-brand duplicate modelCode", () => {
    const candidates = [makeCandidate("brand-a", "SHARED"), makeCandidate("brand-b", "SHARED")];
    const conflicts = detectConflicts(candidates);
    expect(conflicts).toHaveLength(1);
    expect(conflicts[0].kind).toBe("DUPLICATE_MODEL_CODE_CROSS_BRAND");
    expect(conflicts[0].brandIds).toEqual(["brand-a", "brand-b"]);
  });

  test("normalizes case and whitespace before comparing (a real conflict, not two different codes)", () => {
    const candidates = [makeCandidate("brand-a", "abc-1"), makeCandidate("brand-a", " ABC-1 ")];
    const conflicts = detectConflicts(candidates);
    expect(conflicts).toHaveLength(1);
  });

  test("never auto-resolves -- both candidateIds are preserved in the report", () => {
    const a = makeCandidate("brand-a", "X1", "src-a");
    const b = makeCandidate("brand-a", "X1", "src-b");
    const conflicts = detectConflicts([a, b]);
    expect(conflicts[0].candidateIds.sort()).toEqual([a.candidateId, b.candidateId].sort());
  });
});
