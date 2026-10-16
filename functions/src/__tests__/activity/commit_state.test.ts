/**
 * F46 sequential idempotency, F47 concurrent commits, F48 transaction 2 and compensation,
 * F49 generation pin. (The plan names four files; they share one setup and live in one.)
 */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import { canonicalStoredBytes } from "../../activity_streams/canonical";
import { validateStreamPayload } from "../../activity_streams/validate";
import {
  ACT, Gate, T0, UID, createWorld, expectHttpsError, fx, releaseClock, resetAll, rowOf, seedReady, sha, store,
  streamPath, quarantinePath, ts, uploadOf, useClock, validPayload, writes, firestoreError, type World,
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

const rowWrites = () => writes.filter((x) => x.path.includes("/activity_streams/")).length;
const err500 = () => Object.assign(new Error("storage down"), { code: 500 });

describe("F46 commit is idempotent (sequential)", () => {
  test("a repeat commit after success: success, no row write, no storage call, no stray quarantine", async () => {
    const { uploadId } = await fullUpload(w);
    const n = rowWrites();
    const calls = w.bucket.totalCalls;
    const again = await commit(w, { activityId: ACT, uploadId });
    expect(again.status).toBe("already_stored");
    expect(rowWrites()).toBe(n);
    expect(w.bucket.totalCalls).toBe(calls);
    expect(w.bucket.keys("quarantine/")).toEqual([]);
    expect(w.bucket.keys("streams/")).toHaveLength(1);
  });
  test("a stale upload id is bare superseded and changes nothing", async () => {
    const a = await stage(w);
    const b = await create(w, { activityId: ACT, bytes: a.up.bytes.length, contentSha256: a.up.sha });
    const before = JSON.stringify(rowOf(UID, ACT));
    const n = rowWrites();
    const err = await expectHttpsError(commit(w, { activityId: ACT, uploadId: a.uploadId }), "aborted", "superseded");
    expect(err.message).toBe("superseded");
    expect(rowWrites()).toBe(n);
    expect(JSON.stringify(rowOf(UID, ACT))).toBe(before);
    expect(rowOf(UID, ACT).uploadId).toBe(b.uploadId);
  });
  test("a commit with no row at all is superseded", async () => {
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: `up_${"c".repeat(32)}` }), "aborted", "superseded");
  });
  test("a retry after a transient failure before promotion succeeds and leaves one object", async () => {
    const s = await stage(w);
    w.bucket.failOn = (op, p) => (op === "getMetadata" ? err500() : undefined);
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: s.uploadId }), "internal", "commit_failed");
    w.bucket.failOn = null;
    const r = await commit(w, { activityId: ACT, uploadId: s.uploadId });
    expect(r.status).toBe("stored");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, s.uploadId)]);
  });
});

describe("F47 concurrent commits", () => {
  test("different upload ids, the older paused after its read: the newer wins, the older is superseded, one row/object/no quarantine", async () => {
    const a = await stage(w);
    const gate = new Gate("afterRead");
    w.bucket.hook = async (phase, op, path) => {
      if (phase === "after" && op === "download" && path === quarantinePath(UID, ACT, a.uploadId)) await gate.hit();
    };
    const commitA = outcome(commit(w, { activityId: ACT, uploadId: a.uploadId }));
    await gate.reached;
    const b = await stage(w, { ...validPayload(), kinds: { speed: { kind: "speed", unit: "m/s", sourceId: "s", offsetsMs: [0, 5], values: [1, 2] } } });
    expect((await commit(w, { activityId: ACT, uploadId: b.uploadId })).status).toBe("stored");
    gate.release();
    expect(await commitA).toBe("aborted:superseded");
    expect(w.bucket.keys()).toEqual([streamPath(UID, ACT, b.uploadId)]);
    expect(rowOf(UID, ACT)).toMatchObject({ state: "stored", uploadId: b.uploadId, objectPath: streamPath(UID, ACT, b.uploadId) });
    expect([...store.keys()].filter((k) => k.includes("/activity_streams/"))).toHaveLength(1);
  });
  test("the same upload id twice at once: both read before either promotes, neither errors, one object of the canonical content", async () => {
    const s = await stage(w);
    let arrived = 0;
    const gate = new Gate("both-read");
    w.bucket.hook = async (phase, op) => {
      if (phase === "after" && op === "download") {
        arrived += 1;
        if (arrived === 2) gate.release();
        await gate.hit();
      }
    };
    const results = await Promise.all([
      commit(w, { activityId: ACT, uploadId: s.uploadId }),
      commit(w, { activityId: ACT, uploadId: s.uploadId }),
    ]);
    expect(arrived).toBe(2);
    const statuses = results.map((r) => r.status).sort();
    expect(statuses).toEqual(["already_stored", "stored"]);
    const path = streamPath(UID, ACT, s.uploadId);
    expect(w.bucket.keys()).toEqual([path]);
    const parsed = validateStreamPayload(validPayload());
    if (!parsed.ok) throw new Error("x");
    expect(w.bucket.objects.get(path)!.content.equals(canonicalStoredBytes(parsed.value))).toBe(true);
    // Every promotion wrote identical content (no two writes of different content).
    expect(new Set(w.bucket.saves.map((x) => x.size)).size).toBe(1);
    expect(rowOf(UID, ACT).state).toBe("stored");
  });
});

describe("F48 transaction 2 is one write with compensation", () => {
  test("a stored row is written in ONE commit with every field together", async () => {
    await fullUpload(w);
    const t2 = writes.filter((x) => x.path.endsWith(`/activity_streams/${ACT}`) && x.data && "objectPath" in x.data);
    expect(t2).toHaveLength(1);
    for (const k of ["state", "bytes", "kinds", "storedSha256", "expiresAt", "settingsGeneration", "objectPath", "pendingUploadId", "pendingSince"]) {
      expect(t2[0].data).toHaveProperty(k);
    }
  });
  test("a failing T2 commit leaves the row pending (never half stored) and the promoted object at the uploadId path (crash window)", async () => {
    const s = await stage(w);
    let n = 0;
    fx.failOn = (op, path) => (op === "commit" && path.includes(`activity_streams/${ACT}`) && ++n === 2 ? firestoreError("lost", 14) : undefined);
    await expectHttpsError(commit(w, { activityId: ACT, uploadId: s.uploadId }), "internal", "commit_failed");
    fx.failOn = null;
    const row = rowOf(UID, ACT);
    expect(row.state).toBe("pending");
    expect(row).not.toHaveProperty("objectPath");
    expect(row).not.toHaveProperty("bytes");
    const obj = w.bucket.objects.get(streamPath(UID, ACT, s.uploadId));
    expect(obj).toBeDefined();
    // The intermediate state the reconciler repairs from (F72/F84).
    expect(row.intendedStoredSha256).toBe(sha(obj!.content));
  });
  const refusals: Array<[string, (s: { uploadId: string }) => Promise<void> | void, string]> = [
    ["fence set after promotion", () => { store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) }); }, "failed-precondition:account_deleting"],
    ["tombstone created after promotion", () => { store.set(`users/${UID}/activity_tombstones/${ACT}`, { deletedAt: ts(T0) }); }, "failed-precondition:deleted"],
    ["upload id replaced after promotion", async () => { await create(w, { activityId: ACT, bytes: 5, contentSha256: "a".repeat(64) }); }, "aborted:superseded"],
  ];
  test.each(refusals)("T2 refusing (%s) compensates: promoted AND quarantine objects removed, row not stored", async (_n, interfere, expected) => {
    const s = await stage(w);
    w.bucket.hook = async (phase, op, path) => {
      if (phase === "after" && op === "save" && path.startsWith("streams/")) await interfere(s);
    };
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe(expected);
    expect(w.bucket.keys(`streams/${UID}/`)).toEqual([]);
    expect(w.bucket.keys(`quarantine/${UID}/${ACT}/${s.uploadId}`)).toEqual([]);
    expect(rowOf(UID, ACT)?.state).not.toBe("stored");
  });
  test("a failure injected in the compensation delete is not retried and does not mask the refusal", async () => {
    const s = await stage(w);
    const promoted = streamPath(UID, ACT, s.uploadId);
    w.bucket.hook = async (phase, op, path) => {
      if (phase === "after" && op === "save" && path === promoted) store.set(`users/${UID}/activity_tombstones/${ACT}`, { deletedAt: ts(T0) });
    };
    w.bucket.failOn = (op, path) => (op === "delete" && path === promoted ? err500() : undefined);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("failed-precondition:deleted");
    expect(w.bucket.deletes.filter((d) => d.path === promoted)).toHaveLength(1);
    expect(w.bucket.objects.has(promoted)).toBe(true); // left for the reconciler, not hidden
  });
  test("the previous object is deleted only AFTER transaction 2 committed", async () => {
    const first = await fullUpload(w);
    const oldPath = streamPath(UID, ACT, first.uploadId);
    const p2 = validPayload();
    p2.kinds.speed.values = [7, 8];
    const second = await stage(w, p2);
    let rowPointedAtNewWhenOldDeleted: string | undefined;
    w.bucket.hook = (phase, op, path) => {
      if (phase === "before" && op === "delete" && path === oldPath) rowPointedAtNewWhenOldDeleted = rowOf(UID, ACT).objectPath;
    };
    await commit(w, { activityId: ACT, uploadId: second.uploadId });
    expect(rowPointedAtNewWhenOldDeleted).toBe(streamPath(UID, ACT, second.uploadId));
    expect(w.bucket.keys("streams/")).toEqual([streamPath(UID, ACT, second.uploadId)]);
  });
  test("with T2 refusing, the old object must still exist", async () => {
    const first = await fullUpload(w);
    const oldPath = streamPath(UID, ACT, first.uploadId);
    const p2 = validPayload();
    p2.kinds.speed.values = [7, 8];
    const second = await stage(w, p2);
    w.bucket.hook = (phase, op, path) => {
      if (phase === "after" && op === "save" && path === streamPath(UID, ACT, second.uploadId)) store.set(`activity_account_state/${UID}`, { fenceAt: ts(T0) });
    };
    await outcome(commit(w, { activityId: ACT, uploadId: second.uploadId }));
    expect(w.bucket.objects.has(oldPath)).toBe(true);
    expect(rowOf(UID, ACT).objectPath).toBe(oldPath);
  });
  test("a failed old-object delete does NOT fail the commit (orphan left for the reconciler)", async () => {
    const first = await fullUpload(w);
    const oldPath = streamPath(UID, ACT, first.uploadId);
    const p2 = validPayload();
    p2.kinds.speed.values = [7, 8];
    const second = await stage(w, p2);
    w.bucket.failOn = (op, path) => (op === "delete" && path === oldPath ? err500() : undefined);
    expect((await commit(w, { activityId: ACT, uploadId: second.uploadId })).status).toBe("stored");
    expect(w.bucket.objects.has(oldPath)).toBe(true);
    expect(rowOf(UID, ACT).objectPath).toBe(streamPath(UID, ACT, second.uploadId));
  });
});

describe("F49 generation pin and validated-equals-promoted", () => {
  test("the quarantine bytes are read exactly once, pinned to the generation seen in the metadata", async () => {
    const s = await stage(w);
    const gen = w.bucket.objects.get(quarantinePath(UID, ACT, s.uploadId))!.generation;
    await commit(w, { activityId: ACT, uploadId: s.uploadId });
    const reads = w.bucket.downloads.filter((d) => d.path === quarantinePath(UID, ACT, s.uploadId));
    expect(reads).toHaveLength(1);
    expect(String(reads[0].generation)).toBe(String(gen));
    expect(w.bucket.metadataCalls.filter((p) => p === quarantinePath(UID, ACT, s.uploadId))).toHaveLength(1);
  });
  test("replacing the object between metadata and read: generation_changed, nothing promoted, quarantine cleaned, row removed", async () => {
    const s = await stage(w);
    const q = quarantinePath(UID, ACT, s.uploadId);
    w.bucket.hook = (phase, op, path) => {
      if (phase === "after" && op === "getMetadata" && path === q) w.bucket.put(q, Buffer.from("replaced"));
    };
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("aborted:generation_changed");
    expect(w.bucket.keys("streams/")).toEqual([]);
    expect(w.bucket.keys("quarantine/")).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("replacing the object AFTER the single read changes nothing that is promoted", async () => {
    const s = await stage(w);
    const q = quarantinePath(UID, ACT, s.uploadId);
    w.bucket.hook = (phase, op, path) => {
      if (phase === "after" && op === "download" && path === q) w.bucket.put(q, Buffer.from("evil bytes after the read"));
    };
    expect((await commit(w, { activityId: ACT, uploadId: s.uploadId })).status).toBe("stored");
    const promoted = w.bucket.objects.get(streamPath(UID, ACT, s.uploadId))!.content;
    const parsed = validateStreamPayload(validPayload());
    if (!parsed.ok) throw new Error("x");
    expect(promoted.equals(canonicalStoredBytes(parsed.value))).toBe(true);
    expect(rowOf(UID, ACT).storedSha256).toBe(sha(promoted));
    expect(w.bucket.keys("quarantine/")).toEqual([]);
  });
  test("an oversize object is refused from the metadata before any download", async () => {
    const s = await stage(w);
    w.bucket.put(quarantinePath(UID, ACT, s.uploadId), Buffer.alloc(5 * 1024 * 1024 + 1, 1));
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("invalid-argument:too_large");
    expect(w.bucket.downloads).toHaveLength(0);
    expect(w.bucket.keys("quarantine/")).toEqual([]);
  });
  test("a missing quarantine object is upload_missing (the PUT never happened)", async () => {
    const up = uploadOf();
    const r = await create(w, { activityId: ACT, bytes: up.bytes.length, contentSha256: up.sha });
    expect(await outcome(commit(w, { activityId: ACT, uploadId: r.uploadId }))).toBe("failed-precondition:upload_missing");
  });
  test("a validation failure deletes the quarantine object, promotes nothing and removes the never-stored row", async () => {
    const bad = validPayload();
    bad.meta.laps[0].avgHrBpm = 150;
    const s = await stage(w, bad);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: s.uploadId }))).toBe("invalid-argument:forbidden_kind");
    expect(w.bucket.keys()).toEqual([]);
    expect(rowOf(UID, ACT)).toBeUndefined();
  });
  test("a hash mismatch between the declared and the uploaded bytes is sha_mismatch", async () => {
    const real = uploadOf();
    const claimed = uploadOf({ ...validPayload(), kinds: { speed: validPayload().kinds.speed } });
    const r = await create(w, { activityId: ACT, bytes: real.bytes.length, contentSha256: claimed.sha });
    w.bucket.put(quarantinePath(UID, ACT, r.uploadId), real.bytes);
    expect(await outcome(commit(w, { activityId: ACT, uploadId: r.uploadId }))).toBe("invalid-argument:sha_mismatch");
    expect(w.bucket.keys()).toEqual([]);
  });
});
