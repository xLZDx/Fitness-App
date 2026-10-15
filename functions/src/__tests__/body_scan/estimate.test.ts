/**
 * `estimateBodyScan` (design s7.2, D-53): done replay, the processing lease,
 * read-time upload checks, the provider call (timeout, failure, terminal
 * failure, invalid output), the racing delete, retention and quota accounting.
 *
 * The provider is a `FakePhotoEstimator` installed through the
 * `__setTestEstimatorForTests` seam. Firestore/Storage are the stateful doubles
 * of `./fakes`; the clock is a `Date.now` spy.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import { estimateBodyScan, ESTIMATE_TIMEOUT_MS } from "../../body_scan/estimate";
import { EstimatorTerminalError, __setTestEstimatorForTests } from "../../body_scan/estimator";
import { __resetAiGatewayControlCacheForTests } from "../../abuse_guard";
import {
  BUCKET, DAY, FakePhotoEstimator, MIN, T0, UID, SCAN, VALID_OUTPUT,
  bodyScanEvents, callReq, expectHttpsError, firestoreError, fx, gcs, jpegBytes, loggedText,
  objectKeys, putPhotos, resetFakes, scanDoc, seedEligibleUser, seedScan, store, timeline, ts,
  usageOf, writes,
} from "./fakes";

let now = T0;
let dateSpy: jest.SpyInstance;
let fake: FakePhotoEstimator;
const spies: jest.SpyInstance[] = [];

const run = (data: unknown = { scanId: SCAN }, uid: string | null = UID): Promise<any> =>
  (estimateBodyScan as any).run(callReq(data, uid));

const SCAN_PATH = `users/${UID}/body_scans/${SCAN}`;
const SUBJECT = { sexAtBirth: "female", ageYears: 35, heightCm: 170, weightKg: 65.5 };
const PROVIDER = { id: "test-fake", version: "1.2.3", provisional: false, requiresPhotos: true };

const pendingDoc = (o: Record<string, unknown> = {}): any => ({
  schema: 1,
  createdAt: ts(now - MIN),
  takenAt: ts(now - MIN),
  weightKg: 65.5,
  status: "pending",
  pendingExpiresAt: ts(now + 47 * 60 * MIN),
  subject: SUBJECT,
  capture: { manualOverride: { front: false, side: true, back: false }, poses: ["front", "side", "back"] },
  provider: PROVIDER,
  photosState: "awaiting_upload",
  purgeAttempts: 0,
  ...o,
});

/** Photos whose bytes identify the pose (marker byte 1/2/3 at offset 10). */
function putMarkedPhotos(): void {
  putPhotos(UID, SCAN, { timeCreated: now - MIN });
  ["front", "side", "back"].forEach((pose, i) => {
    const o = gcs.objects.get(`users/${UID}/scans/${SCAN}/${pose}.jpg`)!;
    o.content[10] = i + 1;
  });
}

const scanWrites = (): typeof writes => writes.filter((w) => w.path === SCAN_PATH);

beforeEach(() => {
  resetFakes();
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  __resetAiGatewayControlCacheForTests();
  process.env.BODY_SCAN_BUCKET = BUCKET;
  process.env.BODY_SCAN_PROVIDER = "test-fake";
  fake = new FakePhotoEstimator();
  __setTestEstimatorForTests(fake);
  seedEligibleUser();
  seedScan(UID, SCAN, pendingDoc());
  putMarkedPhotos();
});

afterEach(() => {
  dateSpy.mockRestore();
  while (spies.length) spies.pop()!.mockRestore();
});

afterAll(() => {
  __setTestEstimatorForTests(undefined);
  delete process.env.BODY_SCAN_BUCKET;
  delete process.env.BODY_SCAN_PROVIDER;
});

describe("success path", () => {
  test("the provider gets the stored subject, capture flags and the three photos; the validated estimate is stored and returned", async () => {
    const res = await run();

    expect(fake.calls).toHaveLength(1);
    const input = fake.calls[0];
    expect(input.scanId).toBe(SCAN);
    expect(input.subject).toEqual(SUBJECT); // server-validated snapshot, not request data
    expect(input.capture).toEqual({ manualOverride: { front: false, side: true, back: false } });
    expect(Buffer.isBuffer(input.photos!.front)).toBe(true);
    expect(input.photos!.front[10]).toBe(1);
    expect(input.photos!.side[10]).toBe(2);
    expect(input.photos!.back[10]).toBe(3);

    expect(res).toEqual({
      scanId: SCAN,
      status: "done",
      provider: PROVIDER,
      estimate: {
        bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium",
        checkCodes: ["looseClothing"], modelId: "test-fake", modelVersion: "1.2.3", estimatedAtMs: now,
      },
      serverNowMs: now,
    });

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("done");
    expect(doc.estimate).toEqual({
      bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "medium",
      checkCodes: ["looseClothing"], modelId: "test-fake", modelVersion: "1.2.3", estimatedAt: ts(now),
    });
    expect(doc.photosState).toBe("stored");
    expect(doc.photosExpireAt).toEqual(ts(now + 30 * DAY)); // retentionDays 30
    for (const gone of ["pendingExpiresAt", "estimateLeaseUntil", "estimateCharged"]) {
      expect(gone in doc).toBe(false);
    }
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
    // Retention 30: the photos are kept.
    expect(objectKeys()).toHaveLength(3);
  });

  test.each([
    [30, 30 * DAY], [90, 90 * DAY], [365, 365 * DAY],
  ])("retention %i days -> photosExpireAt = now + %i ms, photos kept, state stored", async (days, ms) => {
    store.set(`users/${UID}/body_scan_settings/main`, { cloudConsent: { version: 1 }, retentionDays: days });
    await run();
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.photosState).toBe("stored");
    expect(doc.photosExpireAt).toEqual(ts(now + ms));
    expect(objectKeys()).toHaveLength(3);
    expect(gcs.deleteFilesCalls).toEqual([]);
  });

  test("check codes from the provider are de-duplicated and unknown extra provider keys never reach the document", async () => {
    fake.behaviour = async () => ({
      ...VALID_OUTPUT, checkCodes: ["poorLighting", "poorLighting", "weightMissing"], secret: "x", note: "free text",
    } as any);
    await run();
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.estimate.checkCodes).toEqual(["poorLighting", "weightMissing"]);
    expect(JSON.stringify(doc)).not.toContain("free text");
    expect(Object.keys(doc.estimate).sort()).toEqual([
      "bodyFatPct", "checkCodes", "confidence", "estimatedAt", "modelId", "modelVersion", "rangeHighPct", "rangeLowPct",
    ]);
  });

  test("the structured log has the outcome and provider id/version only: no uid, path, scan id or body metric", async () => {
    fake.behaviour = async () => ({ ...VALID_OUTPUT, bodyFatPct: 21.37, rangeLowPct: 18.11, rangeHighPct: 24.93 });
    await run();
    const events = bodyScanEvents(logger);
    expect(events).toHaveLength(1);
    expect(events[0]).toMatchObject({ operation: "bodyScanEstimate", outcome: "done", providerId: "test-fake", providerVersion: "1.2.3" });
    const text = loggedText(logger);
    for (const secret of [UID, SCAN, "users/", "21.37", "18.11", "24.93", "65.5"]) {
      expect(text).not.toContain(secret);
    }
  });
});

describe("retention 0 (delete after analysis)", () => {
  test.each([
    ["no settings document", undefined],
    ["retentionDays 0", { cloudConsent: { version: 1 }, retentionDays: 0 }],
    ["retentionDays malformed (7)", { cloudConsent: { version: 1 }, retentionDays: 7 }],
    ["retentionDays a string", { cloudConsent: { version: 1 }, retentionDays: "30" }],
  ])("%s -> objects deleted inline and photosState deleted", async (_name, settings) => {
    if (settings === undefined) store.delete(`users/${UID}/body_scan_settings/main`);
    else store.set(`users/${UID}/body_scan_settings/main`, settings as any);
    const res = await run();

    expect(res.status).toBe("done");
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("done");
    expect(doc.photosState).toBe("deleted");
    expect(doc.photosDeletedAt).toEqual(ts(now));
    expect("photosExpireAt" in doc).toBe(false);
    expect(objectKeys()).toEqual([]);
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).toEqual([`users/${UID}/scans/${SCAN}/`]);
    // The estimate is persisted BEFORE the objects go (a crash keeps the result).
    const written = timeline.indexOf(`fs:update:${SCAN_PATH}`);
    const deleted = timeline.indexOf(`gcs:deleteFiles:users/${UID}/scans/${SCAN}/`);
    expect(written).toBeGreaterThanOrEqual(0);
    expect(deleted).toBeGreaterThan(written);
  });

  test("a failing object delete -> the call still succeeds, the photos stay `stored` with photosExpireAt = now so the purge retries at once", async () => {
    store.set(`users/${UID}/body_scan_settings/main`, { cloudConsent: { version: 1 }, retentionDays: 0 });
    gcs.failOn = (op) => (op === "deleteFiles" ? firestoreError(`cannot delete users/${UID}`, 503) : undefined);
    const res = await run();

    expect(res.status).toBe("done");
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("done");
    expect(doc.photosState).toBe("stored");
    expect(doc.photosExpireAt).toEqual(ts(now));
    expect(objectKeys()).toHaveLength(3);
    const warn = bodyScanEvents(logger, "warn");
    expect(warn).toEqual([{ operation: "bodyScanEstimate", outcome: "inline-delete-failed", errorCode: "503" }]);
    expect(loggedText(logger)).not.toContain(UID);
  });

  test("objects deleted but the follow-up document update fails -> still `stored` with photosExpireAt = now", async () => {
    store.set(`users/${UID}/body_scan_settings/main`, { cloudConsent: { version: 1 }, retentionDays: 0 });
    fx.failOn = (op, path) => (op === "update" && path === SCAN_PATH ? firestoreError("x", "unavailable") : undefined);
    const res = await run();
    expect(res.status).toBe("done");
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.photosState).toBe("stored");
    expect(doc.photosExpireAt).toEqual(ts(now));
  });

  test("a failing settings read falls back to the privacy-protective default (retention 0)", async () => {
    fx.failOn = (op, path) => (op === "get" && path.endsWith("body_scan_settings/main") ? firestoreError("x", "unavailable") : undefined);
    await run();
    expect(scanDoc(UID, SCAN)!.photosState).toBe("deleted");
    expect(objectKeys()).toEqual([]);
  });
});

describe("done replay", () => {
  test("a done scan returns the stored entry with zero provider calls, zero quota, zero document writes and no storage reads", async () => {
    seedScan(UID, SCAN, {
      status: "done",
      photosState: "stored",
      provider: PROVIDER,
      estimate: {
        bodyFatPct: 25, rangeLowPct: 22, rangeHighPct: 28, confidence: "low", checkCodes: [],
        modelId: "test-fake", modelVersion: "0.9", estimatedAt: ts(T0 - DAY),
      },
    });
    const before = JSON.stringify(scanDoc(UID, SCAN));
    const res = await run();

    expect(res).toEqual({
      scanId: SCAN,
      status: "done",
      provider: PROVIDER,
      estimate: {
        bodyFatPct: 25, rangeLowPct: 22, rangeHighPct: 28, confidence: "low", checkCodes: [],
        modelId: "test-fake", modelVersion: "0.9", estimatedAtMs: T0 - DAY,
      },
      serverNowMs: now,
    });
    expect(fake.calls).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(writes).toEqual([]);
    expect(JSON.stringify(scanDoc(UID, SCAN))).toBe(before);
    expect(gcs.downloadCalls).toEqual([]);
  });

  test("a done replay works even when the provider is not configured (it never needs one)", async () => {
    seedScan(UID, SCAN, { status: "done", photosState: "deleted", provider: PROVIDER, estimate: { bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "low", checkCodes: [], modelId: "a", modelVersion: "b", estimatedAt: ts(T0) } });
    delete process.env.BODY_SCAN_PROVIDER;
    expect((await run()).status).toBe("done");
  });
});

describe("request and state errors (no provider call, no charge)", () => {
  test.each([
    ["scanId missing", {}],
    ["scanId too short", { scanId: "abc" }],
    ["scanId with a slash", { scanId: "abcd/efgh" }],
    ["body null", null],
  ])("%s -> invalid-argument invalid-scan-id", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-scan-id");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(fake.calls).toEqual([]);
  });

  test("unknown scan -> not-found scan-not-found", async () => {
    await expectHttpsError(run({ scanId: "other_scan_1" }), "not-found", "scan-not-found");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });

  test("a scan of ANOTHER user is not visible (path is derived from the caller's uid)", async () => {
    store.set(`users/someone_else/body_scans/theirs_scan_1`, pendingDoc());
    await expectHttpsError(run({ scanId: "theirs_scan_1" }), "not-found", "scan-not-found");
    expect(fake.calls).toEqual([]);
  });

  test.each([
    ["cancelled", "scan-cancelled"],
    ["failed", "scan-failed"],
  ])("a %s scan -> failed-precondition %s", async (status, slug) => {
    seedScan(UID, SCAN, pendingDoc({ status }));
    await expectHttpsError(run(), "failed-precondition", slug);
    expect(fake.calls).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(scanWrites()).toEqual([]);
  });

  test.each([
    ["photosState none", { photosState: "none" }],
    ["photosState deleted", { photosState: "deleted" }],
    ["photosState stored", { photosState: "stored" }],
  ])("a pending scan with %s -> scan-not-ready, charge refunded", async (_n, patch) => {
    seedScan(UID, SCAN, pendingDoc(patch));
    await expectHttpsError(run(), "failed-precondition", "scan-not-ready");
    expect(fake.calls).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });

  test("no provider configured -> provider-not-configured before any charge or lease", async () => {
    delete process.env.BODY_SCAN_PROVIDER;
    await expectHttpsError(run(), "failed-precondition", "provider-not-configured");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(scanWrites()).toEqual([]);
  });

  test("daily quota exhausted -> resource-exhausted, no lease, no provider call", async () => {
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanEstimate: 14 });
    await expectHttpsError(run(), "resource-exhausted");
    expect(fake.calls).toEqual([]);
    expect(scanWrites()).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(14);
  });
});

describe("processing lease (D-53)", () => {
  test("two concurrent calls make exactly ONE provider call; the loser answers estimate-in-progress and its charge is refunded", async () => {
    const gate = require("./fakes").barrier(2) as () => Promise<void>;
    fx.afterTxRead = async (path) => {
      if (path === SCAN_PATH) await gate();
    };
    let release!: () => void;
    const hold = new Promise<void>((r) => { release = r; });
    fake.behaviour = async () => {
      await hold;
      return { ...VALID_OUTPUT };
    };

    // Handlers are attached at once so the loser's early rejection is never unhandled.
    const settled = Promise.allSettled([run(), run()]);
    // Wait until the winner is inside the provider (the loser has settled by then).
    for (let i = 0; i < 200 && fake.calls.length === 0; i++) await new Promise((r) => setImmediate(r));
    expect(fake.calls).toHaveLength(1);
    release();
    const results = await settled;

    const ok = results.filter((r) => r.status === "fulfilled");
    const bad = results.filter((r) => r.status === "rejected") as PromiseRejectedResult[];
    expect(ok).toHaveLength(1);
    expect(bad).toHaveLength(1);
    expect(bad[0].reason.code).toBe("failed-precondition");
    expect(bad[0].reason.message).toBe("estimate-in-progress");
    expect(fake.calls).toHaveLength(1);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
    expect(scanDoc(UID, SCAN)!.status).toBe("done");
  });

  test("a live lease held by another call -> estimate-in-progress, no provider call, no charge", async () => {
    seedScan(UID, SCAN, pendingDoc({ estimateLeaseUntil: ts(now + 30 * 1000) }));
    await expectHttpsError(run(), "failed-precondition", "estimate-in-progress");
    expect(fake.calls).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(scanWrites()).toEqual([]);
  });

  test("an expired lease is taken over; a scan already marked charged is not charged again", async () => {
    seedScan(UID, SCAN, pendingDoc({ estimateLeaseUntil: ts(now - 1), estimateCharged: true }));
    const res = await run();
    expect(res.status).toBe("done");
    expect(fake.calls).toHaveLength(1);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });

  test("the lease taken is 60 s and the charge marker is recorded while the provider runs", async () => {
    let seen: any;
    fake.behaviour = async () => {
      seen = { ...scanDoc(UID, SCAN)! };
      return { ...VALID_OUTPUT };
    };
    await run();
    expect(seen.estimateLeaseUntil).toEqual(ts(now + 60 * 1000));
    expect(seen.estimateCharged).toBe(true);
  });

  test("a Firestore failure while taking the lease -> internal scan-estimate-failed and the charge is refunded", async () => {
    fx.failOn = (op, path) => (op === "commit" && path.includes("body_scans") ? firestoreError("x", "unavailable") : undefined);
    await expectHttpsError(run(), "internal", "scan-estimate-failed");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(fake.calls).toEqual([]);
  });
});

describe("a delete racing the estimate (D-59)", () => {
  test("tombstone written while the provider runs -> scan-cancelled, nothing written over the tombstone, charge refunded", async () => {
    const tombstone = { status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(now + 48 * 60 * MIN) };
    fake.behaviour = async () => {
      seedScan(UID, SCAN, tombstone);
      return { ...VALID_OUTPUT };
    };
    await expectHttpsError(run(), "failed-precondition", "scan-cancelled");

    expect(scanDoc(UID, SCAN)).toEqual(tombstone);
    expect("estimate" in scanDoc(UID, SCAN)!).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(bodyScanEvents(logger).map((e) => e.outcome)).toEqual(["raced-delete"]);
  });

  test("the document removed while the provider runs (account erased) -> scan-cancelled, no document resurrected", async () => {
    fake.behaviour = async () => {
      store.delete(SCAN_PATH);
      return { ...VALID_OUTPUT };
    };
    await expectHttpsError(run(), "failed-precondition", "scan-cancelled");
    expect(scanDoc(UID, SCAN)).toBeUndefined();
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });

  test("photos-only delete while the provider runs (photosState deleted) -> scan-cancelled", async () => {
    fake.behaviour = async () => {
      seedScan(UID, SCAN, pendingDoc({ photosState: "deleted" }));
      return { ...VALID_OUTPUT };
    };
    await expectHttpsError(run(), "failed-precondition", "scan-cancelled");
    expect("estimate" in scanDoc(UID, SCAN)!).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });
});

describe("read-time upload checks (a PUT can overwrite an object while its URL lives)", () => {
  test("a missing pose -> failed-precondition missing-upload:<poses>; provider not called; lease cleared; the charge STAYS on the scan", async () => {
    gcs.objects.delete(`users/${UID}/scans/${SCAN}/side.jpg`);
    await expectHttpsError(run(), "failed-precondition", "missing-upload:side");

    expect(fake.calls).toEqual([]);
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect(doc.estimateCharged).toBe(true);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
  });

  test("after the user re-uploads, the retry succeeds WITHOUT a second charge", async () => {
    gcs.objects.delete(`users/${UID}/scans/${SCAN}/side.jpg`);
    await expectHttpsError(run(), "failed-precondition", "missing-upload:side");
    putMarkedPhotos();
    const res = await run();
    expect(res.status).toBe("done");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
    expect(fake.calls).toHaveLength(1);
  });

  test("all poses missing are listed in canonical order", async () => {
    gcs.objects.clear();
    await expectHttpsError(run(), "failed-precondition", "missing-upload:front,side,back");
    expect(fake.calls).toEqual([]);
  });

  test.each([
    ["wrong content type", (p: string) => { gcs.objects.get(p)!.contentType = "image/png"; }],
    ["1023 bytes (below the minimum)", (p: string) => { gcs.objects.get(p)!.content = jpegBytes(1023); }],
    ["3 MiB + 1 byte (above the maximum)", (p: string) => { gcs.objects.get(p)!.content = jpegBytes(3 * 1024 * 1024 + 1); }],
    ["JPEG content type but PNG bytes", (p: string) => { const c = jpegBytes(2048); c[0] = 0x89; c[1] = 0x50; c[2] = 0x4e; gcs.objects.get(p)!.content = c; }],
    ["empty object", (p: string) => { gcs.objects.get(p)!.content = Buffer.alloc(0); }],
  ])("an invalid upload (%s) is treated as missing", async (_n, corrupt) => {
    corrupt(`users/${UID}/scans/${SCAN}/back.jpg`);
    await expectHttpsError(run(), "failed-precondition", "missing-upload:back");
    expect(fake.calls).toEqual([]);
  });

  test.each([
    ["exactly 1024 bytes", 1024],
    ["exactly 3 MiB", 3 * 1024 * 1024],
  ])("%s is accepted", async (_n, size) => {
    gcs.objects.get(`users/${UID}/scans/${SCAN}/front.jpg`)!.content = jpegBytes(size);
    expect((await run()).status).toBe("done");
  });

  test("a storage failure other than 404 -> internal scan-estimate-failed, lease and charge marker cleared, charge refunded, log has the code only", async () => {
    gcs.failOn = (op, name) => (op === "getMetadata" && name.endsWith("front.jpg") ? firestoreError(`denied ${name}`, 403) : undefined);
    await expectHttpsError(run(), "internal", "scan-estimate-failed");

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect("estimateCharged" in doc).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(fake.calls).toEqual([]);
    expect(bodyScanEvents(logger, "error")).toEqual([{ operation: "bodyScanEstimate", outcome: "storage-failed", errorCode: "403" }]);
    expect(loggedText(logger)).not.toContain("denied");
    expect(loggedText(logger)).not.toContain(UID);
  });
});

describe("provider failures", () => {
  test("a transient provider error -> unavailable provider-unavailable; refund; lease and marker cleared; scan stays pending and retryable", async () => {
    fake.behaviour = async () => { throw new Error(`vendor said no for ${UID}`); };
    await expectHttpsError(run(), "unavailable", "provider-unavailable");

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect(doc.photosState).toBe("awaiting_upload");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect("estimateCharged" in doc).toBe(false);
    expect("estimate" in doc).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(objectKeys()).toHaveLength(3);
    expect(bodyScanEvents(logger, "warn").map((e) => e.outcome)).toEqual(["provider-error"]);
    expect(loggedText(logger)).not.toContain("vendor said no");
    expect(loggedText(logger)).not.toContain(UID);

    // Retry works and is charged exactly once in total.
    fake.behaviour = async () => ({ ...VALID_OUTPUT });
    expect((await run()).status).toBe("done");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
  });

  test("EstimatorTerminalError -> scan-failed; document `failed`; lease and marker cleared; refund; later calls say scan-failed without charging", async () => {
    fake.behaviour = async () => { throw new EstimatorTerminalError("vendor rejected the photos"); };
    await expectHttpsError(run(), "failed-precondition", "scan-failed");

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("failed");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect("estimateCharged" in doc).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(bodyScanEvents(logger, "warn").map((e) => e.outcome)).toEqual(["provider-terminal"]);

    fake.calls.length = 0;
    await expectHttpsError(run(), "failed-precondition", "scan-failed");
    expect(fake.calls).toEqual([]);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
  });

  test("a terminal failure racing a delete does not overwrite the tombstone with `failed`", async () => {
    const tombstone = { status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(now + DAY) };
    fake.behaviour = async () => {
      seedScan(UID, SCAN, tombstone);
      throw new EstimatorTerminalError();
    };
    await expectHttpsError(run(), "failed-precondition", "scan-failed");
    expect(scanDoc(UID, SCAN)).toEqual(tombstone);
  });

  test("the provider runs under a 25 s timeout: a hung provider -> provider-unavailable, refund, scan still pending", async () => {
    expect(ESTIMATE_TIMEOUT_MS).toBe(25000);
    const realSetTimeout = global.setTimeout;
    const delays: number[] = [];
    spies[spies.push(jest.spyOn(global, "setTimeout")) - 1].mockImplementation(((cb: any, ms?: number, ...args: any[]) => {
      delays.push(ms ?? 0);
      return realSetTimeout(cb, ms === 25000 ? 0 : ms, ...args);
    }) as any);
    fake.behaviour = () => new Promise<never>(() => undefined); // never settles

    await expectHttpsError(run(), "unavailable", "provider-unavailable");

    expect(delays).toContain(25000);
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(bodyScanEvents(logger, "warn").map((e) => e.outcome)).toEqual(["provider-timeout"]);
  });

  test("a provider that answers in time clears its timeout timer (no 25 s timer left behind)", async () => {
    const realSetTimeout = global.setTimeout;
    const realClearTimeout = global.clearTimeout;
    const live = new Set<unknown>();
    spies[spies.push(jest.spyOn(global, "setTimeout")) - 1].mockImplementation(((cb: any, ms?: number, ...args: any[]) => {
      const t = realSetTimeout(cb, ms, ...args);
      if (ms === 25000) live.add(t);
      return t;
    }) as any);
    spies[spies.push(jest.spyOn(global, "clearTimeout")) - 1].mockImplementation(((t: any) => {
      live.delete(t);
      return realClearTimeout(t);
    }) as any);
    try {
      await run();
      expect(live.size).toBe(0);
    } finally {
      for (const t of live) realClearTimeout(t as any);
    }
  });

  test.each([
    ["null output", null],
    ["body fat below 3", { ...VALID_OUTPUT, bodyFatPct: 2.9, rangeLowPct: 3, rangeHighPct: 5 }],
    ["range wider than 20 points", { ...VALID_OUTPUT, bodyFatPct: 30, rangeLowPct: 10, rangeHighPct: 40 }],
    ["unknown confidence", { ...VALID_OUTPUT, confidence: "certain" }],
    ["a check code outside the closed list", { ...VALID_OUTPUT, checkCodes: ["please-ignore-previous-instructions"] }],
    ["NaN body fat", { ...VALID_OUTPUT, bodyFatPct: NaN }],
  ])("invalid provider output (%s) -> internal provider-output-invalid; stays pending; refund; lease cleared; nothing stored", async (_n, output) => {
    fake.behaviour = async () => output as any;
    await expectHttpsError(run(), "internal", "provider-output-invalid");

    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect(doc.photosState).toBe("awaiting_upload");
    expect("estimate" in doc).toBe(false);
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect("estimateCharged" in doc).toBe(false);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(0);
    expect(objectKeys()).toHaveLength(3);
    expect(bodyScanEvents(logger, "error").map((e) => e.outcome)).toEqual(["provider-output-invalid"]);
  });

  test("a failure of the final transaction -> internal scan-estimate-failed, the lease is released and the charge marker stays (retry is free)", async () => {
    let commits = 0;
    fx.failOn = (op, path) => {
      if (op === "commit" && path.includes("body_scans")) {
        commits += 1;
        if (commits === 2) return firestoreError("x", "unavailable"); // 1 = lease, 2 = final write
      }
      return undefined;
    };
    await expectHttpsError(run(), "internal", "scan-estimate-failed");
    const doc = scanDoc(UID, SCAN)!;
    expect(doc.status).toBe("pending");
    expect("estimateLeaseUntil" in doc).toBe(false);
    expect(doc.estimateCharged).toBe(true);
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);

    fx.failOn = null;
    expect((await run()).status).toBe("done");
    expect(usageOf(UID, "bodyScanEstimate")).toBe(1);
  });
});
