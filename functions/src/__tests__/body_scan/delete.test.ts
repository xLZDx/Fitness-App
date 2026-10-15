/**
 * `deleteBodyScan` (design s7.3, D-59): photos-only delete, the 48 h scrubbed
 * `cancelled` tombstone, the order document-before-objects, idempotency,
 * isolation between scans/users and failure handling.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import { deleteBodyScan } from "../../body_scan/delete";
import { createBodyScan } from "../../body_scan/create";
import { __setTestEstimatorForTests } from "../../body_scan/estimator";
import { __resetAiGatewayControlCacheForTests } from "../../abuse_guard";
import {
  BUCKET, DAY, FakePhotoEstimator, MIN, T0, UID, SCAN,
  bodyScanEvents, callReq, expectHttpsError, firestoreError, fx, gcs, loggedText, objectKeys,
  putPhotos, resetFakes, scanDoc, seedEligibleUser, seedScan, store, timeline, ts, usageOf, writes,
} from "./fakes";

let now = T0;
let dateSpy: jest.SpyInstance;

const run = (data: unknown, uid: string | null = UID): Promise<any> =>
  (deleteBodyScan as any).run(callReq(data, uid));

const SCAN_PATH = `users/${UID}/body_scans/${SCAN}`;
const PREFIX = `users/${UID}/scans/${SCAN}/`;

/** A done scan carrying every field a tombstone must scrub, plus ones it keeps. */
const fullDoc = (o: Record<string, unknown> = {}): any => ({
  schema: 1,
  createdAt: ts(T0 - 3 * DAY),
  takenAt: ts(T0 - 3 * DAY),
  weightKg: 70.25,
  clientNote: "felt bloated",
  status: "done",
  subject: { sexAtBirth: "male", ageYears: 40, heightCm: 180, weightKg: 70.25 },
  capture: { manualOverride: { front: false, side: false, back: false }, poses: ["front", "side", "back"] },
  provider: { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true },
  estimate: {
    bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium", checkCodes: [],
    modelId: "test-fake", modelVersion: "1.2.3", estimatedAt: ts(T0 - 3 * DAY),
  },
  photosState: "stored",
  photosExpireAt: ts(T0 + 20 * DAY),
  estimateLeaseUntil: ts(T0 - DAY),
  estimateCharged: true,
  purgeAttempts: 2,
  ...o,
});

beforeEach(() => {
  resetFakes();
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  __resetAiGatewayControlCacheForTests();
  process.env.BODY_SCAN_BUCKET = BUCKET;
  process.env.BODY_SCAN_PROVIDER = "test-fake";
  __setTestEstimatorForTests(new FakePhotoEstimator());
  seedEligibleUser();
  seedScan(UID, SCAN, fullDoc());
  putPhotos(UID, SCAN);
});

afterEach(() => {
  dateSpy.mockRestore();
});

afterAll(() => {
  __setTestEstimatorForTests(undefined);
  delete process.env.BODY_SCAN_BUCKET;
  delete process.env.BODY_SCAN_PROVIDER;
});

describe("validation and quota", () => {
  test.each([
    ["scanId missing", { photosOnly: true }],
    ["scanId too short", { scanId: "abc", photosOnly: true }],
    ["scanId with a slash", { scanId: "abcd/efgh", photosOnly: false }],
    ["scanId with a wildcard", { scanId: "abcd*efgh", photosOnly: false }],
    ["body null", null],
  ])("%s -> invalid-argument invalid-scan-id, nothing touched", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-scan-id");
    expect(usageOf(UID, "bodyScanDelete")).toBe(0);
    expect(gcs.deleteFilesCalls).toEqual([]);
    expect(writes.filter((w) => w.path === SCAN_PATH)).toEqual([]);
  });

  test.each([
    ["missing", { scanId: SCAN }],
    ["the string 'true'", { scanId: SCAN, photosOnly: "true" }],
    ["the number 1", { scanId: SCAN, photosOnly: 1 }],
    ["null", { scanId: SCAN, photosOnly: null }],
  ])("photosOnly %s -> invalid-argument invalid-photos-only (no default that could erase a scan)", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-photos-only");
    expect(scanDoc(UID, SCAN)!.status).toBe("done");
    expect(objectKeys()).toHaveLength(3);
    expect(usageOf(UID, "bodyScanDelete")).toBe(0);
  });

  test("each single-scan delete charges one bodyScanDelete unit", async () => {
    await run({ scanId: SCAN, photosOnly: true });
    expect(usageOf(UID, "bodyScanDelete")).toBe(1);
  });

  test("at the daily limit (60) -> resource-exhausted and the scan and photos are left alone", async () => {
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanDelete: 60 });
    await expectHttpsError(run({ scanId: SCAN, photosOnly: false }), "resource-exhausted");
    expect(scanDoc(UID, SCAN)!.status).toBe("done");
    expect(objectKeys()).toHaveLength(3);
  });

  test("the response is {scanId, deleted: true, serverNowMs}", async () => {
    expect(await run({ scanId: SCAN, photosOnly: true })).toEqual({ scanId: SCAN, deleted: true, serverNowMs: now });
  });
});

describe("photosOnly: true", () => {
  test("keeps the scan and its estimate, marks the photos deleted and removes the objects", async () => {
    const before = fullDoc();
    await run({ scanId: SCAN, photosOnly: true });

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("done");
    expect(doc.estimate).toEqual(before.estimate);
    expect(doc.subject).toEqual(before.subject);
    expect(doc.weightKg).toBe(70.25);
    expect(doc.clientNote).toBe("felt bloated");
    expect(doc.takenAt).toEqual(before.takenAt);
    expect(doc.photosState).toBe("deleted");
    expect(doc.photosDeletedAt).toEqual(ts(now));
    expect("photosExpireAt" in doc).toBe(false);
    expect(objectKeys()).toEqual([]);
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).toEqual([PREFIX]);
    expect(bodyScanEvents(logger).map((e) => e.outcome)).toEqual(["photos-deleted"]);
  });

  test("for a scan the server never saw: no document is invented, the (idempotent) object delete still runs", async () => {
    putPhotos(UID, "never_seen_1");
    await run({ scanId: "never_seen_1", photosOnly: true });
    expect(scanDoc(UID, "never_seen_1")).toBeUndefined();
    expect(objectKeys(`users/${UID}/scans/never_seen_1/`)).toEqual([]);
  });
});

describe("photosOnly: false -> scrubbed 48 h cancelled tombstone", () => {
  test("every metric, estimate and note is removed; only the bookkeeping that keeps late uploads discoverable stays", async () => {
    await run({ scanId: SCAN, photosOnly: false });

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("cancelled");
    expect(doc.photosState).toBe("deleted");
    expect(doc.photosDeletedAt).toEqual(ts(now));
    expect(doc.pendingExpiresAt).toEqual(ts(now + 48 * 60 * MIN));
    for (const gone of ["subject", "estimate", "weightKg", "capture", "clientNote", "takenAt", "photosExpireAt", "estimateLeaseUntil", "estimateCharged"]) {
      expect(gone in doc).toBe(false);
    }
    expect(Object.keys(doc).sort()).toEqual([
      "createdAt", "photosDeletedAt", "photosState", "pendingExpiresAt", "provider", "purgeAttempts", "schema", "status",
    ].sort());
    expect(JSON.stringify(doc)).not.toContain("felt bloated");
    expect(JSON.stringify(doc)).not.toContain("70.25");
    expect(objectKeys()).toEqual([]);
    expect(bodyScanEvents(logger).map((e) => e.outcome)).toEqual(["tombstoned"]);
  });

  test("the tombstone is written BEFORE the objects are deleted (a racing estimate can never resurrect the scan)", async () => {
    await run({ scanId: SCAN, photosOnly: false });
    const written = timeline.indexOf(`fs:update:${SCAN_PATH}`);
    const deleted = timeline.indexOf(`gcs:deleteFiles:${PREFIX}`);
    expect(written).toBeGreaterThanOrEqual(0);
    expect(deleted).toBeGreaterThan(written);
  });

  test("a scan the server never saw still gets a tombstone, so a later create of that id is refused", async () => {
    await run({ scanId: "offline_one_1", photosOnly: false });

    const doc = scanDoc(UID, "offline_one_1")!;
    expect(doc).toEqual({
      schema: 1,
      createdAt: ts(now),
      purgeAttempts: 0,
      status: "cancelled",
      photosState: "deleted",
      photosDeletedAt: ts(now),
      pendingExpiresAt: ts(now + 48 * 60 * MIN),
    });

    const created = (createBodyScan as any).run(
      callReq({
        scanId: "offline_one_1",
        takenAtMs: now - 1000,
        subject: { sexAtBirth: "female", heightCm: 170, weightKg: 65 },
        capture: { manualOverride: { front: false, side: false, back: false } },
      }),
    );
    await expectHttpsError(created, "failed-precondition", "scan-cancelled");
    expect(usageOf(UID, "bodyScanCreate")).toBe(0);
  });

  test("deleting twice is idempotent: both calls succeed and the scan stays a tombstone", async () => {
    await run({ scanId: SCAN, photosOnly: false });
    const again = await run({ scanId: SCAN, photosOnly: false });
    expect(again.deleted).toBe(true);
    expect(scanDoc(UID, SCAN)!.status).toBe("cancelled");
    expect(usageOf(UID, "bodyScanDelete")).toBe(2);
  });

  test("a pending scan with uploaded photos is tombstoned and its objects removed", async () => {
    seedScan(UID, SCAN, fullDoc({ status: "pending", photosState: "awaiting_upload", estimate: undefined }));
    await run({ scanId: SCAN, photosOnly: false });
    expect(scanDoc(UID, SCAN)!.status).toBe("cancelled");
    expect(objectKeys()).toEqual([]);
  });
});

describe("isolation", () => {
  test("another user's scan with the same id, and their objects, are untouched", async () => {
    store.set(`users/other_user/body_scans/${SCAN}`, fullDoc());
    putPhotos("other_user", SCAN);
    await run({ scanId: SCAN, photosOnly: false });
    expect(store.get(`users/other_user/body_scans/${SCAN}`)!.status).toBe("done");
    expect(objectKeys("users/other_user/")).toHaveLength(3);
  });

  test("a scan whose id merely starts with this id keeps its objects (the prefix ends with a slash)", async () => {
    seedScan(UID, `${SCAN}9`, fullDoc());
    putPhotos(UID, `${SCAN}9`);
    await run({ scanId: SCAN, photosOnly: false });
    expect(scanDoc(UID, `${SCAN}9`)!.status).toBe("done");
    expect(objectKeys(`users/${UID}/scans/${SCAN}9/`)).toHaveLength(3);
    expect(objectKeys(PREFIX)).toEqual([]);
  });
});

describe("failures", () => {
  test("object delete fails -> internal scan-delete-failed, the tombstone is already written, the log has the error code only", async () => {
    gcs.failOn = (op, name) => (op === "deleteFiles" ? firestoreError(`cannot delete ${name} of ${UID}`, 503) : undefined);
    await expectHttpsError(run({ scanId: SCAN, photosOnly: false }), "internal", "scan-delete-failed");

    expect(scanDoc(UID, SCAN)!.status).toBe("cancelled");
    expect(objectKeys()).toHaveLength(3); // left for the purge / a retry
    expect(bodyScanEvents(logger, "error")).toEqual([{ operation: "bodyScanDelete", outcome: "failed", photosOnly: false, errorCode: "503" }]);
    const text = loggedText(logger);
    expect(text).not.toContain(UID);
    expect(text).not.toContain("users/");

    // The retry (idempotent) finishes the job.
    gcs.failOn = null;
    await run({ scanId: SCAN, photosOnly: false });
    expect(objectKeys()).toEqual([]);
  });

  test("Firestore fails -> internal scan-delete-failed and the objects are NOT deleted", async () => {
    fx.failOn = (op, path) => (op === "commit" && path.includes("body_scans") ? firestoreError("x", "unavailable") : undefined);
    await expectHttpsError(run({ scanId: SCAN, photosOnly: false }), "internal", "scan-delete-failed");
    expect(scanDoc(UID, SCAN)!.status).toBe("done");
    expect(objectKeys()).toHaveLength(3);
    expect(gcs.deleteFilesCalls).toEqual([]);
  });
});
