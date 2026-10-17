/** S02-05b: F14-F19, F63-F67, F88, F89 (purge, derived expiry, recompute, index limits). */
jest.mock("firebase-admin", () => require("./support/fakes").adminMock());
jest.mock("firebase-functions/logger", () => require("./support/fakes").loggerMock());

import * as logger from "firebase-functions/logger";
import {
  advanceRecomputeCursor, recomputeUser, runRecomputeContinuation,
} from "../../activity_streams/recompute";
import { purgeRow, runActivityStreamPurge } from "../../activity_streams/purge";
import {
  DEFAULT_RETENTION_LIMITS, effectiveRecomputeCursor, type RetentionDeps, type RetentionLimits,
} from "../../activity_streams/retention";
import {
  DAY, T0, UID, UID_B, createWorld, firestoreError, firestoreInstance, fx, loggedText, releaseClock, resetAll,
  rowOf, settingsOf, store, streamPath, ts, useClock, writes, type World,
} from "./support/fakes";
import { installIndexGuard, loadIndexFile, queryProblem } from "./support/indexes";

let w: World;
const actId = (n: number): string => `act_${n.toString(16).padStart(40, "0")}`;
const deps = (): RetentionDeps => ({
  firestore: () => firestoreInstance as unknown as FirebaseFirestore.Firestore,
  bucket: () => w.bucket,
  nowMs: () => Date.now(),
});
const limits = (o: Partial<RetentionLimits> = {}): RetentionLimits => ({ ...DEFAULT_RETENTION_LIMITS, ...o });
const sumPath = (uid: string, id: string): string => `users/${uid}/activities/${id}`;

interface SeedOpts { startMs?: number; hint?: number | null; state?: string; gen?: number; extra?: Record<string, unknown>; noObject?: boolean }
/** Seeds summary + row (+ object). Default hint is "already past" so the purge query picks the row up. */
function seedStream(uid: string, id: string, o: SeedOpts = {}): string {
  const path = streamPath(uid, id, "up_1");
  store.set(sumPath(uid, id), { startUtc: ts(o.startMs ?? T0 - 100 * DAY), rev: 1 });
  store.set(`users/${uid}/activity_streams/${id}`, {
    state: o.state ?? "stored",
    objectPath: path,
    expiresAt: o.hint === null ? null : ts(o.hint ?? T0 - 1),
    settingsGeneration: o.gen ?? 1,
    ...(o.extra ?? {}),
  });
  if (!o.noObject) w.bucket.put(path, Buffer.from("x"));
  return path;
}
function seedSettings(uid: string, days: number | null, extra: Record<string, unknown> = {}): void {
  store.set(`users/${uid}/activity_settings/main`, { streamRetentionDays: days, settingsGeneration: 1, ...extra });
}

beforeEach(() => {
  resetAll();
  useClock(T0);
  w = createWorld();
  (logger.info as jest.Mock).mockClear();
});
afterEach(() => releaseClock());

describe("F15 purge decision uses the DERIVED expiry (boundaries)", () => {
  test("due at now and now-1ms is purged, now+1ms is not, summary survives, other user purged, a stored null is the 730 day default (not 'never')", async () => {
    seedSettings(UID, 90);
    seedSettings(UID_B, 90);
    const ids = { eq: actId(1), before: actId(2), after: actId(3), never: actId(4), other: actId(5), nullOld: actId(6) };
    const pEq = seedStream(UID, ids.eq, { startMs: T0 - 90 * DAY });
    const pBefore = seedStream(UID, ids.before, { startMs: T0 - 90 * DAY - 1 });
    const pAfter = seedStream(UID, ids.after, { startMs: T0 - 90 * DAY + 1 });
    seedStream(UID_B, ids.other, { startMs: T0 - 91 * DAY });
    seedSettings("uid_never", null);
    const pNever = seedStream("uid_never", ids.never, { startMs: T0 - 729 * DAY });
    const pNullOld = seedStream("uid_never", ids.nullOld, { startMs: T0 - 900 * DAY });

    const r = await runActivityStreamPurge(deps(), limits());

    expect(rowOf(UID, ids.eq).state).toBe("expired");
    expect(rowOf(UID, ids.before).state).toBe("expired");
    expect(rowOf(UID_B, ids.other).state).toBe("expired");
    expect(rowOf(UID, ids.after).state).toBe("stored");
    expect(rowOf("uid_never", ids.never).state).toBe("stored");
    expect(w.bucket.objects.has(pEq)).toBe(false);
    expect(w.bucket.objects.has(pBefore)).toBe(false);
    expect(w.bucket.objects.has(pAfter)).toBe(true);
    expect(w.bucket.objects.has(pNever)).toBe(true);
    // a stored null no longer means "never": the 900 day old stream is purged under the 730 day default
    expect(rowOf("uid_never", ids.nullOld).state).toBe("expired");
    expect(w.bucket.objects.has(pNullOld)).toBe(false);
    for (const id of [ids.eq, ids.before, ids.after]) expect(store.has(sumPath(UID, id))).toBe(true);
    expect(r.purged).toBe(4);
    // the not-due row got its hint rewritten to the derived value (the hint can only ever follow the derivation)
    expect(rowOf(UID, ids.after).expiresAt.toMillis()).toBe(T0 + 1);
    expect(rowOf("uid_never", ids.never).expiresAt.toMillis()).toBe(T0 + 1 * DAY);
  });
});

describe("F16 second run is a no-op", () => {
  test("no storage delete and no row write on the second run", async () => {
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { startMs: T0 - 91 * DAY });
    await runActivityStreamPurge(deps(), limits());
    const deletes = w.bucket.deletes.length;
    const wr = writes.length;
    const r = await runActivityStreamPurge(deps(), limits());
    expect(r.purged).toBe(0);
    expect(w.bucket.deletes.length).toBe(deletes);
    expect(w.bucket.deleteFilesCalls.length).toBe(0);
    expect(writes.length).toBe(wr);
  });
});

describe("F17 purge failures", () => {
  test("a non-404 storage error keeps the row stored; a 404 counts as success", async () => {
    seedSettings(UID, 90);
    const a = actId(1);
    const b = actId(2);
    seedStream(UID, a, { startMs: T0 - 91 * DAY });
    seedStream(UID, b, { startMs: T0 - 91 * DAY, noObject: true }); // object already gone (404)
    w.bucket.failOn = (op, path) => (op === "delete" && path.includes(a) ? Object.assign(new Error("boom"), { code: 500 }) : null);
    const r = await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, a).state).toBe("stored");
    expect(rowOf(UID, a).purgeAttempts).toBe(1);
    expect(rowOf(UID, b).state).toBe("expired");
    expect(r.failures).toBe(1);
    expect(r.purged).toBe(1);
  });
  test("an exhausted run budget stops new work and the next run continues", async () => {
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { startMs: T0 - 91 * DAY });
    const r1 = await runActivityStreamPurge(deps(), limits({ runBudgetMs: 0 }));
    expect(r1.budgetExhausted).toBe(true);
    expect(rowOf(UID, actId(1)).state).toBe("stored");
    const r2 = await runActivityStreamPurge(deps(), limits());
    expect(r2.purged).toBe(1);
    expect(rowOf(UID, actId(1)).state).toBe("expired");
  });
});

describe("F18 shorten and lengthen", () => {
  test("shortening: not due until the hints are rewritten, then purged by the recompute of the same run", async () => {
    const id = actId(1);
    const p = seedStream(UID, id, { startMs: T0 - 100 * DAY, hint: T0 + 265 * DAY });
    seedSettings(UID, 90, { settingsGeneration: 2 }); // shortened 365 -> 90 days, no recompute flag yet
    await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, id).state).toBe("stored");
    expect(w.bucket.objects.has(p)).toBe(true);
    settingsOf(UID).recomputePending = true;
    const r = await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, id).state).toBe("expired");
    expect(w.bucket.objects.has(p)).toBe(false);
    expect(r.recompute?.usersCompleted).toBe(1);
    expect(settingsOf(UID).recomputePending).toBe(false);
  });
  test("lengthening does not resurrect an expired row (design 5.3 wins over the plan wording)", async () => {
    const id = actId(1);
    seedStream(UID, id, { state: "expired", startMs: T0 - 100 * DAY, hint: T0 - 70 * DAY });
    seedSettings(UID, null, { settingsGeneration: 3, recomputePending: true });
    await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, id).state).toBe("expired");
    expect(settingsOf(UID).recomputePending).toBe(false);
    expect(rowOf(UID, id).settingsGeneration).toBe(3); // only stamped
  });
});

describe("F19 overdue metric", () => {
  test("oldest overdue age is reported for a failing row and no log field holds a uid, id or path", async () => {
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { startMs: T0 - 93 * DAY, hint: T0 - 3 * DAY });
    w.bucket.failOn = (op) => (op === "delete" ? Object.assign(new Error(`bad ${UID}`), { code: 500 }) : null);
    const r = await runActivityStreamPurge(deps(), limits());
    expect(r.oldestOverdueAgeMs).toBe(3 * DAY);
    const text = loggedText(logger);
    expect(text).toContain("oldestOverdueAgeMs");
    expect(text).not.toContain(UID);
    expect(text).not.toContain(actId(1));
    expect(text).not.toContain("streams/");
  });
});

describe("F63 the hint never decides", () => {
  test("(a) hint in the past but retention lengthened: object kept and hint rewritten", async () => {
    const id = actId(1);
    const p = seedStream(UID, id, { startMs: T0 - 90 * DAY, hint: T0 - 1 });
    seedSettings(UID, 365);
    await runActivityStreamPurge(deps(), limits());
    expect(w.bucket.objects.has(p)).toBe(true);
    expect(rowOf(UID, id).state).toBe("stored");
    expect(rowOf(UID, id).expiresAt.toMillis()).toBe(T0 - 90 * DAY + 365 * DAY);
  });
  test("(b) hint in the future with a shortened setting: not purged by the walk, purged after the recompute", async () => {
    const id = actId(1);
    seedStream(UID, id, { startMs: T0 - 100 * DAY, hint: T0 + 265 * DAY });
    seedSettings(UID, 90, { settingsGeneration: 2 });
    await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, id).state).toBe("stored");
    settingsOf(UID).recomputePending = true;
    await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, id).state).toBe("expired");
  });
  test("(c) a hint that says due while the derivation says not due never purges", async () => {
    const d = actId(1);
    const p = seedStream(UID, d, { startMs: T0 - 1 * DAY, hint: T0 - 10 * DAY });
    seedSettings(UID, 90);
    const res = await purgeRow(deps(), limits(), w.bucket, UID, d, T0);
    expect(res.outcome).toBe("rehinted");
    expect(w.bucket.objects.has(p)).toBe(true);
  });
  test("the start date is clamped to [2000-01-01, now] and no request value is read", async () => {
    seedSettings(UID, 90);
    const old = actId(1);
    const fut = actId(2);
    seedStream(UID, old, { startMs: Date.UTC(1990, 0, 1) });
    seedStream(UID, fut, { startMs: T0 + 365 * DAY });
    await runActivityStreamPurge(deps(), limits());
    expect(rowOf(UID, old).state).toBe("expired"); // 2000-01-01 + 30 d is long past
    expect(rowOf(UID, fut).state).toBe("stored"); // clamped to now: due in 30 d
    expect(rowOf(UID, fut).expiresAt.toMillis()).toBe(T0 + 90 * DAY);
  });
});

describe("F64 per-candidate transaction", () => {
  test("a row no longer stored is skipped without any storage call", async () => {
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { state: "deleted", startMs: T0 - 100 * DAY });
    const res = await purgeRow(deps(), limits(), w.bucket, UID, actId(1), T0);
    expect(res.outcome).toBe("skipped");
    expect(w.bucket.totalCalls).toBe(0);
  });
  test("the object goes first; a crash before the row write is finished by the rerun without a storage error", async () => {
    seedSettings(UID, 90);
    const id = actId(1);
    const p = seedStream(UID, id, { startMs: T0 - 100 * DAY });
    const order: string[] = [];
    w.bucket.hook = (phase, op) => { if (phase === "after" && op === "delete") order.push(`row:${rowOf(UID, id).state}`); };
    fx.failOn = (op, path) => (op === "commit" && path.includes(`activity_streams/${id}`) ? firestoreError("killed", 14) : undefined);
    await expect(purgeRow(deps(), limits(), w.bucket, UID, id, T0)).rejects.toBeDefined();
    expect(order).toEqual(["row:stored"]); // object deleted while the row was still stored
    expect(w.bucket.objects.has(p)).toBe(false);
    expect(rowOf(UID, id).state).toBe("stored");
    fx.failOn = null;
    w.bucket.failOn = (op) => (op === "delete" ? Object.assign(new Error("x"), { code: 500 }) : null);
    w.bucket.failOn = null;
    const again = await purgeRow(deps(), limits(), w.bucket, UID, id, T0);
    expect(again.outcome).toBe("purged");
    expect(rowOf(UID, id).state).toBe("expired");
  });
  test("a failure records purgeAttempts, a bare lastErrorCode and lastPurgeAttemptAt", async () => {
    seedSettings(UID, 90);
    const id = actId(1);
    seedStream(UID, id, { startMs: T0 - 100 * DAY, extra: { purgeAttempts: 2 } });
    w.bucket.failOn = (op) => (op === "delete" ? Object.assign(new Error(`secret ${UID}`), { code: "storage/denied" }) : null);
    await purgeRow(deps(), limits(), w.bucket, UID, id, T0);
    const row = rowOf(UID, id);
    expect(row.state).toBe("stored");
    expect(row.purgeAttempts).toBe(3);
    expect(row.lastErrorCode).toBe("storage/denied");
    expect(row.lastPurgeAttemptAt.toMillis()).toBe(T0);
    expect(String(row.lastErrorCode)).not.toContain("secret"); // never the SDK message
  });
});

describe("F65 no give-up state", () => {
  test("a row beyond the attempt cap is retried every run, counted as capped, and purged on recovery with counters cleared", async () => {
    seedSettings(UID, 90);
    const id = actId(1);
    const p = seedStream(UID, id, { startMs: T0 - 100 * DAY, extra: { purgeAttempts: 5, lastErrorCode: "500" } });
    w.bucket.failOn = (op) => (op === "delete" ? Object.assign(new Error("x"), { code: 500 }) : null);
    const lim = limits({ maxPurgeAttempts: 2 });
    const r1 = await runActivityStreamPurge(deps(), lim);
    const r2 = await runActivityStreamPurge(deps(), lim);
    expect(w.bucket.deletes.length).toBe(2); // attempted on BOTH runs
    expect(r1.cappedRows).toBe(1);
    expect(r2.cappedRows).toBe(1);
    expect(rowOf(UID, id).purgeAttempts).toBe(7);
    expect(r2.oldestOverdueAgeMs).toBeGreaterThan(0);
    w.bucket.failOn = null;
    await runActivityStreamPurge(deps(), lim);
    expect(w.bucket.objects.has(p)).toBe(false);
    const row = rowOf(UID, id);
    expect(row.state).toBe("expired");
    expect(row.purgeAttempts).toBe(0);
    expect(row.lastErrorCode).toBeUndefined();
  });
});

function seedRecompute(uid: string, n: number, gen = 2): void {
  seedSettings(uid, 90, { settingsGeneration: gen, recomputePending: true });
  for (let i = 1; i <= n; i++) seedStream(uid, actId(i), { startMs: T0 - 5 * DAY, hint: T0 + 399 * DAY, gen: 1, noObject: true });
}
const rowWrites = (id: string): number => writes.filter((x) => x.path.endsWith(`/activity_streams/${id}`)).length;
const far = (): number => Date.now() + 1e9;

describe("F14/F66 recompute is paged, idempotent and resumable", () => {
  test("250 rows, page 100: a crash on page 2 keeps the cursor, the rerun writes every row exactly once and clears the flag", async () => {
    seedRecompute(UID, 250);
    const lim = limits({ recomputePage: 100 });
    const crashRow = actId(150);
    fx.failOn = (op, path) => (op === "commit" && path === `users/${UID}/activity_streams/${crashRow}` ? firestoreError("crash", 14) : undefined);
    const failures: unknown[] = [];
    const r1 = await runRecomputeContinuation(deps(), lim, T0, far(), (e) => failures.push(e));
    expect(failures).toHaveLength(1);
    expect(r1.backlogUsers).toBe(1);
    expect(settingsOf(UID).recomputeCursor).toBe(actId(100));
    expect(settingsOf(UID).recomputeGeneration).toBe(2);
    expect(settingsOf(UID).recomputePending).toBe(true);
    fx.failOn = null;
    await runRecomputeContinuation(deps(), lim, T0, far(), (e) => failures.push(e));
    expect(failures).toHaveLength(1);
    for (let i = 1; i <= 250; i++) {
      const row = rowOf(UID, actId(i));
      expect(row.settingsGeneration).toBe(2);
      expect(row.expiresAt.toMillis()).toBe(T0 - 5 * DAY + 90 * DAY);
      expect(rowWrites(actId(i))).toBe(1 + (i <= 100 ? 0 : 0)); // rows 1..100 were NOT rewritten by the rerun
    }
    expect(settingsOf(UID).recomputePending).toBe(false);
    expect(settingsOf(UID).recomputeCursor).toBeNull();
  });
  test("idempotent: a clean rerun writes nothing; unchanged rows are not rewritten", async () => {
    seedRecompute(UID, 3);
    await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    const n = writes.length;
    settingsOf(UID).recomputePending = true;
    await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    expect(writes.filter((x) => x.path.includes("activity_streams")).length).toBe(3);
    expect(writes.length - n).toBeLessThanOrEqual(1); // only the settings flag clear
  });
  test("the purge run starts the continuation and the shared budget stops it; the next run resumes", async () => {
    seedRecompute(UID, 3);
    const r1 = await runActivityStreamPurge(deps(), limits({ runBudgetMs: 0 }));
    expect(r1.recompute?.rowsWritten).toBe(0);
    expect(settingsOf(UID).recomputePending).toBe(true);
    const r2 = await runActivityStreamPurge(deps(), limits());
    expect(r2.recompute?.rowsWritten).toBe(3);
    expect(settingsOf(UID).recomputePending).toBe(false);
  });
  test("a page cap per user lets the next run resume after the persisted cursor", async () => {
    seedRecompute(UID, 5);
    const lim = limits({ recomputePage: 2, recomputePagesPerUser: 1 });
    await runRecomputeContinuation(deps(), lim, T0, far(), () => undefined);
    expect(settingsOf(UID).recomputeCursor).toBe(actId(2));
    await runRecomputeContinuation(deps(), lim, T0, far(), () => undefined);
    expect(settingsOf(UID).recomputeCursor).toBe(actId(4));
    await runRecomputeContinuation(deps(), lim, T0, far(), () => undefined);
    for (let i = 1; i <= 5; i++) expect(rowWrites(actId(i))).toBe(1);
  });
});

describe("F67 recompute generation races", () => {
  test("a row committed with the older generation after its page was passed is caught by the final pass", async () => {
    seedRecompute(UID, 3);
    const late = actId(0); // sorts before the cursor
    let injected = false;
    fx.afterCommit = (paths) => {
      if (!injected && paths.some((x) => x.endsWith(actId(2)))) {
        injected = true;
        seedStream(UID, late, { startMs: T0 - 5 * DAY, hint: T0 + 399 * DAY, gen: 1, noObject: true });
      }
    };
    await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    expect(rowOf(UID, late).settingsGeneration).toBe(2);
    expect(rowOf(UID, late).expiresAt.toMillis()).toBe(T0 - 5 * DAY + 90 * DAY);
    expect(settingsOf(UID).recomputePending).toBe(false);
  });
  test("a second setting change resets the cursor and the walk restarts from the beginning", async () => {
    seedRecompute(UID, 4);
    const lim = limits({ recomputePage: 2, recomputePagesPerUser: 1 });
    await runRecomputeContinuation(deps(), lim, T0, far(), () => undefined);
    expect(effectiveRecomputeCursor(settingsOf(UID))).toBe(actId(2));
    settingsOf(UID).settingsGeneration = 3; // changed again
    expect(effectiveRecomputeCursor(settingsOf(UID))).toBeUndefined();
    await runRecomputeContinuation(deps(), lim, T0, far(), () => undefined);
    expect(rowOf(UID, actId(1)).settingsGeneration).toBe(3); // revisited under the newest setting
  });
  test("the cursor advance and the clear are refused when the generation moved", async () => {
    seedRecompute(UID, 1);
    expect(await advanceRecomputeCursor(deps(), UID, 1, actId(1))).toBe(false);
    expect(settingsOf(UID).recomputeCursor).toBeUndefined();
    expect(await advanceRecomputeCursor(deps(), UID, 2, actId(1))).toBe(true);
    const res = await recomputeUser(deps(), limits(), UID, T0, far());
    expect(res.completed).toBe(true);
  });
});

describe("F89 recompute discovery", () => {
  test("25 pending users: 20 processed per run, 5 left; a user not pending is untouched", async () => {
    for (let i = 0; i < 25; i++) seedRecompute(`uid_p${String(i).padStart(2, "0")}`, 1);
    seedSettings("uid_idle", 90, { recomputePending: false });
    store.set(`users/uid_idle/activity_streams/${actId(1)}`, { state: "stored", settingsGeneration: 0, expiresAt: null });
    const r = await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    expect(r.usersSelected).toBe(20);
    expect(r.usersCompleted).toBe(20);
    const stillPending = [...store.entries()].filter(([k, d]) => k.endsWith("/activity_settings/main") && d.recomputePending === true);
    expect(stillPending).toHaveLength(5);
    expect(store.get(`users/uid_idle/activity_streams/${actId(1)}`)!.settingsGeneration).toBe(0);
    const q = (await import("./support/fakes")).store; // same store
    expect(q.get(`users/uid_idle/activity_settings/main`)!.recomputePending).toBe(false);
    const r2 = await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    expect(r2.usersCompleted).toBe(5);
  });
  test("the discovery query is the collection group activity_settings on recomputePending == true", async () => {
    seedRecompute(UID, 1);
    const seen: string[] = [];
    fx.checkQuery = (q) => seen.push(`${q.kind}:${q.name}:${q.filters.map((f) => `${f.f}${f.op}${f.v}`).join(",")}`);
    await runRecomputeContinuation(deps(), limits(), T0, far(), () => undefined);
    expect(seen[0]).toBe("group:activity_settings:recomputePending==true");
  });
});

describe("F88 the fake enforces index and query limits", () => {
  const file = loadIndexFile();
  test("the two real queries of design 5.3 pass with the merged index file", async () => {
    installIndexGuard(file);
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { startMs: T0 - 100 * DAY });
    seedSettings("uid_x", 90, { recomputePending: true });
    const r = await runActivityStreamPurge(deps(), limits());
    expect(r.missingIndex).toBe(false);
    expect(r.purged).toBe(1);
  });
  test("a group query without a matching entry fails with FAILED_PRECONDITION (the proof the fake can fail)", async () => {
    installIndexGuard({ indexes: file.indexes.filter((i) => i.collectionGroup !== "activity_streams"), fieldOverrides: file.fieldOverrides });
    seedSettings(UID, 90);
    seedStream(UID, actId(1), { startMs: T0 - 100 * DAY });
    const r = await runActivityStreamPurge(deps(), limits());
    expect(r.missingIndex).toBe(true); // F71 row 9
    expect(rowOf(UID, actId(1)).state).toBe("stored");
    await expect(
      firestoreInstance.collectionGroup("activity_streams").where("state", "==", "stored").where("expiresAt", "<=", 1).orderBy("expiresAt").get(),
    ).rejects.toMatchObject({ code: 9 });
  });
  test("inequalities on two fields, and the withdrawn cross-field shape, are rejected", () => {
    const q = (filters: Array<{ f: string; op: string; v: unknown }>, orders: string[] = []) =>
      queryProblem({ kind: "group", name: "activity_streams", filters: filters as never, orders }, file);
    expect(q([{ f: "settingsGeneration", op: "<", v: 3 }, { f: "expiresAt", op: "<=", v: 1 }])).toMatch(/more than one field/);
    expect(q([{ f: "state", op: "==", v: "stored" }, { f: "expiresAt", op: "<=", v: 1 }], ["expiresAt"])).toBeUndefined();
    expect(q([{ f: "recomputePending", op: "==", v: true }])).toMatch(/missing/); // no override for this group name
    expect(queryProblem({ kind: "group", name: "activity_settings", filters: [{ f: "recomputePending", op: "==", v: true }], orders: [] }, file)).toBeUndefined();
    expect(queryProblem({ kind: "group", name: "activity_streams", filters: [{ f: "settingsGeneration", op: "<", v: 3 }], orders: [] }, file)).toMatch(/missing/);
  });
});
