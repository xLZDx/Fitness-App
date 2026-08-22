import { z } from "zod";
import { mapRecordToCandidate } from "../p1/adapters/candidate_mapper";
import { RawCaptureRecord } from "../p1/adapters/contracts";

const BASE_RECORD: RawCaptureRecord = {
  brandNameRaw: "Example Brand",
  productNameRaw: "Example Leg Press 3000",
  modelCodeRaw: "  ex-lp-3000  ", // deliberately mixed-case/whitespace-padded
  productLineRaw: "Example Line",
  lifecycleStatusRaw: "Active",
  typeHintsRaw: ["leg_press"],
  sourceUrl: "https://example.com/leg-press-3000",
  retrievalMethod: "DIRECT_FETCH",
};

const OPTS = {
  sourceId: "example_product_catalog",
  brandId: "example-brand",
  adapterId: "example-adapter",
  adapterVersion: "1.0.0",
  fixtureSha256: "a".repeat(64),
  capturedAt: "2026-08-22T00:00:00Z",
};

describe("mapRecordToCandidate", () => {
  test("preserves modelCode exactly, including whitespace/case, as captured", () => {
    const candidate = mapRecordToCandidate(BASE_RECORD, OPTS);
    expect(candidate.modelCode).toBe("  ex-lp-3000  ");
    expect(candidate.sourceStableKey).toBe("  ex-lp-3000  ");
  });

  test("never sets a primaryTypeId field on the emitted candidate (§5.8)", () => {
    const candidate = mapRecordToCandidate(BASE_RECORD, OPTS) as Record<string, unknown>;
    expect("primaryTypeId" in candidate).toBe(false);
  });

  test("typeHints carries the raw hints through, non-binding", () => {
    const candidate = mapRecordToCandidate(BASE_RECORD, OPTS);
    expect(candidate.typeHints).toEqual(["leg_press"]);
  });

  test("provenance is complete: sourceId/sourceUrl/fixtureSha256/adapterId/adapterVersion/fields all set", () => {
    const candidate = mapRecordToCandidate(BASE_RECORD, OPTS);
    expect(candidate.provenance).toHaveLength(1);
    const p = candidate.provenance[0];
    expect(p.sourceId).toBe(OPTS.sourceId);
    expect(p.sourceUrl).toBe(BASE_RECORD.sourceUrl);
    expect(p.fixtureSha256).toBe(OPTS.fixtureSha256);
    expect(p.adapterId).toBe(OPTS.adapterId);
    expect(p.adapterVersion).toBe(OPTS.adapterVersion);
    expect(p.fields).toEqual(
      expect.arrayContaining(["canonicalNameCandidate", "modelCode", "brandId", "productLineCandidate", "catalogStatusCandidate", "typeHints"]),
    );
  });

  test("provenance.fields never claims specsRaw -- StagedEquipmentModelCandidate has no field it maps to", () => {
    const withSpecs: RawCaptureRecord = { ...BASE_RECORD, specsRaw: { weight: "500 lb" } };
    const candidate = mapRecordToCandidate(withSpecs, OPTS);
    expect(candidate.provenance[0].fields).not.toContain("specsRaw");
  });

  test("omits productLineCandidate/catalogStatusCandidate-in-fields when the raw record didn't have them", () => {
    const minimal: RawCaptureRecord = {
      brandNameRaw: "Example Brand",
      productNameRaw: "Bare Model",
      modelCodeRaw: "BARE-1",
      typeHintsRaw: [],
      sourceUrl: "https://example.com/bare-1",
      retrievalMethod: "DIRECT_FETCH",
    };
    const candidate = mapRecordToCandidate(minimal, OPTS);
    expect(candidate.productLineCandidate).toBeUndefined();
    expect(candidate.catalogStatusCandidate).toBe("UNKNOWN");
    expect(candidate.provenance[0].fields).not.toContain("productLineCandidate");
    expect(candidate.provenance[0].fields).not.toContain("catalogStatusCandidate");
    expect(candidate.provenance[0].fields).not.toContain("typeHints");
  });

  test("propagates retrievalMethod from the raw record onto the provenance ref", () => {
    const direct = mapRecordToCandidate({ ...BASE_RECORD, retrievalMethod: "DIRECT_FETCH" }, OPTS);
    expect(direct.provenance[0].retrievalMethod).toBe("DIRECT_FETCH");
    const snippet = mapRecordToCandidate(
      { ...BASE_RECORD, retrievalMethod: "SEARCH_INDEX_SNIPPET" },
      OPTS,
    );
    expect(snippet.provenance[0].retrievalMethod).toBe("SEARCH_INDEX_SNIPPET");
  });

  test("maps a known lifecycle synonym (Active/Current product) to ACTIVE", () => {
    const rec: RawCaptureRecord = { ...BASE_RECORD, lifecycleStatusRaw: "Active/Current product" };
    expect(mapRecordToCandidate(rec, OPTS).catalogStatusCandidate).toBe("ACTIVE");
  });

  test("maps Discontinued to DISCONTINUED", () => {
    const rec: RawCaptureRecord = { ...BASE_RECORD, lifecycleStatusRaw: "Discontinued" };
    expect(mapRecordToCandidate(rec, OPTS).catalogStatusCandidate).toBe("DISCONTINUED");
  });

  test("maps an unrecognized lifecycle string to UNKNOWN rather than guessing", () => {
    const rec: RawCaptureRecord = { ...BASE_RECORD, lifecycleStatusRaw: "Something Novel" };
    expect(mapRecordToCandidate(rec, OPTS).catalogStatusCandidate).toBe("UNKNOWN");
  });

  test("does NOT claim catalogStatusCandidate in fields when the raw status was unrecognized (falls back to UNKNOWN)", () => {
    // Reviewer-found gap (P1.G2 review, 2026-08-22): fields used to be
    // pushed whenever lifecycleStatusRaw was merely present, even if
    // mapLifecycle silently fell back to UNKNOWN -- indistinguishable from
    // a genuinely-informed UNKNOWN. Contrast with the "Something Novel"
    // test above, whose catalogStatusCandidate is legitimately UNKNOWN but
    // whose fields must not claim that value came from source evidence.
    const rec: RawCaptureRecord = { ...BASE_RECORD, lifecycleStatusRaw: "Something Novel" };
    const candidate = mapRecordToCandidate(rec, OPTS);
    expect(candidate.catalogStatusCandidate).toBe("UNKNOWN");
    expect(candidate.provenance[0].fields).not.toContain("catalogStatusCandidate");
  });

  test("DOES claim catalogStatusCandidate in fields when the raw status was recognized", () => {
    const rec: RawCaptureRecord = { ...BASE_RECORD, lifecycleStatusRaw: "Discontinued" };
    const candidate = mapRecordToCandidate(rec, OPTS);
    expect(candidate.provenance[0].fields).toContain("catalogStatusCandidate");
  });

  test("candidateId is scoped by brandId, not just sourceId+modelCode (a multi-brand source safeguard)", () => {
    // Two different brands sharing one sourceId (e.g. Life Fitness +
    // Hammer Strength) must never collide onto the same candidateId even
    // if they happen to share a modelCode string.
    const brandA = mapRecordToCandidate(BASE_RECORD, { ...OPTS, brandId: "brand-a" });
    const brandB = mapRecordToCandidate(BASE_RECORD, { ...OPTS, brandId: "brand-b" });
    expect(brandA.candidateId).not.toBe(brandB.candidateId);
  });

  test("candidateId is deterministic for the same sourceId+brandId+modelCode", () => {
    const a = mapRecordToCandidate(BASE_RECORD, OPTS);
    const b = mapRecordToCandidate(BASE_RECORD, OPTS);
    expect(a.candidateId).toBe(b.candidateId);
  });

  test("throws (schema validation) if the mapped candidate would be structurally invalid", () => {
    // sourceUrl is not a real URL -- RawCaptureRecordSchema itself would
    // catch this at fixture-load time, but mapRecordToCandidate must not
    // silently succeed if handed a value bypassing that gate.
    const rec = { ...BASE_RECORD, sourceUrl: "not-a-url" } as RawCaptureRecord;
    expect(() => mapRecordToCandidate(rec, OPTS)).toThrow(z.ZodError);
  });
});
