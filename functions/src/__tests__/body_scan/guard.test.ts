/**
 * The shared guard preamble of the four body-scan callables (design s7, D-60):
 * auth -> App Check note -> non-anonymous -> AI Gateway kill switch -> bucket
 * flag, ALL before any quota is charged and before any document or object is
 * touched. The same table runs against every callable, so the order cannot
 * drift between them.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import { createBodyScan } from "../../body_scan/create";
import { estimateBodyScan } from "../../body_scan/estimate";
import { deleteBodyScan } from "../../body_scan/delete";
import { manageBodyScanData } from "../../body_scan/manage";
import { __setTestEstimatorForTests } from "../../body_scan/estimator";
import { __resetAiGatewayControlCacheForTests } from "../../abuse_guard";
import {
  BUCKET, FakePhotoEstimator, T0, UID, SCAN,
  callReq, expectHttpsError, gateway, gcs, resetFakes, seedEligibleUser, store, writes,
} from "./fakes";

let dateSpy: jest.SpyInstance;

interface Subject {
  name: string;
  fn: any;
  data: () => unknown;
  quota: string;
  /** What a call that passes every guard does with seeded state. */
  control: (res: any, err: any) => void;
  /** Erase callables ignore the AI kill switch and the intake switch (P-2). */
  erase?: boolean;
}

const SUBJECTS: Subject[] = [
  {
    name: "createBodyScan",
    fn: createBodyScan,
    quota: "bodyScanCreate",
    data: () => ({
      scanId: SCAN,
      takenAtMs: T0 - 1000,
      subject: { sexAtBirth: "female", heightCm: 170, weightKg: 65 },
      capture: { manualOverride: { front: false, side: false, back: false } },
    }),
    control: (res, err) => { expect(err).toBeUndefined(); expect(res.status).toBe("pending"); },
  },
  {
    name: "estimateBodyScan",
    fn: estimateBodyScan,
    quota: "bodyScanEstimate",
    data: () => ({ scanId: SCAN }),
    control: (_res, err) => { expect(err.code).toBe("not-found"); expect(err.message).toBe("scan-not-found"); },
  },
  {
    name: "deleteBodyScan",
    fn: deleteBodyScan,
    quota: "bodyScanDelete",
    erase: true,
    data: () => ({ scanId: SCAN, photosOnly: false }),
    control: (res, err) => { expect(err).toBeUndefined(); expect(res.deleted).toBe(true); },
  },
  {
    name: "manageBodyScanData",
    fn: manageBodyScanData,
    quota: "bodyScanManage",
    erase: true,
    data: () => ({ action: "deleteAllScans" }),
    control: (res, err) => { expect(err).toBeUndefined(); expect(res.processed).toBe(0); },
  },
];

const call = (s: Subject, auth: { uid: string | null; provider?: string } = { uid: UID }): Promise<any> =>
  s.fn.run(callReq(s.data(), auth.uid, auth.provider ?? "password"));

const settle = async (p: Promise<any>): Promise<{ res?: any; err?: any }> =>
  p.then((res) => ({ res }), (err) => ({ err }));

/** Nothing was charged, written or touched in storage. */
function expectUntouched(quota: string): void {
  const usage = [...store.keys()].filter((k) => k.includes("/usage/"));
  expect(usage).toEqual([]);
  expect(quota.length).toBeGreaterThan(0);
  expect(writes).toEqual([]);
  expect(gcs.signed).toEqual([]);
  expect(gcs.deleteFilesCalls).toEqual([]);
  expect(gcs.getFilesCalls).toEqual([]);
}

beforeEach(() => {
  resetFakes();
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => T0);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  __resetAiGatewayControlCacheForTests();
  process.env.BODY_SCAN_BUCKET = BUCKET;
  process.env.BODY_SCAN_PROVIDER = "test-fake";
  __setTestEstimatorForTests(new FakePhotoEstimator());
  seedEligibleUser();
});

afterEach(() => {
  dateSpy.mockRestore();
});

afterAll(() => {
  __setTestEstimatorForTests(undefined);
  delete process.env.BODY_SCAN_BUCKET;
  delete process.env.BODY_SCAN_PROVIDER;
});

describe.each(SUBJECTS)("$name guard preamble", (s) => {
  test("control: with every guard passing the call reaches its own logic", async () => {
    const { res, err } = await settle(call(s));
    s.control(res, err);
  });

  test("no auth -> unauthenticated sign-in-required, and the kill switch is not even read", async () => {
    await expectHttpsError(call(s, { uid: null }), "unauthenticated", "sign-in-required");
    expect(gateway.reads).toBe(0);
    expectUntouched(s.quota);
  });

  test("anonymous sign-in -> permission-denied before the kill switch is read, nothing charged", async () => {
    await expectHttpsError(call(s, { uid: UID, provider: "anonymous" }), "permission-denied");
    expect(gateway.reads).toBe(0);
    expectUntouched(s.quota);
  });

  test("kill switch off -> unavailable (erase callables: still work, the switch is not read), nothing charged or written when refused", async () => {
    gateway.enabled = false;
    if (s.erase) {
      const { res, err } = await settle(call(s));
      s.control(res, err);
      expect(gateway.reads).toBe(0);
      return;
    }
    await expectHttpsError(call(s), "unavailable", /temporarily unavailable/i);
    expect(gateway.reads).toBe(1);
    expectUntouched(s.quota);
  });

  test("kill switch unreadable -> unavailable fail closed (erase callables: still work)", async () => {
    gateway.readFails = true;
    if (s.erase) {
      const { res, err } = await settle(call(s));
      s.control(res, err);
      return;
    }
    await expectHttpsError(call(s), "unavailable", /temporarily unavailable/i);
    expectUntouched(s.quota);
  });

  test("BODY_SCAN_ACCEPT_UPLOADS=false stops intake only: create/estimate refuse with feature-disabled, erase callables still run", async () => {
    process.env.BODY_SCAN_ACCEPT_UPLOADS = "false";
    try {
      if (s.erase) {
        const { res, err } = await settle(call(s));
        s.control(res, err);
        return;
      }
      await expectHttpsError(call(s), "failed-precondition", "feature-disabled");
      expectUntouched(s.quota);
    } finally {
      delete process.env.BODY_SCAN_ACCEPT_UPLOADS;
    }
  });

  test("bucket flag off (BODY_SCAN_BUCKET unset) -> failed-precondition feature-disabled, nothing charged or written", async () => {
    delete process.env.BODY_SCAN_BUCKET;
    await expectHttpsError(call(s), "failed-precondition", "feature-disabled");
    expectUntouched(s.quota);
  });

  test("a malformed bucket name counts as unset", async () => {
    process.env.BODY_SCAN_BUCKET = "Not A Bucket";
    await expectHttpsError(call(s), "failed-precondition", "feature-disabled");
    expectUntouched(s.quota);
  });

  test("order: with the kill switch off AND the flag off the kill switch answers first (erase callables: feature-disabled, they never read the switch)", async () => {
    gateway.enabled = false;
    delete process.env.BODY_SCAN_BUCKET;
    if (s.erase) await expectHttpsError(call(s), "failed-precondition", "feature-disabled");
    else await expectHttpsError(call(s), "unavailable");
    expectUntouched(s.quota);
  });

  test("the call is noted for App Check under its own name (attested false without a token)", async () => {
    await settle(call(s));
    const notes = (logger.info as jest.Mock).mock.calls.filter((c) => c[1]?.fn === s.name);
    expect(notes).toHaveLength(1);
    expect(notes[0][1]).toEqual({ fn: s.name, attested: false });
    expect(JSON.stringify(notes)).not.toContain(UID);
  });
});

describe("function options", () => {
  test.each(SUBJECTS)("$name runs as the dedicated fn-bodyscan identity in europe-west1, capped at 10 instances", (s) => {
    const ep = s.fn.__endpoint;
    expect(ep.region).toEqual(["europe-west1"]);
    expect(ep.serviceAccountEmail).toMatch(/^fn-bodyscan@/);
    expect(ep.maxInstances).toBe(10);
    expect(ep.platform).toBe("gcfv2");
  });
});
