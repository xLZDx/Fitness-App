/** F84 intended hash before promotion, F85 overlapping commits, F86 re-upload over a stored row. */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { gzipSync } from "zlib";
import {
  ACT, DAY, Gate, T0, UID, createWorld, firestoreInstance, quarantinePath, releaseClock, resetAll, rowOf, seedConsent,
  seedReady, seedSummary, sha, store, streamPath, ts, uploadOf, useClock, validPayload, type World,
} from "./support/fakes";
import { commit, create, fullUpload, outcome, stage } from "./support/flow";

let w: World;
beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  seedReady();
});
afterEach(() => releaseClock());

const variant = (n: number): any => {
  const p = validPayload();
  p.kinds.speed.values = [n, n + 1];
  return p;
};

/** Same data as validPayload, different key order and whitespace: content hash != stored hash. */
const scrambledUpload = () => {
  const p = validPayload();
  const text = JSON.stringify({ meta: p.meta, kinds: { speed: p.kinds.speed, altitude: p.kinds.altitude, gps: p.kinds.gps }, schema: 1 }, null, 2);
  const bytes = gzipSync(Buffer.from(text));
  return { bytes, sha: sha(bytes) };
};

describe("F84 intended stored hash is recorded before promotion", () => {
  test("at the moment of promotion the row already holds intendedStoredSha256, which differs from contentSha256 and equals the promoted bytes", async () => {
    const up = scrambledUpload();
    const r = await create(w, { activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha });
    w.bucket.put(quarantinePath(UID, ACT, r.uploadId), up.bytes);
    let seen: any;
    w.bucket.hook = (phase, op, path) => {
      if (phase === "before" && op === "save" && path.startsWith("streams/")) seen = { ...rowOf(UID, ACT) };
    };
    await commit(w, { activityId: ACT, uploadId: r.uploadId });
    expect(seen.state).toBe("pending");
    expect(seen.intendedStoredSha256).toMatch(/^[0-9a-f]{64}$/);
    expect(seen.intendedStoredSha256).not.toBe(seen.contentSha256);
    const promoted = w.bucket.objects.get(streamPath(UID, ACT, r.uploadId))!.content;
    expect(seen.intendedStoredSha256).toBe(sha(promoted));
    expect(rowOf(UID, ACT).storedSha256).toBe(seen.intendedStoredSha256);
    expect(rowOf(UID, ACT)).not.toHaveProperty("intendedStoredSha256");
  });
  test("each upload id has its own intended hash (no sharing across commits)", async () => {
    const seen: string[] = [];
    w.bucket.hook = (phase, op, path) => {
      if (phase === "before" && op === "save" && path.startsWith("streams/")) seen.push(rowOf(UID, ACT).intendedStoredSha256);
    };
    await fullUpload(w, variant(1));
    await fullUpload(w, variant(5));
    expect(seen).toHaveLength(2);
    expect(seen[0]).not.toBe(seen[1]);
  });
});

describe.each([["after promotion", "after"], ["before promotion", "before"]] as const)("F85 overlapping commits (A paused %s)", (_n, phase) => {
  test("neither commit destroys the other's object; exactly one is selected; the loser removes only its own", async () => {
    const a = await stage(w, variant(1));
    const aPromoted = streamPath(UID, ACT, a.uploadId);
    const gate = new Gate("A");
    let rowPointsAtMissingObject = false;
    w.bucket.hook = async (ph, op, path) => {
      if (ph === phase && op === "save" && path === aPromoted) await gate.hit();
    };
    const commitA = outcome(commit(w, { activityId: ACT, uploadId: a.uploadId }));
    await gate.reached;

    const b = await stage(w, variant(9)); // supersedes A
    expect((await commit(w, { activityId: ACT, uploadId: b.uploadId })).status).toBe("stored");
    const bPromoted = streamPath(UID, ACT, b.uploadId);
    const before = w.bucket.objects.get(bPromoted)!.content;
    rowPointsAtMissingObject = !w.bucket.objects.has(rowOf(UID, ACT).objectPath);
    expect(rowPointsAtMissingObject).toBe(false);

    gate.release();
    expect(await commitA).toBe("aborted:superseded");
    expect(w.bucket.keys("streams/")).toEqual([bPromoted]);
    expect(w.bucket.keys("quarantine/")).toEqual([]);
    expect(w.bucket.objects.get(bPromoted)!.content.equals(before)).toBe(true);
    expect(rowOf(UID, ACT)).toMatchObject({ state: "stored", uploadId: b.uploadId, objectPath: bPromoted });
  });

  test("with a previous stored object, it is deleted only AFTER the winner's transaction 2 and never while the row points at it", async () => {
    const first = await fullUpload(w, variant(100));
    const p0 = streamPath(UID, ACT, first.uploadId);
    const a = await stage(w, variant(1));
    const aPromoted = streamPath(UID, ACT, a.uploadId);
    const gate = new Gate("A2");
    const rowAtP0Delete: string[] = [];
    w.bucket.hook = async (ph, op, path) => {
      if (ph === phase && op === "save" && path === aPromoted) await gate.hit();
      if (ph === "before" && op === "delete" && path === p0) rowAtP0Delete.push(rowOf(UID, ACT).objectPath);
    };
    const commitA = outcome(commit(w, { activityId: ACT, uploadId: a.uploadId }));
    await gate.reached;
    // While A is paused the row still points at the previous, existing object.
    expect(w.bucket.objects.has(rowOf(UID, ACT).objectPath)).toBe(true);
    expect(rowOf(UID, ACT).objectPath).toBe(p0);

    const b = await stage(w, variant(9));
    await commit(w, { activityId: ACT, uploadId: b.uploadId });
    const bPromoted = streamPath(UID, ACT, b.uploadId);
    expect(rowAtP0Delete).toEqual([bPromoted]);
    gate.release();
    expect(await commitA).toBe("aborted:superseded");
    expect(w.bucket.keys("streams/")).toEqual([bPromoted]);
    expect(w.bucket.keys("quarantine/")).toEqual([]);
  });
});

describe("F86 re-upload over a stored row", () => {
  test("create keeps state=stored, adds the pending marker and the old object stays; the purge predicate still selects the row", async () => {
    const first = await fullUpload(w, variant(1));
    const up2 = uploadOf(variant(2));
    const r = await create(w, { activityId: ACT, bytes: up2.bytes.length, contentSha256: up2.sha });
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row.pendingUploadId).toBe(r.uploadId);
    expect(row.pendingSince.toMillis()).toBe(T0);
    expect(row.objectPath).toBe(streamPath(UID, ACT, first.uploadId));
    expect(w.bucket.objects.has(row.objectPath)).toBe(true);
    // The purge query of design 5.3: state == stored and expiresAt <= now.
    store.set(`users/${UID}/activity_streams/${ACT}`, { ...row, expiresAt: ts(T0 - 1) });
    const snap = await (firestoreInstance as any).collectionGroup("activity_streams").where("state", "==", "stored").where("expiresAt", "<=", ts(T0)).get();
    expect(snap.docs.map((d: any) => d.id)).toEqual([ACT]);
  });
  test("a failed validation of the re-upload clears the pending fields, leaves state=stored and the old object intact", async () => {
    const first = await fullUpload(w, variant(1));
    const bad = variant(2);
    bad.meta.laps[0].hr = 1;
    const s = await stage(w, bad);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("invalid-argument:forbidden_kind");
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    for (const k of ["pendingUploadId", "pendingSince", "pendingContentSha256"]) expect(row).not.toHaveProperty(k);
    expect(row.objectPath).toBe(streamPath(UID, ACT, first.uploadId));
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, first.uploadId)]);
  });
  test("a successful re-upload switches objectPath, clears both pending fields and removes the old object", async () => {
    const first = await fullUpload(w, variant(1));
    const second = await fullUpload(w, variant(2));
    const row = rowOf(UID, ACT);
    expect(row).toMatchObject({ state: "stored", uploadId: second.uploadId, objectPath: streamPath(UID, ACT, second.uploadId) });
    expect(row).not.toHaveProperty("pendingUploadId");
    expect(row).not.toHaveProperty("pendingSince");
    expect(w.bucket.objects.has(streamPath(UID, ACT, first.uploadId))).toBe(false);
    expect(w.bucket.keys()).toHaveLength(1);
  });
  test("when the expiry becomes due while the re-upload is pending, the commit is expired: pending cleared, quarantine deleted, old object kept for the purge", async () => {
    const first = await fullUpload(w, variant(1));
    const s = await stage(w, variant(2));
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:expired");
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("stored");
    expect(row).not.toHaveProperty("pendingUploadId");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, first.uploadId)]);
  });
  test("a never-stored row whose expiry is due at commit is removed and nothing is promoted", async () => {
    const s = await stage(w, variant(2));
    seedConsent(UID, { streamRetentionDays: 90, settingsGeneration: 2 });
    seedSummary(UID, ACT, T0 - 100 * DAY);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:expired");
    expect(rowOf(UID, ACT)).toBeUndefined();
    expect(w.bucket.keys()).toEqual([]);
  });
});
