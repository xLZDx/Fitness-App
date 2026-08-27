/**
 * `runEnforcementStateCheck`'s own handler -- mirrors
 * `canary_schedule.test.ts`'s coverage shape for the same reason: the
 * SCHEDULE_HANDLER backstop and the "non-OK result still fails the
 * Scheduler execution" path both need a direct test, or a future refactor
 * could silently drop either one while every other test in this file stays
 * green.
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

const runEnforcementStateProbe = jest.fn();
jest.mock("../enforcement_state", () => ({
  runEnforcementStateProbe: (...args: unknown[]) => runEnforcementStateProbe(...args),
}));

import { runEnforcementStateCheck } from "../enforcement_state_schedule";
import * as logger from "firebase-functions/logger";
import { ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT } from "../monitoring/log_signals";

const FAKE_EVENT = { scheduleTime: "2026-08-27T00:00:00.000Z" };

const okSection = { status: "OK" as const, data: { count: 1 } };
const badSection = { status: "UNAVAILABLE" as const, error: "synthetic: HTTP 500" };

beforeEach(() => {
  jest.clearAllMocks();
});

describe("runEnforcementStateCheck — the SCHEDULE_HANDLER backstop", () => {
  test("an unexpected rejection from runEnforcementStateProbe() is logged and rethrown", async () => {
    const boom = new Error("synthetic: something inside the probe blew up unexpectedly");
    runEnforcementStateProbe.mockRejectedValue(boom);

    await expect(runEnforcementStateCheck.run(FAKE_EVENT)).rejects.toThrow(boom);

    expect(logger.error).toHaveBeenCalledWith(
      ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
      expect.objectContaining({
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: boom.message,
      }),
    );
  });

  test("a rejection with a non-Error value is still logged and rethrown", async () => {
    runEnforcementStateProbe.mockRejectedValue("a plain string rejection reason");

    await expect(runEnforcementStateCheck.run(FAKE_EVENT)).rejects.toBe(
      "a plain string rejection reason",
    );
    expect(logger.error).toHaveBeenCalledWith(
      ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
      expect.objectContaining({
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: "a plain string rejection reason",
      }),
    );
  });
});

describe("runEnforcementStateCheck — non-OK results still fail the Scheduler execution", () => {
  test("a FAILED result is logged with the unavailable sections and thrown, not silently swallowed", async () => {
    runEnforcementStateProbe.mockResolvedValue({
      status: "FAILED",
      generatedAt: "2026-08-27T00:00:00.000Z",
      sections: {
        functions: badSection,
        firestoreRules: badSection,
        appCheck: badSection,
        identityToolkit: badSection,
      },
    });

    await expect(runEnforcementStateCheck.run(FAKE_EVENT)).rejects.toThrow(/FAILED/);
    expect(logger.error).toHaveBeenCalledWith(
      ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
      expect.objectContaining({
        overallStatus: "FAILED",
        unavailableSections: ["functions", "firestoreRules", "appCheck", "identityToolkit"],
      }),
    );
  });

  test("a DEGRADED result (only one section unavailable) is logged and thrown", async () => {
    runEnforcementStateProbe.mockResolvedValue({
      status: "DEGRADED",
      generatedAt: "2026-08-27T00:00:00.000Z",
      sections: {
        functions: okSection,
        firestoreRules: badSection,
        appCheck: okSection,
        identityToolkit: okSection,
      },
    });

    await expect(runEnforcementStateCheck.run(FAKE_EVENT)).rejects.toThrow(/DEGRADED/);
    expect(logger.error).toHaveBeenCalledWith(
      ENFORCEMENT_STATE_DEGRADED_OR_FAILED_EVENT,
      expect.objectContaining({
        overallStatus: "DEGRADED",
        unavailableSections: ["firestoreRules"],
      }),
    );
  });

  test("an OK result resolves cleanly and logs no error", async () => {
    runEnforcementStateProbe.mockResolvedValue({
      status: "OK",
      generatedAt: "2026-08-27T00:00:00.000Z",
      sections: {
        functions: okSection,
        firestoreRules: okSection,
        appCheck: okSection,
        identityToolkit: okSection,
      },
    });

    await expect(runEnforcementStateCheck.run(FAKE_EVENT)).resolves.toBeUndefined();
    expect(logger.error).not.toHaveBeenCalled();
  });
});
