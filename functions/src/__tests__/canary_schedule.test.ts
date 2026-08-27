/**
 * `runProductionCanary`'s own handler -- specifically the SCHEDULE_HANDLER
 * backstop GPT-PM's review of `b9d1e9a` required: when `runCanaryProbe()`
 * itself unexpectedly rejects (a bug, not a captured failure -- that
 * function is documented to never throw), the handler must still emit
 * `CANARY_PROBE_FAILED_EVENT` and still fail the Scheduler execution.
 * Without a direct test for this path, a future refactor could remove the
 * catch, change the event, or swallow the rethrow while every other test in
 * this file stays green -- exactly the silent-failure risk this test exists
 * to close (GPT-PM's round-2 review of the fix that first added the catch).
 */
jest.mock("firebase-functions/logger", () => ({
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

const runCanaryProbe = jest.fn();
jest.mock("../canary_probe", () => ({ runCanaryProbe: (...args: unknown[]) => runCanaryProbe(...args) }));

import { runProductionCanary } from "../canary_schedule";
import * as logger from "firebase-functions/logger";
import { CANARY_PROBE_FAILED_EVENT } from "../monitoring/log_signals";

const FAKE_EVENT = { scheduleTime: "2026-08-27T00:00:00.000Z" };

beforeEach(() => {
  jest.clearAllMocks();
});

describe("runProductionCanary — the SCHEDULE_HANDLER backstop", () => {
  test("an unexpected rejection from runCanaryProbe() is logged and rethrown", async () => {
    const boom = new Error("synthetic: something inside runCanaryProbe blew up unexpectedly");
    runCanaryProbe.mockRejectedValue(boom);

    await expect(runProductionCanary.run(FAKE_EVENT)).rejects.toThrow(boom);

    expect(logger.error).toHaveBeenCalledWith(
      CANARY_PROBE_FAILED_EVENT,
      expect.objectContaining({
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: boom.message,
      }),
    );
  });

  test("a rejection with a non-Error value is still logged and rethrown", async () => {
    // `runCanaryProbe()`'s own contract is "never throws", so a rejection at
    // all is already the unexpected case -- this proves the handler doesn't
    // also assume the rejection reason is an Error instance.
    runCanaryProbe.mockRejectedValue("a plain string rejection reason");

    await expect(runProductionCanary.run(FAKE_EVENT)).rejects.toBe(
      "a plain string rejection reason",
    );
    expect(logger.error).toHaveBeenCalledWith(
      CANARY_PROBE_FAILED_EVENT,
      expect.objectContaining({
        stage: "SCHEDULE_HANDLER",
        failureClass: "UNEXPECTED",
        message: "a plain string rejection reason",
      }),
    );
  });
});

describe("runProductionCanary — the captured-failure path (unchanged behavior)", () => {
  test("a captured probe failure (success: false) is logged and thrown, not silently swallowed", async () => {
    runCanaryProbe.mockResolvedValue({
      success: false,
      latencyMs: 42,
      stage: "FIRESTORE_WRITE",
      failureClass: "FIRESTORE_WRITE",
      cleanupAttempted: true,
      cleanupSucceeded: true,
    });

    await expect(runProductionCanary.run(FAKE_EVENT)).rejects.toThrow(
      /FIRESTORE_WRITE/,
    );
    expect(logger.error).toHaveBeenCalledWith(
      CANARY_PROBE_FAILED_EVENT,
      expect.objectContaining({ stage: "FIRESTORE_WRITE", failureClass: "FIRESTORE_WRITE" }),
    );
  });

  test("a successful probe run resolves cleanly and logs no error", async () => {
    runCanaryProbe.mockResolvedValue({
      success: true,
      latencyMs: 42,
      cleanupAttempted: false,
      cleanupSucceeded: true,
    });

    await expect(runProductionCanary.run(FAKE_EVENT)).resolves.toBeUndefined();
    expect(logger.error).not.toHaveBeenCalled();
  });
});
