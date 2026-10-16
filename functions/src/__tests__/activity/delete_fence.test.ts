/** S02-06a: F20-F23 and F59 deleteActivity, F76 every callable refuses behind the fence, F79 Auth existence, fence.ts. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as admin from "firebase-admin";
import {
  LATE_SWEEP_DELAY_MS, activityAccountStatePath, defaultFenceDeps, writeActivityAccountFence,
} from "../../activity_streams/fence";
import {
  ACT, ACT_2, DAY, MIN, T0, UID, UID_B, createWorld, expectHttpsError, firestoreError, fx, quarantinePath,
  releaseClock, resetAll, rowOf, seedReady, setNow, store, streamPath, ts, usageOf, useClock, validPayload, writes, type World,
} from "./support/fakes";
import { commit, create, outcome, stage } from "./support/flow";
import { SEVEN, prime, type Primed } from "./support/seven";

let w: World;
let p: Primed;
const del = (id: string = ACT, uid = UID) => SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: id }, uid);
const TOMB = `users/${UID}/activity_tombstones/${ACT}`;
const SUMMARY = `users/${UID}/activities/${ACT}`;
const ROW = `users/${UID}/activity_streams/${ACT}`;
const alt = (): any => {
  const q = validPayload();
  q.kinds.speed.values = [9, 9.5];
  return q;
};
const err500 = () => Object.assign(new Error("storage down"), { code: 500 });

beforeEach(async () => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
  p = await prime(w);
});
afterEach(() => releaseClock());

describe("F20 deleteActivity order", () => {
  test("tombstone FIRST, then streams/ and quarantine/ objects, then the index row, then the summary LAST; no late job", async () => {
    await stage(w, undefined, UID, ACT_2).catch(() => undefined);
    const order: string[] = [];
    fx.afterCommit = (paths) => { for (const x of paths) if (!x.includes("/usage/")) order.push(`fs:${x}`); };
    w.bucket.hook = (phase, op, path) => { if (phase === "before" && op === "deleteFiles") order.push(`gcs:${path}`); };
    const keysBefore = new Set(store.keys());
    await del();
    expect(order).toEqual([`fs:${TOMB}`, `gcs:streams/${UID}/${ACT}/`, `gcs:quarantine/${UID}/${ACT}/`, `fs:${ROW}`, `fs:${SUMMARY}`]);
    const added = [...store.keys()].filter((k) => !keysBefore.has(k) && !k.includes("/usage/"));
    expect(added).toEqual([TOMB]); // no per-activity late job document, nothing else
  });
  test("the tombstone carries deletedAt and expireAt = +400 days", async () => {
    await del();
    expect(store.get(TOMB)!.deletedAt.toMillis()).toBe(T0);
    expect(store.get(TOMB)!.expireAt.toMillis()).toBe(T0 + 400 * DAY);
  });
  test("the fence documents and Auth are read before the tombstone is written (a fenced account gets no tombstone)", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(del(), "failed-precondition", "account_deleting");
    expect(store.has(TOMB)).toBe(false);
    expect(store.has(SUMMARY)).toBe(true);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
  });
  test("A10: erasure is not behind the feature flag: with the bucket unset and NO stream row the object step is a no-op and the rest completes", async () => {
    w.bucketOn = false;
    store.delete(ROW);
    expect((await del()).deleted).toBe(true);
    expect(store.has(SUMMARY)).toBe(false);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
  });
  test("A10: with the bucket unset and a stream row (stored or pending) the delete fails delete_failed, keeps the row and the summary, the tombstone stays", async () => {
    for (const state of ["stored", "pending"]) {
      store.delete(TOMB);
      store.set(ROW, { ...store.get(ROW), state });
      w.bucketOn = false;
      await expectHttpsError(del(), "internal", "delete_failed");
      expect(store.has(ROW)).toBe(true);
      expect(store.get(ROW)!.state).toBe(state);
      expect(store.has(SUMMARY)).toBe(true);
      expect(store.has(TOMB)).toBe(true);
      expect(w.bucket.deleteFilesCalls).toEqual([]);
    }
    w.bucketOn = true; // the bucket is back: a rerun completes the cascade
    expect((await del()).deleted).toBe(true);
    expect(store.has(ROW)).toBe(false);
    expect(store.has(SUMMARY)).toBe(false);
  });
});

describe("F21 idempotent, 404", () => {
  test("a second call succeeds, reports no new tombstone and keeps the earliest deletedAt", async () => {
    const first = await del();
    setNow(T0 + 5 * MIN);
    const second = await del();
    expect(first.tombstoneCreated).toBe(true);
    expect(second).toMatchObject({ deleted: true, tombstoneCreated: false });
    expect(store.get(TOMB)!.deletedAt.toMillis()).toBe(T0);
  });
  test("an object already gone (404 from the bucket) is success", async () => {
    w.bucket.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("nf"), { code: 404 }) : undefined);
    expect((await del()).deleted).toBe(true);
    expect(store.has(SUMMARY)).toBe(false);
    expect(store.has(ROW)).toBe(false);
  });
  test("a never-uploaded activity (no row, no objects) deletes cleanly", async () => {
    seedReady(UID, ACT_2);
    expect((await del(ACT_2)).deleted).toBe(true);
    expect(store.has(`users/${UID}/activities/${ACT_2}`)).toBe(false);
  });
});

describe("F22 failure injection after each step, and F59 tombstone-first", () => {
  const orphanFree = () => {
    // The summary may exist while pieces remain, but the summary is NEVER gone while an object or row remains.
    const summaryGone = !store.has(SUMMARY);
    const pieces = store.has(ROW) || w.bucket.keys(`streams/${UID}/${ACT}/`).length > 0;
    expect(summaryGone && pieces).toBe(false);
  };
  test("a storage error on the first prefix: tombstone stays, BOTH prefixes attempted, row and summary kept, bare code, a rerun completes", async () => {
    await stage(w, alt()); // a pending re-upload: a quarantine object too
    w.bucket.failOn = (op, path) => (op === "deleteFiles" && path.startsWith("streams/") ? err500() : undefined);
    const err = await expectHttpsError(del(), "internal", "delete_failed");
    expect(err.message).not.toContain(UID);
    expect(store.has(TOMB)).toBe(true);
    expect(store.has(ROW)).toBe(true);
    expect(store.has(SUMMARY)).toBe(true);
    expect(w.bucket.deleteFilesCalls).toEqual([`streams/${UID}/${ACT}/`, `quarantine/${UID}/${ACT}/`]);
    expect(w.bucket.keys(`quarantine/`)).toEqual([]);
    orphanFree();
    w.bucket.failOn = null;
    expect((await del()).tombstoneCreated).toBe(false);
    expect(store.has(ROW)).toBe(false);
    expect(store.has(SUMMARY)).toBe(false);
    expect(w.bucket.keys()).toEqual([]);
  });
  test("killed after the object delete (row delete fails): summary stays, rerun finishes", async () => {
    fx.failOn = (op, path) => (op === "delete" && path === ROW ? firestoreError("lost", 14) : undefined);
    await expectHttpsError(del(), "internal", "delete_failed");
    expect(w.bucket.keys()).toEqual([]);
    expect(store.has(SUMMARY)).toBe(true);
    orphanFree();
    fx.failOn = null;
    await del();
    expect(store.has(ROW)).toBe(false);
    expect(store.has(SUMMARY)).toBe(false);
  });
  test("killed after the row delete (summary delete fails): rerun finishes", async () => {
    fx.failOn = (op, path) => (op === "delete" && path === SUMMARY ? firestoreError("lost", 14) : undefined);
    await expectHttpsError(del(), "internal", "delete_failed");
    expect(store.has(ROW)).toBe(false);
    expect(store.has(SUMMARY)).toBe(true);
    fx.failOn = null;
    await del();
    expect(store.has(SUMMARY)).toBe(false);
  });
  test("a failing storage delete keeps the tombstone (written first) even though nothing else was deleted", async () => {
    w.bucket.failOn = (op) => (op === "deleteFiles" ? err500() : undefined);
    await expectHttpsError(del(), "internal", "delete_failed");
    expect(writes.some((x) => x.path === TOMB && x.op === "set")).toBe(true);
    expect(store.has(TOMB)).toBe(true);
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
  });
  test("F59: the tombstone refuses create, commit and download for the id, and a replayed create after delete yields nothing", async () => {
    const pending = await stage(w, undefined, UID, ACT_2).catch(() => undefined);
    void pending;
    await del();
    const rows = (): number => [...store.keys()].filter((k) => k.includes("/activity_streams/")).length;
    // The summary was deleted with the activity; a client replay re-creates it (offline queue), the tombstone still wins.
    seedReady();
    const signed = w.bucket.signed.length;
    await expectHttpsError(create(w, { activityId: ACT, bytes: p.bytes, contentSha256: p.sha }), "failed-precondition", "deleted");
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: p.uploadId }), "failed-precondition", "deleted");
    expect(w.bucket.signed.length).toBe(signed);
    expect(rows()).toBe(0);
    expect(w.bucket.keys()).toEqual([]);
    const dl = await SEVEN.find((e) => e.name === "getActivityStreamDownloadUrls")!.call(w, { activityIds: [ACT, `act_${"9".repeat(40)}`] });
    expect(dl.results[0]).toEqual({ activityId: ACT, status: "unavailable", code: "not_found" });
    expect(dl.results[1]).toEqual({ activityId: `act_${"9".repeat(40)}`, status: "unavailable", code: "not_found" });
  });
  test("F59: a pending upload staged before the delete cannot be committed afterwards and leaves no promoted object", async () => {
    const s = await stage(w, alt(), UID, ACT);
    await del();
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:deleted");
    expect(w.bucket.keys(`streams/`)).toEqual([]);
    expect(w.bucket.keys(quarantinePath(UID, ACT, s.uploadId))).toEqual([]);
  });
  test("tombstone expireAt is always set (a tombstone without it never expires)", async () => {
    await del(ACT_2);
    expect(store.get(`users/${UID}/activity_tombstones/${ACT_2}`)!.expireAt).toBeDefined();
  });
});

describe("F23 cross-user delete", () => {
  test("B deleting A's id removes and reveals nothing of A and answers like any unknown id", async () => {
    const a = JSON.stringify([...store.entries()].filter(([k]) => k.includes(UID) && !k.includes("/usage/")));
    const objs = w.bucket.keys();
    const forA = await del(ACT, UID_B);
    const forUnknown = await del(ACT_2, UID_B);
    expect(forA).toEqual(forUnknown);
    expect(JSON.stringify([...store.entries()].filter(([k]) => k.includes(UID) && !k.includes("/usage/")))).toBe(a);
    expect(w.bucket.keys()).toEqual(objs);
    expect(store.has(TOMB)).toBe(false);
    expect(store.has(`users/${UID_B}/activity_tombstones/${ACT}`)).toBe(true);
    expect(w.bucket.deleteFilesCalls.every((x) => x.includes(UID_B) || !x.includes(UID))).toBe(true);
  });
});

/* ------------------------------ F76 / F79 -------------------------------- */

describe("F76 every callable refuses after the Step 2 recursiveDelete", () => {
  function afterRecursiveDelete(): void {
    for (const k of [...store.keys()]) if (k.startsWith(`users/${UID}/`)) store.delete(k);
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0), lateSweepAt: ts(T0 + 15 * MIN) });
  }
  test.each(SEVEN.map((e) => e.name))("%s refuses with a bare code and creates nothing", async (name) => {
    const e = SEVEN.find((x) => x.name === name)!;
    afterRecursiveDelete();
    const keys = [...store.keys()].sort();
    const bucketCalls = w.bucket.totalCalls;
    const err = await expectHttpsError(e.call(w, e.ok(p)), "failed-precondition", "account_deleting");
    expect(err.message).toBe("account_deleting");
    expect([...store.keys()].filter((k) => !k.includes("/usage/")).sort()).toEqual(keys.filter((k) => !k.includes("/usage/")));
    expect(w.bucket.totalCalls).toBe(bucketCalls);
    expect([...store.keys()].some((k) => k.startsWith("debug_sessions/"))).toBe(false);
    // Nothing was charged for the refused call.
    expect(usageOf(UID, e.quotaAction)).toBe(0);
  });
  test("in particular: settings recreates no consent document, delete writes no tombstone, deleteAll starts no job", async () => {
    afterRecursiveDelete();
    await outcome(SEVEN[3].call(w, { cloudStreams: { granted: false, version: 1 } }));
    await outcome(del());
    await outcome(SEVEN[5].call(w, {}));
    expect(store.has(`users/${UID}/activity_settings/main`)).toBe(false);
    expect(store.has(TOMB)).toBe(false);
  });
  test("the accountDeletionRetries marker alone also refuses every callable", async () => {
    store.set(`accountDeletionRetries/${UID}`, { n: 1 });
    for (const e of SEVEN) expect(await outcome(e.call(w, e.ok(p)))).toBe("failed-precondition:account_deleting");
  });
  test("control: with the fence absent and the Auth user present each callable proceeds", async () => {
    for (const e of SEVEN) expect(await outcome(e.call(w, e.ok(p)))).toBe("OK");
  });
  test.each(SEVEN.map((e) => e.name))("%s: a fence written between the transaction's read and its commit makes the call refuse (conflict fake)", async (name) => {
    const e = SEVEN.find((x) => x.name === name)!;
    let fired = false;
    fx.afterTxRead = async (path) => {
      if (!fired && path === `activity_account_state/${UID}`) {
        fired = true;
        store.set(path, { fenceAt: ts(T0) });
      }
    };
    expect(await outcome(e.call(w, e.ok(p)))).toBe("failed-precondition:account_deleting");
    expect(fired).toBe(true);
  });
});

describe("F79 token valid after deleteUser: the Auth-existence check", () => {
  test.each(SEVEN.map((e) => e.name))("%s refuses when Auth reports the user gone and the fence document is ABSENT", async (name) => {
    const e = SEVEN.find((x) => x.name === name)!;
    w.auth.users.delete(UID);
    expect(store.has(`activity_account_state/${UID}`)).toBe(false);
    const err = await expectHttpsError(e.call(w, e.ok(p)), "unauthenticated", "account_deleted");
    expect(err.message).toBe("account_deleted");
  });
  test.each(SEVEN.map((e) => e.name))("%s: a transient Auth lookup error fails closed with a bare internal code, never success and never 'deleted'", async (name) => {
    const e = SEVEN.find((x) => x.name === name)!;
    w.auth.lookupError = Object.assign(new Error(`transient for ${UID}`), { code: "auth/internal-error" });
    const o = await outcome(e.call(w, e.ok(p)));
    expect(o).toMatch(/^internal:[a-z_]+$/);
    expect(o).not.toContain("account_deleted");
    expect(o).not.toContain(UID);
  });
  test("the check runs INSIDE the transaction: the user vanishing after the fence read still refuses (create)", async () => {
    fx.afterTxRead = async (path) => { if (path === `accountDeletionRetries/${UID}`) w.auth.users.delete(UID); };
    expect(await outcome(create(w, { activityId: ACT, bytes: p.bytes, contentSha256: "c".repeat(64) }))).toBe("unauthenticated:account_deleted");
  });
  test("the two guards are independent: fence only refuses, Auth only refuses", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    expect(w.auth.users.has(UID)).toBe(true);
    expect(await outcome(create(w, { activityId: ACT, bytes: p.bytes, contentSha256: "c".repeat(64) }))).toBe("failed-precondition:account_deleting");
    store.delete(`activity_account_state/${UID}`);
    w.auth.users.delete(UID);
    expect(await outcome(create(w, { activityId: ACT, bytes: p.bytes, contentSha256: "c".repeat(64) }))).toBe("unauthenticated:account_deleted");
  });
  describe("the default Auth seam", () => {
    const auth = admin.auth as unknown as jest.Mock;
    test("user-not-found is false, found is true, any other error is rethrown", async () => {
      auth.mockReturnValue({ getUser: jest.fn().mockResolvedValue({}) });
      await expect(defaultFenceDeps.authUserExists(UID)).resolves.toBe(true);
      auth.mockReturnValue({ getUser: jest.fn().mockRejectedValue({ code: "auth/user-not-found" }) });
      await expect(defaultFenceDeps.authUserExists(UID)).resolves.toBe(false);
      const boom = { code: "auth/internal-error" };
      auth.mockReturnValue({ getUser: jest.fn().mockRejectedValue(boom) });
      await expect(defaultFenceDeps.authUserExists(UID)).rejects.toBe(boom);
    });
  });
});

describe("fence.ts writeActivityAccountFence (design 6.1 step 1)", () => {
  test("creates fenceAt and lateSweepAt = +15 minutes and keeps the EARLIEST values on a retry", async () => {
    const path = activityAccountStatePath(UID_B);
    expect(await writeActivityAccountFence(w.deps, UID_B)).toBe(true);
    expect(store.get(path)!.fenceAt.toMillis()).toBe(T0);
    expect(store.get(path)!.lateSweepAt.toMillis()).toBe(T0 + LATE_SWEEP_DELAY_MS);
    expect(LATE_SWEEP_DELAY_MS).toBe(15 * MIN);
    expect(store.get(path)!.touchedAt.toMillis()).toBe(T0); // A1: new document, touchedAt = fenceAt
    setNow(T0 + HOUR_MS);
    expect(await writeActivityAccountFence(w.deps, UID_B)).toBe(false);
    expect(store.get(path)!.fenceAt.toMillis()).toBe(T0);
    expect(store.get(path)!.lateSweepAt.toMillis()).toBe(T0 + LATE_SWEEP_DELAY_MS);
    expect(store.get(path)!.touchedAt.toMillis()).toBe(T0 + HOUR_MS); // A1: only the heartbeat moves
    setNow(T0 + 2 * HOUR_MS);
    await writeActivityAccountFence(w.deps, UID_B);
    expect(store.get(path)!.touchedAt.toMillis()).toBe(T0 + 2 * HOUR_MS); // every call
    expect(store.get(path)!.fenceAt.toMillis()).toBe(T0);
  });
  test("a Firestore failure surfaces (deleteAccount must abort before sweeping)", async () => {
    fx.failOn = (op, path) => (op === "commit" && path.includes("activity_account_state") ? firestoreError("x", 14) : undefined);
    await expect(writeActivityAccountFence(w.deps, UID_B)).rejects.toBeDefined();
    expect(store.has(activityAccountStatePath(UID_B))).toBe(false);
  });
  test("path helpers", () => {
    expect(activityAccountStatePath("u1")).toBe("activity_account_state/u1");
    void streamPath;
    void rowOf;
  });
});
const HOUR_MS = 60 * MIN;
