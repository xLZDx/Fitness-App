/**
 * P2.G5-readiness step 3a -- unit tests for `telemetry_handler.ts`'s OWN
 * wiring, mirroring `identity_handler.test.ts`'s own rationale: the
 * repository is mocked so these tests prove request validation runs first
 * and the repository call receives exactly the server-owned uid plus the
 * parsed report, independent of the repository's own merge-rule business
 * logic (covered separately by `__e2e__/telemetry_repository.e2e.test.ts`).
 */
jest.mock("../telemetry_repository", () => ({ recordMobileTelemetryFragment: jest.fn() }));

import { recordEquipmentIdentityTelemetryFragment } from "../telemetry_handler";
import { recordMobileTelemetryFragment } from "../telemetry_repository";

const mRecord = recordMobileTelemetryFragment as jest.Mock;

const NOW = "2026-09-16T10:00:00.000Z";
const LATER = "2026-09-16T10:00:05.000Z";

beforeEach(() => {
  jest.clearAllMocks();
  mRecord.mockResolvedValue(undefined);
});

describe("recordEquipmentIdentityTelemetryFragment -- request validation runs before the repository", () => {
  test("a malformed report never reaches the repository", async () => {
    await expect(
      recordEquipmentIdentityTelemetryFragment("u1", { not: "a valid report" }),
    ).rejects.toThrow();
    expect(mRecord).not.toHaveBeenCalled();
  });

  test("a client-submitted SERVER_TERMINAL state is rejected at the contract boundary -- mobile has no authority to assert it", async () => {
    await expect(
      recordEquipmentIdentityTelemetryFragment("u1", {
        scanId: "scan-1",
        state: "SERVER_TERMINAL",
        scanStartedAt: NOW,
        scanEndedAt: LATER,
      }),
    ).rejects.toThrow();
    expect(mRecord).not.toHaveBeenCalled();
  });

  test("a scanId containing '/' is rejected at the contract boundary", async () => {
    await expect(
      recordEquipmentIdentityTelemetryFragment("u1", {
        scanId: "scan/../other",
        state: "LOCAL_FAILURE",
        reason: "ocrException",
        scanStartedAt: NOW,
        scanEndedAt: LATER,
      }),
    ).rejects.toThrow();
    expect(mRecord).not.toHaveBeenCalled();
  });

  test("a non-UTC timestamp (missing the Z suffix) is rejected", async () => {
    await expect(
      recordEquipmentIdentityTelemetryFragment("u1", {
        scanId: "scan-1",
        state: "LOCAL_FAILURE",
        reason: "ocrException",
        scanStartedAt: "2026-09-16T10:00:00.000",
        scanEndedAt: LATER,
      }),
    ).rejects.toThrow();
    expect(mRecord).not.toHaveBeenCalled();
  });

  test("scanEndedAt before scanStartedAt is rejected", async () => {
    await expect(
      recordEquipmentIdentityTelemetryFragment("u1", {
        scanId: "scan-1",
        state: "LOCAL_FAILURE",
        reason: "ocrException",
        scanStartedAt: LATER,
        scanEndedAt: NOW,
      }),
    ).rejects.toThrow();
    expect(mRecord).not.toHaveBeenCalled();
  });

  // Design doc §5.4, round 4: no upper bound on the gap -- a long-running
  // legitimate retry (scanId reused, no time boundary of its own) must not
  // be rejected.
  test("a multi-hour gap between scanStartedAt and scanEndedAt is ACCEPTED -- no upper bound", async () => {
    const result = await recordEquipmentIdentityTelemetryFragment("u1", {
      scanId: "scan-1",
      state: "REQUEST_FAILURE",
      reason: "timeout",
      scanStartedAt: "2026-09-16T06:00:00.000Z",
      scanEndedAt: "2026-09-16T10:00:00.000Z",
    });
    expect(result).toEqual({ ok: true });
    expect(mRecord).toHaveBeenCalledTimes(1);
  });
});

describe("recordEquipmentIdentityTelemetryFragment -- repository wiring", () => {
  test("passes the authenticated uid and the parsed report, for a LOCAL_FAILURE fragment", async () => {
    await recordEquipmentIdentityTelemetryFragment("server-owned-uid", {
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      reason: "ocrException",
      scanStartedAt: NOW,
      scanEndedAt: LATER,
    });
    expect(mRecord).toHaveBeenCalledWith("server-owned-uid", {
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      reason: "ocrException",
      scanStartedAt: NOW,
      scanEndedAt: LATER,
    });
  });

  test("passes a REQUEST_FAILURE fragment through, including the malformedReply reason", async () => {
    await recordEquipmentIdentityTelemetryFragment("u1", {
      scanId: "scan-1",
      state: "REQUEST_FAILURE",
      reason: "malformedReply",
      scanStartedAt: NOW,
      scanEndedAt: LATER,
    });
    expect(mRecord).toHaveBeenCalledWith(
      "u1",
      expect.objectContaining({ state: "REQUEST_FAILURE", reason: "malformedReply" }),
    );
  });

  test("passes a timing-only (state-less) success fragment through", async () => {
    await recordEquipmentIdentityTelemetryFragment("u1", {
      scanId: "scan-1",
      scanStartedAt: NOW,
      scanEndedAt: LATER,
    });
    expect(mRecord).toHaveBeenCalledWith("u1", { scanId: "scan-1", scanStartedAt: NOW, scanEndedAt: LATER });
  });

  test("a repository write failure never propagates -- the client still gets ok:true", async () => {
    mRecord.mockRejectedValue(new Error("firestore outage"));
    const result = await recordEquipmentIdentityTelemetryFragment("u1", {
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      reason: "ocrException",
      scanStartedAt: NOW,
      scanEndedAt: LATER,
    });
    expect(result).toEqual({ ok: true });
  });
});
