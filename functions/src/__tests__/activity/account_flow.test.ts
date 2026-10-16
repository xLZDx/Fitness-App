/**
 * S02-06b through the REAL `deleteAccount`, `reconcileAccountDeletions` and the scheduled late
 * sweep of functions/src/index.ts: F56, F77, F78 (A, B, C), F80, F95 order, F26, E05 (functions
 * part), plus E03 (stream lifecycle). The offline-replay half of E05 needs the rules emulator
 * (epic 5) and is not modelled here.
 */
jest.mock("firebase-admin", () => {
  const m = require("./support/fakes").adminMock();
  m.auth = () => (globalThis as any).__flowAuth;
  return m;
});
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());
jest.mock("stripe", () => {
  const ctor: any = jest.fn(() => ({ subscriptions: { cancel: jest.fn(), retrieve: jest.fn(), list: jest.fn() } }));
  return ctor;
});
jest.mock("firebase-admin/storage", () => ({
  getStorage: () => ({ bucket: (name: string) => ((globalThis as any).__flowBuckets as Record<string, unknown>)[name] }),
}));

import { deleteAccount, reconcileAccountDeletions } from "../../index";
import { reconcileActivityStreams } from "../../activity_streams/reconcile";
import { sweepLateActivityStreams } from "../../activity_streams/late_sweep";
import { handleGetActivityStreamDownloadUrls } from "../../activity_streams/download_urls";
import { runActivityStreamPurge } from "../../activity_streams/purge";
import { sweepActivityStreamObjects } from "../../activity_streams/sweep";
import { DEFAULT_RETENTION_LIMITS } from "../../activity_streams/retention";
import {
  ACT, BUCKET_NAME, DAY, FakeBucket, HOUR, MIN, T0, UID, callReq, createWorld, firestoreError, firestoreInstance, fx,
  quarantinePath, releaseClock, resetAll, rowOf, seedReady, setNow, store, streamPath, ts, uploadIdN, useClock, writes, type World,
} from "./support/fakes";
import { commit, fullUpload, outcome, stage } from "./support/flow";
import { SEVEN } from "./support/seven";

const FENCE = `activity_account_state/${UID}`;
const RETRIES = `accountDeletionRetries/${UID}`;
const BODY_BUCKET = "body-scan-test-bucket";
let w: World;
let body: FakeBucket;
let tl: string[];
let killed = false;
let deleteUserFails: unknown = null;
const origRd = firestoreInstance.recursiveDelete;

const notFound = () => Object.assign(new Error("There is no user record"), { code: "auth/user-not-found" });

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  body = new FakeBucket();
  tl = [];
  killed = false;
  deleteUserFails = null;
  process.env.ACTIVITY_STREAM_BUCKET = BUCKET_NAME;
  process.env.BODY_SCAN_BUCKET = BODY_BUCKET;
  (globalThis as any).__flowBuckets = { [BUCKET_NAME]: w.bucket, [BODY_BUCKET]: body };
  (globalThis as any).__flowAuth = {
    revokeRefreshTokens: jest.fn(async () => undefined),
    getUser: async (uid: string) => { if (!w.auth.users.has(uid)) throw notFound(); return { uid }; },
    deleteUser: async (uid: string) => {
      tl.push("auth:delete");
      if (deleteUserFails) throw deleteUserFails;
      w.auth.users.delete(uid);
      onAuthDeleted?.();
    },
  };
  onAuthDeleted = null;
  fx.afterCommit = (paths) => {
    for (const p of paths) {
      if (p === FENCE) tl.push(store.get(FENCE)?.authDeletedAt !== undefined && !tl.includes("fs:authDeletedAt") ? "fs:authDeletedAt" : "fs:fence");
      else if (p === RETRIES) tl.push(store.has(RETRIES) ? "fs:retries" : "fs:retries-cleared");
    }
  };
  w.bucket.hook = (phase, op, path) => { if (phase === "before" && op === "deleteFiles") tl.push(`act:${path}`); };
  body.hook = (phase, op, path) => { if (phase === "before" && op === "deleteFiles") tl.push(`body:${path}`); };
  (firestoreInstance as any).recursiveDelete = async (ref: { path: string }) => {
    if (killed) throw firestoreError("killed", 14);
    tl.push(`rd:${ref.path}`);
    await origRd(ref);
    onRd?.(ref.path);
  };
});
afterEach(() => {
  (firestoreInstance as any).recursiveDelete = origRd;
  releaseClock();
});
let onAuthDeleted: (() => void) | null = null;
let onRd: ((path: string) => void) | null = null;
afterEach(() => { onRd = null; onAuthDeleted = null; });

const run = (uid = UID): Promise<any> => (deleteAccount as any).run(callReq({}, uid));
const runReconciler = (): Promise<void> => (reconcileAccountDeletions as any).run({ scheduleTime: new Date(Date.now()).toISOString() });
const runLate = (): Promise<void> => (sweepLateActivityStreams as any).run({});
const seedBoth = (): void => {
  w.bucket.put(streamPath(UID, ACT, uploadIdN(1)), Buffer.from("s"));
  w.bucket.put(quarantinePath(UID, ACT, uploadIdN(2)), Buffer.from("q"));
  body.put(`users/${UID}/scans/s1/front.jpg`, Buffer.from("photo"));
};
const activityDocs = (): string[] => [...store.keys()].filter((k) => /^users\/[^/]+\/activit/.test(k));
const idx = (e: string, from = 0): number => tl.indexOf(e, from);

describe("F56/F95 deleteAccount order (real flow)", () => {
  test("fence first, then sweep 1 (Firestore then body scan then activity, both prefixes), Auth deletion, authDeletedAt, sweep 2; the fence survives", async () => {
    store.set(`users/${UID}/profile/main`, { name: "x" });
    seedReady();
    seedBoth();
    const res = await run();
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    const fence = idx("fs:fence");
    const rd1 = idx(`rd:users/${UID}`);
    const s1 = idx(`act:streams/${UID}/`);
    const q1 = idx(`act:quarantine/${UID}/`);
    const retries = idx("fs:retries");
    const auth = idx("auth:delete");
    const authAt = idx("fs:authDeletedAt");
    const rd2 = idx(`rd:users/${UID}`, rd1 + 1);
    const s2 = idx(`act:streams/${UID}/`, s1 + 1);
    expect(fence).toBeGreaterThanOrEqual(0);
    expect([fence, rd1, s1, q1, retries, auth, authAt, rd2, s2]).toEqual([...[fence, rd1, s1, q1, retries, auth, authAt, rd2, s2]].sort((a, b) => a - b));
    expect(new Set([fence, rd1, s1, q1, retries, auth, authAt, rd2, s2]).size).toBe(9);
    expect(idx(`body:users/${UID}/`)).toBeLessThan(s1); // body scan before the activity sweep (F78 A)
    expect(idx("fs:retries-cleared")).toBeGreaterThan(s2);
    expect(store.has(FENCE)).toBe(true); // F80: Step 4 clears the retries record, NOT the fence
    expect(store.has(RETRIES)).toBe(false);
    expect(store.get(FENCE)!.authDeletedAt.toMillis()).toBe(T0);
    expect(store.get(FENCE)!.lateSweepDone).toBeUndefined();
    expect(w.bucket.keys()).toEqual([]);
    expect(body.keys()).toEqual([]);
    expect(activityDocs()).toEqual([]);
  });
  test("a second deleteAccount run keeps the EARLIEST fenceAt", async () => {
    await run();
    const first = store.get(FENCE)!.fenceAt.toMillis();
    setNow(T0 + 3 * MIN);
    await run();
    expect(store.get(FENCE)!.fenceAt.toMillis()).toBe(first);
    expect(store.get(FENCE)!.lateSweepAt.toMillis()).toBe(T0 + 15 * MIN);
  });
  test("when the fence write fails nothing is deleted and the user can retry", async () => {
    store.set(`users/${UID}/profile/main`, { name: "x" });
    fx.failOn = (op, p) => (op === "commit" && p.includes("activity_account_state") ? firestoreError("down", 14) : undefined);
    await expect(run()).rejects.toMatchObject({ code: "internal" });
    expect(store.has(`users/${UID}/profile/main`)).toBe(true);
    expect(tl.some((e) => e.startsWith("rd:") || e === "auth:delete")).toBe(false);
    expect(w.auth.users.has(UID)).toBe(true);
  });
  test("an upload injected between the Firestore delete and the first storage sweep leaves both prefixes empty", async () => {
    onRd = (p) => {
      if (p === `users/${UID}`) {
        w.bucket.put(streamPath(UID, ACT, uploadIdN(5)), Buffer.from("raced"));
        w.bucket.put(quarantinePath(UID, ACT, uploadIdN(6)), Buffer.from("raced"));
      }
    };
    await run();
    expect(w.bucket.keys()).toEqual([]);
  });
});

describe("F78 both sweep calls clean the activity bucket; cleanups are independent", () => {
  test("Part A: Step 2 alone (Auth deletion fails) empties both prefixes; the reconciler call alone (rows already gone) empties both", async () => {
    seedBoth();
    deleteUserFails = Object.assign(new Error("auth down"), { code: "auth/internal-error" });
    await expect(run()).rejects.toMatchObject({ code: "internal" });
    expect(w.bucket.keys()).toEqual([]);
    expect(body.keys()).toEqual([]);
    // reconciler-only path: rows/settings already deleted, objects arrive afterwards
    w.auth.users.delete(UID);
    seedBoth();
    store.set(RETRIES, { uid: UID, status: "pending", attempts: 0, nextAttemptAt: ts(T0 - 1), createdAt: ts(T0), expireAt: ts(T0 + 30 * DAY) });
    await runReconciler();
    expect(w.bucket.keys()).toEqual([]);
    expect(body.keys()).toEqual([]);
    expect(store.has(RETRIES)).toBe(false);
  });
  test("Part B case 1: body scan cleanup fails: the activity prefixes are still EMPTY, body objects remain, ONE bare code is recorded", async () => {
    onAuthDeleted = () => { seedBoth(); body.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error(`secret ${UID}`), { code: 500 }) : null); };
    const res = await run();
    expect(res.finalCleanup).toBe("scheduled");
    expect(w.bucket.keys()).toEqual([]);
    expect(body.keys()).toHaveLength(1);
    expect(store.get(RETRIES)!.lastErrorCode).toBe("500");
    expect(JSON.stringify(store.get(RETRIES))).not.toContain("secret");
  });
  test("Part B case 2: activity storage fails on both prefixes: the body scan bucket is still EMPTY, activity objects remain, ONE bare code", async () => {
    onAuthDeleted = () => { seedBoth(); w.bucket.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("gs://x"), { code: 403 }) : null); };
    const res = await run();
    expect(res.finalCleanup).toBe("scheduled");
    expect(body.keys()).toEqual([]);
    expect(w.bucket.keys()).toHaveLength(2);
    expect(store.get(RETRIES)!.lastErrorCode).toBe("403");
  });
  test("Step 2 with the body scan bucket failing aborts with a retryable error but the activity prefixes are still emptied", async () => {
    seedBoth();
    body.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("x"), { code: 500 }) : null);
    await expect(run()).rejects.toMatchObject({ code: "internal" });
    expect(w.bucket.keys()).toEqual([]);
    expect(w.auth.users.has(UID)).toBe(true); // Auth not deleted: the user can retry
  });
  test("Part B case 3 + Part C and F26: both failing keeps both; after recovery the reconciler retry empties them and clears the record", async () => {
    onAuthDeleted = () => {
      seedBoth();
      body.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("x"), { code: 500 }) : null);
      w.bucket.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("x"), { code: 403 }) : null);
    };
    await run();
    expect(body.keys()).toHaveLength(1);
    expect(w.bucket.keys()).toHaveLength(2);
    expect(store.get(RETRIES)!.attempts).toBe(1);
    body.failOn = null;
    w.bucket.failOn = null;
    setNow(T0 + 20 * MIN);
    await runReconciler();
    expect(w.bucket.keys()).toEqual([]);
    expect(body.keys()).toEqual([]);
    expect(store.has(RETRIES)).toBe(false);
  });
  test("F26 one failing attempt then success: the retry count stays far below RETRY_MAX_ATTEMPTS = 12", async () => {
    onAuthDeleted = () => { seedBoth(); w.bucket.failOn = (op, p) => (op === "deleteFiles" && p.startsWith("streams/") ? Object.assign(new Error("x"), { code: 500 }) : null); };
    await run();
    expect(w.bucket.keys(`quarantine/`)).toEqual([]); // the other prefix is no longer left untouched
    expect(store.get(RETRIES)!.attempts).toBe(1);
    w.bucket.failOn = null;
    setNow(T0 + 20 * MIN);
    await runReconciler();
    expect(store.has(RETRIES)).toBe(false);
    expect(w.bucket.keys()).toEqual([]);
  });
});

describe("F77 a killed invocation still leaves the late job", () => {
  const points: Array<[string, () => void]> = [
    ["after the fence write", () => { fx.afterCommit = (paths) => { if (paths.includes(FENCE)) throw firestoreError("killed", 14); }; }],
    ["after the first sweep (Step 2)", () => { w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "deleteFiles" && path.startsWith("quarantine/")) throw firestoreError("killed", 14); }; }],
    ["right after Auth deletion", () => { onAuthDeleted = () => { killed = true; fx.failOn = () => firestoreError("killed", 14); }; }],
    ["after accountDeletionRetries is cleared", () => { const prev = fx.afterCommit; fx.afterCommit = (paths) => { prev?.(paths); if (paths.includes(RETRIES) && !store.has(RETRIES)) throw firestoreError("killed", 14); }; }],
  ];
  test.each(points)("killed %s: the job exists with lateSweepAt and no lateSweepDone", async (_n, arm) => {
    arm();
    await run().catch(() => undefined);
    fx.failOn = null;
    killed = false;
    const fence = store.get(FENCE)!;
    expect(fence.lateSweepAt.toMillis()).toBe(T0 + 15 * MIN);
    expect(fence.lateSweepDone).toBeUndefined();
  });
  test("killed right after Auth deletion: the late sweep later removes both prefixes and recreated documents and sets lateSweepDone", async () => {
    onAuthDeleted = () => { killed = true; fx.failOn = () => firestoreError("killed", 14); };
    const res = await run();
    expect(res.finalCleanup).toBe("scheduled");
    fx.failOn = null;
    killed = false;
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(7)), Buffer.from("late PUT"));
    store.set(`users/${UID}/activities/${ACT}`, { startUtc: ts(T0), rev: 1 });
    expect(store.get(FENCE)!.authDeletedAt).toBeUndefined(); // the write was lost
    setNow(T0 + 15 * MIN);
    await runLate();
    expect(w.bucket.keys()).toEqual([]);
    expect(activityDocs()).toEqual([]);
    expect(store.get(FENCE)!.lateSweepDone.toMillis()).toBe(T0 + 15 * MIN);
    expect(store.get(FENCE)!.authDeletedAt.toMillis()).toBe(T0 + 15 * MIN); // derived from Auth absence at the first run
  });
});

describe("E05 deletion races end to end (functions part)", () => {
  test("commit and settings calls during the deletion are refused, late PUTs are swept, the fence outlives the sweep and then goes; reconciler rerun writes nothing", async () => {
    seedReady();
    const s = await stage(w);
    onRd = (p) => {
      if (p !== `users/${UID}` || tl.filter((e) => e === `rd:users/${UID}`).length !== 1) return;
      (globalThis as any).__during = Promise.all([
        outcome(commit(w, { activityId: ACT, uploadId: s.uploadId })),
        outcome(SEVEN.find((e) => e.name === "setActivityCloudSettings")!.call(w, { streamRetentionDays: 365 })),
      ]);
    };
    onAuthDeleted = () => { w.bucket.put(quarantinePath(UID, ACT, uploadIdN(8)), Buffer.from("2nd PUT after Auth deletion")); };
    const res = await run();
    const [c, st] = await (globalThis as any).__during;
    expect(c).toBe("failed-precondition:account_deleting");
    expect(st).toBe("failed-precondition:account_deleting");
    expect(res.finalCleanup).toBe("complete");
    expect(store.has(`users/${UID}/activity_settings/main`)).toBe(false); // no consent document recreated
    expect(w.bucket.keys()).toEqual([]);
    // a PUT after Step 4 (still-valid signed URL) and a document that slipped in
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(9)), Buffer.from("post-Step-4 PUT"));
    store.set(`users/${UID}/activities/${ACT}`, { startUtc: ts(T0), rev: 1 });
    setNow(T0 + 15 * MIN - 1000);
    await runLate();
    expect(w.bucket.keys()).toHaveLength(1);
    setNow(T0 + 15 * MIN);
    await runLate();
    expect(w.bucket.keys()).toEqual([]);
    expect(activityDocs()).toEqual([]);
    const done = store.get(FENCE)!.lateSweepDone.toMillis();
    const removeAfter = Math.max(done + HOUR, T0 + 70 * MIN);
    setNow(removeAfter - MIN);
    await runLate();
    expect(store.has(FENCE)).toBe(true);
    setNow(removeAfter + MIN);
    await runLate();
    expect(store.has(FENCE)).toBe(false);
    // second reconciler run issues no write
    const n = writes.length;
    await (reconcileActivityStreams as any).run({});
    await (reconcileActivityStreams as any).run({});
    const meaningful = writes.slice(n).filter((x) => !x.path.startsWith("activity_reconcile_state/"));
    expect(meaningful).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
});

describe("E03 stream lifecycle", () => {
  test("upload, commit, download URL, shorten retention, purge, delete activity, account sweep", async () => {
    seedReady();
    const dl = () => handleGetActivityStreamDownloadUrls(w.deps, UID, "password", { activityIds: [ACT], expectedUid: UID });
    const f = await fullUpload(w);
    expect(rowOf(UID, ACT).state).toBe("stored");
    const url1 = await dl();
    expect(url1.results[0]).toMatchObject({ status: "ok", expiresAtMs: T0 + 15 * MIN });
    // shorten the retention so the activity (100 days old) is due
    store.set(`users/${UID}/activities/${ACT}`, { startUtc: ts(T0 - 100 * DAY), rev: 1 });
    store.get(`users/${UID}/activity_settings/main`)!.streamRetentionDays = 90;
    store.get(`users/${UID}/activity_settings/main`)!.settingsGeneration = 2;
    store.get(`users/${UID}/activity_settings/main`)!.recomputePending = true;
    const r = await runActivityStreamPurge(
      { firestore: () => firestoreInstance as never, bucket: () => w.bucket, nowMs: () => Date.now() },
      DEFAULT_RETENTION_LIMITS,
    );
    expect(r.purged).toBe(1);
    expect(w.bucket.objects.has(streamPath(UID, ACT, f.uploadId))).toBe(false);
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(true); // the summary stays
    const url2 = await dl();
    expect(url2.results[0]).toEqual({ activityId: ACT, status: "unavailable", code: "expired" });
    await SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT });
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(false);
    expect(store.has(`users/${UID}/activity_tombstones/${ACT}`)).toBe(true);
    expect((await dl()).results[0]).toEqual({ activityId: ACT, status: "unavailable", code: "not_found" });
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(3)), Buffer.from("left over"));
    await sweepActivityStreamObjects(UID, { bucket: () => w.bucket });
    expect(w.bucket.keys()).toEqual([]);
  });
});
