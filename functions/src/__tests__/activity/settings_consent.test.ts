/** S02-05a: F13 settings validation, F75 atomic change, F68 consent withdrawal, F82 bulk-delete quota. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { handleDeleteAllActivityStreams } from "../../activity_streams/delete_all_streams";
import {
  ALLOWED_STREAM_RETENTION_DAYS, STREAM_RETENTION_NEVER_OFFERED, isValidStreamRetentionDays, parseSettingsRequest,
  planSettingsChange,
} from "../../activity_streams/settings";
import {
  ACT, ACT_2, DAY, T0, UID, UID_B, createWorld, expectHttpsError, fx, firestoreError, quarantinePath, releaseClock,
  resetAll, rowOf, seedConsent, seedReady, seedSummary, settingsOf, store, streamPath, ts, usageOf, useClock, writes,
  type World,
} from "./support/fakes";
import { commit, create, fullUpload, outcome, stage } from "./support/flow";
import { SEVEN } from "./support/seven";

let w: World;
const settings = (d: unknown, uid = UID, provider = "password") => SEVEN.find((e) => e.name === "setActivityCloudSettings")!.call(w, d, uid, provider);
const SETTINGS_PATH = `users/${UID}/activity_settings/main`;
const settingsWrites = () => writes.filter((x) => x.path === SETTINGS_PATH);
const GRANT = { cloudStreams: { granted: true, version: 1 } };
const WITHDRAW = { cloudStreams: { granted: false, version: 1 } };

const savedEnv = process.env.ACTIVITY_STREAM_BUCKET;
beforeEach(() => {
  resetAll();
  useClock(T0);
  process.env.ACTIVITY_STREAM_BUCKET = "demo-activity-streams-test";
  w = createWorld();
});
afterEach(() => {
  releaseClock();
  if (savedEnv === undefined) delete process.env.ACTIVITY_STREAM_BUCKET; else process.env.ACTIVITY_STREAM_BUCKET = savedEnv;
});

describe("F13 settings validation", () => {
  test.each([[0], [-1], [1e9], [1.5], ["90"], [NaN], [91], [undefined], [true], [[90]]])("retention %p is refused and writes nothing", async (v) => {
    await expectHttpsError(settings({ streamRetentionDays: v }), "invalid-argument", "invalid_retention");
    expect(store.has(SETTINGS_PATH)).toBe(false);
    expect(settingsWrites()).toEqual([]);
  });
  test.each(ALLOWED_STREAM_RETENTION_DAYS.map((d) => [d]))("retention %p is accepted (design 5.3: 90, 365, 730; the plan row says 'refused' by mistake)", async (d) => {
    const r = await settings({ streamRetentionDays: d });
    expect(r.streamRetentionDays).toBe(d);
  });
  test("the allowed set is exactly 90, 365 and 730", () => {
    expect([...ALLOWED_STREAM_RETENTION_DAYS]).toEqual([90, 365, 730]);
  });
  test("'never' (null) is consistent between the exported flag and the validator (PENDING operator decision DQ-7)", async () => {
    expect(isValidStreamRetentionDays(null)).toBe(STREAM_RETENTION_NEVER_OFFERED);
    if (STREAM_RETENTION_NEVER_OFFERED) {
      expect((await settings({ streamRetentionDays: null })).streamRetentionDays).toBeNull();
    } else {
      await expectHttpsError(settings({ streamRetentionDays: null }), "invalid-argument", "invalid_retention");
    }
  });
  test.each([
    [{}, "invalid_request"], [null, "invalid_request"], ["x", "invalid_request"], [[1], "invalid_request"],
    [{ streamRetentionDays: 90, extra: 1 }, "invalid_request"],
    [{ cloudStreams: { granted: true } }, "invalid_consent"],
    [{ cloudStreams: { granted: "yes", version: 1 } }, "invalid_consent"],
    [{ cloudStreams: { granted: true, version: 2 } }, "invalid_consent"],
    [{ cloudStreams: { granted: true, version: 1, extra: 1 } }, "invalid_consent"],
    [{ cloudStreams: { granted: true, version: 1, deleteExisting: true } }, "invalid_consent"],
    [{ cloudStreams: { granted: false, version: 1, deleteExisting: "y" } }, "invalid_consent"],
    [{ cloudStreams: 5 }, "invalid_consent"],
  ])("parse of %j is refused with the bare code", (data, code) => {
    expect(() => parseSettingsRequest(data)).toThrow(code);
  });
  test("a client-sent version older than the current consent text cannot grant consent", async () => {
    await expectHttpsError(settings({ cloudStreams: { granted: true, version: 0 } }), "invalid-argument", "invalid_consent");
    expect(store.has(SETTINGS_PATH)).toBe(false);
  });
});

describe("F75 a settings change is atomic", () => {
  test("retention change writes retention, generation+1, recomputePending and the reset cursor in ONE write", async () => {
    seedConsent(UID, { streamRetentionDays: 730, settingsGeneration: 3, recomputeCursor: "act_x" });
    const before = settingsWrites().length;
    const r = await settings({ streamRetentionDays: 90 });
    expect(r).toMatchObject({ changed: true, settingsGeneration: 4, streamRetentionDays: 90, recomputePending: true });
    const ws = settingsWrites().slice(before);
    expect(ws).toHaveLength(1);
    expect(ws[0].data).toMatchObject({ streamRetentionDays: 90, settingsGeneration: 4, recomputePending: true, recomputeCursor: null });
    expect(settingsOf(UID)).toMatchObject({ streamRetentionDays: 90, settingsGeneration: 4, recomputePending: true, recomputeCursor: null });
  });
  test("a failing commit leaves NO partial state and a bare code; the quota charge is returned", async () => {
    seedConsent(UID, { streamRetentionDays: 730, settingsGeneration: 3 });
    const snapshot = JSON.stringify(settingsOf(UID));
    fx.failOn = (op, path) => (op === "commit" && path.includes("activity_settings") ? firestoreError(`boom ${UID}`, 14) : undefined);
    const err = await expectHttpsError(settings({ streamRetentionDays: 90 }), "internal", "settings_failed");
    expect(err.message).not.toContain(UID);
    fx.failOn = null;
    expect(JSON.stringify(settingsOf(UID))).toBe(snapshot);
    expect(usageOf(UID, "activitySettingsSet")).toBe(0);
  });
  test("a rejected value does not change the generation", async () => {
    seedConsent(UID, { settingsGeneration: 3 });
    await outcome(settings({ streamRetentionDays: 91 }));
    expect(settingsOf(UID).settingsGeneration).toBe(3);
  });
  test("an identical request is a no-op: no write, same generation, nothing queued", async () => {
    seedConsent(UID, { streamRetentionDays: 730, settingsGeneration: 3 });
    const n = settingsWrites().length;
    const r = await settings({ streamRetentionDays: 730 });
    expect(r).toMatchObject({ changed: false, settingsGeneration: 3, recomputePending: false });
    expect(settingsWrites().length).toBe(n);
    expect(settingsOf(UID).recomputePending).toBeUndefined();
  });
  test("retention and consent in one call bump the generation exactly once", async () => {
    const r = await settings({ streamRetentionDays: 365, cloudStreams: { granted: true, version: 1 } });
    expect(r.settingsGeneration).toBe(1);
    expect(settingsOf(UID)).toMatchObject({ streamRetentionDays: 365, settingsGeneration: 1 });
    expect(settingsOf(UID).cloudStreams.acceptedAt.toMillis()).toBe(T0);
  });
  test("a pending recompute from an earlier change stays pending after an unrelated consent change", () => {
    const plan = planSettingsChange({ recomputePending: true, settingsGeneration: 2, streamRetentionDays: 90 }, { cloudStreamsGranted: true }, T0);
    expect(plan.recomputePending).toBe(true);
    expect(plan.retentionChanged).toBe(false);
    expect(plan.settingsGeneration).toBe(3);
  });
  test("the server records the consent time and version; a client cannot supply either", async () => {
    await settings({ cloudStreams: { granted: true, version: 1 } });
    const c = settingsOf(UID).cloudStreams;
    expect(c.version).toBe(1);
    expect(c.acceptedAt.toMillis()).toBe(T0);
  });
  test("granting needs the bucket (feature-disabled); retention change and withdrawal always work", async () => {
    delete process.env.ACTIVITY_STREAM_BUCKET;
    await expectHttpsError(settings(GRANT), "failed-precondition");
    expect(store.has(SETTINGS_PATH)).toBe(false);
    expect((await settings({ streamRetentionDays: 90 })).changed).toBe(true);
    seedConsent(UID);
    expect((await settings(WITHDRAW)).consent).toBe("withdrawn");
  });
});

describe("F68 consent withdrawal", () => {
  test("withdrawal records withdrawnAt, bumps the generation, and upload/commit refuse with the bare code", async () => {
    seedReady();
    const staged = await stage(w);
    const gen = settingsOf(UID).settingsGeneration;
    const r = await settings(WITHDRAW);
    expect(r).toMatchObject({ changed: true, consent: "withdrawn", settingsGeneration: gen + 1 });
    expect(settingsOf(UID).cloudStreams.withdrawnAt.toMillis()).toBe(T0);
    await expectHttpsError(create(w, { activityId: ACT, bytes: staged.up.bytes.length, contentSha256: staged.up.sha }), "failed-precondition", "consent_withdrawn");
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: staged.uploadId }), "failed-precondition", "consent_withdrawn");
    expect(w.bucket.keys("streams/")).toEqual([]);
  });
  test("withdrawal alone is not charged against the settings quota; a grant is", async () => {
    seedConsent(UID);
    await settings(WITHDRAW);
    expect(usageOf(UID, "activitySettingsSet")).toBe(0);
    await settings(GRANT);
    expect(usageOf(UID, "activitySettingsSet")).toBe(1);
  });
  test("withdrawal is allowed when the settings quota is exhausted", async () => {
    seedConsent(UID);
    store.set(`users/${UID}/usage/2026-10-15`, { activitySettingsSet: 20 });
    await expectHttpsError(settings({ streamRetentionDays: 90 }), "resource-exhausted", "quota_exceeded");
    expect((await settings(WITHDRAW)).consent).toBe("withdrawn");
  });
  test("withdrawing when consent was never granted records nothing", async () => {
    const r = await settings(WITHDRAW);
    expect(r).toMatchObject({ changed: false, consent: "none" });
    expect(settingsWrites()).toEqual([]);
  });
  test("re-granting clears the withdrawal and uploads work again", async () => {
    seedReady();
    await settings(WITHDRAW);
    const r = await settings(GRANT);
    expect(r.consent).toBe("granted");
    expect((await fullUpload(w)).result.status).toBe("stored");
  });
  test("stored streams remain after a plain withdrawal (no bulk call) and individual deleteActivity still works", async () => {
    seedReady();
    const f = await fullUpload(w);
    const r = await settings(WITHDRAW);
    expect(r.streamDeleteStarted).toBe(false);
    expect(settingsOf(UID).streamDeletePending).toBeUndefined();
    expect(w.bucket.keys("streams/")).toEqual([streamPath(UID, ACT, f.uploadId)]);
    expect(rowOf(UID, ACT).state).toBe("stored");
    const del = await SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT });
    expect(del.deleted).toBe(true);
    expect(w.bucket.keys("streams/")).toEqual([]);
  });
  test("withdrawal with deleteExisting starts the job; the bulk call removes streams and rows, keeps every summary, touches nobody else", async () => {
    seedReady();
    seedReady(UID, ACT_2);
    seedReady(UID_B, ACT);
    await fullUpload(w, undefined, UID, ACT);
    await fullUpload(w, undefined, UID, ACT_2);
    await fullUpload(w, undefined, UID_B, ACT);
    const bKeys = w.bucket.keys(`streams/${UID_B}/`);
    const r = await settings({ cloudStreams: { granted: false, version: 1, deleteExisting: true } });
    expect(r.streamDeleteStarted).toBe(true);
    expect(settingsOf(UID)).toMatchObject({ streamDeletePending: true });
    expect(settingsOf(UID).streamDeleteJobId).toMatch(/^job_/);
    const res = await handleDeleteAllActivityStreams(w.deps, UID, "password", { expectedUid: UID });
    expect(res).toMatchObject({ status: "done", deleted: 2 });
    expect(w.bucket.keys(`streams/${UID}/`)).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(rowOf(UID, ACT_2)).toBeUndefined();
    for (const id of [ACT, ACT_2]) expect(store.has(`users/${UID}/activities/${id}`)).toBe(true);
    expect(w.bucket.keys(`streams/${UID_B}/`)).toEqual(bKeys);
    expect(rowOf(UID_B, ACT).state).toBe("stored");
    expect(settingsOf(UID).streamDeletePending).toBeUndefined();
    expect(settingsOf(UID).cloudStreams.withdrawnAt).toBeDefined();
  });
  test("a running delete job is never replaced by a second withdrawal request", async () => {
    seedConsent(UID, { streamDeletePending: true, streamDeleteJobId: "job_running", streamDeleteCursor: "act_c" });
    const r = await settings({ cloudStreams: { granted: false, version: 1, deleteExisting: true } });
    expect(r.streamDeleteStarted).toBe(false);
    expect(settingsOf(UID).streamDeleteJobId).toBe("job_running");
    expect(settingsOf(UID).streamDeleteCursor).toBe("act_c");
  });
});

describe("F82 activityDeleteAll has its own quota", () => {
  const all = () => handleDeleteAllActivityStreams(w.deps, UID, "password", { expectedUid: UID });
  test("the 10th start of a day is accepted, the 11th is a bare quota code with no side effect, the next day resets", async () => {
    for (let i = 0; i < 10; i++) expect((await all()).status).toBe("done");
    expect(usageOf(UID, "activityDeleteAll")).toBe(10);
    const state = JSON.stringify([...store.entries()].filter(([k]) => !k.includes("/usage/")));
    await expectHttpsError(all(), "resource-exhausted", "quota_exceeded");
    expect(JSON.stringify([...store.entries()].filter(([k]) => !k.includes("/usage/")))).toBe(state);
    jest.setSystemTime(T0 + DAY);
    expect((await all()).status).toBe("done");
  });
  test("a continuation of a started job is not charged again (120 rows, pages of 50)", async () => {
    seedSummary(UID, ACT);
    for (let i = 0; i < 120; i++) {
      const id = `act_${i.toString(16).padStart(40, "0")}`;
      store.set(`users/${UID}/activity_streams/${id}`, { state: "stored", objectPath: streamPath(UID, id, `up_${"0".repeat(32)}`) });
    }
    const r1 = await all();
    expect(r1).toMatchObject({ status: "more", deleted: 50 });
    expect(usageOf(UID, "activityDeleteAll")).toBe(1);
    expect((await all()).status).toBe("more");
    expect((await all())).toMatchObject({ status: "done", deleted: 20 });
    expect(usageOf(UID, "activityDeleteAll")).toBe(1);
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toEqual([]);
    expect(store.has(`users/${UID}/activities/${ACT}`)).toBe(true);
  });
  test("exhausting activityDelete does not block the bulk call; exhausting the bulk quota does not block deleteActivity", async () => {
    store.set(`users/${UID}/usage/2026-10-15`, { activityDelete: 1000 });
    expect((await all()).status).toBe("done");
    store.set(`users/${UID}/usage/2026-10-15`, { activityDeleteAll: 10 });
    const del = await SEVEN.find((e) => e.name === "deleteActivity")!.call(w, { activityId: ACT });
    expect(del.deleted).toBe(true);
  });
  test("a fenced account's bulk call is refused and the quota charge returned", async () => {
    store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    await expectHttpsError(all(), "failed-precondition", "account_deleting");
    expect(usageOf(UID, "activityDeleteAll")).toBe(0);
    expect(store.has(SETTINGS_PATH)).toBe(false);
    void quarantinePath;
  });
});
