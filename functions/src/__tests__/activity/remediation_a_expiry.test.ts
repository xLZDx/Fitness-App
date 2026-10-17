/**
 * S02 remediation batch A, epic 8a: A7 (expiry falling due between commit transactions 1 and 2; download
 * URLs for a stored row whose derived expiry is due). Oracles: S02_REMEDIATION_A_TEST_NOTES.md, design 5.2/5.3/7.1.
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { classifyRow } from "../../activity_streams/download_urls";
import { selectPromotedObject } from "../../activity_streams/commit_stream";
import { runActivityReconcile, type ReconcileDeps } from "../../activity_streams/reconcile";
import {
  ACT, DAY, MIN, T0, UID, createWorld, releaseClock, resetAll, rowOf, seedConsent, seedReady, seedSummary, setNow,
  store, streamPath, useClock, validPayload, writes, type World,
} from "./support/fakes";
import { commit, fullUpload, outcome, stage } from "./support/flow";
import { SEVEN } from "./support/seven";

let w: World;
const recDeps = (): ReconcileDeps => ({ ...w.deps, listing: () => w.bucket });
const variant = (n: number): any => {
  const p = validPayload();
  p.kinds.speed.values = [n, n + 0.5];
  return p;
};
const ROW = `users/${UID}/activity_streams/${ACT}`;
/** Retention 90 days and a summary that falls due exactly one minute after T0. */
function dueSoon(): void {
  seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
  seedSummary(UID, ACT, T0 - 90 * DAY + MIN);
}
/** After the promoted object is saved (between T1 and T2) the clock passes the expiry. */
function expiryFallsDueAfterPromotion(): void {
  w.bucket.hook = (phase, op, path) => {
    if (phase === "after" && op === "save" && path.startsWith("streams/")) setNow(T0 + 2 * MIN);
  };
}

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
});
afterEach(() => releaseClock());

describe("A7 commit transaction 2 refuses an expiry that became due after transaction 1", () => {
  test("never-stored row: commit answers expired, the row is removed, quarantine and promoted objects are deleted, nothing stored", async () => {
    const s = await stage(w, variant(1));
    dueSoon();
    expiryFallsDueAfterPromotion();
    const n = writes.length;
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:expired");
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(w.bucket.keys()).toEqual([]);
    expect(w.bucket.saves.map((x) => x.path)).toEqual([streamPath(UID, ACT, s.uploadId)]); // it WAS promoted, then removed
    const rowWrites = writes.slice(n).filter((x) => x.path === ROW);
    expect(rowWrites.some((x) => x.data && (x.data as any).state === "stored")).toBe(false);
  });
  test("stored row with a pending re-upload: state, objectPath and old object are kept, the marker is cleared, both new objects are deleted", async () => {
    const first = await fullUpload(w, variant(1));
    const s = await stage(w, variant(2));
    dueSoon();
    expiryFallsDueAfterPromotion();
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:expired");
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row.objectPath).toBe(streamPath(UID, ACT, first.uploadId));
    expect(row.uploadId).toBe(first.uploadId);
    expect(row).not.toHaveProperty("pendingUploadId");
    expect(row).not.toHaveProperty("pendingSince");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, first.uploadId)]);
  });
  test("control: with the clock NOT advancing the same commit stores", async () => {
    const s = await stage(w, variant(1));
    dueSoon();
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("OK");
    expect(rowOf(UID, ACT).state).toBe("stored");
  });
  test("selectPromotedObject itself returns expired: true and writes only the marker clear (row deleted when never stored)", async () => {
    const s = await stage(w, variant(1));
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    const n = writes.length;
    const sel = await selectPromotedObject(w.deps, UID, { activityId: ACT, uploadId: s.uploadId }, {
      bytes: 10, kinds: ["gps"], storedSha256: "a".repeat(64), contentSha256: "b".repeat(64),
    });
    expect(sel).toMatchObject({ expired: true, alreadySelected: false });
    expect(writes.slice(n).map((x) => `${x.op}:${x.path}`)).toEqual([`delete:${ROW}`]);
  });
  test("selectPromotedObject on a stored row: only the three pending fields are removed, state and object stay", async () => {
    const first = await fullUpload(w, variant(1));
    const s = await stage(w, variant(2));
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    const before = { ...rowOf(UID, ACT) };
    const sel = await selectPromotedObject(w.deps, UID, { activityId: ACT, uploadId: s.uploadId }, {
      bytes: 10, kinds: ["gps"], storedSha256: "a".repeat(64), contentSha256: "b".repeat(64),
    });
    expect(sel.expired).toBe(true);
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row.objectPath).toBe(before.objectPath);
    expect(row.objectPath).toBe(streamPath(UID, ACT, first.uploadId));
    expect(row).not.toHaveProperty("pendingUploadId");
    expect(row.storedSha256).toBe(before.storedSha256);
  });
  test("reconciler repair of an interrupted commit whose expiry is due: treated as aborted, both objects deleted, never-stored row removed", async () => {
    const s = await stage(w, variant(1));
    w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "save" && path.startsWith("streams/")) throw new Error("killed after promotion"); };
    await commit(w, { activityId: ACT, uploadId: s.uploadId }).catch(() => undefined);
    w.bucket.hook = null;
    expect(w.bucket.keys(`streams/${UID}/`)).toHaveLength(1);
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r).toMatchObject({ pendingAborted: 1, pendingRepaired: 0 });
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("reconciler repair on a stored row with a due expiry: marker cleared, old object kept, the interrupted upload's objects deleted", async () => {
    const first = await fullUpload(w, variant(1));
    const s = await stage(w, variant(2));
    w.bucket.hook = (phase, op, path) => { if (phase === "after" && op === "save" && path.startsWith("streams/")) throw new Error("killed after promotion"); };
    await commit(w, { activityId: ACT, uploadId: s.uploadId }).catch(() => undefined);
    w.bucket.hook = null;
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    setNow(T0 + 61 * MIN);
    const r = await runActivityReconcile(recDeps(), undefined, []);
    expect(r.pendingAborted).toBe(1);
    expect(rowOf(UID, ACT).state).toBe("stored");
    expect(rowOf(UID, ACT)).not.toHaveProperty("pendingUploadId");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, first.uploadId)]);
  });
});

describe("A7 getActivityStreamDownloadUrls with a derived expiry", () => {
  const dl = (ids: string[]) => SEVEN.find((e) => e.name === "getActivityStreamDownloadUrls")!.call(w, { activityIds: ids });
  const put = (): void => {
    store.set(ROW, { state: "stored", objectPath: streamPath(UID, ACT, "up_1") });
    w.bucket.put(streamPath(UID, ACT, "up_1"), Buffer.from("x"));
  };
  test("a stored row whose derived expiry is due answers expired and signs no URL", async () => {
    put();
    seedConsent(UID, { streamRetentionDays: 90 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    const res = await dl([ACT]);
    expect(res.results[0]).toEqual({ activityId: ACT, status: "unavailable", code: "expired" });
    expect(w.bucket.signed).toEqual([]);
  });
  test("boundary: expiry exactly now is due, one millisecond later is not", async () => {
    put();
    seedConsent(UID, { streamRetentionDays: 90 });
    seedSummary(UID, ACT, T0 - 90 * DAY);
    expect((await dl([ACT])).results[0]).toMatchObject({ status: "unavailable", code: "expired" });
    seedSummary(UID, ACT, T0 - 90 * DAY + 1);
    expect((await dl([ACT])).results[0]).toMatchObject({ status: "ok" });
  });
  test("a stored row that is not due still signs", async () => {
    put();
    const res = await dl([ACT]);
    expect(res.results[0]).toMatchObject({ activityId: ACT, status: "ok" });
    expect(w.bucket.signed).toHaveLength(1);
  });
  test("a missing summary falls back to signing as before", async () => {
    put();
    store.delete(`users/${UID}/activities/${ACT}`);
    expect((await dl([ACT])).results[0]).toMatchObject({ status: "ok" });
    expect(w.bucket.signed).toHaveLength(1);
  });
  test("classifyRow: fourth argument optional, a null retention given directly to the pure classifier is never due (defensive; callers pass effectiveStreamRetentionDays, which never returns null now), due stored is expired, other states unchanged", () => {
    const row = { state: "stored", objectPath: streamPath(UID, ACT, "up_1") };
    expect(classifyRow(UID, ACT, false, row)).toMatchObject({ kind: "sign" });
    expect(classifyRow(UID, ACT, false, row, { startUtcMs: T0 - 5000 * DAY, retentionDays: null, nowMs: T0 })).toMatchObject({ kind: "sign" });
    expect(classifyRow(UID, ACT, false, row, { startUtcMs: T0 - 91 * DAY, retentionDays: 90, nowMs: T0 })).toEqual({ activityId: ACT, kind: "unavailable", code: "expired" });
    expect(classifyRow(UID, ACT, false, { state: "pending" }, { startUtcMs: T0 - 500 * DAY, retentionDays: 90, nowMs: T0 })).toMatchObject({ code: "not_ready" });
    expect(classifyRow(UID, ACT, true, row, { startUtcMs: T0 - 91 * DAY, retentionDays: 90, nowMs: T0 })).toMatchObject({ code: "not_found" });
  });
});
