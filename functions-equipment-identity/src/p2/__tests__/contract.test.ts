import {
  EquipmentIdentityRequestSchema,
  EquipmentIdentityResponseSchema,
  isSupportedIdentityContractVersion,
  CURRENT_IDENTITY_CONTRACT_VERSION,
  TEXT_ONLY_EVIDENCE_LANE,
} from "../contract";

function validAuthority() {
  return {
    catalogVersion: "catalog-v1",
    ocrVersion: "ocr-1.0.0",
    textPolicyVersion: "text-policy-1",
    fusionPolicyVersion: "fusion-policy-1",
    identityPolicyVersion: "identity-policy-1",
  };
}

function validResponseBase() {
  return {
    scanId: "scan-1",
    recognitionSessionId: "session-1",
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    authority: validAuthority(),
    evidenceLane: TEXT_ONLY_EVIDENCE_LANE,
    verifierInvoked: false,
  };
}

describe("EquipmentIdentityRequestSchema", () => {
  test("accepts a well-formed request", () => {
    const request = {
      scanId: "scan-1",
      identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
      clientCapabilities: ["MULTI_VIEW"],
      evidence: {
        brandCandidates: ["technogym"],
        productLineCandidates: [],
        modelCodeCandidates: ["8TRX"],
        typeHints: [],
        conflicts: [],
      },
      ocrVersion: "ocr-1.0.0",
    };
    expect(EquipmentIdentityRequestSchema.safeParse(request).success).toBe(true);
  });

  test("rejects an unknown/extra field (strict schema)", () => {
    const request = {
      scanId: "scan-1",
      identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
      clientCapabilities: [],
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: [],
        typeHints: [],
        conflicts: [],
      },
      ocrVersion: "ocr-1.0.0",
      rawImageBase64: "should-never-exist", // T4: no image ever enters the request schema
    };
    expect(EquipmentIdentityRequestSchema.safeParse(request).success).toBe(false);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: no bound existed on
  // any evidence array/string, so a single quota-charged request could
  // drive an unbounded number of per-candidate Firestore calls in
  // orchestrator.ts (cost amplification, not merely an oversized payload).
  test("rejects a modelCodeCandidates array over the bound", () => {
    const request = {
      scanId: "scan-1",
      identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
      clientCapabilities: [],
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: Array.from({ length: 21 }, (_, i) => `CODE${i}`),
        typeHints: [],
        conflicts: [],
      },
      ocrVersion: "ocr-1.0.0",
    };
    expect(EquipmentIdentityRequestSchema.safeParse(request).success).toBe(false);
  });

  test("rejects an over-length string inside an evidence array", () => {
    const request = {
      scanId: "scan-1",
      identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
      clientCapabilities: [],
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: ["X".repeat(129)],
        typeHints: [],
        conflicts: [],
      },
      ocrVersion: "ocr-1.0.0",
    };
    expect(EquipmentIdentityRequestSchema.safeParse(request).success).toBe(false);
  });

  test("accepts an evidence array right at the bound", () => {
    const request = {
      scanId: "scan-1",
      identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
      clientCapabilities: [],
      evidence: {
        brandCandidates: [],
        productLineCandidates: [],
        modelCodeCandidates: Array.from({ length: 20 }, (_, i) => `CODE${i}`),
        typeHints: [],
        conflicts: [],
      },
      ocrVersion: "ocr-1.0.0",
    };
    expect(EquipmentIdentityRequestSchema.safeParse(request).success).toBe(true);
  });
});

describe("isSupportedIdentityContractVersion", () => {
  test("the current version is supported", () => {
    expect(isSupportedIdentityContractVersion(CURRENT_IDENTITY_CONTRACT_VERSION)).toBe(true);
  });

  test("an unrecognized version is not supported", () => {
    expect(isSupportedIdentityContractVersion("v0")).toBe(false);
    expect(isSupportedIdentityContractVersion("v99")).toBe(false);
  });
});

describe("EquipmentIdentityResponseSchema -- decision/abstainReason/failureCode mutual exclusion", () => {
  test("a MATCH decision with identityLevel/model is valid", () => {
    const response = {
      ...validResponseBase(),
      decision: "MATCH",
      identityLevel: "EXACT_MODEL",
      model: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "VERIFIED" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });

  test("an ABSTAIN decision with a genuine abstainReason is valid", () => {
    const response = { ...validResponseBase(), decision: "ABSTAIN", abstainReason: "LOW_CONFIDENCE" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });

  test("an UNAVAILABLE_* decision with a matching failureCode is valid", () => {
    const response = {
      ...validResponseBase(),
      decision: "UNAVAILABLE_CATALOG_VERSION",
      failureCode: "CATALOG_VERSION_UNAVAILABLE",
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });

  test("rejects abstainReason AND failureCode both present on the same response", () => {
    const response = {
      ...validResponseBase(),
      decision: "ABSTAIN",
      abstainReason: "LOW_CONFIDENCE",
      failureCode: "TIMEOUT",
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("rejects abstainReason present when decision is not ABSTAIN", () => {
    const response = { ...validResponseBase(), decision: "MATCH", abstainReason: "LOW_CONFIDENCE" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("rejects an UNAVAILABLE_* decision with NO failureCode", () => {
    const response = { ...validResponseBase(), decision: "UNAVAILABLE_TIMEOUT" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("rejects a failureCode present when decision is not UNAVAILABLE_*", () => {
    const response = { ...validResponseBase(), decision: "MATCH", failureCode: "TIMEOUT" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("an UNSUPPORTED_CLIENT_CONTRACT decision needs neither abstainReason nor failureCode", () => {
    const response = { ...validResponseBase(), decision: "UNSUPPORTED_CLIENT_CONTRACT" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });
});

// GPT-PM MAJOR, P2.G3 pre-commit review, 2026-09-11: verifierInvoked was
// entirely absent from the response shape -- v4.4 defines TEXT_ONLY partly
// BY verifierInvoked == false, and an omitted field is not the same claim
// as an explicit false. Required (not optional) below.
describe("EquipmentIdentityResponseSchema -- verifierInvoked", () => {
  test("rejects a response missing verifierInvoked entirely", () => {
    const { verifierInvoked: _drop, ...rest } = { ...validResponseBase(), decision: "UNSUPPORTED_CLIENT_CONTRACT" };
    expect(EquipmentIdentityResponseSchema.safeParse(rest).success).toBe(false);
  });

  test("rejects verifierInvoked: true on a TEXT_ONLY response", () => {
    const response = {
      ...validResponseBase(),
      decision: "UNSUPPORTED_CLIENT_CONTRACT",
      verifierInvoked: true,
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });
});

// GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11 (correcting
// round 1's own matchAuthority side-channel remediation): an EXPERIMENTAL
// (shadow-only) exact match must never be represented as a MATCH+EXACT_MODEL
// claim at all -- it is now a genuinely separate response shape
// (shadowCandidate), never coexisting with `model`/`decision: MATCH`.
describe("EquipmentIdentityResponseSchema -- model / shadowCandidate separation", () => {
  test("MATCH requires model", () => {
    const response = { ...validResponseBase(), decision: "MATCH", identityLevel: "EXACT_MODEL" };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("model.textSupportStatus must be VERIFIED -- EXPERIMENTAL is rejected", () => {
    const response = {
      ...validResponseBase(),
      decision: "MATCH",
      identityLevel: "EXACT_MODEL",
      model: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "EXPERIMENTAL" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("a non-MATCH decision must not carry model", () => {
    const response = {
      ...validResponseBase(),
      decision: "NOT_SUPPORTED",
      model: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "VERIFIED" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("a NOT_SUPPORTED decision carrying a shadowCandidate is valid (non-authoritative evidence)", () => {
    const response = {
      ...validResponseBase(),
      decision: "NOT_SUPPORTED",
      shadowCandidate: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "EXPERIMENTAL" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });

  test("shadowCandidate.textSupportStatus must be EXPERIMENTAL -- VERIFIED is rejected", () => {
    const response = {
      ...validResponseBase(),
      decision: "NOT_SUPPORTED",
      shadowCandidate: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "VERIFIED" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });

  test("model and shadowCandidate are mutually exclusive on the same response", () => {
    const response = {
      ...validResponseBase(),
      decision: "MATCH",
      identityLevel: "EXACT_MODEL",
      model: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "VERIFIED" },
      shadowCandidate: { modelId: "m1", catalogVersion: "catalog-v1", textSupportStatus: "EXPERIMENTAL" },
    };
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(false);
  });
});
