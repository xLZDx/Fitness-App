/**
 * S02 remediation batch A, epic 8a: A2 (reconciler deadline), A3 (bulk-delete fairness and age signal),
 * A14 (unrecognised row ids), A15 (silent-skip counters and scan-cycle progress), A4 (abort path re-read).
 * Oracles: S02_REMEDIATION_A_TEST_NOTES.md and design 6.1 / 9.1.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import { bulkDeleteContinuationPass, handleDeleteAllActivityStreams } from "../../activity_streams/delete_all_streams";
import {
  ACTIVITY_RECONCILE_EVENT, DEFAULT_RECONCILE_LIMITS, RECONCILE_STATE_PATH, newReconcileResult, reconcilePendingRow,
  runActivityReconcile, type ReconcileDeps,
} from "../../activity_streams/reconcile";
import {
  ACT, ACT_2, DAY, HOUR, MIN, T0, UID, createWorld, quarantinePath, releaseClock, resetAll,
  rowOf, seedReady, seedSummary, setNow, store, streamPath, ts, uploadIdN, useClock, validPayload, writes, type World,
} from "./support/fakes";
import { commit, fullUpload, stage } from "./support/flow";

let w: World;
const recDeps = (): ReconcileDeps => ({ ...w.deps, listing: () => w.bucket });
const settingsOf = (u: string): any => store.get(`users/${u}/activity_settings/main`);
const SET = (u: string) => `users/${u}/activity_settings/main`;
const ACT_3 = `act_${"c".repeat(40)}`;
const user = (n: number): string => `bulk_${n.toString().padStart(3, "0")}`;
const pendingJob = (u: string, extra: Record<string, unknown> = {}): void => {
  w.auth.users.add(u);
  store.set(SET(u), { streamDeletePending: true, streamDeleteJobId: `job_${u}`, ...extra });
};
const logCalls = (fn: unknown): string[] => (fn as jest.Mock).mock.calls.map((c) => JSON.stringify(c));

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  for (const l of [logger.info, logger.warn, logger.error]) (l as jest.Mock).mockClear();
});
afterEach(() => releaseClock());

describe("A2 reconciler continuation pass deadline", () => {
  test("deadline already passed: no user advanced, no write to any job, budgetExhausted, and the run still logs run-complete", async () => {
    pendingJob(user(1));
    pendingJob(user(2));
    const n = writes.length;
    const r = await runActivityReconcile(recDeps(), { ...DEFAULT_RECONCILE_LIMITS, runBudgetMs: 0 });
    expect(r.bulkDeleteAdvanced).toBe(0);
    expect(r.budgetExhausted).toBe(true);
    expect(writes.slice(n).filter((x) => x.path.startsWith("users/"))).toEqual([]);
    expect(settingsOf(user(1)).streamDeleteAttempts).toBeUndefined();
    expect(logCalls(logger.info).some((c) => c.includes(ACTIVITY_RECONCILE_EVENT) && c.includes("run-complete") && c.includes("\"budgetExhausted\":true"))).toBe(true);
  });
  test("called directly with a deadline in the past: nothing advanced; called with two arguments (no deadline) it still works", async () => {
    pendingJob(user(1));
    const res = newReconcileResult();
    await bulkDeleteContinuationPass(recDeps(), res, Date.now() - 1);
    expect(res).toMatchObject({ bulkDeleteAdvanced: 0, budgetExhausted: true });
    expect(settingsOf(user(1)).streamDeletePending).toBe(true);
    const res2 = newReconcileResult();
    await bulkDeleteContinuationPass(recDeps(), res2);
    expect(res2.bulkDeleteAdvanced).toBe(1);
    expect(settingsOf(user(1)).streamDeletePending).toBeUndefined();
  });
  test("the page budget never exceeds the remaining run time: 1000 ms left and 600 ms per row stops after two of three rows", async () => {
    pendingJob(user(1));
    for (const id of [ACT, ACT_2, ACT_3]) store.set(`users/${user(1)}/activity_streams/${id}`, { state: "stored" });
    w.bucket.hook = (phase, op) => { if (phase === "before" && op === "deleteFiles") setNow(Date.now() + 300); };
    const res = newReconcileResult();
    await bulkDeleteContinuationPass(recDeps(), res, Date.now() + 1000);
    const left = [ACT, ACT_2, ACT_3].filter((id) => store.has(`users/${user(1)}/activity_streams/${id}`));
    expect(left).toEqual([ACT_3]);
    expect(settingsOf(user(1)).streamDeletePending).toBe(true);
    // control: with a distant deadline the same job removes all three rows in one page
    w.bucket.hook = null;
    await bulkDeleteContinuationPass(recDeps(), newReconcileResult(), Date.now() + 10 * HOUR);
    expect(store.has(`users/${user(1)}/activity_streams/${ACT_3}`)).toBe(false);
  });
});

describe("A3 bulk-delete fairness, stamps and age signal", () => {
  test("more than 20 pending jobs: the 20 with a missing attempt stamp go first, the 5 recently attempted ones wait", async () => {
    for (let i = 0; i < 5; i++) pendingJob(user(i), { streamDeleteAttemptAt: ts(T0 - 10 * MIN), streamDeleteAttempts: 1 });
    for (let i = 5; i < 25; i++) pendingJob(user(i));
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.bulkDeleteAdvanced).toBe(20);
    for (let i = 5; i < 25; i++) expect(settingsOf(user(i)).streamDeletePending).toBeUndefined();
    for (let i = 0; i < 5; i++) {
      expect(settingsOf(user(i)).streamDeletePending).toBe(true);
      expect(settingsOf(user(i)).streamDeleteAttempts).toBe(1);
    }
  });
  test("stamped jobs go in order of the oldest streamDeleteAttemptAt", async () => {
    for (let i = 0; i < 22; i++) pendingJob(user(i), { streamDeleteAttemptAt: ts(T0 - (100 - i) * MIN), streamDeleteAttempts: 1 });
    // user(0) has the oldest stamp, user(21) the newest
    await runActivityReconcile(recDeps(), undefined);
    for (let i = 0; i < 20; i++) expect(settingsOf(user(i)).streamDeletePending).toBeUndefined();
    expect(settingsOf(user(20)).streamDeletePending).toBe(true);
    expect(settingsOf(user(21)).streamDeletePending).toBe(true);
  });
  test("a permanently failing job is stamped (+1, attemptAt now) and the next run advances a different job first", async () => {
    const F = "bulk_fail";
    pendingJob(F, { streamDeleteAttemptAt: ts(T0 - 10 * HOUR), streamDeleteAttempts: 1 });
    store.set(`users/${F}/activity_streams/${ACT}`, { state: "stored" });
    w.bucket.failOn = (op, p) => (op === "deleteFiles" && p.startsWith(`streams/${F}/`) ? Object.assign(new Error("x"), { code: 500 }) : null);
    for (let i = 0; i < 40; i++) pendingJob(user(i), { streamDeleteAttemptAt: ts(T0 - 5 * HOUR) });
    const r1 = await runActivityReconcile(recDeps(), undefined);
    expect(r1.failures).toBe(1);
    expect(settingsOf(F).streamDeleteAttempts).toBe(2);
    expect(settingsOf(F).streamDeleteAttemptAt.toMillis()).toBe(T0);
    expect(settingsOf(F).streamDeletePending).toBe(true);
    const pendingAfter1 = [...Array(40).keys()].filter((i) => settingsOf(user(i)).streamDeletePending === true).length;
    expect(pendingAfter1).toBe(40 - 19); // the failing job used one of the 20 slots
    setNow(T0 + MIN);
    await runActivityReconcile(recDeps(), undefined);
    // run 2: the 21 healthy leftovers outrank the freshly stamped failing job; it is not touched again
    expect(settingsOf(F).streamDeleteAttempts).toBe(2);
    const pendingAfter2 = [...Array(40).keys()].filter((i) => settingsOf(user(i)).streamDeletePending === true).length;
    expect(pendingAfter2).toBe(1);
  });
  test("a fenced user's job is stamped too (so it cannot block the line) and is not advanced", async () => {
    pendingJob(user(1), { streamDeleteAttemptAt: ts(T0 - HOUR) });
    store.set(`activity_account_state/${user(1)}`, { fenceAt: ts(T0) });
    store.set(`users/${user(1)}/activity_streams/${ACT}`, { state: "stored" });
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.bulkDeleteAdvanced).toBe(0);
    expect(r.failures).toBe(0);
    expect(settingsOf(user(1)).streamDeleteAttempts).toBe(1);
    expect(settingsOf(user(1)).streamDeleteAttemptAt.toMillis()).toBe(T0);
    expect(store.has(`users/${user(1)}/activity_streams/${ACT}`)).toBe(true);
  });
  test("a job start sets streamDeleteStartedAt and clears the attempt fields; done clears all three", async () => {
    seedReady();
    store.set(SET(UID), { ...settingsOf(UID), streamDeleteAttemptAt: ts(T0 - DAY), streamDeleteAttempts: 4 });
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored" });
    w.bucket.failOn = (op) => (op === "deleteFiles" ? Object.assign(new Error("x"), { code: 500 }) : null);
    await expect(handleDeleteAllActivityStreams(w.deps, UID, "password")).rejects.toMatchObject({ message: "delete_failed" });
    expect(settingsOf(UID).streamDeleteStartedAt.toMillis()).toBe(T0);
    expect(settingsOf(UID).streamDeleteAttemptAt).toBeUndefined();
    expect(settingsOf(UID).streamDeleteAttempts).toBeUndefined();
    expect(settingsOf(UID).streamDeletePending).toBe(true);
    w.bucket.failOn = null;
    setNow(T0 + MIN);
    // a stamp from the reconciler, then the job completes
    store.set(SET(UID), { ...settingsOf(UID), streamDeleteAttemptAt: ts(T0), streamDeleteAttempts: 1 });
    expect((await handleDeleteAllActivityStreams(w.deps, UID, "password")).status).toBe("done");
    for (const f of ["streamDeleteStartedAt", "streamDeleteAttemptAt", "streamDeleteAttempts", "streamDeleteJobId", "streamDeletePending"]) {
      expect(settingsOf(UID)[f]).toBeUndefined();
    }
  });
  test("oldestBulkDeleteAgeMs is now minus the oldest streamDeleteStartedAt", async () => {
    pendingJob(user(1), { streamDeleteStartedAt: ts(T0 - 3 * HOUR) });
    pendingJob(user(2), { streamDeleteStartedAt: ts(T0 - HOUR) });
    pendingJob(user(3));
    const r = await runActivityReconcile(recDeps(), undefined);
    expect(r.oldestBulkDeleteAgeMs).toBe(3 * HOUR);
    expect(logCalls(logger.info).some((c) => c.includes("run-complete") && c.includes(`"oldestBulkDeleteAgeMs":${3 * HOUR}`))).toBe(true);
  });
  test("no pending job: oldestBulkDeleteAgeMs is 0", async () => {
    expect((await runActivityReconcile(recDeps(), undefined)).oldestBulkDeleteAgeMs).toBe(0);
  });
});

describe("A14 a non-activity row id under activity_streams", () => {
  test("deleted directly by the bulk delete, no object path built, job done, warn log carries 'unrecognised'", async () => {
    seedReady();
    await fullUpload(w);
    store.set(`users/${UID}/activity_streams/weird id!`, { state: "stored" });
    store.set(`users/${UID}/activity_streams/not_an_activity`, { state: "pending" });
    w.bucket.deleteFilesCalls.length = 0;
    const res = await handleDeleteAllActivityStreams(w.deps, UID, "password");
    expect(res.status).toBe("done");
    expect(res.deleted).toBe(1); // only the recognised row is counted
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toEqual([]);
    expect(w.bucket.deleteFilesCalls.every((p) => p.includes(`/${ACT}/`))).toBe(true);
    expect(w.bucket.deleteFilesCalls.length).toBe(2); // streams/ and quarantine/ of the ONE real activity
    expect(logCalls(logger.warn).some((c) => c.includes("unrecognised"))).toBe(true);
    expect(settingsOf(UID).streamDeletePending).toBeUndefined();
  });
});

describe("A15 silent-skip counters and scan-cycle progress", () => {
  test("previous-object-delete-failed: the repair is still 'repaired', the failed previous delete counts as a silent skip", async () => {
    seedReady();
    const first = await fullUpload(w);
    const prev = streamPath(UID, ACT, first.uploadId);
    const alt = validPayload();
    alt.kinds.speed.values = [9, 9.5];
    const s = await stage(w, alt);
    w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "save" && path.startsWith("streams/")) throw new Error("killed after promotion"); };
    await commit(w, { activityId: ACT, uploadId: s.uploadId }).catch(() => undefined);
    w.bucket.hook = null;
    w.bucket.failOn = (op, p) => (op === "delete" && p === prev ? Object.assign(new Error("x"), { code: 500 }) : null);
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingRepaired).toBe(1);
    expect(r.silentSkips).toBe(1);
    expect(rowOf(UID, ACT).state).toBe("stored");
    expect(rowOf(UID, ACT).objectPath).toBe(streamPath(UID, ACT, s.uploadId));
    expect(logCalls(logger.warn).some((c) => c.includes("previous-object-delete-failed"))).toBe(true);
  });
  test.each([
    ["missing objectPath", {}],
    ["objectPath outside the activity prefix", { objectPath: `streams/other/${ACT}/x.json.gz` }],
  ])("a stored row with %s increments silentSkips and is left in place", async (_n, extra) => {
    seedSummary(UID, ACT);
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored", expiresAt: ts(T0 + DAY), ...extra });
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.silentSkips).toBe(1);
    expect(r.storedObjectMissing).toBe(0);
    expect(rowOf(UID, ACT).state).toBe("stored");
  });
  test("a healthy stored row adds no silent skip", async () => {
    seedReady();
    await fullUpload(w);
    expect((await runActivityReconcile(recDeps(), undefined, [])).silentSkips).toBe(0);
  });
  test("an object with an unparseable timeCreated increments silentSkips and is not deleted", async () => {
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(1)), Buffer.from("x"));
    const orig = w.bucket.getFiles.bind(w.bucket);
    w.bucket.getFiles = async (o: any) => {
      const [files, next] = await orig(o);
      for (const f of files) f.metadata = { timeCreated: "not-a-date" };
      return [files, next];
    };
    setNow(T0 + 2 * DAY);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.silentSkips).toBe(1);
    expect(r.orphansDeleted).toBe(0);
    expect(w.bucket.keys("quarantine/")).toHaveLength(1);
  });
  test("scan cycle: the start is set while the cursor walks on, kept across runs, deleted when the cycle ends; the age is reported", async () => {
    for (let i = 1; i <= 3; i++) w.bucket.put(quarantinePath(UID, ACT, uploadIdN(i)), Buffer.from("x"));
    const limits = { ...DEFAULT_RECONCILE_LIMITS, objectPage: 1, objectPagesPerRun: 1 };
    const state = (): any => store.get(RECONCILE_STATE_PATH) ?? {};
    const r1 = await runActivityReconcile(recDeps(), limits, []);
    expect(state().quarantineCursor).toBeDefined();
    expect(state().quarantineCursorCycleStartedAt).toBe(T0);
    expect(r1.oldestScanCycleAgeMs).toBe(0);
    setNow(T0 + 5 * MIN);
    const r2 = await runActivityReconcile(recDeps(), limits, []);
    expect(state().quarantineCursorCycleStartedAt).toBe(T0); // kept, not restarted
    expect(r2.oldestScanCycleAgeMs).toBe(5 * MIN);
    setNow(T0 + 10 * MIN);
    const r3 = await runActivityReconcile(recDeps(), limits, []);
    expect(r3.oldestScanCycleAgeMs).toBe(10 * MIN);
    expect(logCalls(logger.info).some((c) => c.includes(`"oldestScanCycleAgeMs":${10 * MIN}`))).toBe(true);
    // the walk ends (no more pages): both cursor and cycle start are deleted
    let guard = 0;
    while (state().quarantineCursor !== undefined && guard++ < 6) {
      setNow(Date.now() + MIN);
      await runActivityReconcile(recDeps(), limits, []);
    }
    expect(state().quarantineCursor).toBeUndefined();
    expect(state().quarantineCursorCycleStartedAt).toBeUndefined();
    // the next cycle starts fresh
    setNow(Date.now() + HOUR);
    await runActivityReconcile(recDeps(), limits, []);
    if (state().quarantineCursor !== undefined) expect(state().quarantineCursorCycleStartedAt).toBe(Date.now());
  });
  test("the streams/ walk has its own cycle start, independent of quarantine/", async () => {
    for (let i = 1; i <= 3; i++) w.bucket.put(streamPath(UID, ACT, uploadIdN(i)), Buffer.from("x"));
    const limits = { ...DEFAULT_RECONCILE_LIMITS, objectPage: 1, objectPagesPerRun: 1 };
    await runActivityReconcile(recDeps(), limits, []);
    const st = store.get(RECONCILE_STATE_PATH)!;
    expect(st.streamsCursorCycleStartedAt).toBe(T0);
    expect(st.quarantineCursorCycleStartedAt).toBeUndefined();
  });
});

describe("A4 reconcilePendingRow abort path re-reads the row", () => {
  async function pendingRow(): Promise<{ uploadId: string }> {
    seedReady();
    const s = await stage(w);
    // a pending row whose promoted object is missing/bad: the abort path
    store.set(`users/${UID}/activity_streams/${ACT}`, { ...rowOf(UID, ACT), pendingSince: ts(T0) });
    return { uploadId: s.uploadId };
  }
  test("unchanged row: still aborts, deleting this upload's objects and the never-stored row", async () => {
    await pendingRow();
    setNow(T0 + 61 * MIN);
    expect(await reconcilePendingRow(recDeps(), w.bucket, UID, ACT)).toBe("aborted");
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("the row's upload id changes between the first read and the abort: 'kept', nothing deleted", async () => {
    const { uploadId } = await pendingRow();
    const other = uploadIdN(99);
    w.bucket.put(quarantinePath(UID, ACT, other), Buffer.from("new upload of the replacing commit"));
    let swapped = false;
    w.bucket.hook = (phase, op) => {
      if (phase === "before" && op === "download" && !swapped) {
        swapped = true; // a new create replaced the pending upload after the reconciler read the row
        const row = rowOf(UID, ACT);
        for (const k of Object.keys(row)) if (row[k] === uploadId) row[k] = other;
        expect(row.pendingUploadId === other || row.uploadId === other).toBe(true);
      }
    };
    const before = w.bucket.keys();
    expect(await reconcilePendingRow(recDeps(), w.bucket, UID, ACT)).toBe("kept");
    expect(swapped).toBe(true);
    expect(w.bucket.keys()).toEqual(before);
    expect(rowOf(UID, ACT)).toBeDefined();
  });
  test("intendedStoredSha256 changes between the first read and the abort: 'kept', nothing deleted", async () => {
    await pendingRow();
    let swapped = false;
    w.bucket.hook = (phase, op) => {
      if (phase === "before" && op === "download" && !swapped) {
        swapped = true;
        rowOf(UID, ACT).intendedStoredSha256 = "f".repeat(64); // a commit recorded its intent meanwhile
      }
    };
    const before = w.bucket.keys();
    expect(await reconcilePendingRow(recDeps(), w.bucket, UID, ACT)).toBe("kept");
    expect(swapped).toBe(true);
    expect(w.bucket.keys()).toEqual(before);
    expect(rowOf(UID, ACT)).toBeDefined();
  });
});
