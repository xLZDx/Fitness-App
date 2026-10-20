/**
 * S02 remediation batch A, epic 8a: A11 (withdrawal no-op short circuit), A13 (a consent grant cancels a running
 * bulk-delete job), A16 (recompute final pass terminates for rows in every state with an older generation).
 * Oracles: S02_REMEDIATION_A_TEST_NOTES.md and design 9.1 / 5.3.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { DEFAULT_DELETE_ALL_LIMITS, runBulkDeletePage } from "../../activity_streams/delete_all_streams";
import { runRecomputeContinuation } from "../../activity_streams/recompute";
import { DEFAULT_RETENTION_LIMITS, type RetentionDeps } from "../../activity_streams/retention";
import {
  ACT, ACT_2, DAY, T0, UID, createWorld, expectHttpsError, firestoreInstance, fx, firestoreError, releaseClock, resetAll,
  rowOf, seedConsent, seedReady, settingsOf, store, ts, usageOf, useClock, writes, type World,
} from "./support/fakes";
import { SEVEN } from "./support/seven";

let w: World;
const settings = (d: unknown) => SEVEN.find((e) => e.name === "setActivityCloudSettings")!.call(w, d, UID, "password");
const SETTINGS_PATH = `users/${UID}/activity_settings/main`;
const settingsWrites = () => writes.filter((x) => x.path === SETTINGS_PATH);
const GRANT = { cloudStreams: { granted: true, version: 1 } };
const WITHDRAW = { cloudStreams: { granted: false, version: 1 } };
const WITHDRAW_DELETE = { cloudStreams: { granted: false, version: 1, deleteExisting: true } };
const JOB_FIELDS = ["streamDeletePending", "streamDeleteJobId", "streamDeleteCursor", "streamDeleteStartedAt", "streamDeleteAttemptAt", "streamDeleteAttempts"];
const withJob = (extra: Record<string, unknown> = {}): Record<string, unknown> => ({
  streamDeletePending: true, streamDeleteJobId: "job_running", streamDeleteCursor: `act_${"c".repeat(40)}`,
  streamDeleteStartedAt: ts(T0 - DAY), streamDeleteAttemptAt: ts(T0 - 60000), streamDeleteAttempts: 3, ...extra,
});
const withdrawn = { cloudStreams: { withdrawnAt: ts(T0 - DAY) }, settingsGeneration: 4, streamRetentionDays: 730 };

const savedEnv = process.env.ACTIVITY_STREAM_BUCKET;
let txSpy: jest.SpyInstance;
beforeEach(() => {
  resetAll();
  useClock(T0);
  process.env.ACTIVITY_STREAM_BUCKET = "demo-activity-streams-test";
  w = createWorld();
  txSpy = jest.spyOn(firestoreInstance as any, "runTransaction");
});
afterEach(() => {
  txSpy.mockRestore();
  releaseClock();
  if (savedEnv === undefined) delete process.env.ACTIVITY_STREAM_BUCKET; else process.env.ACTIVITY_STREAM_BUCKET = savedEnv;
});

describe("A11 withdrawal-only no-op short circuit", () => {
  const expectNoWork = (): void => {
    expect(w.auth.lookups).toBe(0);
    expect(txSpy).not.toHaveBeenCalled();
    expect(writes).toEqual([]);
    expect(usageOf(UID, "activitySettingsSet")).toBe(0);
  };
  test("consent never granted, no document: changed false, no transaction, no Auth lookup, no write, not metered", async () => {
    const r = await settings(WITHDRAW);
    expect(r).toMatchObject({ changed: false, consent: "none", streamDeleteStarted: false, settingsGeneration: 0 });
    expectNoWork();
    expect(store.has(SETTINGS_PATH)).toBe(false);
  });
  test("consent already withdrawn: the current state is answered, nothing else happens", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn });
    const r = await settings(WITHDRAW);
    expect(r).toMatchObject({ changed: false, consent: "withdrawn", settingsGeneration: 4, streamRetentionDays: 730 });
    expectNoWork();
  });
  test("withdrawn with deleteExisting while a job is already active: no-op, the running job is untouched", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn, ...withJob({ streamDeleteCursor: undefined }) });
    const r = await settings(WITHDRAW_DELETE);
    expect(r).toMatchObject({ changed: false, streamDeleteStarted: false });
    expectNoWork();
    expect(settingsOf(UID).streamDeleteJobId).toBe("job_running");
  });
  test("a fenced account's no-op withdrawal also answers without Auth or fence work (nothing to change)", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn });
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    const r = await settings(WITHDRAW);
    expect(r.changed).toBe(false);
    expect(w.auth.lookups).toBe(0);
    expect(txSpy).not.toHaveBeenCalled();
  });
  test("a withdrawal that really changes state still runs the fenced transaction (Auth looked up, generation bumped, not metered)", async () => {
    seedConsent(UID);
    const r = await settings(WITHDRAW);
    expect(r).toMatchObject({ changed: true, consent: "withdrawn", settingsGeneration: 2 });
    expect(txSpy).toHaveBeenCalled();
    expect(w.auth.lookups).toBeGreaterThan(0);
    expect(usageOf(UID, "activitySettingsSet")).toBe(0);
    expect(settingsOf(UID).cloudStreams.withdrawnAt).toBeDefined();
  });
  test("an already-withdrawn account that asks deleteExisting with no active job starts the job inside the fenced transaction", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn });
    const r = await settings(WITHDRAW_DELETE);
    expect(r).toMatchObject({ changed: false, streamDeleteStarted: true });
    expect(txSpy).toHaveBeenCalled();
    expect(w.auth.lookups).toBeGreaterThan(0);
    expect(settingsOf(UID).streamDeletePending).toBe(true);
    expect(settingsOf(UID).streamDeleteJobId).toMatch(/^job_/);
  });
  test("the fence still refuses a withdrawal that would change state or start a job", async () => {
    seedConsent(UID);
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(settings(WITHDRAW), "failed-precondition", "account_deleting");
    expect(settingsOf(UID).cloudStreams.withdrawnAt).toBeUndefined();
  });
  test("a read failure answers settings_failed and writes nothing", async () => {
    fx.failOn = (op, p) => (op === "get" && p === SETTINGS_PATH ? firestoreError("down", 14) : undefined);
    await expectHttpsError(settings(WITHDRAW), "internal", "settings_failed");
    fx.failOn = null;
    expect(writes).toEqual([]);
  });
});

describe("A13 a consent grant cancels a running bulk-delete job", () => {
  test("a changed grant clears all six job fields in the SAME write as the consent", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn, ...withJob() });
    expect(settingsOf(UID).streamDeleteCursor).toBeDefined(); // precondition: the cursor field exists and must be cleared
    const r = await settings(GRANT);
    expect(r).toMatchObject({ changed: true, consent: "granted" });
    const s = settingsOf(UID);
    for (const f of JOB_FIELDS) expect(s[f]).toBeUndefined();
    expect(s.cloudStreams.acceptedAt).toBeDefined();
    expect(settingsWrites()).toHaveLength(1);
    expect(settingsWrites()[0].data).toHaveProperty("cloudStreams");
    for (const f of JOB_FIELDS) expect(settingsWrites()[0].data).toHaveProperty(f);
  });
  test("a grant with no active job writes none of the job fields", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn });
    await settings(GRANT);
    expect(settingsWrites()).toHaveLength(1);
    for (const f of JOB_FIELDS) expect(settingsWrites()[0].data).not.toHaveProperty(f);
    expect(settingsOf(UID).cloudStreams.acceptedAt).toBeDefined();
  });
  test("a grant that changes nothing (already granted) leaves a running job alone", async () => {
    seedConsent(UID, withJob());
    const r = await settings(GRANT);
    expect(r.changed).toBe(false);
    expect(settingsOf(UID).streamDeleteJobId).toBe("job_running");
    expect(settingsOf(UID).streamDeletePending).toBe(true);
  });
  test("a withdrawal never cancels a job", async () => {
    seedConsent(UID, withJob());
    await settings(WITHDRAW);
    expect(settingsOf(UID).cloudStreams.withdrawnAt).toBeDefined();
    expect(settingsOf(UID).streamDeleteJobId).toBe("job_running");
    expect(settingsOf(UID).streamDeletePending).toBe(true);
    expect(settingsOf(UID).streamDeleteAttempts).toBe(3);
  });
  test("after the grant the continuation finds no job (continue mode returns null) and erases nothing", async () => {
    seedReady();
    store.set(SETTINGS_PATH, { ...withdrawn, ...withJob({ streamDeleteCursor: undefined }) });
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored" });
    store.set(`users/${UID}/activity_streams/${ACT_2}`, { state: "stored" });
    await settings(GRANT);
    expect(await runBulkDeletePage(w.deps, UID, DEFAULT_DELETE_ALL_LIMITS, "continue")).toBeNull();
    expect(rowOf(UID, ACT)).toBeDefined();
    expect(rowOf(UID, ACT_2)).toBeDefined();
    expect(w.bucket.deleteFilesCalls).toEqual([]);
  });
  test("control: without the grant the same continuation erases the rows", async () => {
    store.set(SETTINGS_PATH, { ...withdrawn, ...withJob({ streamDeleteCursor: undefined }) });
    store.set(`users/${UID}/activity_streams/${ACT}`, { state: "stored" });
    expect((await runBulkDeletePage(w.deps, UID, DEFAULT_DELETE_ALL_LIMITS, "continue"))?.status).toBe("done");
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
});

describe("A16 recompute final pass terminates for every row state", () => {
  const deps = (): RetentionDeps => ({
    firestore: () => firestoreInstance as unknown as FirebaseFirestore.Firestore,
    bucket: () => w.bucket,
    nowMs: () => Date.now(),
  });
  const id = (n: number): string => `act_${n.toString(16).padStart(40, "0")}`;
  test("stored, expired, deleted and pending rows with an older generation all end with the current generation and recomputePending false", async () => {
    store.set(SETTINGS_PATH, { streamRetentionDays: 90, settingsGeneration: 3, recomputePending: true });
    const states = ["stored", "expired", "deleted", "pending"];
    states.forEach((state, i) => {
      store.set(`users/${UID}/activities/${id(i + 1)}`, { startUtc: ts(T0 - 5 * DAY), rev: 1 });
      store.set(`users/${UID}/activity_streams/${id(i + 1)}`, {
        state, settingsGeneration: 1, expiresAt: ts(T0 + 300 * DAY), objectPath: `streams/${UID}/${id(i + 1)}/up_1.json.gz`,
        ...(state === "pending" ? { pendingSince: ts(T0 - 1000), uploadId: "up_1" } : {}),
      });
    });
    const failures: unknown[] = [];
    const r = await runRecomputeContinuation(deps(), DEFAULT_RETENTION_LIMITS, T0, Date.now() + 1e9, (e) => failures.push(e));
    expect(failures).toEqual([]);
    expect(r.usersCompleted).toBe(1);
    expect(settingsOf(UID).recomputePending).toBe(false);
    states.forEach((state, i) => {
      expect(rowOf(UID, id(i + 1)).settingsGeneration).toBe(3);
      expect(rowOf(UID, id(i + 1)).state).toBe(state); // only stamped, never resurrected or removed
    });
  });
});
