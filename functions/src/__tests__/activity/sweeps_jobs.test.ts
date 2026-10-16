/**
 * S02-06b with direct seams: F24, F25, F57 (sweep), F55, F58, F95 timing table (late sweep),
 * F27, F28, F72 (reconciler), F54 (commit racing delete), F81 (bulk delete job),
 * plus the documented OPEN RISK of the late sweep after an aborted deletion.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import { DEFAULT_DELETE_ALL_LIMITS, handleDeleteAllActivityStreams, type DeleteAllLimits } from "../../activity_streams/delete_all_streams";
import { writeActivityAccountFence } from "../../activity_streams/fence";
import { ACTIVITY_LATE_SWEEP_EVENT, recordAuthDeletedAt, runActivityLateSweep, type LateSweepDeps } from "../../activity_streams/late_sweep";
import { runActivityReconcile, type ReconcileDeps } from "../../activity_streams/reconcile";
import { ACTIVITY_SWEEP_SKIPPED, runIndependentCleanups, sweepActivityStreamObjects } from "../../activity_streams/sweep";
import {
  ACT, ACT_2, DAY, HOUR, MIN, T0, UID, UID_B, createWorld, firestoreInstance, loggedText, quarantinePath,
  releaseClock, resetAll, rowOf, seedReady, seedSummary, setNow, store, streamPath, ts, uploadIdN, usageOf, useClock, validPayload, writes,
  type World,
} from "./support/fakes";
import { commit, outcome, stage } from "./support/flow";
import { SEVEN } from "./support/seven";

let w: World;
const FENCE = `activity_account_state/${UID}`;
const bareErr = (code: number | string) => Object.assign(new Error(`SDK says gs://secret-bucket/streams/${UID}/x`), { code });
const lateDeps = (): LateSweepDeps => ({
  firestore: w.deps.firestore, authUserExists: w.deps.authUserExists, nowMs: w.deps.nowMs, bucket: w.deps.bucket,
});
const recDeps = (): ReconcileDeps => ({ ...w.deps, listing: () => w.bucket });
const actId = (n: number): string => `act_${n.toString(16).padStart(40, "0")}`;

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  (logger.info as jest.Mock).mockClear();
});
afterEach(() => releaseClock());

describe("F24 sweepActivityStreamObjects prefix", () => {
  test("removes both prefixes of the uid only; abc is not abcd", async () => {
    for (const u of ["abc", "abcd"]) {
      w.bucket.put(`streams/${u}/${ACT}/up.json.gz`, Buffer.from("s"));
      w.bucket.put(`quarantine/${u}/${ACT}/up`, Buffer.from("q"));
    }
    await sweepActivityStreamObjects("abc", { bucket: () => w.bucket });
    expect(w.bucket.keys()).toEqual([`quarantine/abcd/${ACT}/up`, `streams/abcd/${ACT}/up.json.gz`]);
    expect(w.bucket.deleteFilesCalls).toEqual(["streams/abc/", "quarantine/abc/"]);
  });
});

describe("F25/F57 sweep error contract and both-prefix attempt", () => {
  test("unset bucket is a logged no-op, not a throw", async () => {
    await expect(sweepActivityStreamObjects(UID, { bucket: () => undefined })).resolves.toBeUndefined();
    expect((logger.info as jest.Mock).mock.calls.some((c) => c[0] === ACTIVITY_SWEEP_SKIPPED)).toBe(true);
  });
  test("404 on both prefixes is success", async () => {
    w.bucket.failOn = (op) => (op === "deleteFiles" ? bareErr(404) : null);
    await expect(sweepActivityStreamObjects(UID, { bucket: () => w.bucket })).resolves.toBeUndefined();
  });
  test("a failing streams/ prefix leaves quarantine/ attempted (and cleaned), and the reverse", async () => {
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("s"));
    w.bucket.put(quarantinePath(UID, ACT, "up_1"), Buffer.from("q"));
    w.bucket.failOn = (op, p) => (op === "deleteFiles" && p.startsWith("streams/") ? bareErr(403) : null);
    await expect(sweepActivityStreamObjects(UID, { bucket: () => w.bucket })).rejects.toMatchObject({ code: "403", message: "activity stream storage sweep failed" });
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, "up_1")]);
    w.bucket.put(quarantinePath(UID, ACT, "up_1"), Buffer.from("q"));
    w.bucket.failOn = (op, p) => (op === "deleteFiles" && p.startsWith("quarantine/") ? bareErr(403) : null);
    await expect(sweepActivityStreamObjects(UID, { bucket: () => w.bucket })).rejects.toMatchObject({ code: "403" });
    expect(w.bucket.keys()).toEqual([quarantinePath(UID, ACT, "up_1")]);
  });
  test("both failing throws ONE bare error without path, uid or SDK message", async () => {
    w.bucket.failOn = (op) => (op === "deleteFiles" ? bareErr(500) : null);
    const e: any = await sweepActivityStreamObjects(UID, { bucket: () => w.bucket }).then(() => null, (x) => x);
    expect(e.code).toBe("500");
    expect(e.message).not.toContain(UID);
    expect(e.message).not.toContain("gs://");
    expect(w.bucket.deleteFilesCalls).toHaveLength(2);
  });
  test("runIndependentCleanups attempts every cleanup and aggregates to one bare code", async () => {
    const ran: string[] = [];
    const bad = (n: string, code: number) => async () => { ran.push(n); throw bareErr(code); };
    await expect(runIndependentCleanups([bad("a", 7), async () => { ran.push("b"); }, bad("c", 9)])).rejects.toMatchObject({ code: 7, message: "account storage sweep failed" });
    expect(ran).toEqual(["a", "b", "c"]);
    const single = bareErr(5);
    await expect(runIndependentCleanups([async () => { throw single; }])).rejects.toBe(single);
  });
});

async function seedFence(atMs = T0): Promise<void> {
  setNow(atMs);
  await writeActivityAccountFence(lateDeps(), UID);
}
function seedUserActivityDocs(uid = UID): void {
  seedSummary(uid, ACT);
  store.set(`users/${uid}/activity_streams/${ACT}`, { state: "stored" });
  store.set(`users/${uid}/activity_settings/main`, { settingsGeneration: 1 });
  store.set(`users/${uid}/activity_tombstones/${ACT_2}`, { deletedAt: ts(T0) });
  store.set(`users/${uid}/profile/main`, { keep: true });
}
const LATE_AT = T0 + 15 * MIN;

describe("F55/F58 late sweep job", () => {
  test("not run one second early; at lateSweepAt both prefixes and the activity docs are gone and lateSweepDone is set", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    seedUserActivityDocs();
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(1)), Buffer.from("late PUT")); // control: the scenario is real
    expect(w.bucket.keys(`quarantine/${UID}/`)).toHaveLength(1);
    expect(store.get(FENCE)!.lateSweepAt.toMillis()).toBe(LATE_AT);
    setNow(LATE_AT - 1000);
    expect((await runActivityLateSweep(lateDeps())).due).toBe(0);
    expect(w.bucket.keys(`quarantine/${UID}/`)).toHaveLength(1);
    setNow(LATE_AT);
    const r = await runActivityLateSweep(lateDeps());
    expect(r.swept).toBe(1);
    expect(w.bucket.keys()).toEqual([]);
    for (const c of ["activities", "activity_streams", "activity_settings", "activity_tombstones"]) {
      expect([...store.keys()].filter((k) => k.startsWith(`users/${UID}/${c}/`))).toEqual([]);
    }
    expect(store.has(`users/${UID}/profile/main`)).toBe(true); // only the activity collections
    expect(store.get(FENCE)!.lateSweepDone.toMillis()).toBe(LATE_AT);
  });
  test("a failing part leaves the job not done, still attempts the final recursive delete, records a bare code", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    seedUserActivityDocs();
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("s"));
    w.bucket.failOn = (op) => (op === "deleteFiles" ? bareErr(403) : null);
    setNow(LATE_AT);
    const r = await runActivityLateSweep(lateDeps());
    expect(r.failures).toBe(1);
    const fence = store.get(FENCE)!;
    expect(fence.lateSweepDone).toBeUndefined();
    expect(fence.lastErrorCode).toBe("403");
    expect(fence.lateSweepAttempts).toBe(1);
    expect([...store.keys()].filter((k) => k.includes("/activity_"))).toEqual([]); // final delete still ran
    w.bucket.failOn = null;
    setNow(LATE_AT + 5 * MIN);
    const r2 = await runActivityLateSweep(lateDeps());
    expect(r2.swept).toBe(1);
    expect(w.bucket.keys()).toEqual([]);
    expect(store.get(FENCE)!.lastErrorCode).toBeUndefined();
  });
  test("a job stuck more than one hour is counted and the log carries no uid", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    w.bucket.failOn = (op) => (op === "deleteFiles" ? bareErr(500) : null);
    setNow(LATE_AT + 2 * HOUR);
    const r = await runActivityLateSweep(lateDeps());
    expect(r.stuck).toBe(1);
    expect(r.oldestStuckAgeMs).toBe(2 * HOUR);
    expect(loggedText(logger)).toContain(ACTIVITY_LATE_SWEEP_EVENT);
    expect(loggedText(logger)).not.toContain(UID);
  });
  test("the job lives outside users/{uid}: recursiveDelete(users/uid) leaves it; user A's job never touches user B", async () => {
    await seedFence();
    await writeActivityAccountFence(lateDeps(), UID_B);
    await firestoreInstance.recursiveDelete({ path: `users/${UID}` });
    expect(store.has(FENCE)).toBe(true);
    w.bucket.put(streamPath(UID_B, ACT, "up_1"), Buffer.from("b"));
    w.bucket.put(`streams/${UID}x/${ACT}/up`, Buffer.from("x"));
    store.delete(`activity_account_state/${UID_B}`);
    w.auth.users.delete(UID);
    setNow(LATE_AT);
    await runActivityLateSweep(lateDeps());
    expect(w.bucket.keys()).toEqual([`streams/${UID}x/${ACT}/up`, streamPath(UID_B, ACT, "up_1")]);
  });
  test("a done job issues no storage deletes and no writes before the removal is due (idempotent)", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    setNow(LATE_AT);
    await runActivityLateSweep(lateDeps());
    const dels = w.bucket.deleteFilesCalls.length;
    const n = writes.length;
    setNow(LATE_AT + MIN);
    const r = await runActivityLateSweep(lateDeps());
    expect(w.bucket.deleteFilesCalls.length).toBe(dels);
    expect(writes.length - n).toBe(0);
    expect(r.swept).toBe(0);
  });
  test("an invalid document id is dropped", async () => {
    store.set("activity_account_state/bad id!", { lateSweepAt: ts(T0 - 1) });
    const r = await runActivityLateSweep(lateDeps());
    expect(r.invalid).toBe(1);
    expect(store.has("activity_account_state/bad id!")).toBe(false);
  });
});

describe("F95/F80 fence removal timing table (injected clock, one minute either side)", () => {
  async function doneAt(doneMs: number, authMs: number | null): Promise<void> {
    await seedFence();
    w.auth.users.delete(UID);
    if (authMs !== null) { setNow(authMs); await recordAuthDeletedAt(lateDeps(), UID); }
    setNow(doneMs);
    await runActivityLateSweep(lateDeps());
    expect(store.get(FENCE)!.lateSweepDone.toMillis()).toBe(doneMs);
  }
  const at = async (ms: number): Promise<boolean> => { setNow(ms); await runActivityLateSweep(lateDeps()); return store.has(FENCE); };
  test("(a) lateSweepDone + 1 h is the later bound: authDeletedAt = T - 20 min: kept at T + 59 min, removed at T + 61 min", async () => {
    const T = LATE_AT;
    await doneAt(T, T - 20 * MIN);
    expect(await at(T + 59 * MIN)).toBe(true);
    expect(await at(T + 61 * MIN)).toBe(false);
  });
  test("(a2) plan cell (a) says authDeletedAt = T - 5 min is removed at T + 1 h; the design formula gives max(T + 60, T + 65) = T + 65 min and wins", async () => {
    const T = LATE_AT;
    await doneAt(T, T - 5 * MIN);
    expect(await at(T + 61 * MIN)).toBe(true);
    expect(await at(T + 64 * MIN)).toBe(true);
    expect(await at(T + 66 * MIN)).toBe(false);
  });
  test("(b) authDeletedAt = T + 30 min: kept at T + 99 min, removed after T + 100 min (not at T + 1 h)", async () => {
    const T = LATE_AT;
    await seedFence();
    w.auth.users.delete(UID);
    setNow(T);
    await runActivityLateSweep(lateDeps());
    // the invocation recorded authDeletedAt later than the sweep (set directly: the job found Auth gone and derived T)
    store.get(FENCE)!.authDeletedAt = ts(T + 30 * MIN);
    expect(await at(T + 61 * MIN)).toBe(true);
    expect(await at(T + 99 * MIN)).toBe(true);
    expect(await at(T + 101 * MIN)).toBe(false);
  });
  test("(c) crash before authDeletedAt: derived at the first run, removal at first run + 70 min; Auth present: never removed", async () => {
    const T = LATE_AT;
    await doneAt(T, null);
    expect(store.get(FENCE)!.authDeletedAt.toMillis()).toBe(T);
    expect(await at(T + 69 * MIN)).toBe(true);
    expect(await at(T + 71 * MIN)).toBe(false);
  });
  test("(c2) the Auth user still exists: nothing is swept, the job stays armed, the fence is never removed", async () => {
    await seedFence();
    setNow(LATE_AT);
    await runActivityLateSweep(lateDeps());
    setNow(LATE_AT + 10 * DAY);
    const r = await runActivityLateSweep(lateDeps());
    expect(store.has(FENCE)).toBe(true);
    expect(r.skippedLive).toBe(1);
    expect(r.swept).toBe(0);
    expect(store.get(FENCE)!.lateSweepDone).toBeUndefined();
    expect(store.get(FENCE)!.authDeletedAt).toBeUndefined();
  });
  test("(d) a retry of Step 1 keeps the earliest fenceAt; (e) the removal job run twice is idempotent", async () => {
    await seedFence();
    const first = store.get(FENCE)!.fenceAt.toMillis();
    setNow(T0 + 5 * MIN);
    expect(await writeActivityAccountFence(lateDeps(), UID)).toBe(false);
    expect(store.get(FENCE)!.fenceAt.toMillis()).toBe(first);
    w.auth.users.delete(UID);
    setNow(LATE_AT);
    await runActivityLateSweep(lateDeps());
    setNow(LATE_AT + 80 * MIN);
    await runActivityLateSweep(lateDeps());
    expect(store.has(FENCE)).toBe(false);
    const n = writes.length;
    await runActivityLateSweep(lateDeps());
    expect(writes.length).toBe(n);
  });
  test("recordAuthDeletedAt keeps the earliest value and does nothing without a fence", async () => {
    expect(await recordAuthDeletedAt(lateDeps(), UID)).toBeUndefined();
    expect(store.has(FENCE)).toBe(false);
    await seedFence();
    const a = await recordAuthDeletedAt(lateDeps(), UID);
    setNow(T0 + HOUR);
    expect(await recordAuthDeletedAt(lateDeps(), UID)).toBe(a);
  });
});

describe("REGRESSION: the late sweep never touches a LIVE account (aborted deletion)", () => {
  test("a fence left by an aborted deletion: the job skips, the live user's objects and documents survive, the job stays armed and logs a bare slug", async () => {
    await seedFence(); // Step 1c ran, then the deletion aborted: the Auth user still exists
    seedUserActivityDocs();
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("precious gps"));
    const docsBefore = [...store.keys()].filter((k) => k.startsWith("users/")).sort();
    for (const at of [LATE_AT, LATE_AT + HOUR, LATE_AT + 3 * DAY]) {
      setNow(at);
      const r = await runActivityLateSweep(lateDeps());
      expect(r).toMatchObject({ skippedLive: 1, swept: 0, removed: 0, failures: 0 });
    }
    expect(w.auth.users.has(UID)).toBe(true);
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, "up_1")]);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
    expect([...store.keys()].filter((k) => k.startsWith("users/")).sort()).toEqual(docsBefore);
    expect(store.get(FENCE)!.lateSweepDone).toBeUndefined();
    expect(loggedText(logger)).toContain("skipped-live-account");
    expect(loggedText(logger)).not.toContain(UID);
  });
  test("the same job proceeds as soon as the deletion really completes (Auth user gone)", async () => {
    await seedFence();
    seedUserActivityDocs();
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("gps"));
    setNow(LATE_AT);
    await runActivityLateSweep(lateDeps());
    expect(w.bucket.keys()).toHaveLength(1);
    w.auth.users.delete(UID);
    setNow(LATE_AT + 5 * MIN);
    const r = await runActivityLateSweep(lateDeps());
    expect(r.swept).toBe(1);
    expect(w.bucket.keys()).toEqual([]);
    expect([...store.keys()].filter((k) => k.includes("/activit"))).toEqual([]);
    expect(store.get(FENCE)!.lateSweepDone).toBeDefined();
  });
  test("a failing Auth lookup fails closed: nothing is erased, the failure is counted", async () => {
    await seedFence();
    seedUserActivityDocs();
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("gps"));
    w.auth.users.delete(UID);
    w.auth.lookupError = Object.assign(new Error("auth down"), { code: "auth/internal-error" });
    setNow(LATE_AT);
    const r = await runActivityLateSweep(lateDeps());
    expect(r.failures).toBe(1);
    expect(r.swept).toBe(0);
    expect(w.bucket.keys()).toHaveLength(1);
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(true);
    expect(store.get(FENCE)!.lateSweepDone).toBeUndefined();
  });
});

/* ------------------------------ reconciler ------------------------------ */

async function interruptedCommit(id = ACT): Promise<{ uploadId: string; promoted: string }> {
  seedReady(UID, id);
  const s = await stage(w, undefined, UID, id);
  w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "save" && path.startsWith("streams/")) throw new Error("killed after promotion"); };
  await commit(w, { activityId: id, uploadId: s.uploadId }).catch(() => undefined);
  w.bucket.hook = null;
  return { uploadId: s.uploadId, promoted: streamPath(UID, id, s.uploadId) };
}

describe("F72 pending-row repair rules", () => {
  test("a good promoted object with intact summary, no fence and no tombstone is REPAIRED to stored (not deleted)", async () => {
    const { promoted } = await interruptedCommit();
    expect(w.bucket.objects.has(promoted)).toBe(true);
    expect(rowOf(UID, ACT).state).toBe("pending");
    expect(rowOf(UID, ACT).intendedStoredSha256).toBeDefined();
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingRepaired).toBe(1);
    expect(rowOf(UID, ACT).state).toBe("stored");
    expect(rowOf(UID, ACT).objectPath).toBe(promoted);
    expect(w.bucket.objects.has(promoted)).toBe(true);
  });
  test("a pending row younger than one hour is not touched", async () => {
    const { promoted } = await interruptedCommit();
    setNow(T0 + 59 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingRepaired + r.pendingAborted).toBe(0);
    expect(rowOf(UID, ACT).state).toBe("pending");
    expect(w.bucket.objects.has(promoted)).toBe(true);
  });
  const negatives: Array<[string, (p: string) => void]> = [
    ["hash mismatch", (p) => { w.bucket.put(p, Buffer.from("tampered")); }],
    ["missing summary", () => { store.delete(`users/${UID}/activities/${ACT}`); }],
    ["fence set", () => { store.set(FENCE, { fenceAt: ts(T0) }); }],
    ["tombstone present", () => { store.set(`users/${UID}/activity_tombstones/${ACT}`, { deletedAt: ts(T0) }); }],
    ["missing object", (p) => { w.bucket.objects.delete(p); }],
  ];
  test.each(negatives)("%s: the upload is DELETED (objects and never-stored row), not repaired", async (_n, mutate) => {
    const { promoted } = await interruptedCommit();
    mutate(promoted);
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingRepaired).toBe(0);
    expect(r.pendingAborted).toBe(1);
    expect(w.bucket.keys(`streams/${UID}/`)).toEqual([]);
    expect(w.bucket.keys(`quarantine/${UID}/`)).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("hook case: a fence created between the object read and the repair commit makes it delete instead", async () => {
    const { promoted } = await interruptedCommit();
    setNow(T0 + 61 * MIN);
    w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "download" && path === promoted) store.set(FENCE, { fenceAt: ts(T0) }); };
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingAborted).toBe(1);
    expect(w.bucket.keys(`streams/${UID}/`)).toEqual([]);
  });
  test("a stored row whose object is missing becomes deleted with object_missing; a healthy stored row is NOT written", async () => {
    seedReady(UID, ACT);
    seedReady(UID, ACT_2);
    const a = await stage(w, undefined, UID, ACT);
    await commit(w, { activityId: ACT, uploadId: a.uploadId });
    const b = await stage(w, undefined, UID, ACT_2);
    await commit(w, { activityId: ACT_2, uploadId: b.uploadId });
    w.bucket.objects.delete(streamPath(UID, ACT, a.uploadId));
    const before = JSON.stringify(rowOf(UID, ACT_2));
    const n = writes.filter((x) => x.path.includes(ACT_2)).length;
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.storedObjectMissing).toBe(1);
    expect(rowOf(UID, ACT).state).toBe("deleted");
    expect(rowOf(UID, ACT).lastErrorCode).toBe("object_missing");
    expect(JSON.stringify(rowOf(UID, ACT_2))).toBe(before);
    expect(writes.filter((x) => x.path.includes(ACT_2)).length).toBe(n);
  });
});

describe("F27 orphan objects and rows", () => {
  test("an unreferenced object older than the upload TTL is deleted, a younger one is kept; unrecognised names are left alone", async () => {
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(1)), Buffer.from("old"));
    w.bucket.put(streamPath(UID, ACT_2, uploadIdN(2)), Buffer.from("old stream"));
    w.bucket.put("streams/weird-name", Buffer.from("?"));
    setNow(T0 + 9 * MIN);
    w.bucket.put(quarantinePath(UID, ACT_2, uploadIdN(3)), Buffer.from("young"));
    setNow(T0 + 11 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.orphansDeleted).toBe(2);
    expect(r.unrecognised).toBe(1);
    expect(w.bucket.keys()).toEqual([quarantinePath(UID, ACT_2, uploadIdN(3)), "streams/weird-name"]);
  });
  test("a referenced stored object is kept", async () => {
    seedReady();
    const s = await stage(w);
    await commit(w, { activityId: ACT, uploadId: s.uploadId });
    setNow(T0 + 2 * DAY);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.orphansDeleted).toBe(0);
    expect(w.bucket.objects.has(streamPath(UID, ACT, s.uploadId))).toBe(true);
  });
  test("a stored row WITHOUT a summary is removed with its objects (code and design; plan F27 says kept)", async () => {
    seedReady();
    const s = await stage(w);
    await commit(w, { activityId: ACT, uploadId: s.uploadId });
    store.delete(`users/${UID}/activities/${ACT}`);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.rowsWithoutSummary).toBe(1);
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(w.bucket.keys()).toEqual([]);
  });
});

describe("F28 reconciler failure injection", () => {
  test("a storage failure in one pass is counted, the other passes still run, and the rerun completes the work", async () => {
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(1)), Buffer.from("o1"));
    w.bucket.put(streamPath(UID, ACT_2, uploadIdN(2)), Buffer.from("o2"));
    setNow(T0 + 20 * MIN);
    w.bucket.failOn = (op, p) => (op === "delete" && p.startsWith("quarantine/") ? bareErr(500) : null);
    const r1 = await runActivityReconcile(recDeps(), undefined, []);
    expect(r1.failures).toBe(1);
    expect(w.bucket.keys()).toEqual([quarantinePath(UID, ACT, uploadIdN(1))]); // streams orphan still removed
    w.bucket.failOn = null;
    const r2 = await runActivityReconcile(recDeps(), undefined, []);
    expect(r2.failures).toBe(0);
    expect(w.bucket.keys()).toEqual([]);
    expect(loggedText(logger)).not.toContain(UID);
  });
  test("a feature-off bucket is a no-op run", async () => {
    const r = await runActivityReconcile({ ...recDeps(), listing: () => undefined }, undefined, []);
    expect(r.bucketConfigured).toBe(false);
  });
});

/* ------------------------------ F54 ------------------------------ */

describe("F54 commit racing deleteActivity", () => {
  const del = () => SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT });
  test("deleteActivity (tombstone first) runs fully between promotion and transaction 2: nothing survives", async () => {
    seedReady();
    const s = await stage(w);
    let once = false;
    w.bucket.hook = async (phase, op, path) => {
      if (!once && phase === "after" && op === "save" && path.startsWith("streams/")) { once = true; await del(); }
    };
    const res = await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }));
    w.bucket.hook = null;
    expect(res).not.toBe("OK");
    expect(w.bucket.keys(`streams/${UID}/`)).toEqual([]);
    expect(w.bucket.keys(`quarantine/${UID}/`)).toEqual([]);
    expect(rowOf(UID, ACT)?.state).not.toBe("stored");
    expect(store.has(`users/${UID}/activity_tombstones/${ACT}`)).toBe(true);
  });
  test("deleteActivity AFTER the commit finished removes object, row and summary", async () => {
    seedReady();
    const s = await stage(w);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("OK");
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
    await del();
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(false);
  });
});

/* ------------------------------ F81 ------------------------------ */

describe("F81 deleteAllActivityStreams resumable job", () => {
  const SETTINGS = `users/${UID}/activity_settings/main`;
  const lim = (o: Partial<DeleteAllLimits> = {}): DeleteAllLimits => ({ ...DEFAULT_DELETE_ALL_LIMITS, budgetMs: 1e9, ...o });
  const call = (o: Partial<DeleteAllLimits> = {}) => handleDeleteAllActivityStreams(w.deps, UID, "password", lim(o));
  function seedMany(n: number): void {
    store.set(SETTINGS, { cloudStreams: { version: 1, acceptedAt: ts(T0) }, settingsGeneration: 1, streamRetentionDays: 730 });
    for (let i = 1; i <= n; i++) {
      seedSummary(UID, actId(i));
      store.set(`users/${UID}/activity_streams/${actId(i)}`, { state: "stored", objectPath: streamPath(UID, actId(i), "up_1") });
      w.bucket.put(streamPath(UID, actId(i), "up_1"), Buffer.from("x"));
    }
    w.bucket.put(streamPath(UID_B, ACT, "up_1"), Buffer.from("other user"));
    seedSummary(UID_B, ACT);
  }
  test("120 rows: more, more, done; at most 50 per call; cursor and job id persisted; summaries survive; other user untouched", async () => {
    seedMany(120);
    const r1 = await call();
    expect(r1).toMatchObject({ status: "more", deleted: 50 });
    expect(store.get(SETTINGS)!.streamDeleteCursor).toBe(actId(50));
    expect(store.get(SETTINGS)!.streamDeletePending).toBe(true);
    const job = store.get(SETTINGS)!.streamDeleteJobId;
    expect(job).toMatch(/^job_/);
    const r2 = await call();
    expect(r2).toMatchObject({ status: "more", deleted: 50 });
    expect(store.get(SETTINGS)!.streamDeleteJobId).toBe(job);
    const r3 = await call();
    expect(r3).toMatchObject({ status: "done", deleted: 20 });
    expect(store.get(SETTINGS)!.streamDeleteJobId).toBeUndefined();
    expect(store.get(SETTINGS)!.streamDeletePending).toBeUndefined();
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toEqual([]);
    expect([...store.keys()].filter((k) => k.startsWith(`users/${UID}/activities/`))).toHaveLength(120);
    expect(w.bucket.keys()).toEqual([streamPath(UID_B, ACT, "up_1")]);
    expect(usageOf(UID, "activityDeleteAll")).toBe(1); // only the call that STARTED the job is charged
    const again = await call();
    expect(again).toMatchObject({ status: "done", deleted: 0 });
  });
  test("interrupted job: a storage failure persists progress and the rerun deletes each row's objects exactly once", async () => {
    seedMany(70);
    w.bucket.failOn = (op, p) => (op === "deleteFiles" && p === `streams/${UID}/${actId(30)}/` ? bareErr(500) : null);
    await expect(call()).rejects.toMatchObject({ code: "internal", message: "delete_failed" });
    expect(store.get(SETTINGS)!.streamDeleteCursor).toBe(actId(29));
    expect(rowOf(UID, actId(29))).toBeUndefined();
    expect(rowOf(UID, actId(30))).toBeDefined();
    w.bucket.failOn = null;
    expect(await call()).toMatchObject({ status: "done", deleted: 41 });
    for (let i = 1; i <= 29; i++) expect(w.bucket.deleteFilesCalls.filter((p) => p === `streams/${UID}/${actId(i)}/`)).toHaveLength(1);
  });
  test("object first, then row (a row still exists when its objects go)", async () => {
    seedMany(2);
    const seen: boolean[] = [];
    w.bucket.hook = (phase, op, p) => { if (phase === "before" && op === "deleteFiles" && p.startsWith("streams/")) seen.push(rowOf(UID, actId(1)) !== undefined || rowOf(UID, actId(2)) !== undefined); };
    await call();
    expect(seen[0]).toBe(true);
  });
  test("the time budget stops a call before any row", async () => {
    seedMany(3);
    expect(await call({ budgetMs: 0 })).toMatchObject({ status: "more", deleted: 0 });
    expect(rowOf(UID, actId(1))).toBeDefined();
  });
  test("the scheduled reconciler continues an unfinished job without a caller", async () => {
    seedMany(60);
    await call();
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.bulkDeleteAdvanced).toBe(1);
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toEqual([]);
    expect(store.get(SETTINGS)!.streamDeletePending).toBeUndefined();
  });
  test("fenced and Auth-checked: a fence refuses and gives the charge back; a deleted Auth user is refused", async () => {
    seedMany(3);
    store.set(FENCE, { fenceAt: ts(T0) });
    await expect(call()).rejects.toMatchObject({ code: "failed-precondition", message: "account_deleting" });
    expect(usageOf(UID, "activityDeleteAll")).toBe(0);
    store.delete(FENCE);
    w.auth.users.delete(UID);
    await expect(call()).rejects.toMatchObject({ code: "unauthenticated", message: "account_deleted" });
    expect(rowOf(UID, actId(1))).toBeDefined();
  });
  test("an anonymous caller is refused", async () => {
    seedMany(1);
    await expect(handleDeleteAllActivityStreams(w.deps, UID, "anonymous", lim())).rejects.toMatchObject({ code: "permission-denied" });
  });
});

describe("F72 withdrawn consent (design 9.1: pending rows are aborted by the reconciler; plan F72 says not aborted, a plan error)", () => {
  const withdrawCall = () => SEVEN.find((e) => e.name === "setActivityCloudSettings")!.call(w, { cloudStreams: { granted: false, version: 1 } });
  test("a pending upload of a user who withdrew consent is aborted and its objects deleted", async () => {
    seedReady();
    await stage(w);
    await withdrawCall();
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingAborted).toBe(1);
    expect(w.bucket.keys(`quarantine/${UID}/`)).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("an interrupted GOOD upload is also aborted once consent is withdrawn (nothing is stored after withdrawal)", async () => {
    const { promoted } = await interruptedCommit();
    await withdrawCall();
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingRepaired).toBe(0);
    expect(w.bucket.objects.has(promoted)).toBe(false);
  });
});

describe("F54 third interleaving: tombstone written, object delete failing", () => {
  const del = () => SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT });
  test("the delete reports a bare failure, the tombstone already blocks any commit, and the retry of deleteActivity finishes (no per-activity late job by design F20)", async () => {
    seedReady();
    const s = await stage(w);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("OK");
    const other = validPayload();
    other.kinds.speed.values = [9, 9.5];
    const s2 = await stage(w, other);
    w.bucket.failOn = (op) => (op === "deleteFiles" ? bareErr(500) : null);
    await expect(del()).rejects.toMatchObject({ code: "internal" });
    expect(store.has(`users/${UID}/activity_tombstones/${ACT}`)).toBe(true);
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s2.uploadId }))).not.toBe("OK");
    expect([...store.keys()].filter((k) => k.startsWith("activity_late"))).toEqual([]);
    w.bucket.failOn = null;
    await del();
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
});

describe("F81 consent withdrawal and the bulk job (deleteExisting)", () => {
  const SETTINGS = `users/${UID}/activity_settings/main`;
  const withdraw = (extra: Record<string, unknown> = {}) =>
    SEVEN.find((e) => e.name === "setActivityCloudSettings")!.call(w, { cloudStreams: { granted: false, version: 1, ...extra } });
  async function seedStored(): Promise<void> {
    seedReady();
    const s = await stage(w);
    await commit(w, { activityId: ACT, uploadId: s.uploadId });
  }
  test("a withdrawal that chose the offer starts the job; the scheduled reconciler deletes the streams and keeps the summary", async () => {
    await seedStored();
    await withdraw({ deleteExisting: true });
    expect(store.get(SETTINGS)!.streamDeletePending).toBe(true);
    expect(store.get(SETTINGS)!.streamDeleteJobId).toMatch(/^job_/);
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.bulkDeleteAdvanced).toBe(1);
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(true);
    expect(store.get(SETTINGS)!.streamDeletePending).toBeUndefined();
  });
  test("a withdrawal that did not choose it keeps the stored streams and starts no job", async () => {
    await seedStored();
    await withdraw();
    expect(store.get(SETTINGS)!.streamDeletePending).toBeUndefined();
    expect(store.get(SETTINGS)!.streamDeleteJobId).toBeUndefined();
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.bulkDeleteAdvanced).toBe(0);
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
  });
  test("a running job is kept (same job id) when the withdrawal is repeated with the option", async () => {
    await seedStored();
    store.get(SETTINGS)!.streamDeleteJobId = "job_running";
    store.get(SETTINGS)!.streamDeletePending = true;
    await withdraw({ deleteExisting: true });
    expect(store.get(SETTINGS)!.streamDeleteJobId).toBe("job_running");
  });
});
