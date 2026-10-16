/**
 * S02 remediation batch A, epic 8a: A1 (abandoned fence of a live account), A5 (usage counters in the
 * final recursive delete), A10 (late sweep with an unset bucket). Oracles: S02_REMEDIATION_A_TEST_NOTES.md
 * and design 6.1, not the code under test.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import { writeActivityAccountFence } from "../../activity_streams/fence";
import {
  ACTIVITY_USER_COLLECTIONS, LIVE_FENCE_CLEARED_SLUG, runActivityLateSweep, type LateSweepDeps,
} from "../../activity_streams/late_sweep";
import {
  ACT, ACT_2, HOUR, MIN, T0, UID, createWorld, loggedText, releaseClock, resetAll, seedSummary, setNow, store,
  streamPath, ts, useClock, writes, type World,
} from "./support/fakes";

let w: World;
const FENCE = `activity_account_state/${UID}`;
const RETRIES = `accountDeletionRetries/${UID}`;
const lateDeps = (): LateSweepDeps => ({
  firestore: w.deps.firestore, authUserExists: w.deps.authUserExists, nowMs: w.deps.nowMs, bucket: w.deps.bucket,
});
const LATE_AT = T0 + 15 * MIN;

async function seedFence(atMs = T0): Promise<void> {
  setNow(atMs);
  await writeActivityAccountFence(lateDeps(), UID);
}
function seedLiveData(): void {
  seedSummary(UID, ACT);
  store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored" });
  store.set(`users/${UID}/activity_settings/main`, { settingsGeneration: 1 });
  store.set(`users/${UID}/usage/activity_x`, { count: 3 });
  w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("precious gps"));
}
const userDocs = (): string[] => [...store.keys()].filter((k) => k.startsWith("users/")).sort();

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  (logger.warn as jest.Mock).mockClear();
  (logger.error as jest.Mock).mockClear();
});
afterEach(() => releaseClock());

describe("A1 late sweep of a LIVE account: abandoned fence cleared by compare-and-delete, never any data", () => {
  test("Auth exists, no retries record, touchedAt older than 24 h: fence deleted, clearedLive 1, nothing else touched, slug logged", async () => {
    await seedFence();
    seedLiveData();
    const docsBefore = userDocs();
    const n = writes.length;
    setNow(T0 + 24 * HOUR + MIN);
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ clearedLive: 1, skippedLive: 1, swept: 0, removed: 0, failures: 0 });
    expect(store.has(FENCE)).toBe(false);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, "up_1")]);
    expect(userDocs()).toEqual(docsBefore);
    expect(writes.slice(n).filter((x) => x.path.startsWith("users/"))).toEqual([]);
    expect(writes.slice(n).map((x) => `${x.op}:${x.path}`)).toEqual([`delete:${FENCE}`]);
    expect(LIVE_FENCE_CLEARED_SLUG).toBe("fence_cleared_live_account");
    expect(loggedText(logger)).toContain("fence_cleared_live_account");
    expect(loggedText(logger)).not.toContain(UID);
  });

  test("boundary: touchedAt exactly 24 h old is kept (strictly older is required), 24 h + 1 ms is cleared", async () => {
    await seedFence();
    setNow(T0 + 24 * HOUR);
    expect(await runActivityLateSweep(lateDeps())).toMatchObject({ clearedLive: 0, skippedLive: 1 });
    expect(store.has(FENCE)).toBe(true);
    setNow(T0 + 24 * HOUR + 1);
    expect(await runActivityLateSweep(lateDeps())).toMatchObject({ clearedLive: 1 });
    expect(store.has(FENCE)).toBe(false);
  });

  test("touchedAt younger than 24 h: nothing is deleted, the job stays armed", async () => {
    await seedFence();
    seedLiveData();
    setNow(T0 + 23 * HOUR);
    const n = writes.length;
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ clearedLive: 0, skippedLive: 1, swept: 0, stuck: 0 });
    expect(store.has(FENCE)).toBe(true);
    expect(writes.length).toBe(n);
  });

  test("an accountDeletionRetries record exists: the fence is NOT deleted, the job is stuck with oldestStuckAgeMs > 24 h", async () => {
    await seedFence();
    seedLiveData();
    store.set(RETRIES, { attempts: 2 });
    setNow(T0 + 25 * HOUR);
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ clearedLive: 0, skippedLive: 1, stuck: 1, swept: 0 });
    expect(r.oldestStuckAgeMs).toBe(25 * HOUR);
    expect(r.oldestStuckAgeMs).toBeGreaterThan(24 * HOUR);
    expect(store.has(FENCE)).toBe(true);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
    expect(store.has(RETRIES)).toBe(true);
    // the run-complete entry is error level because of the stuck job (signal for the alert)
    const errors = (logger.error as jest.Mock).mock.calls.map((c) => JSON.stringify(c));
    expect(errors.some((e) => e.includes("run-complete") && e.includes("\"stuck\":1"))).toBe(true);
  });

  test("a retried deleteAccount refreshes touchedAt: the fence survives a run that would otherwise have cleared it", async () => {
    await seedFence();
    setNow(T0 + 23 * HOUR);
    await writeActivityAccountFence(lateDeps(), UID); // the retry (Step 1c) refreshes the heartbeat
    setNow(T0 + 25 * HOUR); // 25 h after fenceAt, but only 2 h after the heartbeat
    const r = await runActivityLateSweep(lateDeps());
    expect(r.clearedLive).toBe(0);
    expect(store.has(FENCE)).toBe(true);
    setNow(T0 + 23 * HOUR + 24 * HOUR + MIN);
    expect((await runActivityLateSweep(lateDeps())).clearedLive).toBe(1);
    expect(store.has(FENCE)).toBe(false);
  });

  test("retry race: touchedAt is refreshed between the job read and the transaction: compare-and-delete deletes nothing", async () => {
    await seedFence();
    setNow(T0 + 25 * HOUR);
    const deps = lateDeps();
    let bumped = false;
    deps.authUserExists = async (uid) => {
      if (!bumped) {
        bumped = true; // the retried deleteAccount lands after the due-query read, before the clearing transaction
        store.get(FENCE)!.touchedAt = ts(T0 + 25 * HOUR - MIN);
      }
      return w.auth.exists(uid);
    };
    const r = await runActivityLateSweep(deps);
    expect(bumped).toBe(true);
    expect(r.clearedLive).toBe(0);
    expect(store.has(FENCE)).toBe(true);
    expect(store.get(FENCE)!.touchedAt.toMillis()).toBe(T0 + 25 * HOUR - MIN);
  });

  test("retry race on the intent record: the retries record appears inside the transaction window: nothing is deleted", async () => {
    await seedFence();
    setNow(T0 + 25 * HOUR);
    const deps = lateDeps();
    deps.authUserExists = async (uid) => {
      store.set(RETRIES, { attempts: 1 });
      return w.auth.exists(uid);
    };
    const r = await runActivityLateSweep(deps);
    expect(r.clearedLive).toBe(0);
    expect(r.stuck).toBe(1);
    expect(store.has(FENCE)).toBe(true);
  });

  test("a failing Auth lookup fails closed: nothing is deleted even for a stale fence", async () => {
    await seedFence();
    seedLiveData();
    w.auth.lookupError = Object.assign(new Error("auth down"), { code: "auth/internal-error" });
    setNow(T0 + 30 * HOUR);
    const docsBefore = userDocs();
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ failures: 1, clearedLive: 0, swept: 0 });
    expect(store.has(FENCE)).toBe(true);
    expect(userDocs()).toEqual(docsBefore);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
  });

  test("a fence written before touchedAt existed falls back to fenceAt for the 24 h test", async () => {
    store.set(FENCE, { fenceAt: ts(T0 - 25 * HOUR), lateSweepAt: ts(T0 - 25 * HOUR + 15 * MIN) });
    seedLiveData();
    const r = await runActivityLateSweep(lateDeps());
    expect(r.clearedLive).toBe(1);
    expect(store.has(FENCE)).toBe(false);
    store.set(FENCE, { fenceAt: ts(T0 - 23 * HOUR), lateSweepAt: ts(T0 - 23 * HOUR + 15 * MIN) });
    expect((await runActivityLateSweep(lateDeps())).clearedLive).toBe(0);
    expect(store.has(FENCE)).toBe(true);
  });

  test("never erases data while Auth exists: a stale fence of a live account with data keeps every document and object over many runs", async () => {
    await seedFence();
    seedLiveData();
    const docsBefore = userDocs();
    for (const at of [LATE_AT, T0 + 5 * HOUR, T0 + 25 * HOUR, T0 + 50 * HOUR]) {
      setNow(at);
      await runActivityLateSweep(lateDeps());
    }
    expect(userDocs()).toEqual(docsBefore);
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, "up_1")]);
    expect(w.bucket.deleteFilesCalls).toEqual([]);
  });

  test("a done job (Auth gone) is not treated as a live account: normal fence removal still applies", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    setNow(LATE_AT);
    expect((await runActivityLateSweep(lateDeps())).swept).toBe(1);
    setNow(LATE_AT + 71 * MIN);
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ removed: 1, clearedLive: 0, skippedLive: 0 });
  });
});

describe("A5 the final recursive delete also removes users/{uid}/usage/*", () => {
  test("ACTIVITY_USER_COLLECTIONS has exactly five entries, usage last", () => {
    expect([...ACTIVITY_USER_COLLECTIONS]).toEqual(["activities", "activity_streams", "activity_settings", "activity_tombstones", "usage"]);
  });
  test("late sweep with Auth gone removes the usage counters (a call racing the deletion recreated them) and spares other documents", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    seedLiveData();
    store.set(`users/${UID}/usage/activity_y`, { count: 1 });
    store.set(`users/${UID}/profile/main`, { keep: true });
    setNow(LATE_AT);
    expect((await runActivityLateSweep(lateDeps())).swept).toBe(1);
    expect([...store.keys()].filter((k) => k.startsWith(`users/${UID}/usage/`))).toEqual([]);
    expect(store.has(`users/${UID}/profile/main`)).toBe(true);
  });
});

describe("A10 late sweep with an unset bucket", () => {
  test("a row under activity_streams: lastErrorCode bucket_unset, job not done, rows and fence kept, error-level log", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    seedSummary(UID, ACT);
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored" });
    store.set(`users/${UID}/activity_streams/${ACT_2}`, { state: "pending" });
    w.bucketOn = false;
    setNow(LATE_AT);
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ swept: 0, failures: 1 });
    const fence = store.get(FENCE)!;
    expect(fence.lastErrorCode).toBe("bucket_unset");
    expect(fence.lateSweepDone).toBeUndefined();
    expect(fence.lateSweepAttempts).toBe(1);
    expect(store.has(`users/${UID}/activity_streams/${ACT}`)).toBe(true);
    expect(store.has(`users/${UID}/activity_streams/${ACT_2}`)).toBe(true);
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(true); // the final recursive delete was skipped
    expect((logger.error as jest.Mock).mock.calls.length).toBeGreaterThan(0);
    // repaired bucket: the same job completes
    w.bucketOn = true;
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("x"));
    setNow(LATE_AT + 5 * MIN);
    expect((await runActivityLateSweep(lateDeps())).swept).toBe(1);
    expect(w.bucket.keys()).toEqual([]);
    expect(store.has(`users/${UID}/activity_streams/${ACT}`)).toBe(false);
    expect(store.get(FENCE)!.lastErrorCode).toBeUndefined();
  });
  test("with no rows the job completes as before (unset bucket is a no-op)", async () => {
    await seedFence();
    w.auth.users.delete(UID);
    seedSummary(UID, ACT);
    w.bucketOn = false;
    setNow(LATE_AT);
    const r = await runActivityLateSweep(lateDeps());
    expect(r).toMatchObject({ swept: 1, failures: 0 });
    expect(store.get(FENCE)!.lateSweepDone).toBeDefined();
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(false);
  });
});
