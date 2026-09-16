/**
 * P2.G5-readiness step 3a -- unit tests for `telemetry_contract.ts`'s NEW
 * pieces: the mobile-submittable report-request discriminated union
 * (design doc §6/§7) and its timestamp validation (§5.4). The pre-existing
 * `EquipmentIdentityTelemetryRecordSchema` (step 2) has no dedicated unit
 * suite of its own -- it is exercised indirectly through
 * `__e2e__/telemetry_repository.e2e.test.ts`'s real writes.
 */
import {
  EquipmentIdentityTelemetryReportRequestSchema,
  LocalFailureReportSchema,
  RequestFailureReportSchema,
  ScanTimingReportSchema,
} from "../telemetry_contract";

const START = "2026-09-16T10:00:00.000Z";
const END = "2026-09-16T10:00:05.000Z";

describe("EquipmentIdentityTelemetryReportRequestSchema -- exactly 3 mobile-submittable shapes", () => {
  test("accepts a well-formed LOCAL_FAILURE report", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      reason: "ocrException",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(true);
  });

  test("accepts a well-formed REQUEST_FAILURE report, including the malformedReply reason", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan-1",
      state: "REQUEST_FAILURE",
      reason: "malformedReply",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(true);
  });

  test("accepts a well-formed timing-only (state-less) report", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(true);
  });

  // design doc §6's authority split: a mobile client may only ever submit
  // LOCAL_FAILURE/REQUEST_FAILURE -- SERVER_TERMINAL/CONFLICT/ENRICHMENT_DISABLED
  // are all rejected outright at this boundary, never accepted as an
  // incoming state from any caller.
  test.each(["SERVER_TERMINAL", "CONFLICT", "ENRICHMENT_DISABLED", "NOT_ATTEMPTED"])(
    "rejects a client-submitted state=%s -- mobile has no authority to assert it",
    (state) => {
      const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
        scanId: "scan-1",
        state,
        reason: "ocrException",
        scanStartedAt: START,
        scanEndedAt: END,
      });
      expect(result.success).toBe(false);
    },
  );

  test("rejects a LOCAL_FAILURE report using a REQUEST_FAILURE-only reason", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan-1",
      state: "LOCAL_FAILURE",
      reason: "malformedReply",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(false);
  });

  test("rejects an unrecognized extra field on any of the 3 shapes (.strict())", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: START,
      scanEndedAt: END,
      extra: "not allowed",
    });
    expect(result.success).toBe(false);
  });

  test("rejects a scanId containing '/' -- the same Firestore-safety rule as the identity request contract", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan/../other",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(false);
  });

  test("accepts a scanId containing '--' -- not part of the unrelated composite scheme", () => {
    const result = EquipmentIdentityTelemetryReportRequestSchema.safeParse({
      scanId: "scan--123",
      scanStartedAt: START,
      scanEndedAt: END,
    });
    expect(result.success).toBe(true);
  });
});

describe("timestamp validation (design doc §5.4)", () => {
  test("rejects scanStartedAt/scanEndedAt missing the Z (UTC) suffix -- a bare DateTime.now() mistake", () => {
    const result = ScanTimingReportSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: "2026-09-16T10:00:00.000",
      scanEndedAt: END,
    });
    expect(result.success).toBe(false);
  });

  test("rejects scanEndedAt strictly before scanStartedAt", () => {
    const result = ScanTimingReportSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: END,
      scanEndedAt: START,
    });
    expect(result.success).toBe(false);
  });

  test("accepts scanEndedAt exactly equal to scanStartedAt", () => {
    const result = ScanTimingReportSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: START,
      scanEndedAt: START,
    });
    expect(result.success).toBe(true);
  });

  // round 4's own correction: no upper bound. scanId is reused across a
  // retry with no time boundary of its own, so a multi-hour gap is real,
  // honest evidence, not a data-quality defect.
  test("accepts a multi-hour gap between scanStartedAt and scanEndedAt -- no upper bound", () => {
    const result = ScanTimingReportSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: "2026-09-16T02:00:00.000Z",
      scanEndedAt: "2026-09-16T10:00:00.000Z",
    });
    expect(result.success).toBe(true);
  });

  test("differing sub-second precision compares by real instant, not lexical string order", () => {
    // "10:00:00Z" > "10:00:00.500Z" lexically (Z > '.'), but the .500Z
    // instant is genuinely LATER -- must not be rejected by a naive string
    // comparison.
    const result = ScanTimingReportSchema.safeParse({
      scanId: "scan-1",
      scanStartedAt: "2026-09-16T10:00:00Z",
      scanEndedAt: "2026-09-16T10:00:00.500Z",
    });
    expect(result.success).toBe(true);
  });
});

describe("LocalFailureReportSchema / RequestFailureReportSchema individually", () => {
  test("LocalFailureReportSchema rejects a REQUEST_FAILURE-shaped payload", () => {
    expect(
      LocalFailureReportSchema.safeParse({
        scanId: "scan-1",
        state: "REQUEST_FAILURE",
        reason: "timeout",
        scanStartedAt: START,
        scanEndedAt: END,
      }).success,
    ).toBe(false);
  });

  test("RequestFailureReportSchema accepts every enum reason value", () => {
    const reasons = [
      "networkUnreachable",
      "timeout",
      "appCheckOrAuth",
      "rateLimited",
      "backendError",
      "unknownClientError",
      "malformedReply",
    ];
    for (const reason of reasons) {
      expect(
        RequestFailureReportSchema.safeParse({
          scanId: "scan-1",
          state: "REQUEST_FAILURE",
          reason,
          scanStartedAt: START,
          scanEndedAt: END,
        }).success,
      ).toBe(true);
    }
  });
});
