/**
 * `purgeExpiredBodyScanPhotos` / `runBodyScanPurge` (design s7.4, D-59): the four
 * passes, `startAfter` paging that cannot be starved by a stuck document, the
 * persisted listing token, `purgeAttempts` up to 10 with the `purge-stuck`
 * event, the 240 s start-of-work budget and the unset-bucket no-op.
 */
jest.mock("firebase-admin", () => require("./fakes").adminMock());
jest.mock("firebase-admin/storage", () => require("./fakes").storageMock());
jest.mock("firebase-functions/logger", () => require("./fakes").loggerMock());
jest.mock("@google-cloud/secret-manager", () => require("./fakes").secretManagerMock());

import * as logger from "firebase-functions/logger";
import {
  MAX_PURGE_ATTEMPTS, PURGE_RUN_BUDGET_MS, purgeExpiredBodyScanPhotos, runBodyScanPurge,
} from "../../body_scan/purge";
import {
  BUCKET, DAY, HOUR, MIN, T0,
  bodyScanEvents, firestoreError, fx, gcs, loggedText, objectKeys, putPhotos, queries, resetFakes,
  seedScan, store, timeline, ts, writes,
} from "./fakes";

let now = T0;
let dateSpy: jest.SpyInstance;

const A = "uid_alice_1";
const B = "uid_bob_22";
const path = (uid: string, id: string): string => `users/${uid}/body_scans/${id}`;
const get = (uid: string, id: string): any => store.get(path(uid, id));
const prefix = (uid: string, id: string): string => `users/${uid}/scans/${id}/`;
const sid = (n: number): string => `scan_${String(n).padStart(4, "0")}`;

/** A done scan whose photos are due `dueInMs` from now (negative = overdue). */
function seedStored(uid: string, id: string, dueInMs: number, o: Record<string, unknown> = {}): void {
  seedScan(uid, id, {
    schema: 1, createdAt: ts(now - 40 * DAY), takenAt: ts(now - 40 * DAY), status: "done",
    estimate: { bodyFatPct: 20 }, photosState: "stored", photosExpireAt: ts(now + dueInMs), purgeAttempts: 0, ...o,
  });
}

function seedPending(uid: string, id: string, expiresInMs: number, o: Record<string, unknown> = {}): void {
  seedScan(uid, id, {
    schema: 1, createdAt: ts(now - 3 * DAY), takenAt: ts(now - 3 * DAY), weightKg: 70, clientNote: "n",
    subject: { sexAtBirth: "male", ageYears: 40, heightCm: 180, weightKg: 70 },
    capture: { manualOverride: { front: false, side: false, back: false }, poses: ["front", "side", "back"] },
    status: "pending", photosState: "awaiting_upload", pendingExpiresAt: ts(now + expiresInMs), purgeAttempts: 0, ...o,
  });
}

function seedTombstone(uid: string, id: string, expiresInMs: number, o: Record<string, unknown> = {}): void {
  seedScan(uid, id, {
    schema: 1, createdAt: ts(now - 3 * DAY), status: "cancelled", photosState: "deleted",
    photosDeletedAt: ts(now - 2 * DAY), pendingExpiresAt: ts(now + expiresInMs), purgeAttempts: 0, ...o,
  });
}

const run = (budget?: number): ReturnType<typeof runBodyScanPurge> => runBodyScanPurge(now, budget);

beforeEach(() => {
  resetFakes();
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
  for (const level of ["debug", "info", "warn", "error"] as const) (logger[level] as jest.Mock).mockClear();
  process.env.BODY_SCAN_BUCKET = BUCKET;
});

afterEach(() => {
  dateSpy.mockRestore();
});

afterAll(() => {
  delete process.env.BODY_SCAN_BUCKET;
});

describe("schedule and bucket flag", () => {
  test("the budget stops starting new work at 240 s of the 300 s function timeout", () => {
    expect(PURGE_RUN_BUDGET_MS).toBe(240 * 1000);
    expect(MAX_PURGE_ATTEMPTS).toBe(10);
  });

  test("the scheduled function is 30 3 * * * with a 300 s timeout, one instance", () => {
    const ep = (purgeExpiredBodyScanPhotos as any).__endpoint;
    expect(ep.scheduleTrigger.schedule).toBe("30 3 * * *");
    expect(ep.timeoutSeconds).toBe(300);
    expect(ep.maxInstances).toBe(1);
    expect(ep.concurrency).toBe(1);
    expect(ep.availableMemoryMb).toBe(256);
    expect(ep.region).toEqual(["europe-west1"]);
    expect(ep.serviceAccountEmail).toMatch(/^fn-bodyscan@/);
  });

  test("the scheduled handler runs the purge (an overdue scan is purged by `.run`)", async () => {
    seedStored(A, "scan_due_001", -MIN);
    putPhotos(A, "scan_due_001");
    await (purgeExpiredBodyScanPhotos as any).run({});
    expect(get(A, "scan_due_001").photosState).toBe("deleted");
  });

  test("bucket unset -> a complete no-op: zero queries, zero storage calls, zero writes, zero logs", async () => {
    delete process.env.BODY_SCAN_BUCKET;
    seedStored(A, "scan_due_001", -MIN);
    putPhotos(A, "scan_due_001");
    const counts = await run();
    expect(counts).toEqual({ expired: 0, pending: 0, tombstones: 0, unmatched: 0, failures: 0 });
    expect(queries).toEqual([]);
    expect(gcs.buckets).toEqual([]);
    expect(gcs.deleteFilesCalls).toEqual([]);
    expect(writes).toEqual([]);
    expect(bodyScanEvents(logger)).toEqual([]);
    expect(get(A, "scan_due_001").photosState).toBe("stored");
  });
});

describe("pass 1: photos past photosExpireAt", () => {
  test("due photos (including exactly now) are deleted and marked; not-yet-due and non-stored scans are untouched; the owner's prefix is used", async () => {
    seedStored(A, "scan_due_001", -DAY);
    seedStored(B, "scan_due_002", 0); // exactly now
    seedStored(A, "scan_fut_001", 1); // 1 ms in the future
    seedScan(A, "scan_gon_001", { status: "done", photosState: "deleted", photosDeletedAt: ts(now - DAY), purgeAttempts: 0 });
    for (const [u, id] of [[A, "scan_due_001"], [B, "scan_due_002"], [A, "scan_fut_001"]]) putPhotos(u, id, { timeCreated: now - 3 * DAY });

    const counts = await run();

    expect(counts).toMatchObject({ expired: 2, failures: 0 });
    for (const [u, id] of [[A, "scan_due_001"], [B, "scan_due_002"]]) {
      expect(get(u, id).photosState).toBe("deleted");
      expect(get(u, id).photosDeletedAt).toEqual(ts(now));
      expect("photosExpireAt" in get(u, id)).toBe(false);
      expect(get(u, id).status).toBe("done"); // the scan itself stays
      expect(get(u, id).estimate).toEqual({ bodyFatPct: 20 });
      expect(objectKeys(prefix(u, id))).toEqual([]);
    }
    expect(get(A, "scan_fut_001").photosState).toBe("stored");
    expect(objectKeys(prefix(A, "scan_fut_001"))).toHaveLength(3);
    expect(gcs.deleteFilesCalls.map((c) => c.prefix).sort()).toEqual([prefix(A, "scan_due_001"), prefix(B, "scan_due_002")].sort());
  });

  test("the pass query is exactly: photosState == stored, photosExpireAt <= now, ordered by photosExpireAt, 200 per page", async () => {
    await run();
    const q = queries.find((x) => x.filters.some((f) => f.f === "photosState"))!;
    expect(q).toMatchObject({
      kind: "group",
      name: "body_scans",
      filters: [{ f: "photosState", op: "==", v: "stored" }, { f: "photosExpireAt", op: "<=", v: ts(now) }],
      orders: [{ f: "photosExpireAt", dir: "asc" }],
      limit: 200,
    });
  });
});

describe("pass 2: pending scans past pendingExpiresAt", () => {
  test("objects removed and the scan becomes a scrubbed 48 h tombstone; a live lease protects an estimate in flight", async () => {
    seedPending(A, "scan_exp_001", -HOUR);
    seedPending(A, "scan_liv_001", -HOUR, { estimateLeaseUntil: ts(now + 30 * 1000) }); // estimate running
    seedPending(A, "scan_old_001", -HOUR, { estimateLeaseUntil: ts(now - 1) }); // lease expired
    seedPending(A, "scan_fut_001", HOUR); // not yet due
    for (const id of ["scan_exp_001", "scan_liv_001", "scan_old_001", "scan_fut_001"]) putPhotos(A, id, { timeCreated: now - 3 * DAY });

    const counts = await run();

    expect(counts).toMatchObject({ pending: 2, failures: 0 });
    for (const id of ["scan_exp_001", "scan_old_001"]) {
      const d = get(A, id);
      expect(d.status).toBe("cancelled");
      expect(d.photosState).toBe("deleted");
      expect(d.photosDeletedAt).toEqual(ts(now));
      expect(d.pendingExpiresAt).toEqual(ts(now + 48 * HOUR));
      for (const gone of ["subject", "capture", "weightKg", "clientNote", "takenAt", "estimateLeaseUntil"]) {
        expect(gone in d).toBe(false);
      }
      expect(objectKeys(prefix(A, id))).toEqual([]);
    }
    // The tombstone just written is not removed in the same run (it is due in 48 h).
    expect(get(A, "scan_exp_001")).toBeDefined();
    expect(get(A, "scan_liv_001").status).toBe("pending");
    expect(objectKeys(prefix(A, "scan_liv_001"))).toHaveLength(3);
    expect(get(A, "scan_fut_001").status).toBe("pending");
    expect(objectKeys(prefix(A, "scan_fut_001"))).toHaveLength(3);
  });
});

describe("pass 3: tombstones past pendingExpiresAt", () => {
  test("due tombstones lose their last objects and are deleted; a tombstone due later is kept", async () => {
    seedTombstone(A, "scan_tmb_001", -1);
    seedTombstone(A, "scan_tmb_002", 1);
    putPhotos(A, "scan_tmb_001", { timeCreated: now - 3 * DAY }); // a late PUT
    putPhotos(A, "scan_tmb_002", { timeCreated: now - 3 * DAY });

    const counts = await run();

    expect(counts).toMatchObject({ tombstones: 1, failures: 0 });
    expect(get(A, "scan_tmb_001")).toBeUndefined();
    expect(objectKeys(prefix(A, "scan_tmb_001"))).toEqual([]);
    expect(get(A, "scan_tmb_002")).toBeDefined();
    // Pass 4 sees the surviving tombstone and removes ITS (old) objects: the scan is cancelled.
    expect(objectKeys(prefix(A, "scan_tmb_002"))).toEqual([]);
  });

  test("a tombstone is removed only after its objects were swept (objects first, then the document)", async () => {
    seedTombstone(A, "scan_tmb_001", -1);
    await run();
    const swept = timeline.indexOf(`gcs:deleteFiles:${prefix(A, "scan_tmb_001")}`);
    const removed = timeline.indexOf(`fs:delete:${path(A, "scan_tmb_001")}`);
    expect(swept).toBeGreaterThanOrEqual(0);
    expect(removed).toBeGreaterThan(swept);
  });
});

describe("pass 4: unmatched-object sweep", () => {
  const old = (): { timeCreated: number } => ({ timeCreated: now - 2 * HOUR });

  test("an object older than 1 h is deleted when its scan has no document, is cancelled, or has photosState none/deleted; kept when stored or awaiting upload", async () => {
    seedTombstone(A, "scan_cxl_001", 10 * DAY);
    seedScan(A, "scan_del_001", { status: "done", photosState: "deleted", purgeAttempts: 0 });
    seedScan(A, "scan_non_001", { status: "pending", photosState: "none", purgeAttempts: 0 });
    seedStored(A, "scan_sto_001", 10 * DAY);
    seedPending(A, "scan_pen_001", 10 * DAY);
    for (const id of ["scan_ghost_01", "scan_cxl_001", "scan_del_001", "scan_non_001", "scan_sto_001", "scan_pen_001"]) putPhotos(A, id, old());

    const counts = await run();

    expect(counts.unmatched).toBe(12); // 4 orphan scans x 3 poses
    for (const id of ["scan_ghost_01", "scan_cxl_001", "scan_del_001", "scan_non_001"]) {
      expect(objectKeys(prefix(A, id))).toEqual([]);
    }
    for (const id of ["scan_sto_001", "scan_pen_001"]) {
      expect(objectKeys(prefix(A, id))).toHaveLength(3);
    }
  });

  test("age rule: 59 min 59 s is kept, exactly 1 h is judged", async () => {
    putPhotos(A, "scan_young_01", { timeCreated: now - HOUR + 1000 });
    putPhotos(A, "scan_edge_001", { timeCreated: now - HOUR });
    await run();
    expect(objectKeys(prefix(A, "scan_young_01"))).toHaveLength(3);
    expect(objectKeys(prefix(A, "scan_edge_001"))).toEqual([]);
  });

  test("names outside users/<uid>/scans/<id>/{front,side,back}.jpg are never touched", async () => {
    const keep = [`users/${A}/profile.txt`, `users/${A}/scans/scan_x_00001/extra.png`, `users/${A}/scans/scan_x_00001/front.jpeg`, `users/${A}/scans/front.jpg`];
    for (const k of keep) gcs.objects.set(k, { content: Buffer.alloc(10), contentType: "text/plain", timeCreated: new Date(now - DAY).toISOString() });
    await run();
    expect(objectKeys()).toEqual([...keep].sort());
  });

  test("deletes use ignoreNotFound so an object removed meanwhile is not a failure", async () => {
    putPhotos(A, "scan_ghost_01", old());
    await run();
    expect(gcs.fileDeleteCalls.length).toBe(3);
    expect(gcs.fileDeleteCalls.every((c) => c.opts?.ignoreNotFound === true)).toBe(true);
  });

  test("one object that fails to delete is counted and logged by code only; the rest are still swept", async () => {
    putPhotos(A, "scan_ghost_01", old());
    putPhotos(B, "scan_ghost_02", old());
    gcs.failOn = (op, name) => (op === "delete" && name === `users/${A}/scans/scan_ghost_01/side.jpg` ? firestoreError(`no access to ${name}`, 403) : undefined);
    const counts = await run();
    expect(counts.unmatched).toBe(5);
    expect(counts.failures).toBe(1);
    expect(objectKeys(prefix(A, "scan_ghost_01"))).toEqual([`users/${A}/scans/scan_ghost_01/side.jpg`]);
    expect(bodyScanEvents(logger, "warn")).toEqual([{ operation: "bodyScanPurge", outcome: "unmatched-delete-failed", errorCode: "403" }]);
    expect(loggedText(logger)).not.toContain(A);
  });

  test("the listing is a single manual page: prefix users/, 500 per page, no autoPaginate; the token is stored in body_scan_purge_state/main", async () => {
    putPhotos(A, "scan_ghost_01", old());
    await run();
    expect(gcs.getFilesCalls[0]).toEqual({ prefix: "users/", autoPaginate: false, maxResults: 500 });
    expect(store.get("body_scan_purge_state/main")).toEqual({ pageToken: "", updatedAt: ts(now) });
  });

  test("700 orphans take two pages; the token is persisted after each page and cleared at the end", async () => {
    for (let i = 0; i < 700; i++) {
      gcs.objects.set(`users/${A}/scans/${sid(i)}/front.jpg`, { content: Buffer.alloc(10), contentType: "image/jpeg", timeCreated: new Date(now - DAY).toISOString() });
    }
    const tokens: unknown[] = [];
    fx.afterCommit = (paths) => {
      if (paths.includes("body_scan_purge_state/main")) tokens.push(store.get("body_scan_purge_state/main")!.pageToken);
    };
    const counts = await run();
    expect(counts.unmatched).toBe(700);
    expect(objectKeys()).toEqual([]);
    const lastOfPage1 = `users/${A}/scans/${sid(499)}/front.jpg`;
    expect(tokens).toEqual([lastOfPage1, ""]);
    expect(gcs.getFilesCalls.map((c) => c.pageToken)).toEqual([undefined, lastOfPage1]);
  });

  test("a run resumes from the stored token instead of restarting", async () => {
    for (let i = 0; i < 700; i++) {
      gcs.objects.set(`users/${A}/scans/${sid(i)}/front.jpg`, { content: Buffer.alloc(10), contentType: "image/jpeg", timeCreated: new Date(now - DAY).toISOString() });
    }
    const token = `users/${A}/scans/${sid(499)}/front.jpg`;
    store.set("body_scan_purge_state/main", { pageToken: token, updatedAt: ts(now - DAY) });
    await run();
    expect(gcs.getFilesCalls[0].pageToken).toBe(token);
    expect(objectKeys().length).toBe(500); // the first 500 (before the token) were not revisited
    expect(objectKeys()[0]).toBe(`users/${A}/scans/${sid(0)}/front.jpg`);
  });

  test("when the budget ends mid-listing the position is kept for the next run", async () => {
    for (let i = 0; i < 700; i++) {
      gcs.objects.set(`users/${A}/scans/${sid(i)}/front.jpg`, { content: Buffer.alloc(10), contentType: "image/jpeg", timeCreated: new Date(now - DAY).toISOString() });
    }
    fx.afterCommit = (paths) => {
      if (paths.includes("body_scan_purge_state/main")) now += 300 * 1000; // the clock passes the deadline after page 1
    };
    await run();
    expect(store.get("body_scan_purge_state/main")!.pageToken).toBe(`users/${A}/scans/${sid(499)}/front.jpg`);
    expect(objectKeys().length).toBe(200);
  });

  test("an unreadable state document means the listing starts from the beginning", async () => {
    putPhotos(A, "scan_ghost_01", old());
    fx.failOn = (op, p) => (op === "get" && p === "body_scan_purge_state/main" ? firestoreError("x", "unavailable") : undefined);
    await run();
    expect(gcs.getFilesCalls[0].pageToken).toBeUndefined();
    expect(objectKeys()).toEqual([]);
  });
});

describe("purgeAttempts and purge-stuck", () => {
  test("a failing document gets purgeAttempts + 1 and a purge-failed warning; its neighbour is still purged", async () => {
    seedStored(A, "scan_bad_001", -2 * DAY);
    seedStored(A, "scan_ok_0001", -1 * DAY);
    putPhotos(A, "scan_bad_001", { timeCreated: now - 3 * DAY });
    putPhotos(A, "scan_ok_0001", { timeCreated: now - 3 * DAY });
    gcs.failOn = (op, p) => (op === "deleteFiles" && p === prefix(A, "scan_bad_001") ? firestoreError(`denied ${p}`, 403) : undefined);

    const counts = await run();

    expect(counts).toMatchObject({ expired: 1, failures: 1 });
    expect(get(A, "scan_bad_001").photosState).toBe("stored");
    expect(get(A, "scan_bad_001").purgeAttempts).toBe(1);
    expect(get(A, "scan_ok_0001").photosState).toBe("deleted");
    expect(bodyScanEvents(logger, "warn")).toEqual([
      { operation: "bodyScanPurge", outcome: "purge-failed", scanId: "scan_bad_001", attempts: 1, errorCode: "403" },
    ]);
    expect(loggedText(logger)).not.toContain(A);
    expect(loggedText(logger)).not.toContain("denied");
  });

  test("the 10th failure logs purge-stuck (error) with the scan id only; a document at 10 attempts is then skipped entirely", async () => {
    seedStored(A, "scan_bad_001", -DAY, { purgeAttempts: 9 });
    putPhotos(A, "scan_bad_001", { timeCreated: now - 3 * DAY });
    gcs.failOn = (op) => (op === "deleteFiles" ? firestoreError("x", 500) : undefined);

    await run();

    expect(get(A, "scan_bad_001").purgeAttempts).toBe(10);
    const stuck = bodyScanEvents(logger, "error").filter((e) => e.outcome === "purge-stuck");
    expect(stuck).toEqual([{ operation: "bodyScanPurge", outcome: "purge-stuck", scanId: "scan_bad_001", attempts: 10, errorCode: "500" }]);
    expect(JSON.stringify(stuck)).not.toContain(A);

    // Third run: no storage call for it, no more increments, no new event.
    gcs.deleteFilesCalls.length = 0;
    (logger.error as jest.Mock).mockClear();
    const again = await run();
    expect(gcs.deleteFilesCalls.filter((c) => c.prefix === prefix(A, "scan_bad_001"))).toEqual([]);
    expect(get(A, "scan_bad_001").purgeAttempts).toBe(10);
    expect(again.failures).toBe(0);
    expect(bodyScanEvents(logger, "error").filter((e) => e.outcome === "purge-stuck")).toEqual([]);
  });

  test("the 9th failure is only a purge-failed warning, not purge-stuck", async () => {
    seedStored(A, "scan_bad_001", -DAY, { purgeAttempts: 8 });
    gcs.failOn = (op) => (op === "deleteFiles" ? firestoreError("x", 500) : undefined);
    await run();
    expect(get(A, "scan_bad_001").purgeAttempts).toBe(9);
    expect(bodyScanEvents(logger, "error").filter((e) => e.outcome === "purge-stuck")).toEqual([]);
    expect(bodyScanEvents(logger, "warn")[0]).toMatchObject({ outcome: "purge-failed", attempts: 9 });
  });

  test("stuck documents in pass 2 and pass 3 are skipped the same way", async () => {
    seedPending(A, "scan_pen_001", -HOUR, { purgeAttempts: 10 });
    seedTombstone(A, "scan_tmb_001", -1, { purgeAttempts: 10 });
    await run();
    expect(get(A, "scan_pen_001").status).toBe("pending");
    expect(get(A, "scan_tmb_001")).toBeDefined();
    expect(gcs.deleteFilesCalls.map((c) => c.prefix)).not.toContain(prefix(A, "scan_pen_001"));
  });

  test("a pass-3 failure keeps the tombstone and counts an attempt", async () => {
    seedTombstone(A, "scan_tmb_001", -1);
    gcs.failOn = (op) => (op === "deleteFiles" ? firestoreError("x", 503) : undefined);
    const counts = await run();
    expect(counts.tombstones).toBe(0);
    expect(get(A, "scan_tmb_001").purgeAttempts).toBe(1);
  });
});

describe("paging cannot be starved by stuck documents", () => {
  test("205 stuck documents (which stay in the query forever) do not hide the normal documents behind them", async () => {
    for (let i = 0; i < 205; i++) seedStored(A, sid(i), -(400 - i) * HOUR, { purgeAttempts: 10 });
    seedStored(A, "scan_norm_01", -HOUR);
    seedStored(A, "scan_norm_02", -MIN);
    const counts = await run();
    expect(counts.expired).toBe(2);
    expect(get(A, "scan_norm_01").photosState).toBe("deleted");
    expect(get(A, "scan_norm_02").photosState).toBe("deleted");
    expect(get(A, sid(0)).photosState).toBe("stored");
    const pages = queries.filter((q) => q.filters.some((f) => f.f === "photosState"));
    expect(pages.length).toBeGreaterThanOrEqual(2);
    expect(pages[1].startAfter).toBeDefined();
  });

  test("450 due documents are all purged across 200-document pages", async () => {
    for (let i = 0; i < 450; i++) seedStored(A, sid(i), -(500 - i) * MIN);
    const counts = await run();
    expect(counts.expired).toBe(450);
    for (let i = 0; i < 450; i += 97) expect(get(A, sid(i)).photosState).toBe("deleted");
  });
});

describe("run budget", () => {
  test("once the clock passes the budget no further document or pass is started", async () => {
    seedStored(A, "scan_aaa_001", -2 * DAY);
    seedStored(A, "scan_bbb_001", -DAY);
    seedPending(A, "scan_pen_001", -HOUR);
    gcs.onDeleteFiles = () => { now += 250 * 1000; }; // first document costs more than the whole budget
    const counts = await run(PURGE_RUN_BUDGET_MS);

    expect(counts.expired).toBe(1);
    expect(get(A, "scan_aaa_001").photosState).toBe("deleted");
    expect(get(A, "scan_bbb_001").photosState).toBe("stored"); // not started
    expect(get(A, "scan_pen_001").status).toBe("pending"); // later pass not started
    expect(gcs.getFilesCalls).toEqual([]); // pass 4 not started
  });

  test("a small custom budget is honoured the same way", async () => {
    seedStored(A, "scan_aaa_001", -2 * DAY);
    seedStored(A, "scan_bbb_001", -DAY);
    gcs.onDeleteFiles = () => { now += 2000; };
    const counts = await run(1000);
    expect(counts.expired).toBe(1);
  });
});

describe("failure isolation and logging", () => {
  test("a broken pass (query failure) is counted and logged by pass name and code; the other passes still run", async () => {
    seedPending(A, "scan_pen_001", -HOUR);
    let first = true;
    fx.failOn = (op, name) => {
      if (op === "query" && name === "body_scans" && first) { first = false; return firestoreError("The query requires an index", "failed-precondition"); }
      return undefined;
    };
    const counts = await run();
    expect(counts.failures).toBe(1);
    expect(counts.pending).toBe(1);
    expect(bodyScanEvents(logger, "error")).toEqual([
      { operation: "bodyScanPurge", outcome: "pass-failed", pass: "purgeExpiredPhotos", errorCode: "failed-precondition" },
    ]);
    expect(loggedText(logger)).not.toContain("requires an index");
  });

  test("the run-complete log carries counts only: no uid, path or scan id", async () => {
    seedStored(A, "scan_due_001", -DAY);
    putPhotos(A, "scan_due_001", { timeCreated: now - 3 * DAY });
    putPhotos(B, "scan_ghost_01", { timeCreated: now - 3 * DAY });
    await run();
    const done = bodyScanEvents(logger).filter((e) => e.outcome === "run-complete");
    expect(done).toEqual([{ operation: "bodyScanPurge", outcome: "run-complete", latencyMs: 0, expired: 1, pending: 0, tombstones: 0, unmatched: 3, failures: 0 }]);
    const text = loggedText(logger);
    for (const secret of [A, B, "scan_due_001", "scan_ghost_01", "users/"]) expect(text).not.toContain(secret);
  });

  test("a run with nothing to do is clean and idempotent", async () => {
    const first = await run();
    const second = await run();
    expect(first).toEqual({ expired: 0, pending: 0, tombstones: 0, unmatched: 0, failures: 0 });
    expect(second).toEqual(first);
  });
});
