/**
 * P2.G3 -- unit tests for the orchestrator's OWN wiring/branching logic:
 * contract negotiation -> admission (session ownership/latest-scan
 * ordering/quota, all atomic) -> catalog pointer -> lookup -> policy ->
 * lane mapping -> revocation re-check -> finalize -> response assembly.
 *
 * Every collaborator is mocked so these tests isolate the orchestrator's
 * decisions from each collaborator's own business rules, which already
 * have dedicated suites (exact_resolution_policy.test.ts's tests cover
 * policy correctness; text_key_index.test.ts covers lookup/materialization;
 * session_repository's own transaction semantics are proven for real
 * against a Firestore emulator in src/__e2e__/session_repository.e2e.test.ts).
 * The real end-to-end wiring (actual Firestore reads/writes agreeing with
 * each other) is proven separately by src/__e2e__/orchestrator.e2e.test.ts.
 */
jest.mock("../catalog_reader", () => ({
  fetchActiveCatalogPointer: jest.fn(),
  fetchModelFields: jest.fn(),
  checkModelStillEligibleForExact: jest.fn(),
  verifyActiveCatalogVersionStillCurrent: jest.fn(),
}));
jest.mock("../text_key_index", () => ({ resolveModelCodeLookup: jest.fn() }));
jest.mock("../exact_resolution_policy", () => ({ evaluateExactResolutionPolicy: jest.fn() }));
jest.mock("../session_repository", () => ({
  admitSessionClaim: jest.fn(),
  finalizeSessionOutcome: jest.fn(),
  readSession: jest.fn(),
  readLatestSession: jest.fn(),
}));
jest.mock("../app_check_readiness", () => ({
  loadAppCheckPlatformReadiness: jest.fn(),
  resolveAppCheckEnforcement: jest.fn(),
}));

import { resolveEquipmentIdentityFromText } from "../orchestrator";
import {
  fetchActiveCatalogPointer,
  fetchModelFields,
  checkModelStillEligibleForExact,
  verifyActiveCatalogVersionStillCurrent,
} from "../catalog_reader";
import { resolveModelCodeLookup } from "../text_key_index";
import { evaluateExactResolutionPolicy } from "../exact_resolution_policy";
import { admitSessionClaim, finalizeSessionOutcome, readSession, readLatestSession } from "../session_repository";
import { loadAppCheckPlatformReadiness, resolveAppCheckEnforcement } from "../app_check_readiness";
import { CURRENT_IDENTITY_CONTRACT_VERSION, EquipmentIdentityResponseSchema } from "../contract";

const mFetchPointer = fetchActiveCatalogPointer as jest.Mock;
const mFetchModelFields = fetchModelFields as jest.Mock;
const mCheckEligible = checkModelStillEligibleForExact as jest.Mock;
const mVerifyPointerCurrent = verifyActiveCatalogVersionStillCurrent as jest.Mock;
const mResolveLookup = resolveModelCodeLookup as jest.Mock;
const mEvaluatePolicy = evaluateExactResolutionPolicy as jest.Mock;
const mAdmit = admitSessionClaim as jest.Mock;
const mFinalize = finalizeSessionOutcome as jest.Mock;
const mReadSession = readSession as jest.Mock;
const mReadLatestSession = readLatestSession as jest.Mock;
const mLoadReadiness = loadAppCheckPlatformReadiness as jest.Mock;
const mResolveEnforcement = resolveAppCheckEnforcement as jest.Mock;

const MODEL_ID = "11111111-1111-4111-8111-111111111111";
const CATALOG_VERSION = "catalog-v1";

function baseRequest(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    scanId: "scan-1",
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    clientCapabilities: [],
    evidence: {
      brandCandidates: [],
      productLineCandidates: [],
      modelCodeCandidates: ["8TRX"],
      typeHints: [],
      conflicts: [],
    },
    ocrVersion: "ocr-1.0.0",
    ...overrides,
  } as never;
}

function resolvedRecord(overrides: Partial<{ requestFingerprint: string; textSupportStatus: "EXPERIMENTAL" | "VERIFIED"; modelId: string }> = {}) {
  return {
    schemaVersion: 1,
    status: "RESOLVED",
    scanId: "scan-1",
    requestFingerprint: overrides.requestFingerprint ?? "fp-1",
    authority: {
      catalogVersion: CATALOG_VERSION,
      ocrVersion: "ocr-1.0.0",
      textPolicyVersion: "p2g3-text-exact-v1",
      fusionPolicyVersion: "none",
      identityPolicyVersion: "p2g3-text-exact-v1",
    },
    createdAt: "now",
    matchOutcome: {
      modelId: overrides.modelId ?? MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: overrides.textSupportStatus ?? "VERIFIED",
    },
  } as const;
}

beforeEach(() => {
  jest.clearAllMocks();
  // Default admission: a fresh claim, always granted -- most tests exercise
  // the ADMITTED pipeline path unless they override this.
  mAdmit.mockResolvedValue({ outcome: "ADMITTED", claimId: "claim-1" });
  // Mirrors the REAL finalizeSessionOutcome's RESOLVED branch: the returned
  // record's matchOutcome is exactly what THIS call was invoked with. This
  // is deliberate, not incidental -- the orchestrator's own TOCTOU-defense
  // (GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11, preserved
  // through round 3's admission/finalize redesign) means the final response
  // is built from what this function RETURNS, so a test that wants to prove
  // that discipline must be able to make the two diverge -- see the
  // dedicated "returned record wins over local computation" tests below,
  // which override this default with a genuinely different matchOutcome.
  mFinalize.mockImplementation(
    (
      _uid: string,
      _sessionId: string,
      authority: unknown,
      outcome: { requestFingerprint: string; matchOutcome: unknown },
    ) =>
      Promise.resolve({
        outcome: "RESOLVED",
        record: {
          schemaVersion: 1,
          status: "RESOLVED",
          scanId: "scan-1",
          requestFingerprint: outcome.requestFingerprint,
          authority,
          createdAt: "now",
          matchOutcome: outcome.matchOutcome,
        },
      }),
  );
  mReadSession.mockResolvedValue(null);
  mReadLatestSession.mockResolvedValue(null);
  mFetchPointer.mockResolvedValue({ activeCatalogVersion: CATALOG_VERSION });
  mResolveLookup.mockResolvedValue({ outcome: "UNIQUE", modelId: MODEL_ID, keyKinds: ["MODEL_CODE"] });
  mFetchModelFields.mockResolvedValue({
    modelId: MODEL_ID,
    catalogVersion: CATALOG_VERSION,
    textSupportStatus: "VERIFIED",
    primaryTypeId: "leg_press",
    supportedTypeIds: ["leg_press"],
  });
  mEvaluatePolicy.mockReturnValue({ outcome: "EXACT_PRODUCTION", modelId: MODEL_ID, catalogVersion: CATALOG_VERSION });
  mCheckEligible.mockResolvedValue({ eligible: true });
  mVerifyPointerCurrent.mockResolvedValue(true);
  mLoadReadiness.mockReturnValue({ status: "BLOCKED_EXTERNAL_PLATFORM_MIGRATION" });
  mResolveEnforcement.mockReturnValue(false);
});

afterEach(() => {
  jest.useRealTimers();
});

describe("resolveEquipmentIdentityFromText -- contract negotiation runs before admission", () => {
  test("an unsupported contract version -> UNSUPPORTED_CLIENT_CONTRACT, never attempts admission", async () => {
    const response = await resolveEquipmentIdentityFromText({
      uid: "u1",
      request: baseRequest({ identityContractVersion: "v99" }),
    });
    expect(response.decision).toBe("UNSUPPORTED_CLIENT_CONTRACT");
    expect(response.abstainReason).toBeUndefined();
    expect(response.failureCode).toBeUndefined();
    expect(mAdmit).not.toHaveBeenCalled();
    expect(mFetchPointer).not.toHaveBeenCalled();
  });
});

describe("resolveEquipmentIdentityFromText -- admission error boundary", () => {
  test("a thrown admission attempt -> UNAVAILABLE_BACKEND, never reaches the pipeline", async () => {
    mAdmit.mockRejectedValue(new Error("firestore outage"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
    expect(mFetchPointer).not.toHaveBeenCalled();
  });
});

describe("resolveEquipmentIdentityFromText -- admission: RATE_LIMITED", () => {
  test("-> UNAVAILABLE_RATE_LIMIT/RATE_LIMITED, never consults the catalog", async () => {
    mAdmit.mockResolvedValue({ outcome: "RATE_LIMITED" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_RATE_LIMIT");
    expect(response.failureCode).toBe("RATE_LIMITED");
    expect(response.authority.catalogVersion).toBe("unresolved");
    expect(mFetchPointer).not.toHaveBeenCalled();
  });
});

describe("resolveEquipmentIdentityFromText -- admission: STALE", () => {
  test("-> CANCELLED_STALE immediately, no pipeline, no finalize", async () => {
    mAdmit.mockResolvedValue({ outcome: "STALE" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("CANCELLED_STALE");
    expect(mFetchPointer).not.toHaveBeenCalled();
    expect(mFinalize).not.toHaveBeenCalled();
  });
});

describe("resolveEquipmentIdentityFromText -- admission: REPLAY", () => {
  test("still latest and still eligible -> replays the stored MATCH, never re-runs the pipeline", async () => {
    const record = resolvedRecord();
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("MATCH");
    expect(response.model).toEqual(record.matchOutcome);
    expect(mFetchPointer).not.toHaveBeenCalled();
    expect(mFinalize).not.toHaveBeenCalled();
    expect(mCheckEligible).toHaveBeenCalledWith(CATALOG_VERSION, MODEL_ID, "VERIFIED");
  });

  test("still latest but the pinned outcome is no longer eligible -> UNAVAILABLE_CATALOG_VERSION, fails closed instead of replaying a stale MATCH", async () => {
    const record = resolvedRecord();
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record });
    mCheckEligible.mockResolvedValue({ eligible: false, reason: "revoked" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(response.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
    expect(response.model).toBeUndefined();
  });

  test("a genuinely newer scan is now this uid's latest -> CANCELLED_STALE, never replays a superseded scan", async () => {
    const record = resolvedRecord();
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record });
    mReadLatestSession.mockResolvedValue({
      recognitionSessionId: "some-other-newer-session-id",
      scanId: "scan-2",
      pinnedAt: "later",
    });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("CANCELLED_STALE");
    expect(mCheckEligible).not.toHaveBeenCalled();
  });

  test("readLatestSession throwing -> UNAVAILABLE_BACKEND", async () => {
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record: resolvedRecord() });
    mReadLatestSession.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("the eligibility re-check throwing -> UNAVAILABLE_BACKEND", async () => {
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record: resolvedRecord() });
    mCheckEligible.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("an EXPERIMENTAL replayed outcome -> NOT_SUPPORTED + shadowCandidate, never a MATCH", async () => {
    const record = resolvedRecord({ textSupportStatus: "EXPERIMENTAL" });
    mAdmit.mockResolvedValue({ outcome: "REPLAY", record });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(response.model).toBeUndefined();
    expect(response.shadowCandidate).toEqual(record.matchOutcome);
  });
});

describe("resolveEquipmentIdentityFromText -- admission: WAIT (a genuinely concurrent identical duplicate)", () => {
  test("polling observes the winner's RESOLVED outcome -> replays it, still latest and eligible", async () => {
    jest.useFakeTimers();
    mAdmit.mockResolvedValue({ outcome: "WAIT" });
    const record = resolvedRecord();
    let pollCount = 0;
    mReadSession.mockImplementation(() => {
      pollCount += 1;
      return Promise.resolve(pollCount < 3 ? { status: "PENDING" } : record);
    });

    const responsePromise = resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    await jest.advanceTimersByTimeAsync(1000);
    const response = await responsePromise;

    expect(response.decision).toBe("MATCH");
    expect(response.model).toEqual(record.matchOutcome);
    expect(mFetchPointer).not.toHaveBeenCalled();
    expect(pollCount).toBeGreaterThanOrEqual(3);
  });

  test("polling observes the winner's claim was SUPERSEDED -> CANCELLED_STALE", async () => {
    jest.useFakeTimers();
    mAdmit.mockResolvedValue({ outcome: "WAIT" });
    mReadSession.mockResolvedValue({ status: "SUPERSEDED", scanId: "scan-1", requestFingerprint: "fp-1", createdAt: "now" });

    const responsePromise = resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    await jest.advanceTimersByTimeAsync(500);
    const response = await responsePromise;

    expect(response.decision).toBe("CANCELLED_STALE");
  });

  test("the wait window elapses with no resolution -> UNAVAILABLE_TIMEOUT/TIMEOUT", async () => {
    jest.useFakeTimers();
    mAdmit.mockResolvedValue({ outcome: "WAIT" });
    mReadSession.mockResolvedValue({ status: "PENDING" });

    const responsePromise = resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    await jest.advanceTimersByTimeAsync(5000);
    const response = await responsePromise;

    expect(response.decision).toBe("UNAVAILABLE_TIMEOUT");
    expect(response.failureCode).toBe("TIMEOUT");
  });

  test("a thrown poll read -> UNAVAILABLE_BACKEND", async () => {
    jest.useFakeTimers();
    mAdmit.mockResolvedValue({ outcome: "WAIT" });
    mReadSession.mockRejectedValue(new Error("emulator down"));

    const responsePromise = resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    await jest.advanceTimersByTimeAsync(500);
    const response = await responsePromise;

    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });
});

describe("resolveEquipmentIdentityFromText -- Firestore I/O error boundaries (GPT-PM MAJOR, 2026-09-11)", () => {
  test("a thrown active-pointer read -> UNAVAILABLE_BACKEND, not an unhandled rejection", async () => {
    mFetchPointer.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("a thrown candidate lookup -> UNAVAILABLE_BACKEND", async () => {
    mResolveLookup.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("a thrown model-fields fetch -> UNAVAILABLE_BACKEND", async () => {
    mFetchModelFields.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("a thrown pre-emission eligibility check -> UNAVAILABLE_BACKEND", async () => {
    mCheckEligible.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("a thrown active-pointer re-verification at the pre-emission stage -> UNAVAILABLE_BACKEND", async () => {
    mVerifyPointerCurrent.mockRejectedValue(new Error("emulator down"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });
});

describe("resolveEquipmentIdentityFromText -- pre-emission pointer re-verification (GPT-PM MAJOR, 2026-09-11)", () => {
  test("the active pointer having moved to a different catalogVersion blocks emission -> UNAVAILABLE_CATALOG_VERSION, never finalizes", async () => {
    mVerifyPointerCurrent.mockResolvedValue(false);
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(response.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
    expect(mFinalize).not.toHaveBeenCalled();
  });

  test("re-verifies against the SAME catalogVersion the model eligibility check uses", async () => {
    await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(mVerifyPointerCurrent).toHaveBeenCalledWith(CATALOG_VERSION);
  });
});

describe("resolveEquipmentIdentityFromText -- policy-outcome to decision mapping", () => {
  test("EXACT_PRODUCTION -> MATCH/EXACT_MODEL, finalizes with textSupportStatus VERIFIED", async () => {
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("MATCH");
    expect(response.identityLevel).toBe("EXACT_MODEL");
    expect(response.verifierInvoked).toBe(false);
    expect(response.shadowCandidate).toBeUndefined();
    expect(response.model).toEqual({
      modelId: MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: "VERIFIED",
    });
    expect(mCheckEligible).toHaveBeenCalledWith(CATALOG_VERSION, MODEL_ID, "VERIFIED");
    expect(mFinalize).toHaveBeenCalledTimes(1);
  });

  // GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11 (correcting
  // round 1's own matchAuthority side-channel remediation): a shadow-only
  // (EXPERIMENTAL) exact resolution must never be represented as a MATCH --
  // v4.4 binds MATCH/EXACT_MODEL to VERIFIED text support only. It still
  // gets finalized (shadow evidence gathering keeps running), but the
  // RESPONSE is NOT_SUPPORTED with a separate, explicitly non-authoritative
  // shadowCandidate.
  test("EXACT_SHADOW_ONLY while not production-ready -> NOT_SUPPORTED + shadowCandidate, never a MATCH", async () => {
    mEvaluatePolicy.mockReturnValue({
      outcome: "EXACT_SHADOW_ONLY",
      modelId: MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      reason: "EXPERIMENTAL_TEXT_SUPPORT",
    });
    mResolveEnforcement.mockReturnValue(false);
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(response.model).toBeUndefined();
    expect(response.shadowCandidate).toEqual({
      modelId: MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: "EXPERIMENTAL",
    });
    expect(mCheckEligible).toHaveBeenCalledWith(CATALOG_VERSION, MODEL_ID, "EXPERIMENTAL");
    expect(mFinalize).toHaveBeenCalledTimes(1);
  });

  test("EXACT_SHADOW_ONLY once production-ready -> NOT_SUPPORTED, never re-checks or finalizes", async () => {
    mEvaluatePolicy.mockReturnValue({
      outcome: "EXACT_SHADOW_ONLY",
      modelId: MODEL_ID,
      catalogVersion: CATALOG_VERSION,
      reason: "EXPERIMENTAL_TEXT_SUPPORT",
    });
    mResolveEnforcement.mockReturnValue(true);
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(mCheckEligible).not.toHaveBeenCalled();
    expect(mFinalize).not.toHaveBeenCalled();
  });

  test("NEED_MORE_VIEW passes through unchanged", async () => {
    mEvaluatePolicy.mockReturnValue({ outcome: "NEED_MORE_VIEW", reason: "type conflict" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NEED_MORE_VIEW");
    expect(mFinalize).not.toHaveBeenCalled();
  });

  test("ABSTAIN carries its abstainReason through", async () => {
    mEvaluatePolicy.mockReturnValue({
      outcome: "ABSTAIN",
      abstainReason: "EVIDENCE_CONFLICT",
      reason: "two candidates disagree",
    });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("ABSTAIN");
    expect(response.abstainReason).toBe("EVIDENCE_CONFLICT");
  });

  test("NOT_ELIGIBLE maps to NOT_SUPPORTED", async () => {
    mEvaluatePolicy.mockReturnValue({ outcome: "NOT_ELIGIBLE", reason: "no code resolved" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
  });
});

describe("resolveEquipmentIdentityFromText -- generic type-evidence threading (GPT-PM MAJOR, 2026-09-11; #7 stays OPEN per round 2)", () => {
  test("no typeHints -> evaluateExactResolutionPolicy receives typeEvidence: undefined", async () => {
    await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(mEvaluatePolicy).toHaveBeenCalledWith(expect.objectContaining({ typeEvidence: undefined }));
  });

  test("a single typeHint -> LOW_CONFIDENCE, never vetoes a real match", async () => {
    const response = await resolveEquipmentIdentityFromText({
      uid: "u1",
      request: baseRequest({
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["8TRX"],
          typeHints: ["treadmill"],
          conflicts: [],
        },
      }),
    });
    expect(mEvaluatePolicy).toHaveBeenCalledWith(
      expect.objectContaining({ typeEvidence: { status: "LOW_CONFIDENCE", typeId: "TREADMILL" } }),
    );
    expect(response.decision).toBe("MATCH");
  });

  test("multiple distinct typeHints -> AMBIGUOUS, never HIGH_ASSURANCE/VERIFIED (no typeId-vocabulary alignment to assert that from OCR text alone)", async () => {
    await resolveEquipmentIdentityFromText({
      uid: "u1",
      request: baseRequest({
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["8TRX"],
          typeHints: ["treadmill", "elliptical"],
          conflicts: [],
        },
      }),
    });
    const call = mEvaluatePolicy.mock.calls[0][0];
    expect(call.typeEvidence.status).toBe("AMBIGUOUS");
    expect(["HIGH_ASSURANCE", "VERIFIED"]).not.toContain(call.typeEvidence.status);
  });
});

describe("resolveEquipmentIdentityFromText -- pre-emission revocation and finalize", () => {
  test("a failed pre-emission eligibility re-check blocks emission -> UNAVAILABLE_CATALOG_VERSION, never finalizes", async () => {
    mCheckEligible.mockResolvedValue({ eligible: false, reason: "downgraded" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_CATALOG_VERSION");
    expect(response.failureCode).toBe("CATALOG_VERSION_UNAVAILABLE");
    expect(mFinalize).not.toHaveBeenCalled();
  });

  test("a generic finalize failure -> UNAVAILABLE_BACKEND, never claims MATCH", async () => {
    mFinalize.mockRejectedValue(new Error("firestore outage"));
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("UNAVAILABLE_BACKEND");
    expect(response.failureCode).toBe("BACKEND_ERROR");
  });

  test("finalize reporting SUPERSEDED (a genuinely newer scan won while this pipeline ran) -> CANCELLED_STALE, not a generic backend error", async () => {
    mFinalize.mockResolvedValue({ outcome: "SUPERSEDED" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("CANCELLED_STALE");
    expect(response.failureCode).toBeUndefined();
  });

  test("finalize reporting ABANDONED (defensive-only) -> CANCELLED_STALE, never overwrites whatever actually won", async () => {
    mFinalize.mockResolvedValue({ outcome: "ABANDONED" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("CANCELLED_STALE");
  });

  test("finalizes under the caller's own uid, the derived recognitionSessionId, and the request fingerprint/outcome", async () => {
    const response = await resolveEquipmentIdentityFromText({ uid: "u-alice", request: baseRequest() });
    expect(mFinalize).toHaveBeenCalledWith(
      "u-alice",
      response.recognitionSessionId,
      expect.objectContaining({ catalogVersion: CATALOG_VERSION }),
      expect.objectContaining({
        requestFingerprint: expect.any(String),
        claimId: "claim-1",
        matchOutcome: { modelId: MODEL_ID, catalogVersion: CATALOG_VERSION, textSupportStatus: "VERIFIED" },
      }),
    );
  });

  test("the same (uid, scanId) always derives the SAME recognitionSessionId (deterministic, not randomUUID)", async () => {
    const r1 = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    const r2 = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(r1.recognitionSessionId).toBe(r2.recognitionSessionId);
  });

  test("a different scanId under the same uid derives a DIFFERENT recognitionSessionId", async () => {
    const r1 = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest({ scanId: "scan-a" }) });
    const r2 = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest({ scanId: "scan-b" }) });
    expect(r1.recognitionSessionId).not.toBe(r2.recognitionSessionId);
  });
});

// GPT-PM MAJOR, P2.G3 pre-commit review round 2, 2026-09-11 (preserved
// through round 3's admission/finalize redesign): `authority` alone does
// not encode `modelId`, so the orchestrator must answer with whatever
// `finalizeSessionOutcome` actually returned, never with its own
// locally-computed guess.
describe("resolveEquipmentIdentityFromText -- TOCTOU defense: response is built from finalize's RETURNED record", () => {
  test("when finalize returns a DIFFERENT outcome than locally computed, the response reflects the RETURNED one", async () => {
    const winnerModelId = "22222222-2222-4222-8222-222222222222";
    mFinalize.mockResolvedValue({
      outcome: "RESOLVED",
      record: {
        schemaVersion: 1,
        status: "RESOLVED",
        scanId: "scan-1",
        requestFingerprint: "winner-fp",
        authority: { catalogVersion: CATALOG_VERSION },
        createdAt: "now",
        matchOutcome: { modelId: winnerModelId, catalogVersion: CATALOG_VERSION, textSupportStatus: "VERIFIED" },
      },
    });

    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("MATCH");
    expect(response.model).toEqual({
      modelId: winnerModelId,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: "VERIFIED",
    });
    expect(response.model?.modelId).not.toBe(MODEL_ID);
  });

  test("when finalize's returned outcome is EXPERIMENTAL, the response is NOT_SUPPORTED + shadowCandidate, not a MATCH", async () => {
    const winnerModelId = "22222222-2222-4222-8222-222222222222";
    mFinalize.mockResolvedValue({
      outcome: "RESOLVED",
      record: {
        schemaVersion: 1,
        status: "RESOLVED",
        scanId: "scan-1",
        requestFingerprint: "winner-fp",
        authority: { catalogVersion: CATALOG_VERSION },
        createdAt: "now",
        matchOutcome: { modelId: winnerModelId, catalogVersion: CATALOG_VERSION, textSupportStatus: "EXPERIMENTAL" },
      },
    });

    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(response.decision).toBe("NOT_SUPPORTED");
    expect(response.model).toBeUndefined();
    expect(response.shadowCandidate).toEqual({
      modelId: winnerModelId,
      catalogVersion: CATALOG_VERSION,
      textSupportStatus: "EXPERIMENTAL",
    });
  });
});

describe("resolveEquipmentIdentityFromText -- candidate dedup and response shape", () => {
  test("duplicate raw candidates are resolved only once each", async () => {
    await resolveEquipmentIdentityFromText({
      uid: "u1",
      request: baseRequest({
        evidence: {
          brandCandidates: [],
          productLineCandidates: [],
          modelCodeCandidates: ["8TRX", "8TRX", "8TRX"],
          typeHints: [],
          conflicts: [],
        },
      }),
    });
    expect(mResolveLookup).toHaveBeenCalledTimes(1);
  });

  test("every terminal response satisfies EquipmentIdentityResponseSchema", async () => {
    // Covers every ExactPolicyResult outcome variant, including BOTH
    // EXACT_SHADOW_ONLY sub-branches (readiness true/false).
    const scenarios: Array<() => void> = [
      () => mEvaluatePolicy.mockReturnValue({ outcome: "EXACT_PRODUCTION", modelId: MODEL_ID, catalogVersion: CATALOG_VERSION }),
      () => mEvaluatePolicy.mockReturnValue({ outcome: "NOT_ELIGIBLE", reason: "x" }),
      () =>
        mEvaluatePolicy.mockReturnValue({
          outcome: "ABSTAIN",
          abstainReason: "LOW_CONFIDENCE",
          reason: "x",
        }),
      () => mEvaluatePolicy.mockReturnValue({ outcome: "NEED_MORE_VIEW", reason: "x" }),
      () => {
        mEvaluatePolicy.mockReturnValue({
          outcome: "EXACT_SHADOW_ONLY",
          modelId: MODEL_ID,
          catalogVersion: CATALOG_VERSION,
          reason: "EXPERIMENTAL_TEXT_SUPPORT",
        });
        mResolveEnforcement.mockReturnValue(false);
      },
      () => {
        mEvaluatePolicy.mockReturnValue({
          outcome: "EXACT_SHADOW_ONLY",
          modelId: MODEL_ID,
          catalogVersion: CATALOG_VERSION,
          reason: "EXPERIMENTAL_TEXT_SUPPORT",
        });
        mResolveEnforcement.mockReturnValue(true);
      },
    ];
    for (const setup of scenarios) {
      setup();
      const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
      const parsed = EquipmentIdentityResponseSchema.safeParse(response);
      expect(parsed.success).toBe(true);
    }
  });

  test("a CANCELLED_STALE response also satisfies EquipmentIdentityResponseSchema", async () => {
    mFinalize.mockResolvedValue({ outcome: "SUPERSEDED" });
    const response = await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });
    expect(EquipmentIdentityResponseSchema.safeParse(response).success).toBe(true);
  });
});

describe("resolveEquipmentIdentityFromText -- exhaustiveness guard and dangling-index logging", () => {
  test("an unrecognized ExactPolicyResult outcome throws rather than silently defaulting to NOT_SUPPORTED", async () => {
    mEvaluatePolicy.mockReturnValue({ outcome: "SOME_FUTURE_OUTCOME_NOBODY_HANDLES_YET" });
    await expect(
      resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() }),
    ).rejects.toThrow(/unhandled ExactPolicyResult outcome/);
  });

  test("a UNIQUE-resolved modelId with no catalog fields logs a dangling-index-entry error, not silence", async () => {
    const logger = await import("firebase-functions/logger");
    const errorSpy = jest.spyOn(logger, "error").mockImplementation(() => undefined);
    mFetchModelFields.mockResolvedValue(null);
    mEvaluatePolicy.mockReturnValue({ outcome: "NOT_ELIGIBLE", reason: "no fields" });

    await resolveEquipmentIdentityFromText({ uid: "u1", request: baseRequest() });

    expect(errorSpy).toHaveBeenCalledWith(
      "equipment_identity_dangling_text_key_index_entry",
      expect.objectContaining({ modelId: MODEL_ID, catalogVersion: CATALOG_VERSION }),
    );
    errorSpy.mockRestore();
  });
});
