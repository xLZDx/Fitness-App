/**
 * P2.G5-readiness step 2 -- unit tests for `identity_handler.ts`'s OWN
 * wiring (GPT-PM MAJOR, retrospective review of commit afca346,
 * 2026-09-15: this wiring previously had zero regression coverage --
 * every existing test either called `resolveEquipmentIdentityFromText`
 * directly, bypassing telemetry entirely, or called
 * `recordServerTerminalTelemetry` directly, bypassing the handler). Both
 * collaborators are mocked so these tests prove the WIRING -- request
 * validation happens first, the telemetry call receives exactly the
 * server-owned uid/response.scanId/response, and a telemetry failure never
 * reaches the caller -- independent of either collaborator's own business
 * rules, which already have dedicated suites (`orchestrator.test.ts`,
 * `__e2e__/telemetry_repository.e2e.test.ts`). The real end-to-end wiring
 * against a real Firestore emulator is proven separately by
 * `__e2e__/identity_handler.e2e.test.ts`.
 */
jest.mock("../orchestrator", () => ({ resolveEquipmentIdentityFromText: jest.fn() }));
jest.mock("../telemetry_repository", () => ({ recordServerTerminalTelemetry: jest.fn() }));

import { resolveEquipmentIdentityAndRecordTelemetry } from "../identity_handler";
import { resolveEquipmentIdentityFromText } from "../orchestrator";
import { recordServerTerminalTelemetry } from "../telemetry_repository";
import { CURRENT_IDENTITY_CONTRACT_VERSION } from "../contract";

const mResolve = resolveEquipmentIdentityFromText as jest.Mock;
const mRecordTelemetry = recordServerTerminalTelemetry as jest.Mock;

function validRawRequest(overrides: Partial<Record<string, unknown>> = {}) {
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
  };
}

function matchResponse(overrides: Partial<Record<string, unknown>> = {}) {
  return {
    scanId: "scan-1",
    recognitionSessionId: "session-1",
    identityContractVersion: CURRENT_IDENTITY_CONTRACT_VERSION,
    authority: {
      catalogVersion: "catalog-v1",
      ocrVersion: "ocr-1.0.0",
      textPolicyVersion: "p2g3-text-exact-v1",
      fusionPolicyVersion: "none",
      identityPolicyVersion: "p2g3-text-exact-v1",
    },
    evidenceLane: "TEXT_ONLY",
    decision: "MATCH",
    identityLevel: "EXACT_MODEL",
    model: {
      modelId: "11111111-1111-4111-8111-111111111111",
      catalogVersion: "catalog-v1",
      textSupportStatus: "VERIFIED",
    },
    verifierInvoked: false,
    ...overrides,
  };
}

beforeEach(() => {
  jest.clearAllMocks();
  mResolve.mockResolvedValue(matchResponse());
  mRecordTelemetry.mockResolvedValue(undefined);
});

describe("resolveEquipmentIdentityAndRecordTelemetry -- request validation runs before anything else", () => {
  test("a malformed request never reaches the orchestrator or the telemetry writer", async () => {
    await expect(
      resolveEquipmentIdentityAndRecordTelemetry("u1", { not: "a valid request" }),
    ).rejects.toThrow();
    expect(mResolve).not.toHaveBeenCalled();
    expect(mRecordTelemetry).not.toHaveBeenCalled();
  });

  // GPT-PM MAJOR (retrospective review of commit afca346, round 3,
  // 2026-09-15): the persistence-boundary backstop alone left a
  // contract-valid, Firestore-unsafe scanId able to reach a real identity
  // response while silently losing its telemetry record. The contract
  // schema itself must now reject it before the orchestrator ever runs.
  test("a scanId containing '/' is rejected at the CONTRACT boundary -- the orchestrator never runs", async () => {
    await expect(
      resolveEquipmentIdentityAndRecordTelemetry("u1", validRawRequest({ scanId: "scan/../other" })),
    ).rejects.toThrow();
    expect(mResolve).not.toHaveBeenCalled();
    expect(mRecordTelemetry).not.toHaveBeenCalled();
  });

  test("a scanId containing '--' is NOT rejected -- it is not part of the unrelated {catalogVersion}--{entityId} composite scheme", async () => {
    const response = matchResponse({ scanId: "scan--123" });
    mResolve.mockResolvedValue(response);

    const result = await resolveEquipmentIdentityAndRecordTelemetry("u1", validRawRequest({ scanId: "scan--123" }));
    expect(result).toEqual(response);
    expect(mRecordTelemetry).toHaveBeenCalledWith("u1", "scan--123", response);
  });
});

describe("resolveEquipmentIdentityAndRecordTelemetry -- telemetry wiring", () => {
  test("records telemetry with the server-owned uid, the RESPONSE's own scanId, and the full response", async () => {
    const response = matchResponse({ scanId: "scan-returned" });
    mResolve.mockResolvedValue(response);

    const result = await resolveEquipmentIdentityAndRecordTelemetry("u1", validRawRequest({ scanId: "scan-1" }));

    expect(result).toEqual(response);
    expect(mRecordTelemetry).toHaveBeenCalledTimes(1);
    expect(mRecordTelemetry).toHaveBeenCalledWith("u1", "scan-returned", response);
  });

  test("passes the authenticated uid, not any client-supplied field, to the orchestrator", async () => {
    await resolveEquipmentIdentityAndRecordTelemetry("server-owned-uid", validRawRequest());
    expect(mResolve).toHaveBeenCalledWith({ uid: "server-owned-uid", request: expect.any(Object) });
  });

  // GPT-PM MAJOR, retrospective review of commit afca346, 2026-09-15: the
  // real `recordServerTerminalTelemetry` already never throws (see its own
  // doc comment), but nothing previously proved that a regression there
  // -- or a bug in a future change to it -- cannot turn a real identity
  // response the caller is waiting on into a 500. Mocking a rejection here
  // exercises the handler's own defense-in-depth swallow, independent of
  // whether the real writer still upholds its side of the contract.
  test("a telemetry write failure never propagates -- the identity response is still returned", async () => {
    const response = matchResponse();
    mResolve.mockResolvedValue(response);
    mRecordTelemetry.mockRejectedValue(new Error("firestore outage"));

    const result = await resolveEquipmentIdentityAndRecordTelemetry("u1", validRawRequest());
    expect(result).toEqual(response);
  });

  test("an orchestrator failure IS allowed to propagate -- only the telemetry step is defended", async () => {
    mResolve.mockRejectedValue(new Error("orchestrator outage"));
    await expect(resolveEquipmentIdentityAndRecordTelemetry("u1", validRawRequest())).rejects.toThrow(
      "orchestrator outage",
    );
    expect(mRecordTelemetry).not.toHaveBeenCalled();
  });
});
