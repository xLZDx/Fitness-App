import { evaluateExactResolutionPolicy, type CatalogModelFields } from "../exact_resolution_policy";
import type { ModelCodeLookupResult } from "../text_key_index";

const MODEL_ID_A = "11111111-1111-4111-8111-111111111111";
const MODEL_ID_B = "22222222-2222-4222-8222-222222222222";

function unique(modelId: string): ModelCodeLookupResult {
  return { outcome: "UNIQUE", modelId, keyKinds: ["MODEL_CODE"] };
}
function nonunique(modelIds: string[]): ModelCodeLookupResult {
  return { outcome: "NONUNIQUE", modelIds };
}
function noMatch(): ModelCodeLookupResult {
  return { outcome: "NO_MATCH" };
}

function fields(overrides: Partial<CatalogModelFields> = {}): CatalogModelFields {
  return {
    modelId: MODEL_ID_A,
    catalogVersion: "catalog-v1",
    textSupportStatus: "VERIFIED",
    primaryTypeId: "leg_press",
    supportedTypeIds: ["leg_press"],
    ...overrides,
  };
}

function modelFieldsMap(...entries: CatalogModelFields[]): Map<string, CatalogModelFields> {
  return new Map(entries.map((f) => [f.modelId, f]));
}

describe("evaluateExactResolutionPolicy -- textSupportStatus gating (condition 6)", () => {
  test("VERIFIED unique code -> EXACT_PRODUCTION", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ textSupportStatus: "VERIFIED" })),
    });
    expect(result).toEqual({
      outcome: "EXACT_PRODUCTION",
      modelId: MODEL_ID_A,
      catalogVersion: "catalog-v1",
    });
  });

  test("EXPERIMENTAL unique code -> EXACT_SHADOW_ONLY, never production", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ textSupportStatus: "EXPERIMENTAL" })),
    });
    expect(result).toEqual({
      outcome: "EXACT_SHADOW_ONLY",
      modelId: MODEL_ID_A,
      catalogVersion: "catalog-v1",
      reason: "EXPERIMENTAL_TEXT_SUPPORT",
    });
  });

  test("NONE textSupportStatus -> NOT_ELIGIBLE, no exact claim of any kind", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ textSupportStatus: "NONE" })),
    });
    expect(result.outcome).toBe("NOT_ELIGIBLE");
  });
});

describe("evaluateExactResolutionPolicy -- uniqueness and conflicting codes (conditions 1/2)", () => {
  test("no candidate resolves -> NOT_ELIGIBLE", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "NOSUCHCODE", lookup: noMatch() }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(),
    });
    expect(result.outcome).toBe("NOT_ELIGIBLE");
  });

  test("a candidate resolving NONUNIQUE aborts the whole attempt", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRX", lookup: nonunique([MODEL_ID_A, MODEL_ID_B]) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result).toMatchObject({ outcome: "ABSTAIN", abstainReason: "EVIDENCE_CONFLICT" });
  });

  test("two distinct candidates resolving to two distinct models -> ABSTAIN EVIDENCE_CONFLICT", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [
        { rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) },
        { rawCandidate: "9WAY", lookup: unique(MODEL_ID_B) },
      ],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ modelId: MODEL_ID_A }), fields({ modelId: MODEL_ID_B })),
    });
    expect(result).toMatchObject({ outcome: "ABSTAIN", abstainReason: "EVIDENCE_CONFLICT" });
  });

  test("two candidates resolving to the SAME model is not a conflict", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [
        { rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) },
        { rawCandidate: "8TRXALT", lookup: unique(MODEL_ID_A) },
      ],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });
});

describe("evaluateExactResolutionPolicy -- placard/ownership conflicts (condition 3)", () => {
  test("a non-empty parserConflicts list aborts even a clean unique resolution", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRX", lookup: unique(MODEL_ID_A) }],
      parserConflicts: ["ambiguous ownership between two clusters"],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result).toMatchObject({ outcome: "ABSTAIN", abstainReason: "EVIDENCE_CONFLICT" });
  });
});

describe("evaluateExactResolutionPolicy -- OCR O<->0/I<->1 corroboration (condition 4)", () => {
  test("a sole ambiguous-character reading with no corroboration -> ABSTAIN LOW_CONFIDENCE", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TR0", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result).toMatchObject({ outcome: "ABSTAIN", abstainReason: "LOW_CONFIDENCE" });
  });

  test("an ambiguous reading corroborated by a second, character-clean reading of the same model -> exact", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [
        { rawCandidate: "8TR0", lookup: unique(MODEL_ID_A) },
        { rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) },
      ],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: "8TR0" and "8TRO"
  // are NOT independent readings -- they are the identical underlying
  // token, decoded two different ways, and differ ONLY at the ambiguous
  // O/0 position. Counting them as corroboration of each other was the
  // defect; this test previously asserted the wrong (buggy) outcome.
  test("two raw strings that are OCR-ambiguity variants of the SAME token (differ only at O/0/I/1 positions) do NOT corroborate each other -> ABSTAIN", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [
        { rawCandidate: "8TR0", lookup: unique(MODEL_ID_A) },
        { rawCandidate: "8TRO", lookup: unique(MODEL_ID_A) },
      ],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result).toMatchObject({ outcome: "ABSTAIN", abstainReason: "LOW_CONFIDENCE" });
  });

  test("two GENUINELY distinct ambiguous readings (different canonical forms) that both resolve to the same model still count as corroboration", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [
        { rawCandidate: "8TR0", lookup: unique(MODEL_ID_A) },
        { rawCandidate: "9TL1", lookup: unique(MODEL_ID_A) },
      ],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  test("a code with no ambiguous characters at all never needs corroboration", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });
});

describe("evaluateExactResolutionPolicy -- generic type-evidence reconciliation (condition 5)", () => {
  test("VERIFIED high-assurance type conflicting with the resolved model -> NEED_MORE_VIEW", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ supportedTypeIds: ["leg_press"] })),
      typeEvidence: { status: "VERIFIED", typeId: "treadmill" },
    });
    expect(result.outcome).toBe("NEED_MORE_VIEW");
  });

  test("HIGH_ASSURANCE type compatible with the resolved model does not block exact", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ supportedTypeIds: ["leg_press", "multi_press"] })),
      typeEvidence: { status: "HIGH_ASSURANCE", typeId: "multi_press" },
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  test("LOW_CONFIDENCE conflicting type is soft evidence -- never vetoes a unique verified code match", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ supportedTypeIds: ["leg_press"] })),
      typeEvidence: { status: "LOW_CONFIDENCE", typeId: "treadmill" },
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  test("OFFLINE_FALLBACK conflicting type is soft evidence -- never vetoes", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ supportedTypeIds: ["leg_press"] })),
      typeEvidence: { status: "OFFLINE_FALLBACK", typeId: "treadmill" },
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  test("AMBIGUOUS conflicting type is soft evidence -- never vetoes", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields({ supportedTypeIds: ["leg_press"] })),
      typeEvidence: { status: "AMBIGUOUS", typeId: "treadmill" },
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });

  test("no typeEvidence at all (the real text-only wiring) proceeds normally", () => {
    const result = evaluateExactResolutionPolicy({
      candidates: [{ rawCandidate: "8TRZ", lookup: unique(MODEL_ID_A) }],
      parserConflicts: [],
      modelFieldsByModelId: modelFieldsMap(fields()),
    });
    expect(result.outcome).toBe("EXACT_PRODUCTION");
  });
});
