/**
 * F71: the ten operations signals of design 6.3, each forced by its stated failure and
 * observed in the structured log / run result; every signal carries no uid, id or path.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import { ACTIVITY_COMMIT_EVENT } from "../../activity_streams/commit_stream";
import { runActivityLateSweep, type LateSweepDeps } from "../../activity_streams/late_sweep";
import { runActivityStreamPurge } from "../../activity_streams/purge";
import { runActivityReconcile } from "../../activity_streams/reconcile";
import { DEFAULT_RETENTION_LIMITS, type RetentionDeps } from "../../activity_streams/retention";
import { sweepActivityStreamObjects } from "../../activity_streams/sweep";
import { DEBUG_TELEMETRY_DROP_EVENT, handleSendDebugTelemetry } from "../../activity_streams/telemetry";
import {
  ACT, DAY, HOUR, T0, UID, createWorld, firestoreInstance, loggedText, quarantinePath, releaseClock, resetAll, seedReady,
  setNow, store, streamPath, ts, uploadIdN, useClock, validPayload, type World,
} from "./support/fakes";
import { installIndexGuard, loadIndexFile } from "./support/indexes";
import { commit, outcome, stage } from "./support/flow";

let w: World;
const retDeps = (): RetentionDeps => ({ firestore: () => firestoreInstance as never, bucket: () => w.bucket, nowMs: () => Date.now() });
const recDeps = () => ({ ...w.deps, listing: () => w.bucket });
const lateDeps = (): LateSweepDeps => ({ firestore: w.deps.firestore, authUserExists: w.deps.authUserExists, nowMs: w.deps.nowMs, bucket: w.deps.bucket });
const fail = (code: number | string) => Object.assign(new Error(`gs://secret/${UID}`), { code });
const calls = (event: string): any[] =>
  (["info", "warn", "error"] as const).flatMap((l) => (logger[l] as jest.Mock).mock.calls as any[]).filter((c) => c[0] === event);
const actId = (n: number): string => `act_${n.toString(16).padStart(40, "0")}`;

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  for (const l of ["info", "warn", "error", "debug"] as const) (logger[l] as jest.Mock).mockClear();
});
afterEach(() => {
  releaseClock();
  const text = loggedText(logger);
  expect(text).not.toContain(UID);
  expect(text).not.toContain("gs://");
});

describe("F71 operations signals (design 6.3), forced failure to signal", () => {
  test("(1) a 2 h old pending row: the reconciler failure is counted at error level; after recovery the row is cleared and the signal falls", async () => {
    seedReady();
    await stage(w);
    setNow(T0 + 2 * HOUR);
    w.bucket.failOn = (op) => (op === "download" ? fail(500) : null);
    const r1 = await runActivityReconcile(recDeps(), undefined, []);
    expect(r1.failures).toBe(1);
    expect(calls("activity_reconcile_event").some((c) => c[1].outcome === "run-complete" && c[1].failures === 1)).toBe(true);
    w.bucket.failOn = null;
    const r2 = await runActivityReconcile(recDeps(), undefined, []);
    expect(r2.failures).toBe(0);
    expect(r2.pendingAborted).toBe(1);
    expect(store.has(`users/${UID}/activity_streams/${ACT}`)).toBe(false);
  });
  test("(2) an old quarantine object is reported with its age", async () => {
    w.bucket.put(quarantinePath(UID, ACT, uploadIdN(1)), Buffer.from("x"));
    setNow(T0 + 2 * DAY);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.oldestQuarantineAgeMs).toBe(2 * DAY);
    expect(calls("activity_reconcile_event").some((c) => c[1].oldestQuarantineAgeMs === 2 * DAY)).toBe(true);
  });
  test("(3) one failing prefix gives a counted bare code", async () => {
    w.bucket.failOn = (op, p) => (op === "deleteFiles" && p.startsWith("quarantine/") ? fail(403) : null);
    const e: any = await sweepActivityStreamObjects(UID, { bucket: () => w.bucket }).then(() => null, (x) => x);
    expect(e.code).toBe("403");
    expect(Object.keys(e)).toEqual(["code"]);
  });
  test("(4) a failing purge delete: the row is retried, overdue age grows, a capped row is counted and logged at error level", async () => {
    store.set(`users/${UID}/activity_settings/main`, { streamRetentionDays: 90, settingsGeneration: 1 });
    store.set(`users/${UID}/activities/${ACT}`, { startUtc: ts(T0 - 93 * DAY), rev: 1 });
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored", objectPath: streamPath(UID, ACT, "up_1"), expiresAt: ts(T0 - 3 * DAY), settingsGeneration: 1, purgeAttempts: 4 });
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("x"));
    w.bucket.failOn = (op) => (op === "delete" ? fail(500) : null);
    const r = await runActivityStreamPurge(retDeps(), { ...DEFAULT_RETENTION_LIMITS, maxPurgeAttempts: 3 });
    expect(r.cappedRows).toBe(1);
    expect(r.oldestOverdueAgeMs).toBe(3 * DAY);
    expect(calls("activity_purge_event").some((c) => c[1].outcome === "purge-capped")).toBe(true);
    expect(calls("activity_purge_event").some((c) => c[1].outcome === "run-complete" && c[1].cappedRows === 1)).toBe(true);
  });
  test("(5) a recompute stopped after one page leaves a visible backlog count and age", async () => {
    store.set(`users/${UID}/activity_settings/main`, { streamRetentionDays: 90, settingsGeneration: 2, recomputePending: true, updatedAt: ts(T0 - 2 * HOUR) });
    for (let i = 1; i <= 3; i++) store.set(`users/${UID}/activity_streams/${actId(i)}`, { state: "expired", settingsGeneration: 1 });
    const r = await runActivityStreamPurge(retDeps(), { ...DEFAULT_RETENTION_LIMITS, recomputePage: 1, recomputePagesPerUser: 1 });
    expect(r.recompute).toMatchObject({ backlogUsers: 1, backlogAgeMs: 2 * HOUR });
    expect(calls("activity_purge_event").some((c) => c[1].recomputeBacklogUsers === 1 && c[1].recomputeBacklogAgeMs === 2 * HOUR)).toBe(true);
  });
  describe("(6) one payload per validator code increments exactly its own code", () => {
    const big = (): any => {
      const p = validPayload();
      p.kinds.speed.offsetsMs = new Array(1_000_000).fill(0);
      p.kinds.speed.values = new Array(1_000_000).fill(0);
      return p;
    };
    const hr = (): any => { const p = validPayload(); p.kinds.hr = { kind: "hr", unit: "bpm", sourceId: "src1", offsetsMs: [0], values: [150] }; return p; };
    const unk = (): any => { const p = validPayload(); p.kinds.gps.extraField = 1; return p; };
    test.each([
      ["forbidden_kind", hr], ["unknown_key", unk], ["bomb", big],
    ] as Array<[string, () => any]>)("%s", async (code, make) => {
      seedReady();
      const s = await stage(w, make());
      await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }));
      const reasons = calls(ACTIVITY_COMMIT_EVENT).filter((c) => c[1].outcome === "validation_rejected").map((c) => c[1].reason);
      expect(reasons).toEqual([code]);
    });
    test("sha_mismatch (bytes differ from the declared hash)", async () => {
      seedReady();
      const s = await stage(w);
      w.bucket.put(quarantinePath(UID, ACT, s.uploadId), Buffer.from("different bytes"));
      await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }));
      expect(calls(ACTIVITY_COMMIT_EVENT).filter((c) => c[1].outcome === "validation_rejected").map((c) => c[1].reason)).toEqual(["sha_mismatch"]);
    });
    test("generation_changed (object replaced between the metadata read and the download)", async () => {
      seedReady();
      const s = await stage(w);
      const path = quarantinePath(UID, ACT, s.uploadId);
      w.bucket.hook = (phase, op) => { if (phase === "after" && op === "getMetadata") { w.bucket.hook = null; w.bucket.put(path, s.up.bytes); } };
      await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }));
      expect(calls(ACTIVITY_COMMIT_EVENT).map((c) => c[1].outcome)).toContain("generation_changed");
    });
  });
  test("(7) a commit after the fence is set counts a fence refusal", async () => {
    seedReady();
    const s = await stage(w);
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:account_deleting");
    expect(calls(ACTIVITY_COMMIT_EVENT).map((c) => c[1].outcome)).toContain("account_deleting");
  });
  test("(8) an oversize batch, an over-quota batch and a reported dropped counter are counted", async () => {
    const ev = { type: "log", level: "info", component: "app" };
    await outcome(handleSendDebugTelemetry(w.deps, UID, "password", { events: [], pad: "x".repeat(20000) }));
    for (let i = 0; i < 50; i++) await handleSendDebugTelemetry(w.deps, UID, "password", { events: Array.from({ length: 100 }, () => ev) });
    await outcome(handleSendDebugTelemetry(w.deps, UID, "password", { events: [ev] }));
    await handleSendDebugTelemetry(w.deps, UID, "password", { events: [], droppedCount: 9 });
    const outcomes = calls("debug_telemetry_event").map((c) => c[1].outcome);
    expect(outcomes).toContain("batch_too_large");
    expect(outcomes).toContain("quota_exceeded");
    expect(calls(DEBUG_TELEMETRY_DROP_EVENT).map((c) => c[1].dropped)).toEqual([9]);
  });
  test("(9) the purge query on a fake without the index entry fails with FAILED_PRECONDITION and the missing-index signal fires", async () => {
    const file = loadIndexFile();
    installIndexGuard({ indexes: file.indexes.filter((i) => i.collectionGroup !== "activity_streams"), fieldOverrides: file.fieldOverrides });
    const r = await runActivityStreamPurge(retDeps());
    expect(r.missingIndex).toBe(true);
    expect(calls("activity_purge_event").some((c) => c[1].outcome === "run-complete" && c[1].missingIndex === true)).toBe(true);
  });
  test("(10) a due job with the sweeper failing for more than 1 h raises the stuck-fence signal; it falls once the sweep completes", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0), lateSweepAt: ts(T0 + 15 * 60_000) });
    w.auth.users.delete(UID);
    w.bucket.failOn = (op) => (op === "deleteFiles" ? fail(500) : null);
    setNow(T0 + 15 * 60_000 + 2 * HOUR);
    const r1 = await runActivityLateSweep(lateDeps());
    expect(r1.stuck).toBe(1);
    expect(calls("activity_late_sweep_event").some((c) => c[1].outcome === "run-complete" && c[1].stuck === 1)).toBe(true);
    w.bucket.failOn = null;
    const r2 = await runActivityLateSweep(lateDeps());
    expect(r2.stuck).toBe(0);
    expect(r2.swept).toBe(1);
  });
});
