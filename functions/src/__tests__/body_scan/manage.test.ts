/**
 * `manageBodyScanData` (design s7.8, D-62): applyRetention, deleteAllPhotos,
 * deleteAllScans (paged, cursor) and exportLinks (1 h READ URLs, <= 60 per call,
 * newest first). Own quota (`bodyScanManage`) so "delete all" is never blocked
 * by the per-scan delete limit.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import { manageBodyScanData } from "../../body_scan/manage";
import { deleteFenceActive } from "../../body_scan/shared";
import { __resetAiGatewayControlCacheForTests } from "../../abuse_guard";
import {
  BUCKET, DAY, HOUR, T0, UID,
  bodyScanEvents, callReq, expectHttpsError, firestoreError, fx, gcs, loggedText, objectKeys,
  putPhotos, resetFakes, scanDoc, seedEligibleUser, seedScan, store, timeline, ts, usageOf, writes,
} from "./fakes";

let now = T0;
let dateSpy: jest.SpyInstance;

const run = (data: unknown, uid: string | null = UID): Promise<any> =>
  (manageBodyScanData as any).run(callReq(data, uid));

const USER_PREFIX = `users/${UID}/scans/`;
const sid = (n: number): string => `scan_${String(n).padStart(4, "0")}`;
const scanPrefix = (id: string): string => `users/${UID}/scans/${id}/`;

function seedStored(id: string, takenAtMs: number, o: Record<string, unknown> = {}, photos = true): void {
  seedScan(UID, id, {
    schema: 1,
    createdAt: ts(takenAtMs),
    takenAt: ts(takenAtMs),
    weightKg: 70,
    clientNote: "note",
    status: "done",
    subject: { sexAtBirth: "male", ageYears: 40, heightCm: 180, weightKg: 70 },
    capture: { manualOverride: { front: false, side: false, back: false }, poses: ["front", "side", "back"] },
    provider: { id: "test-fake", version: "1", provisional: false, requiresPhotos: true },
    estimate: { bodyFatPct: 20, rangeLowPct: 17, rangeHighPct: 23, confidence: "low", checkCodes: [], modelId: "a", modelVersion: "b", estimatedAt: ts(takenAtMs) },
    photosState: "stored",
    photosExpireAt: ts(now + 30 * DAY),
    purgeAttempts: 0,
    ...o,
  });
  if (photos) putPhotos(UID, id);
}

beforeEach(() => {
  resetFakes();
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  __resetAiGatewayControlCacheForTests();
  process.env.BODY_SCAN_BUCKET = BUCKET;
  seedEligibleUser();
});

afterEach(() => {
  dateSpy.mockRestore();
});

afterAll(() => {
  delete process.env.BODY_SCAN_BUCKET;
});

describe("validation and quota", () => {
  test.each([
    ["no action", {}],
    ["unknown action", { action: "deleteEverything" }],
    ["action not a string", { action: 3 }],
    ["body null", null],
  ])("%s -> invalid-argument invalid-action, nothing charged", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-action");
    expect(usageOf(UID, "bodyScanManage")).toBe(0);
  });

  test.each([
    ["missing", { action: "applyRetention" }],
    ["7", { action: "applyRetention", retentionDays: 7 }],
    ["the string '30'", { action: "applyRetention", retentionDays: "30" }],
    ["negative", { action: "applyRetention", retentionDays: -1 }],
    ["366", { action: "applyRetention", retentionDays: 366 }],
  ])("applyRetention with retentionDays %s -> invalid-retention", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-retention");
    expect(usageOf(UID, "bodyScanManage")).toBe(0);
  });

  test.each([
    ["non-string cursor", { action: "deleteAllPhotos", cursor: 5 }],
    ["paged cursor too short", { action: "deleteAllScans", cursor: "abc" }],
    ["paged cursor with a slash", { action: "deleteAllScans", cursor: "abcd/efgh" }],
    ["paged cursor with a space", { action: "applyRetention", retentionDays: 30, cursor: "abcd efgh" }],
    ["export cursor not numeric", { action: "exportLinks", cursor: "abcdefgh" }],
    ["export cursor negative", { action: "exportLinks", cursor: "-5" }],
    ["export cursor too long", { action: "exportLinks", cursor: "1".repeat(17) }],
    ["export cursor empty", { action: "exportLinks", cursor: "" }],
    ["export cursor is a bare timestamp (no scan id)", { action: "exportLinks", cursor: "1700000000000" }],
    ["export cursor with a bad id part", { action: "exportLinks", cursor: "1700000000000:a/b" }],
  ])("%s -> invalid-cursor", async (_n, data) => {
    await expectHttpsError(run(data), "invalid-argument", "invalid-cursor");
  });

  test("each call charges one bodyScanManage unit (and never bodyScanDelete)", async () => {
    await run({ action: "deleteAllPhotos" });
    expect(usageOf(UID, "bodyScanManage")).toBe(1);
    expect(usageOf(UID, "bodyScanDelete")).toBe(0);
  });

  test("at the bodyScanManage limit (30) -> resource-exhausted and nothing is deleted", async () => {
    seedStored(sid(1), now - DAY);
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanManage: 30 });
    await expectHttpsError(run({ action: "deleteAllScans" }), "resource-exhausted");
    expect(scanDoc(UID, sid(1))!.status).toBe("done");
    expect(objectKeys()).toHaveLength(3);
  });

  test("an exhausted per-scan delete quota (60) does NOT stop delete-all", async () => {
    seedStored(sid(1), now - DAY);
    store.set(`users/${UID}/usage/${new Date().toISOString().slice(0, 10)}`, { bodyScanDelete: 60 });
    const res = await run({ action: "deleteAllScans" });
    expect(res.processed).toBe(1);
    expect(scanDoc(UID, sid(1))!.status).toBe("cancelled");
  });
});

describe("applyRetention (a LOWERED retention made retroactive)", () => {
  test("photos past takenAt + retention are deleted, longer ones are shortened, shorter ones and non-stored scans are untouched", async () => {
    seedStored("scan_old_1", now - 100 * DAY, { photosExpireAt: ts(now + 265 * DAY) }); // 100 d old, 30 d retention -> due
    seedStored("scan_mid_1", now - 10 * DAY, { photosExpireAt: ts(now + 80 * DAY) }); // -> shortened to takenAt+30d
    seedStored("scan_sho_1", now - 10 * DAY, { photosExpireAt: ts(now + 5 * DAY) }); // already earlier: never extended
    seedStored("scan_del_1", now - 100 * DAY, { photosState: "deleted" }, false);
    seedStored("scan_pen_1", now - 100 * DAY, { status: "pending", photosState: "awaiting_upload" });
    seedStored("scan_nta_1", now - 100 * DAY, {}); // lacks takenAt (below)
    const noTaken = { ...store.get(`users/${UID}/body_scans/scan_nta_1`)! };
    delete noTaken.takenAt;
    store.set(`users/${UID}/body_scans/scan_nta_1`, noTaken);

    const res = await run({ action: "applyRetention", retentionDays: 30 });

    expect(res).toMatchObject({ action: "applyRetention", processed: 6, serverNowMs: now });
    expect(res.nextCursor).toBeUndefined();

    const old = scanDoc(UID, "scan_old_1")!;
    expect(old.photosState).toBe("deleted");
    expect(old.photosDeletedAt).toEqual(ts(now));
    expect("photosExpireAt" in old).toBe(false);
    expect(old.status).toBe("done"); // the scan and its estimate stay
    expect(objectKeys(scanPrefix("scan_old_1"))).toEqual([]);

    const mid = scanDoc(UID, "scan_mid_1")!;
    expect(mid.photosState).toBe("stored");
    expect(mid.photosExpireAt).toEqual(ts(now - 10 * DAY + 30 * DAY));
    expect(objectKeys(scanPrefix("scan_mid_1"))).toHaveLength(3);

    const sho = scanDoc(UID, "scan_sho_1")!;
    expect(sho.photosExpireAt).toEqual(ts(now + 5 * DAY));
    expect(objectKeys(scanPrefix("scan_sho_1"))).toHaveLength(3);

    expect(scanDoc(UID, "scan_pen_1")!.photosState).toBe("awaiting_upload");
    expect(objectKeys(scanPrefix("scan_pen_1"))).toHaveLength(3);
    expect(scanDoc(UID, "scan_nta_1")!.photosState).toBe("stored");
    expect(objectKeys(scanPrefix("scan_nta_1"))).toHaveLength(3);
    // Only the one due scan caused an object delete; there is no whole-user sweep here.
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).toEqual([scanPrefix("scan_old_1")]);
  });

  test("retention 0 makes every stored photo due", async () => {
    seedStored("scan_aaa_1", now - HOUR);
    seedStored("scan_bbb_1", now - 2 * DAY);
    await run({ action: "applyRetention", retentionDays: 0 });
    for (const id of ["scan_aaa_1", "scan_bbb_1"]) {
      expect(scanDoc(UID, id)!.photosState).toBe("deleted");
      expect(objectKeys(scanPrefix(id))).toEqual([]);
    }
  });

  test("a photo exactly at the boundary (takenAt + retention == now) is due", async () => {
    seedStored("scan_edge_1", now - 30 * DAY, { photosExpireAt: ts(now + DAY) });
    await run({ action: "applyRetention", retentionDays: 30 });
    expect(scanDoc(UID, "scan_edge_1")!.photosState).toBe("deleted");
  });

  test("another user's scans are never touched", async () => {
    store.set("users/other_user/body_scans/scan_oth_1", { status: "done", photosState: "stored", takenAt: ts(now - 400 * DAY), photosExpireAt: ts(now + DAY) });
    putPhotos("other_user", "scan_oth_1");
    seedStored("scan_own_1", now - 400 * DAY);
    await run({ action: "applyRetention", retentionDays: 30 });
    expect(store.get("users/other_user/body_scans/scan_oth_1")!.photosState).toBe("stored");
    expect(objectKeys("users/other_user/")).toHaveLength(3);
    expect(scanDoc(UID, "scan_own_1")!.photosState).toBe("deleted");
  });
});

describe("deleteAllPhotos", () => {
  test("every scan with photos is marked deleted and its objects removed; scans and estimates stay; already-deleted scans cost no object call", async () => {
    seedStored("scan_one_1", now - DAY);
    seedStored("scan_two_1", now - 2 * DAY, { status: "pending", photosState: "awaiting_upload", estimate: undefined });
    seedStored("scan_thr_1", now - 3 * DAY, { photosState: "deleted" }, false);
    seedStored("scan_fou_1", now - 4 * DAY, { photosState: "none" }, false);

    const res = await run({ action: "deleteAllPhotos" });

    expect(res).toMatchObject({ action: "deleteAllPhotos", processed: 4 });
    for (const id of ["scan_one_1", "scan_two_1"]) {
      const d = scanDoc(UID, id)!;
      expect(d.photosState).toBe("deleted");
      expect(d.photosDeletedAt).toEqual(ts(now));
      expect("photosExpireAt" in d).toBe(false);
    }
    expect(scanDoc(UID, "scan_one_1")!.status).toBe("done");
    expect(scanDoc(UID, "scan_one_1")!.estimate.bodyFatPct).toBe(20);
    expect(scanDoc(UID, "scan_two_1")!.status).toBe("pending");
    expect(objectKeys()).toEqual([]);
    const prefixes = gcs.deleteFilesCalls.map((c) => c.prefix);
    expect(prefixes).not.toContain(scanPrefix("scan_thr_1"));
    expect(prefixes).not.toContain(scanPrefix("scan_fou_1"));
    // Final page: the whole-user sweep.
    expect(prefixes[prefixes.length - 1]).toBe(USER_PREFIX);
  });

  test("the objects are deleted before the document is marked deleted (per scan, DB-F7)", async () => {
    seedStored("scan_one_1", now - DAY);
    await run({ action: "deleteAllPhotos" });
    const marked = timeline.indexOf(`fs:update:users/${UID}/body_scans/scan_one_1`);
    const deleted = timeline.indexOf(`gcs:deleteFiles:${scanPrefix("scan_one_1")}`);
    expect(deleted).toBeGreaterThanOrEqual(0);
    expect(marked).toBeGreaterThan(deleted);
  });

  test("an object-delete failure leaves the scan photosState stored (never 'deleted' over surviving objects)", async () => {
    seedStored("scan_one_1", now - DAY);
    gcs.failOn = (op) => (op === "deleteFiles" ? firestoreError("x", 503) : undefined);
    await expectHttpsError(run({ action: "deleteAllPhotos" }), "internal", "scan-manage-failed");
    expect(scanDoc(UID, "scan_one_1")!.photosState).toBe("stored");
    expect(objectKeys(scanPrefix("scan_one_1"))).toHaveLength(3);
  });

  test("the final sweep also removes objects no document accounts for (a late PUT, a document-less object)", async () => {
    putPhotos(UID, "ghost_scan_1");
    putPhotos("other_user", "scan_oth_1");
    await run({ action: "deleteAllPhotos" });
    expect(objectKeys(USER_PREFIX)).toEqual([]);
    expect(objectKeys("users/other_user/")).toHaveLength(3); // only THIS user's prefix
  });
});

describe("deleteAllScans", () => {
  test("every scan becomes a scrubbed 48 h tombstone; an existing tombstone is not rewritten but its objects are re-swept", async () => {
    seedStored("scan_one_1", now - DAY);
    seedScan(UID, "scan_cxl_1", { schema: 1, createdAt: ts(now - DAY), status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(now + HOUR), purgeAttempts: 0 });
    putPhotos(UID, "scan_cxl_1"); // a late PUT under a tombstone
    const before = JSON.stringify(scanDoc(UID, "scan_cxl_1"));

    const res = await run({ action: "deleteAllScans" });

    expect(res).toMatchObject({ action: "deleteAllScans", processed: 2 });
    const doc = scanDoc(UID, "scan_one_1")!;
    expect(doc.status).toBe("cancelled");
    expect(doc.photosState).toBe("deleted");
    expect(doc.pendingExpiresAt).toEqual(ts(now + 48 * HOUR));
    for (const gone of ["subject", "estimate", "weightKg", "capture", "clientNote", "takenAt", "photosExpireAt"]) {
      expect(gone in doc).toBe(false);
    }
    expect(JSON.stringify(scanDoc(UID, "scan_cxl_1"))).toBe(before);
    expect(writes.filter((w) => w.path.endsWith("scan_cxl_1"))).toEqual([]);
    expect(objectKeys()).toEqual([]);
    expect(usageOf(UID, "bodyScanDelete")).toBe(0);
  });

  test("objects of a deleted scan with no document at all are removed by the final sweep", async () => {
    putPhotos(UID, "orphan_one_1");
    await run({ action: "deleteAllScans" });
    expect(objectKeys()).toEqual([]);
  });

  test("a delete-all with nothing to delete succeeds with processed 0", async () => {
    const res = await run({ action: "deleteAllScans" });
    expect(res).toMatchObject({ action: "deleteAllScans", processed: 0 });
    expect(res.nextCursor).toBeUndefined();
  });

  test("an object-delete failure -> internal scan-manage-failed with the error code only; the retry completes", async () => {
    seedStored("scan_one_1", now - DAY);
    gcs.failOn = (op, name) => (op === "deleteFiles" ? firestoreError(`cannot delete ${name} for ${UID}`, 503) : undefined);
    await expectHttpsError(run({ action: "deleteAllScans" }), "internal", "scan-manage-failed");
    expect(bodyScanEvents(logger, "error")).toEqual([{ operation: "bodyScanManage", outcome: "failed", action: "deleteAllScans", errorCode: "503" }]);
    expect(loggedText(logger)).not.toContain(UID);
    expect(loggedText(logger)).not.toContain("users/");

    gcs.failOn = null;
    await run({ action: "deleteAllScans" });
    expect(objectKeys()).toEqual([]);
    expect(scanDoc(UID, "scan_one_1")!.status).toBe("cancelled");
  });
});

describe("paging (200 scans per call, document-id order, cursor)", () => {
  test("250 scans take two calls: page 1 returns processed 200 and a nextCursor, the whole-user sweep runs only on the LAST page", async () => {
    for (let i = 1; i <= 250; i++) seedStored(sid(i), now - i * HOUR, {}, false);
    putPhotos(UID, "ghost_scan_1"); // swept only by the final page

    const first = await run({ action: "deleteAllScans" });
    expect(first.processed).toBe(200);
    expect(first.nextCursor).toBe(sid(200));
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).not.toContain(USER_PREFIX);
    expect(objectKeys(scanPrefix("ghost_scan_1"))).toHaveLength(3);
    expect(scanDoc(UID, sid(200))!.status).toBe("cancelled");
    expect(scanDoc(UID, sid(201))!.status).toBe("done");

    const second = await run({ action: "deleteAllScans", cursor: first.nextCursor });
    expect(second.processed).toBe(50);
    expect(second.nextCursor).toBeUndefined();
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).toContain(USER_PREFIX);
    expect(objectKeys()).toEqual([]);
    for (let i = 1; i <= 250; i++) expect(scanDoc(UID, sid(i))!.status).toBe("cancelled");
    expect(usageOf(UID, "bodyScanManage")).toBe(2);
  });

  test("exactly 200 scans: the first call still offers a cursor and the next call finds the end (processed 0)", async () => {
    for (let i = 1; i <= 200; i++) seedStored(sid(i), now - i * HOUR, { photosState: "deleted" }, false);
    const first = await run({ action: "deleteAllPhotos" });
    expect(first.processed).toBe(200);
    expect(first.nextCursor).toBe(sid(200));
    const second = await run({ action: "deleteAllPhotos", cursor: first.nextCursor });
    expect(second.processed).toBe(0);
    expect(second.nextCursor).toBeUndefined();
  });

  test("applyRetention pages the same way but never does the whole-user sweep", async () => {
    for (let i = 1; i <= 201; i++) seedStored(sid(i), now - 400 * DAY, {}, false);
    const first = await run({ action: "applyRetention", retentionDays: 30 });
    expect(first.processed).toBe(200);
    expect(first.nextCursor).toBe(sid(200));
    const second = await run({ action: "applyRetention", retentionDays: 30, cursor: first.nextCursor });
    expect(second.processed).toBe(1);
    expect(second.nextCursor).toBeUndefined();
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).not.toContain(USER_PREFIX);
    expect(scanDoc(UID, sid(201))!.photosState).toBe("deleted");
  });
});

const FENCE_PREFIX = "body_scan_purge_state/delete_fence_";
const LATE_PREFIX = "body_scan_purge_state/late_sweep_";
const fenceKeys = (): string[] => [...store.keys()].filter((k) => k.startsWith(FENCE_PREFIX));
const lateKeys = (): string[] => [...store.keys()].filter((k) => k.startsWith(LATE_PREFIX));
const FENCE_MS = 15 * 60 * 1000;
/** Upload URL TTL (10 min) + 2 min margin. */
const LATE_DELAY_MS = 12 * 60 * 1000;
/** The registered runs of this user's fence document (empty when the document is gone). */
const runsOf = (): Record<string, any> => (fenceKeys().length ? store.get(fenceKeys()[0])!.runs : {});
/** True when a create would be refused right now. */
const fenceOn = (): boolean => deleteFenceActive(fenceKeys().length ? store.get(fenceKeys()[0]) : undefined, now);
const TOKEN = /^[0-9a-f]{32}$/;

describe("bulk-delete fence and straggler pass (a scan created behind the cursor)", () => {
  test("page 1 raises a 15 min fence (uid-free id), a continuation refreshes it, the final page clears it", async () => {
    for (let i = 1; i <= 250; i++) seedStored(sid(i), now - i * HOUR, {}, false);

    const first = await run({ action: "deleteAllScans" });
    expect(first.nextCursor).toBe(sid(200));
    expect(first.fenceToken).toMatch(TOKEN);
    expect(fenceKeys()).toHaveLength(1);
    expect(fenceKeys()[0]).not.toContain(UID);
    expect(store.get(fenceKeys()[0])).toEqual({
      runs: { [first.fenceToken]: { action: "deleteAllScans", startedAtMs: now, activeUntilMs: now + FENCE_MS } },
    });

    now += 5 * 60 * 1000;
    const last = await run({ action: "deleteAllScans", cursor: first.nextCursor, fenceToken: first.fenceToken });
    expect(last.fenceToken).toBeUndefined(); // no token once the operation is complete
    expect(fenceKeys()).toEqual([]);
  });

  test("a continuation page keeps the original startedAtMs and extends activeUntilMs (expiry bound is always now + 15 min)", async () => {
    for (let i = 1; i <= 450; i++) seedStored(sid(i), now - i * HOUR, { photosState: "deleted" }, false);
    const first = await run({ action: "deleteAllPhotos" });
    const startedAt = now;
    now += 10 * 60 * 1000;
    const second = await run({ action: "deleteAllPhotos", cursor: first.nextCursor, fenceToken: first.fenceToken });
    expect(second.nextCursor).toBe(sid(400));
    expect(second.fenceToken).toBe(first.fenceToken);
    expect(store.get(fenceKeys()[0])).toEqual({
      runs: { [first.fenceToken]: { action: "deleteAllPhotos", startedAtMs: startedAt, activeUntilMs: now + FENCE_MS } },
    });
  });

  test("applyRetention and exportLinks never touch the fence", async () => {
    seedStored("scan_one_1", now - DAY);
    await run({ action: "applyRetention", retentionDays: 30 });
    await run({ action: "exportLinks" });
    expect(fenceKeys()).toEqual([]);
  });

  test("(a) deleteAllScans: a scan created with an id BEFORE the cursor between page 1 and the final page is still tombstoned", async () => {
    for (let i = 1; i <= 250; i++) seedStored(sid(i), now - i * HOUR, {}, false);
    const first = await run({ action: "deleteAllScans" });
    expect(first.nextCursor).toBe(sid(200));

    // Created after page 1 started, id sorts before the cursor: the id-ordered walk never visits it.
    now += 60 * 1000;
    seedScan(UID, "scan_0000", { schema: 1, createdAt: ts(now), takenAt: ts(now), status: "pending", photosState: "awaiting_upload", weightKg: 70, purgeAttempts: 0 });
    putPhotos(UID, "scan_0000");

    const second = await run({ action: "deleteAllScans", cursor: first.nextCursor, fenceToken: first.fenceToken });
    expect(second.processed).toBe(51); // 50 on the walk + 1 straggler
    expect(second.nextCursor).toBeUndefined();
    const straggler = scanDoc(UID, "scan_0000")!;
    expect(straggler.status).toBe("cancelled");
    expect(straggler.photosState).toBe("deleted");
    expect("weightKg" in straggler).toBe(false);
    expect(objectKeys()).toEqual([]);
    expect(fenceKeys()).toEqual([]);
  });

  test("(a) deleteAllPhotos: the same straggler gets its photos deleted", async () => {
    for (let i = 1; i <= 250; i++) seedStored(sid(i), now - i * HOUR, { photosState: "deleted" }, false);
    const first = await run({ action: "deleteAllPhotos" });
    now += 60 * 1000;
    seedStored("scan_0000", now, { createdAt: ts(now) });
    expect(objectKeys(scanPrefix("scan_0000"))).toHaveLength(3);

    const second = await run({ action: "deleteAllPhotos", cursor: first.nextCursor, fenceToken: first.fenceToken });
    expect(second.processed).toBe(51);
    expect(scanDoc(UID, "scan_0000")!.photosState).toBe("deleted");
    expect(scanDoc(UID, "scan_0000")!.status).toBe("done"); // photos only: the scan stays
    expect(objectKeys()).toEqual([]);
  });

  test("a delete-all with nothing created after the walk adds no straggler work", async () => {
    seedStored("scan_one_1", now - 2 * DAY);
    const res = await run({ action: "deleteAllScans" });
    expect(res.processed).toBe(1);
  });

  test("a resumed walk whose fence lapsed re-checks every scan (window start 0), so an old straggler is still found", async () => {
    for (let i = 1; i <= 250; i++) seedStored(sid(i), now - i * HOUR, {}, false);
    const first = await run({ action: "deleteAllScans" });
    now += 40 * 60 * 1000; // past the 15 min fence
    seedScan(UID, "scan_0000", { schema: 1, createdAt: ts(now - 30 * 60 * 1000), status: "pending", photosState: "awaiting_upload", purgeAttempts: 0 });
    const second = await run({ action: "deleteAllScans", cursor: first.nextCursor, fenceToken: first.fenceToken });
    expect(second.processed).toBe(51);
    expect(scanDoc(UID, "scan_0000")!.status).toBe("cancelled");
  });

  test("stragglers still pending after the last pass -> aborted delete-incomplete and the fence is kept (never a silent done)", async () => {
    seedStored("scan_one_1", now - DAY, { createdAt: ts(now) });
    // A document that keeps coming back: every update re-opens it.
    fx.afterCommit = (paths) => {
      if (paths.some((p) => p.endsWith("scan_one_1"))) {
        store.set(`users/${UID}/body_scans/scan_one_1`, { ...store.get(`users/${UID}/body_scans/scan_one_1`)!, status: "pending" });
      }
    };
    await expectHttpsError(run({ action: "deleteAllScans" }), "aborted", "delete-incomplete");
    expect(fenceKeys()).toHaveLength(1);
    expect(lateKeys()).toEqual([]); // not complete: nothing is promised, nothing scheduled
  });
});

/** Seeds `n` already-deleted scans so a delete-all takes `ceil(n/200)` pages without object work. */
function seedMany(n: number): void {
  for (let i = 1; i <= n; i++) seedStored(sid(i), now - i * HOUR, { photosState: "deleted" }, false);
}

describe("fence ownership (overlapping bulk operations; GPT-PM MAJOR-02A)", () => {
  test("different actions: the first to finish clears only its own entry; protection holds until the LAST operation completes", async () => {
    seedMany(250);
    const a = await run({ action: "deleteAllScans" }); // page 1 of 2, walking
    expect(fenceOn()).toBe(true);

    now += 60 * 1000;
    const b1 = await run({ action: "deleteAllPhotos" });
    expect(Object.keys(runsOf())).toHaveLength(2);
    const b = await run({ action: "deleteAllPhotos", cursor: b1.nextCursor, fenceToken: b1.fenceToken });
    expect(b.nextCursor).toBeUndefined();
    expect(Object.keys(runsOf())).toEqual([a.fenceToken]);
    expect(runsOf()[a.fenceToken].action).toBe("deleteAllScans");
    expect(fenceOn()).toBe(true);

    now += 60 * 1000;
    await run({ action: "deleteAllScans", cursor: a.nextCursor, fenceToken: a.fenceToken });
    expect(fenceKeys()).toEqual([]);
    expect(fenceOn()).toBe(false);
  });

  test("a later-started operation neither replaces nor shortens the earlier one; either order of completion is safe", async () => {
    seedMany(250);
    const a = await run({ action: "deleteAllPhotos" });
    const aEntry = { ...runsOf()[a.fenceToken] };
    now += 2 * 60 * 1000;
    const b = await run({ action: "deleteAllScans" });
    expect(b.fenceToken).not.toBe(a.fenceToken);
    expect(runsOf()[a.fenceToken]).toEqual(aEntry);
    expect(runsOf()[b.fenceToken]).toEqual({ action: "deleteAllScans", startedAtMs: now, activeUntilMs: now + FENCE_MS });
    await run({ action: "deleteAllScans", cursor: b.nextCursor, fenceToken: b.fenceToken });
    expect(Object.keys(runsOf())).toEqual([a.fenceToken]);
    await run({ action: "deleteAllPhotos", cursor: a.nextCursor, fenceToken: a.fenceToken });
    expect(fenceOn()).toBe(false);
  });

  test("same action started twice: each run owns its entry; the first run completing does not clear the second", async () => {
    seedMany(250);
    const r1 = await run({ action: "deleteAllScans" });
    now += 60 * 1000;
    const r2 = await run({ action: "deleteAllScans" });
    expect(r2.fenceToken).not.toBe(r1.fenceToken);
    expect(Object.keys(runsOf()).sort()).toEqual([r1.fenceToken, r2.fenceToken].sort());

    now += 60 * 1000;
    await run({ action: "deleteAllScans", cursor: r1.nextCursor, fenceToken: r1.fenceToken });
    expect(Object.keys(runsOf())).toEqual([r2.fenceToken]);
    expect(fenceOn()).toBe(true);

    now += 60 * 1000;
    await run({ action: "deleteAllScans", cursor: r2.nextCursor, fenceToken: r2.fenceToken });
    expect(fenceKeys()).toEqual([]);
  });

  test("a run that keeps refreshing extends only its own expiry", async () => {
    seedMany(450);
    const r1 = await run({ action: "deleteAllScans" });
    const t1 = runsOf()[r1.fenceToken];
    now += 60 * 1000;
    const r2 = await run({ action: "deleteAllPhotos" });
    const r2Entry = { ...runsOf()[r2.fenceToken] };
    now += 60 * 1000;
    await run({ action: "deleteAllScans", cursor: r1.nextCursor, fenceToken: r1.fenceToken });
    expect(runsOf()[r1.fenceToken]).toEqual({ ...t1, activeUntilMs: now + FENCE_MS });
    expect(runsOf()[r2.fenceToken]).toEqual(r2Entry);
  });

  test("a continuation without its token registers a NEW run (full re-check) and never clears the original entry; expiry bound holds", async () => {
    seedMany(250);
    const first = await run({ action: "deleteAllScans" });
    now += 60 * 1000;
    seedScan(UID, "scan_0000", { schema: 1, createdAt: ts(now - 30 * 60 * 1000), status: "pending", photosState: "awaiting_upload", purgeAttempts: 0 });
    const res = await run({ action: "deleteAllScans", cursor: first.nextCursor });
    expect(res.processed).toBe(51);
    expect(Object.keys(runsOf())).toEqual([first.fenceToken]);
    expect(fenceOn()).toBe(true);
    now += FENCE_MS - 60 * 1000 - 1;
    expect(fenceOn()).toBe(true);
    now += 1;
    expect(fenceOn()).toBe(false);
  });

  test("racing registration: B registers while A's transaction is in flight, A retries and BOTH entries survive", async () => {
    seedMany(250);
    const bToken = "c".repeat(32);
    let injected = false;
    fx.afterTxRead = async (path, attempt) => {
      if (path.startsWith(FENCE_PREFIX) && attempt === 1 && !injected) {
        injected = true;
        store.set(path, { runs: { [bToken]: { action: "deleteAllPhotos", startedAtMs: now, activeUntilMs: now + FENCE_MS } } });
      }
    };
    const a = await run({ action: "deleteAllScans" });
    fx.afterTxRead = null;
    expect(fx.txRetries).toBeGreaterThanOrEqual(1);
    expect(Object.keys(runsOf()).sort()).toEqual([a.fenceToken, bToken].sort());
  });

  test("racing final page: another operation registers while this one is clearing, and its entry survives the clear", async () => {
    seedMany(10);
    const cToken = "d".repeat(32);
    let injected = false;
    fx.afterTxRead = async (path) => {
      // The second fence read is the completion transaction (the first was the registration).
      if (path.startsWith(FENCE_PREFIX) && !injected && fenceKeys().length === 1 && timeline.some((t) => t.startsWith("fs:set:" + FENCE_PREFIX))) {
        injected = true;
        const doc = store.get(path)!;
        store.set(path, { runs: { ...doc.runs, [cToken]: { action: "deleteAllPhotos", startedAtMs: now, activeUntilMs: now + FENCE_MS } } });
      }
    };
    await run({ action: "deleteAllScans" });
    fx.afterTxRead = null;
    expect(Object.keys(runsOf())).toEqual([cToken]);
    expect(fenceOn()).toBe(true);
  });

  test.each([
    ["not hex", "z".repeat(32)],
    ["too short", "a".repeat(31)],
    ["too long", "a".repeat(33)],
    ["a number", 5],
  ])("a malformed fenceToken (%s) -> invalid-cursor", async (_n, token) => {
    await expectHttpsError(run({ action: "deleteAllScans", cursor: "scan_0001", fenceToken: token }), "invalid-argument", "invalid-cursor");
  });

  test("applyRetention never returns a fenceToken", async () => {
    seedMany(250);
    const res = await run({ action: "applyRetention", retentionDays: 30 });
    expect(res.nextCursor).toBeDefined();
    expect(res.fenceToken).toBeUndefined();
  });
});

describe("late-upload sweep record (GPT-PM MAJOR-02B)", () => {
  test.each(["deleteAllPhotos", "deleteAllScans"])("%s: the final page records dueAtMs = completion + 10 min URL TTL + 2 min margin; the fence is gone", async (action) => {
    seedStored("scan_one_1", now - DAY);
    await run({ action });
    expect(fenceKeys()).toEqual([]);
    expect(lateKeys()).toHaveLength(1);
    expect(lateKeys()[0]).not.toContain(UID);
    expect(store.get(lateKeys()[0])).toEqual({ uid: UID, action, dueAtMs: now + LATE_DELAY_MS, rev: expect.stringMatching(/^[0-9a-f]{16}$/) });
  });

  test("no record before the final page, none from applyRetention or exportLinks; a later completion pushes dueAtMs forward, never back", async () => {
    seedMany(250);
    const first = await run({ action: "deleteAllScans" });
    await run({ action: "applyRetention", retentionDays: 30 });
    await run({ action: "exportLinks" });
    expect(lateKeys()).toEqual([]);

    now += 60 * 1000;
    await run({ action: "deleteAllScans", cursor: first.nextCursor, fenceToken: first.fenceToken });
    const due1 = store.get(lateKeys()[0])!.dueAtMs;
    const rev1 = store.get(lateKeys()[0])!.rev;
    expect(due1).toBe(now + LATE_DELAY_MS);

    now += 5 * 60 * 1000;
    const again = await run({ action: "deleteAllPhotos" });
    await run({ action: "deleteAllPhotos", cursor: again.nextCursor, fenceToken: again.fenceToken });
    expect(lateKeys()).toHaveLength(1);
    expect(store.get(lateKeys()[0])!.dueAtMs).toBe(now + LATE_DELAY_MS);
    expect(store.get(lateKeys()[0])!.dueAtMs).toBeGreaterThan(due1);
    expect(store.get(lateKeys()[0])!.rev).not.toBe(rev1); // every completion rewrites the revision
  });
});

describe("exportLinks", () => {
  test("1-hour V4 READ URLs for stored photos only, newest scan first, poses front/side/back, exact link shape", async () => {
    seedStored("scan_old_1", now - 3 * DAY);
    seedStored("scan_new_1", now - 1 * DAY);
    seedStored("scan_gon_1", now - 2 * DAY, { photosState: "deleted" }, false);
    // A tombstone has no takenAt and is not in the takenAt-ordered history at all.
    seedScan(UID, "scan_cxl_1", { schema: 1, status: "cancelled", photosState: "deleted", pendingExpiresAt: ts(now + HOUR), purgeAttempts: 0 });

    const res = await run({ action: "exportLinks" });

    expect(res.action).toBe("exportLinks");
    expect(res.processed).toBe(6);
    expect(res.nextCursor).toBeUndefined();
    expect(res.links.map((l: any) => `${l.scanId}/${l.pose}`)).toEqual([
      "scan_new_1/front", "scan_new_1/side", "scan_new_1/back",
      "scan_old_1/front", "scan_old_1/side", "scan_old_1/back",
    ]);
    for (const l of res.links) {
      expect(Object.keys(l).sort()).toEqual(["expiresAtMs", "pose", "scanId", "url"]);
      expect(l.expiresAtMs).toBe(now + HOUR);
      expect(l.url).toMatch(/^https:\/\/signed\.invalid\/.*action=read/);
    }
    expect(gcs.signed).toHaveLength(6);
    for (const s of gcs.signed) {
      expect(s.opts).toEqual({ version: "v4", action: "read", expires: now + HOUR });
    }
    expect(gcs.signed.map((s) => s.path).sort()).toContain(`users/${UID}/scans/scan_new_1/side.jpg`);
    // The export signs; it never reads the objects.
    expect(gcs.downloadCalls).toEqual([]);
    expect(scanDoc(UID, "scan_new_1")!.photosState).toBe("stored");
  });

  test("25 stored scans: page 1 = 20 scans = 60 links with a cursor, page 2 = 5 scans = 15 links and no cursor; no scan is repeated or lost", async () => {
    for (let i = 1; i <= 25; i++) seedStored(sid(i), now - i * HOUR, {}, false);

    const first = await run({ action: "exportLinks" });
    expect(first.links).toHaveLength(60);
    expect(first.processed).toBe(60);
    expect(first.links[0].scanId).toBe(sid(1)); // newest first
    expect(first.links[59].scanId).toBe(sid(20));
    expect(first.nextCursor).toBe(`${now - 20 * HOUR}:${sid(20)}`);

    const second = await run({ action: "exportLinks", cursor: first.nextCursor });
    expect(second.links).toHaveLength(15);
    expect(second.nextCursor).toBeUndefined();
    expect(second.links[0].scanId).toBe(sid(21));

    const ids = [...first.links, ...second.links].map((l: any) => l.scanId);
    expect(new Set(ids).size).toBe(25);
  });

  test("a full page of non-stored scans yields no links but still offers the cursor", async () => {
    for (let i = 1; i <= 21; i++) seedStored(sid(i), now - i * HOUR, { photosState: "deleted" }, false);
    const first = await run({ action: "exportLinks" });
    expect(first.links).toEqual([]);
    expect(first.processed).toBe(0);
    expect(first.nextCursor).toBe(`${now - 20 * HOUR}:${sid(20)}`);
  });

  test("scans sharing one takenAt millisecond across a page boundary are neither skipped nor repeated (DB-F6)", async () => {
    for (let i = 1; i <= 25; i++) seedStored(sid(i), now - DAY, {}, false);
    const first = await run({ action: "exportLinks" });
    const second = await run({ action: "exportLinks", cursor: first.nextCursor });
    expect(first.links).toHaveLength(60);
    expect(second.links).toHaveLength(15);
    expect(second.nextCursor).toBeUndefined();
    const ids = [...first.links, ...second.links].map((l: any) => l.scanId);
    expect(new Set(ids).size).toBe(25);
  });

  test("another user's photos are never linked", async () => {
    store.set("users/other_user/body_scans/scan_oth_1", { status: "done", photosState: "stored", takenAt: ts(now - HOUR) });
    seedStored("scan_own_1", now - DAY);
    const res = await run({ action: "exportLinks" });
    expect(res.links.every((l: any) => l.scanId === "scan_own_1")).toBe(true);
    expect(gcs.signed.every((s) => s.path.startsWith(`users/${UID}/`))).toBe(true);
  });

  test("a signing failure -> internal scan-manage-failed", async () => {
    seedStored("scan_own_1", now - DAY);
    gcs.failOn = (op) => (op === "sign" ? firestoreError("denied", 403) : undefined);
    await expectHttpsError(run({ action: "exportLinks" }), "internal", "scan-manage-failed");
  });

  test("the log records the action and the count, never a URL, uid, path or scan id", async () => {
    seedStored("scan_own_1", now - DAY);
    await run({ action: "exportLinks" });
    expect(bodyScanEvents(logger)).toEqual([{ operation: "bodyScanManage", outcome: "exportLinks", latencyMs: 0, processed: 3 }]);
    const text = loggedText(logger);
    for (const secret of [UID, "scan_own_1", "users/", "signed.invalid"]) expect(text).not.toContain(secret);
  });
});

describe("Firestore failure", () => {
  test("a failing page query -> internal scan-manage-failed (the quota stays charged: the call did start)", async () => {
    fx.failOn = (op, path) => (op === "query" && path.endsWith("body_scans") ? firestoreError("x", "unavailable") : undefined);
    await expectHttpsError(run({ action: "deleteAllScans" }), "internal", "scan-manage-failed");
    expect(bodyScanEvents(logger, "error")[0]).toMatchObject({ outcome: "failed", action: "deleteAllScans", errorCode: "unavailable" });
  });
});
