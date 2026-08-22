import * as fs from "fs";
import * as path from "path";
import {
  P0CloudFeasibilityResult,
  P0CloudFeasibilityValidationError,
  assertValidP0CloudFeasibilityResult,
} from "../p0/cloud_feasibility";

function baseResult(overrides: Partial<P0CloudFeasibilityResult> = {}): P0CloudFeasibilityResult {
  return {
    sourceCommit: "0000000000000000000000000000000000000000",
    existingFunctionsRegion: "europe-west1",
    firestoreLocation: "eur3",
    vertexLocationTested: null,
    providerSelectionStatus: "DEFERRED_NO_SAFE_STAGING",
    embeddingProvider: null,
    embeddingModel: null,
    embeddingDimension: null,
    firestoreSdkVersion: null,
    vertexSdkVersion: null,
    firestoreVectorProbe: "NOT_ATTEMPTED",
    vertexEmbeddingProbe: "NOT_ATTEMPTED",
    appCheckCallableProbe: "NOT_ATTEMPTED",
    iamAssessment: "PARTIAL",
    latencyMs: null,
    costEvidence: null,
    dataResidencyAssessment: "No new residency decision made; Firestore stays eur3.",
    outcome: "OCR_TEXT_ONLY_DEFER_VISUAL",
    blockers: ["No safe non-production Firebase/GCP project exists."],
    evidence: [".firebaserc has only default + one unrelated legacy-shared alias."],
    ...overrides,
  };
}

describe("result schema", () => {
  it("accepts a well-formed OCR_TEXT_ONLY_DEFER_VISUAL result", () => {
    expect(() => assertValidP0CloudFeasibilityResult(baseResult())).not.toThrow();
  });

  it("rejects an unknown outcome value (impossible mixed state)", () => {
    const bad = baseResult({ outcome: "NOT_A_REAL_OUTCOME" as P0CloudFeasibilityResult["outcome"] });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("rejects an unknown probe status value", () => {
    const bad = baseResult({
      firestoreVectorProbe: "MAYBE" as P0CloudFeasibilityResult["firestoreVectorProbe"],
    });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("rejects an unknown providerSelectionStatus value", () => {
    const bad = baseResult({
      providerSelectionStatus: "MAYBE" as P0CloudFeasibilityResult["providerSelectionStatus"],
    });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});

describe("COLOCATED_VECTOR_FEASIBLE", () => {
  const colocatedBase = baseResult({
    outcome: "COLOCATED_VECTOR_FEASIBLE",
    providerSelectionStatus: "SELECTED_AND_PROBED",
    embeddingProvider: "vertex-ai",
    embeddingModel: "multimodalembedding@001",
    embeddingDimension: 512,
    firestoreVectorProbe: "PASS",
    vertexEmbeddingProbe: "PASS",
    appCheckCallableProbe: "PASS",
    iamAssessment: "KNOWN",
    firestoreSdkVersion: "@google-cloud/firestore@7.0.0",
    vertexSdkVersion: "@google-cloud/aiplatform@3.0.0",
    blockers: [],
  });

  it("accepts a genuinely-passing colocated result", () => {
    expect(() => assertValidP0CloudFeasibilityResult(colocatedBase)).not.toThrow();
  });

  it("cannot be returned with a required probe FAIL", () => {
    const bad = { ...colocatedBase, vertexEmbeddingProbe: "FAIL" as const };
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("credential/environment absence (NOT_ATTEMPTED) can never become PASS by omission", () => {
    const bad = { ...colocatedBase, vertexEmbeddingProbe: "NOT_ATTEMPTED" as const };
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("requires providerSelectionStatus=SELECTED_AND_PROBED", () => {
    const bad = { ...colocatedBase, providerSelectionStatus: "DEFERRED_NO_SAFE_STAGING" as const };
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("requires appCheckCallableProbe=PASS too, not just the two vector-path probes", () => {
    const bad = { ...colocatedBase, appCheckCallableProbe: "NOT_ATTEMPTED" as const };
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("rejects iamAssessment=UNKNOWN -- a passing probe with no idea which permissions let it pass", () => {
    const bad = { ...colocatedBase, iamAssessment: "UNKNOWN" as const };
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("requires firestoreSdkVersion and vertexSdkVersion to be recorded", () => {
    expect(() =>
      assertValidP0CloudFeasibilityResult({ ...colocatedBase, firestoreSdkVersion: null })
    ).toThrow(P0CloudFeasibilityValidationError);
    expect(() =>
      assertValidP0CloudFeasibilityResult({ ...colocatedBase, vertexSdkVersion: null })
    ).toThrow(P0CloudFeasibilityValidationError);
  });

  it("cannot record vertexLocationTested without vertexEmbeddingProbe actually having run", () => {
    const bad = baseResult({ vertexLocationTested: "us-central1" }); // vertexEmbeddingProbe stays NOT_ATTEMPTED
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});

describe("unknown iamAssessment", () => {
  it("is rejected regardless of outcome", () => {
    const bad = baseResult({ iamAssessment: "NOT_A_REAL_ASSESSMENT" as P0CloudFeasibilityResult["iamAssessment"] });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});

describe("SPLIT_REGION_REQUIRES_OPERATOR", () => {
  it("is always flagged as an operator decision", () => {
    const result = baseResult({
      outcome: "SPLIT_REGION_REQUIRES_OPERATOR",
      providerSelectionStatus: "REQUIRES_OPERATOR_DECISION",
      blockers: ["Vertex embedding is only available in a region that would split from eur3/europe-west1."],
    });
    expect(() => assertValidP0CloudFeasibilityResult(result)).not.toThrow();
  });

  it("rejects SPLIT_REGION without providerSelectionStatus=REQUIRES_OPERATOR_DECISION", () => {
    const bad = baseResult({
      outcome: "SPLIT_REGION_REQUIRES_OPERATOR",
      providerSelectionStatus: "DEFERRED_NO_SAFE_STAGING",
      blockers: ["some blocker"],
    });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("rejects SPLIT_REGION with zero recorded blockers", () => {
    const bad = baseResult({
      outcome: "SPLIT_REGION_REQUIRES_OPERATOR",
      providerSelectionStatus: "REQUIRES_OPERATOR_DECISION",
      blockers: [],
    });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});

describe("OCR_TEXT_ONLY_DEFER_VISUAL", () => {
  it("can close with every visual probe still NOT_ATTEMPTED -- it does not need KNN/Vertex results", () => {
    const result = baseResult();
    expect(result.firestoreVectorProbe).toBe("NOT_ATTEMPTED");
    expect(result.vertexEmbeddingProbe).toBe("NOT_ATTEMPTED");
    expect(result.appCheckCallableProbe).toBe("NOT_ATTEMPTED");
    expect(() => assertValidP0CloudFeasibilityResult(result)).not.toThrow();
  });

  it("must not record a selected embedding provider/model/dimension", () => {
    const bad = baseResult({ embeddingProvider: "vertex-ai" });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("the deferred-provider invariant holds for provider, model, and dimension independently", () => {
    expect(() =>
      assertValidP0CloudFeasibilityResult(baseResult({ embeddingModel: "multimodalembedding@001" }))
    ).toThrow(P0CloudFeasibilityValidationError);
    expect(() => assertValidP0CloudFeasibilityResult(baseResult({ embeddingDimension: 512 }))).toThrow(
      P0CloudFeasibilityValidationError
    );
  });

  it("cannot claim providerSelectionStatus=SELECTED_AND_PROBED -- visual cannot be both deferred and already probed", () => {
    const bad = baseResult({ providerSelectionStatus: "SELECTED_AND_PROBED" });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("requires at least one recorded blocker -- 'deferred' with no reason is not an honest record", () => {
    const bad = baseResult({ blockers: [] });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});

describe("the committed P0.G5 probe result", () => {
  it("is itself a valid result under this module's own invariants", () => {
    const resultPath = path.join(
      __dirname,
      "..",
      "..",
      "..",
      "core",
      "equipment_identity",
      "p0",
      "p0_g5_probe_result.json"
    );
    const raw = fs.readFileSync(resultPath, "utf-8");
    const parsed = JSON.parse(raw) as P0CloudFeasibilityResult;
    expect(parsed.outcome).toBe("OCR_TEXT_ONLY_DEFER_VISUAL");
    expect(() => assertValidP0CloudFeasibilityResult(parsed)).not.toThrow();
  });
});

describe("secret-like strings", () => {
  it("refuses to validate a result whose evidence contains something that looks like a live API key", () => {
    const bad = baseResult({ evidence: ["key=AIzaSyD-FAKE1234567890ABCDEFGHIJKLMNOPQ"] });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("refuses to validate a result whose blockers contain something that looks like an OAuth access token", () => {
    const bad = baseResult({ blockers: ["ya29.FAKE1234567890ABCDEFGHIJKLMNOPQRSTUVWXYZ"] });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });

  it("refuses to validate a result whose costEvidence contains something that looks like a private key block", () => {
    const bad = baseResult({ costEvidence: "-----BEGIN PRIVATE KEY-----\nMIIFAKE\n-----END PRIVATE KEY-----" });
    expect(() => assertValidP0CloudFeasibilityResult(bad)).toThrow(P0CloudFeasibilityValidationError);
  });
});
