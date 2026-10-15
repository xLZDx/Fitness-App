/**
 * Durable account-deletion reconciliation (reviewer MAJOR-03).
 *
 * Before the fix, a failed final sweep of `deleteAccount` (the one that runs
 * after `admin.auth().deleteUser`) was logged and swallowed: the Auth user was
 * gone, so the client could not retry, and whatever a raced webhook had
 * re-created under `users/{uid}` stayed forever. Now the failure is recorded in
 * `accountDeletionRetries/{uid}` and `reconcileAccountDeletions` (a scheduled
 * function with NO user authentication) re-runs the same sweep.
 *
 * Unlike delete_account.test.ts, whose Firestore mock is stateless, this file
 * uses a small STATEFUL in-memory Firestore: documents live in one map keyed by
 * path, `recursiveDelete` really removes everything under a path, queries
 * really filter/order/limit, write batches really apply, and transactions are
 * optimistic (commit-time validation + retry, with an interleaving hook for
 * concurrent-sweep tests; booking rows are settled by them). That is what lets
 * the acceptance test assert "the data is gone afterwards" rather than "a mock
 * was called". The module under test is the real `../index`.
 *
 * Modelled: `users/{uid}/...` (recursive), `donor_wall/{uid}`,
 * `coach_listings/{uid}`, the three shared-record collections
 * (`coach_bookings`, `equipment_reports`, `debug_sessions`) and
 * `accountDeletionRetries`. Time is a controllable `Date.now` spy.
 */

type Doc = Record<string, any>;
const store = new Map<string, Doc>();

/** Failure switches and call logs; reset in beforeEach. */
const sw: {
  recursiveFails: (path: string) => boolean;
  failRecordWrite: boolean;
  failDueQuery: Error | null;
  failBatchCommit: boolean;
  /** A recursiveDelete that never settles (a hung or killed invocation). */
  recursiveHang: boolean;
  /** Throws this exact value (even a non-Error) from recursiveDelete. */
  recursiveThrow: (() => unknown) | null;
  /** Side effect at the start of every recursiveDelete (e.g. advance the clock). */
  onSweep: ((path: string) => void) | null;
  /** Makes every transaction commit fail (a booking-sweep transaction abort). */
  failTxCommit: boolean;
  /**
   * Awaited inside a transaction right after each `tx.get`, BEFORE the commit.
   * This is the interleaving point: two concurrent transactions can both be
   * held here after reading, then released, so both commit from their reads.
   */
  afterTxRead: ((path: string, attempt: number) => Promise<void>) | null;
} = {
  recursiveFails: () => false,
  failRecordWrite: false,
  failDueQuery: null,
  failBatchCommit: false,
  recursiveHang: false,
  recursiveThrow: null,
  onSweep: null,
  failTxCommit: false,
  afterTxRead: null,
};
/** Transaction accounting: committed writes and optimistic-conflict retries. */
const txCommitted: Array<{ op: "update" | "delete"; path: string; attempt: number }> = [];
let txRetries = 0;
const writes: Array<{ op: "set" | "delete"; path: string; merge: boolean }> = [];
const queries: Array<{
  col: string;
  filters: Array<{ f: string; op: string; v: any }>;
  order?: string;
  max: number;
}> = [];
const recursiveDeletedPaths: string[] = [];

const tsValue = (x: any): any =>
  x && typeof x === "object" && "__ts" in x ? x.__ts : x;

const firestoreError = (message: string, code: string): Error =>
  Object.assign(new Error(message), { code });

const refOf = (path: string): any => ({
  path,
  id: path.split("/").pop(),
  get: async () => ({
    exists: store.has(path),
    id: path.split("/").pop(),
    data: () => (store.has(path) ? { ...store.get(path) } : undefined),
  }),
  set: async (data: Doc, options?: { merge?: boolean }) => {
    if (sw.failRecordWrite && path.startsWith("accountDeletionRetries/")) {
      throw firestoreError("record write failed for user@example.com", "unavailable");
    }
    writes.push({ op: "set", path, merge: !!options?.merge });
    store.set(
      path,
      options?.merge ? { ...(store.get(path) ?? {}), ...data } : { ...data },
    );
  },
  delete: async () => {
    writes.push({ op: "delete", path, merge: false });
    store.delete(path);
  },
  collection: (name: string) => collectionOf(`${path}/${name}`),
});

const makeQuery = (
  col: string,
  filters: Array<{ f: string; op: string; v: any }> = [],
  order?: string,
  max = Infinity,
): any => ({
  where: (f: string, op: string, v: any) =>
    makeQuery(col, [...filters, { f, op, v }], order, max),
  orderBy: (f: string) => makeQuery(col, filters, f, max),
  limit: (n: number) => makeQuery(col, filters, order, n),
  get: async () => {
    queries.push({ col, filters, order, max });
    if (col === "accountDeletionRetries" && sw.failDueQuery) {
      throw sw.failDueQuery;
    }
    let rows = [...store.entries()].filter(
      ([p]) => p.startsWith(`${col}/`) && !p.slice(col.length + 1).includes("/"),
    );
    rows = rows.filter(([, d]) =>
      filters.every(({ f, op, v }) => {
        // Firestore excludes documents that lack the filtered field.
        if (!(f in d)) return false;
        const a = tsValue(d[f]);
        const b = tsValue(v);
        if (op === "==") return a === b;
        if (op === "<=") return a <= b;
        throw new Error(`fake firestore: unsupported operator ${op}`);
      }),
    );
    if (order) {
      rows.sort((x, y) => tsValue(x[1][order]) - tsValue(y[1][order]));
    }
    return {
      docs: rows.slice(0, max).map(([p, d]) => ({
        id: p.split("/").pop(),
        ref: refOf(p),
        data: () => ({ ...d }),
      })),
    };
  },
});

const collectionOf = (name: string): any => ({
  doc: (id: string) => refOf(`${name}/${id}`),
  ...makeQuery(name),
});

const recursiveDelete = jest.fn(async (ref: { path: string }) => {
  recursiveDeletedPaths.push(ref.path);
  if (sw.onSweep) sw.onSweep(ref.path);
  if (sw.recursiveHang) await new Promise<void>(() => undefined);
  if (sw.recursiveThrow) throw sw.recursiveThrow();
  if (sw.recursiveFails(ref.path)) {
    throw firestoreError("firestore down for user@example.com", "unavailable");
  }
  for (const key of [...store.keys()]) {
    if (key === ref.path || key.startsWith(`${ref.path}/`)) store.delete(key);
  }
});
const deleteUser = jest.fn(async (_uid?: string) => undefined);
const revokeRefreshTokens = jest.fn(async (_uid?: string) => undefined);
const notFound = (): Error =>
  Object.assign(new Error("There is no user record"), { code: "auth/user-not-found" });
/** Default: the Auth user is gone, which is the state a real reconciliation sees. */
const getUser = jest.fn(async (_uid?: string): Promise<unknown> => {
  throw notFound();
});

jest.mock("firebase-admin", () => {
  const firestoreFn: any = jest.fn(() => ({
    doc: (path: string) => refOf(path),
    collection: (name: string) => collectionOf(name),
    batch: () => {
      const pending: Array<{ op: "update" | "delete"; path: string; data?: Doc }> = [];
      return {
        update: (ref: any, data: Doc) => pending.push({ op: "update", path: ref.path, data }),
        delete: (ref: any) => pending.push({ op: "delete", path: ref.path }),
        commit: async () => {
          if (sw.failBatchCommit) {
            throw firestoreError("batch commit failed", "aborted");
          }
          for (const p of pending) {
            if (p.op === "delete") store.delete(p.path);
            else if (store.has(p.path)) {
              store.set(p.path, { ...store.get(p.path), ...p.data });
            }
          }
        },
      };
    },
    /**
     * A faithful optimistic transaction. Reads see COMMITTED state only;
     * writes are buffered and applied atomically at commit; if any document
     * the transaction read changed before its commit, nothing is applied and
     * the callback re-runs on fresh state (as Firestore retries on
     * contention), up to 5 attempts, then `aborted`. `update` of a missing
     * document fails with `not-found` as in Firestore. Commit validation and
     * apply contain no `await`, so they are atomic under the JS event loop.
     */
    runTransaction: async (fn: (tx: any) => Promise<unknown>) => {
      for (let attempt = 1; attempt <= 5; attempt++) {
        const reads = new Map<string, string>();
        const pending: Array<{ op: "update" | "delete"; path: string; data?: Doc }> = [];
        const tx = {
          get: async (ref: any) => {
            const current = store.get(ref.path);
            reads.set(ref.path, JSON.stringify(current ?? null));
            const snap = {
              exists: current !== undefined,
              id: ref.id,
              ref,
              data: () => (current !== undefined ? { ...current } : undefined),
            };
            if (sw.afterTxRead) await sw.afterTxRead(ref.path, attempt);
            return snap;
          },
          update: (ref: any, data: Doc) => {
            pending.push({ op: "update", path: ref.path, data });
          },
          delete: (ref: any) => {
            pending.push({ op: "delete", path: ref.path });
          },
        };
        const result = await fn(tx);
        if (sw.failTxCommit) throw firestoreError("transaction commit failed", "aborted");
        const stale = [...reads].some(
          ([p, seen]) => JSON.stringify(store.get(p) ?? null) !== seen,
        );
        if (stale) {
          txRetries++;
          continue;
        }
        for (const p of pending) {
          if (p.op === "update" && !store.has(p.path)) {
            throw firestoreError("no document to update", "not-found");
          }
        }
        for (const p of pending) {
          if (p.op === "delete") store.delete(p.path);
          else store.set(p.path, { ...store.get(p.path), ...p.data });
          txCommitted.push({ op: p.op, path: p.path, attempt });
        }
        return result;
      }
      throw firestoreError("too much contention", "aborted");
    },
    recursiveDelete,
  }));
  firestoreFn.Timestamp = { fromMillis: (ms: number) => ({ __ts: ms }) };
  return {
    initializeApp: jest.fn(),
    firestore: firestoreFn,
    auth: jest.fn(() => ({ deleteUser, revokeRefreshTokens, getUser })),
  };
});

jest.mock("stripe", () => {
  const instance = {
    subscriptions: { cancel: jest.fn(), retrieve: jest.fn(), list: jest.fn() },
  };
  const ctor: any = jest.fn(() => instance);
  ctor.__instance = instance;
  return ctor;
});

jest.mock("firebase-functions/logger", () => ({
  debug: jest.fn(),
  info: jest.fn(),
  warn: jest.fn(),
  error: jest.fn(),
}));

/**
 * C12: the account sweep also deletes the user's objects in the private
 * body-scan bucket. Storage is modelled by `deleteFiles` only.
 */
const storageDeleteFiles = jest.fn(async (_opts?: unknown) => undefined as unknown);
const storageBucket = jest.fn((_name?: string) => ({ deleteFiles: storageDeleteFiles }));
jest.mock("firebase-admin/storage", () => ({
  getStorage: jest.fn(() => ({ bucket: storageBucket })),
}));

import * as logger from "firebase-functions/logger";
import { deleteAccount, reconcileAccountDeletions } from "../index";

const MIN = 60 * 1000;
const HOUR = 60 * MIN;
const DAY = 24 * HOUR;
const T0 = Date.UTC(2026, 9, 14, 12, 0, 0);
const U = "uid_deleted";
const RECORD = `accountDeletionRetries/${U}`;

let now = T0;
let dateSpy: jest.SpyInstance;

const ts = (ms: number) => ({ __ts: ms });

function seedRecord(
  uid: string,
  o: {
    status?: string;
    attempts?: number;
    nextAttemptAt?: number;
    createdAt?: number;
  } = {},
): void {
  store.set(`accountDeletionRetries/${uid}`, {
    uid,
    status: o.status ?? "pending",
    attempts: o.attempts ?? 1,
    createdAt: ts(o.createdAt ?? T0),
    nextAttemptAt: ts(o.nextAttemptAt ?? T0 + 15 * MIN),
    lastErrorCode: "unavailable",
    expireAt: ts(T0 + 30 * DAY),
  });
}

const keysUnder = (prefix: string): string[] =>
  [...store.keys()].filter((k) => k === prefix || k.startsWith(`${prefix}/`));
const recordKeys = (): string[] =>
  [...store.keys()].filter((k) => k.startsWith("accountDeletionRetries/"));

const callReq = (uid: string): any => ({ data: {}, auth: { uid }, rawRequest: {} });
/** A scheduler invocation: no auth, no user, only the schedule metadata. */
const runReconciler = (): Promise<void> =>
  (reconcileAccountDeletions as any).run({ scheduleTime: new Date(now).toISOString() });

const logged = (level: "info" | "warn" | "error", event: string): any[] =>
  (logger[level] as jest.Mock).mock.calls.filter((c) => c[0] === event);

/** Seeds one full user footprint: uid-keyed docs plus rows that only mention the uid. */
function seedUserData(uid: string): void {
  store.set(`users/${uid}`, { displayName: "Test" });
  store.set(`users/${uid}/profile/main`, { name: "Test" });
  store.set(`users/${uid}/workouts/w1`, { sets: 3 });
  store.set(`donor_wall/${uid}`, { name: "Test" });
  store.set(`coach_listings/${uid}`, { bio: "x" });
}

beforeEach(() => {
  store.clear();
  writes.length = 0;
  queries.length = 0;
  recursiveDeletedPaths.length = 0;
  sw.recursiveFails = () => false;
  sw.failRecordWrite = false;
  sw.failDueQuery = null;
  sw.failBatchCommit = false;
  sw.recursiveHang = false;
  sw.recursiveThrow = null;
  sw.onSweep = null;
  sw.failTxCommit = false;
  sw.afterTxRead = null;
  txCommitted.length = 0;
  txRetries = 0;
  recursiveDelete.mockClear();
  storageDeleteFiles.mockReset().mockResolvedValue(undefined);
  storageBucket.mockClear();
  delete process.env.BODY_SCAN_BUCKET;
  getUser.mockReset().mockImplementation(async () => {
    throw notFound();
  });
  deleteUser.mockReset().mockResolvedValue(undefined);
  revokeRefreshTokens.mockReset().mockResolvedValue(undefined);
  for (const level of ["debug", "info", "warn", "error"] as const) {
    (logger[level] as jest.Mock).mockClear();
  }
  now = T0;
  dateSpy = jest.spyOn(Date, "now").mockImplementation(() => now);
});

afterEach(() => {
  dateSpy.mockRestore();
});

describe("MAJOR-03 acceptance: a failed final sweep is finished later by the reconciler", () => {
  test("raced write survives a failing final sweep, is recorded, and a later unauthenticated reconciler run removes it", async () => {
    seedUserData(U);
    store.set("coach_bookings/b1", { clientUid: U, coachUid: "coach_9" });
    store.set("debug_sessions/d_other", { uid: "someone_else" });

    // Between the first wipe and the final sweep, a raced Stripe webhook
    // re-creates the subscription doc (and a debug row lands); from the Auth
    // deletion on, every Firestore delete fails.
    deleteUser.mockImplementation(async () => {
      store.set(`users/${U}/subscription/main`, { stripeCustomerId: "cus_raced" });
      store.set("debug_sessions/d_raced", { uid: U });
      sw.recursiveFails = () => true;
    });

    const res = await deleteAccount.run(callReq(U));

    // The caller is told the cleanup is only scheduled, not complete.
    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(deleteUser).toHaveBeenCalledWith(U);
    expect(logged("error", "delete_account_final_sweep_failed")).toHaveLength(1);

    // The first wipe worked; the raced write is what is left.
    expect(store.has(`users/${U}/profile/main`)).toBe(false);
    expect(store.has(`users/${U}/subscription/main`)).toBe(true);
    expect(store.has("debug_sessions/d_raced")).toBe(true);

    // The durable record: exact field set, exact values, no message text.
    const record = store.get(RECORD)!;
    expect(Object.keys(record).sort()).toEqual([
      "attempts",
      "createdAt",
      "expireAt",
      "lastErrorCode",
      "nextAttemptAt",
      "status",
      "uid",
    ]);
    expect(record).toEqual({
      uid: U,
      status: "pending",
      attempts: 1,
      createdAt: ts(T0),
      nextAttemptAt: ts(T0 + 15 * MIN),
      lastErrorCode: "unavailable",
      expireAt: ts(T0 + 30 * DAY),
    });
    expect(JSON.stringify(record)).not.toContain("example.com");
    expect(recordKeys()).toEqual([RECORD]);

    // Firestore recovers; the clock reaches nextAttemptAt.
    sw.recursiveFails = () => false;
    now = T0 + 15 * MIN;
    const deleteUserCalls = deleteUser.mock.calls.length;
    const revokeCalls = revokeRefreshTokens.mock.calls.length;

    await runReconciler();

    expect(keysUnder(`users/${U}`)).toEqual([]);
    expect(store.has(`donor_wall/${U}`)).toBe(false);
    expect(store.has(`coach_listings/${U}`)).toBe(false);
    expect(store.has("debug_sessions/d_raced")).toBe(false);
    // Somebody else's row is untouched.
    expect(store.get("debug_sessions/d_other")).toEqual({ uid: "someone_else" });
    expect(store.has(RECORD)).toBe(false);
    expect(logged("info", "account_deletion_reconciled")).toEqual([
      [
        "account_deletion_reconciled",
        { event: "account_deletion_reconciled", uid: U, attempts: 2 },
      ],
    ]);
    expect(logged("error", "account_deletion_reconcile_exhausted")).toHaveLength(0);
    // The reconciler needs no user authentication: it only READS Auth to make
    // sure the account really is gone, and never deletes or revokes anything.
    expect(deleteUser.mock.calls.length).toBe(deleteUserCalls);
    expect(revokeRefreshTokens.mock.calls.length).toBe(revokeCalls);
  });
});

describe("reconcileAccountDeletions: which records are picked up", () => {
  test("a record that is not yet due is not touched (1 ms early), and one due exactly now is", async () => {
    seedUserData("early");
    seedUserData("exact");
    seedRecord("early", { nextAttemptAt: T0 + 1 });
    seedRecord("exact", { nextAttemptAt: T0 });
    const earlyBefore = { ...store.get("accountDeletionRetries/early")! };

    await runReconciler();

    // The due query is exactly: pending, nextAttemptAt <= now, oldest first, 50.
    const dueQuery = queries.find((q) => q.col === "accountDeletionRetries")!;
    expect(dueQuery).toEqual({
      col: "accountDeletionRetries",
      filters: [
        { f: "status", op: "==", v: "pending" },
        { f: "nextAttemptAt", op: "<=", v: ts(T0) },
      ],
      order: "nextAttemptAt",
      max: 50,
    });
    // `early` untouched: record identical, data still present, no sweep on it.
    expect(store.get("accountDeletionRetries/early")).toEqual(earlyBefore);
    expect(keysUnder("users/early").length).toBeGreaterThan(0);
    expect(recursiveDeletedPaths).not.toContain("users/early");
    expect(writes.filter((w) => w.path.endsWith("/early"))).toEqual([]);
    // `exact` finished.
    expect(keysUnder("users/exact")).toEqual([]);
    expect(store.has("accountDeletionRetries/exact")).toBe(false);
  });

  test("a failed_terminal record is never picked up again, even long after its nextAttemptAt", async () => {
    seedUserData(U);
    seedRecord(U, { status: "failed_terminal", attempts: 12, nextAttemptAt: T0 - DAY });
    const before = { ...store.get(RECORD)! };
    now = T0 + 10 * DAY;

    await runReconciler();

    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(store.get(RECORD)).toEqual(before);
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
    expect(logged("error", "account_deletion_reconcile_exhausted")).toHaveLength(0);
    expect(writes).toEqual([]);
  });

  test("at most 50 due records are processed per run; the rest are left for the next run", async () => {
    for (let i = 0; i < 55; i++) {
      const uid = `bulk_${String(i).padStart(2, "0")}`;
      seedUserData(uid);
      seedRecord(uid, { nextAttemptAt: T0 + i });
    }
    now = T0 + HOUR;

    await runReconciler();

    expect(logged("info", "account_deletion_reconciled")).toHaveLength(50);
    // Oldest nextAttemptAt first: bulk_00..bulk_49 done, bulk_50..bulk_54 left.
    expect(recordKeys().sort()).toEqual(
      [50, 51, 52, 53, 54].map((i) => `accountDeletionRetries/bulk_${i}`),
    );
    expect(store.has("users/bulk_49/profile/main")).toBe(false);
    expect(store.has("users/bulk_50/profile/main")).toBe(true);

    await runReconciler();

    expect(recordKeys()).toEqual([]);
    expect(logged("info", "account_deletion_reconciled")).toHaveLength(55);
    expect(keysUnder("users/bulk_54")).toEqual([]);
  });
});

describe("reconcileAccountDeletions: failures on retry", () => {
  test("backoff doubles from 15 min to a 6 h cap, attempts increment, one record, history preserved", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 + 15 * MIN });
    sw.recursiveFails = () => true;

    // New attempt number n = 2..11 schedules the next try after 15 min * 2^(n-1), capped at 6 h.
    const expectedDelayMin = [30, 60, 120, 240, 360, 360, 360, 360, 360, 360];
    let due = T0 + 15 * MIN;
    for (let i = 0; i < expectedDelayMin.length; i++) {
      now = due;
      await runReconciler();

      const rec = store.get(RECORD)!;
      expect(rec.attempts).toBe(i + 2);
      expect(rec.status).toBe("pending");
      expect(rec.nextAttemptAt).toEqual(ts(due + expectedDelayMin[i] * MIN));
      expect(rec.lastErrorCode).toBe("unavailable");
      // Bookkeeping fields written once stay as they were (merge, not replace).
      expect(rec.createdAt).toEqual(ts(T0));
      expect(rec.expireAt).toEqual(ts(T0 + 30 * DAY));
      expect(rec.uid).toBe(U);
      expect(recordKeys()).toEqual([RECORD]);
      due = rec.nextAttemptAt.__ts;
    }
    // Still failing, still not exhausted, data still there.
    expect(logged("error", "account_deletion_reconcile_exhausted")).toHaveLength(0);
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
    // Updates were merges onto the one record, never a fresh create: per run
    // one claim (attempts + nextAttemptAt) and one error-code note.
    expect(writes.every((w) => w.op === "set" && w.merge && w.path === RECORD)).toBe(true);
    expect(writes).toHaveLength(expectedDelayMin.length * 2);
  });

  test("a record that is not due again is not re-attempted right after a failed attempt", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });
    sw.recursiveFails = () => true;
    await runReconciler();
    const callsAfterFirst = recursiveDelete.mock.calls.length;

    now = T0 + 29 * MIN; // backoff after attempt 2 is 30 min
    await runReconciler();

    expect(recursiveDelete.mock.calls.length).toBe(callsAfterFirst);
    expect(store.get(RECORD)!.attempts).toBe(2);
  });

  test("the 12th failed attempt makes the record failed_terminal and logs the ERROR exhausted event with uid and attempts", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 11, nextAttemptAt: T0 });
    sw.recursiveFails = () => true;

    await runReconciler();

    const rec = store.get(RECORD)!;
    expect(rec.status).toBe("failed_terminal");
    expect(rec.attempts).toBe(12);
    expect(rec.lastErrorCode).toBe("unavailable");
    // The claim already pushed nextAttemptAt out by the 6 h cap.
    expect(rec.nextAttemptAt).toEqual(ts(T0 + 6 * HOUR));
    expect(recordKeys()).toEqual([RECORD]);
    const exhausted = logged("error", "account_deletion_reconcile_exhausted");
    expect(exhausted).toEqual([
      [
        "account_deletion_reconcile_exhausted",
        { event: "account_deletion_reconcile_exhausted", uid: U, attempts: 12 },
      ],
    ]);
    expect(JSON.stringify(exhausted)).not.toContain("example.com");
    // The user's data is, by definition, still there: that is what the alert is for.
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);

    // Nothing picks the terminal record up on later runs, even once Firestore recovers.
    sw.recursiveFails = () => false;
    recursiveDelete.mockClear();
    now = T0 + 2 * DAY;
    await runReconciler();
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(store.get(RECORD)!.status).toBe("failed_terminal");
    expect(logged("error", "account_deletion_reconcile_exhausted")).toHaveLength(1);
  });

  test("one record failing does not stop the others in the same run", async () => {
    seedUserData("bad");
    seedUserData("good");
    seedRecord("bad", { nextAttemptAt: T0 - 2 });
    seedRecord("good", { nextAttemptAt: T0 - 1 });
    sw.recursiveFails = (path) => path.endsWith("/bad");

    await runReconciler();

    expect(store.has("accountDeletionRetries/good")).toBe(false);
    expect(keysUnder("users/good")).toEqual([]);
    expect(store.get("accountDeletionRetries/bad")!.attempts).toBe(2);
    expect(keysUnder("users/bad").length).toBeGreaterThan(0);
    expect(logged("info", "account_deletion_reconciled")).toHaveLength(1);
    expect(logged("info", "account_deletion_reconciled")[0][1].uid).toBe("good");
  });

  test("the shared-record sweep is part of the retry: a failing batch keeps the record, a later run anonymises/deletes the rows", async () => {
    seedUserData(U);
    store.set("coach_bookings/b1", { clientUid: U, coachUid: "coach_9" });
    store.set("equipment_reports/r1", { reporterUid: U, fault: "cable" });
    store.set("debug_sessions/d1", { uid: U });
    seedRecord(U, { nextAttemptAt: T0 });
    sw.failBatchCommit = true;

    await runReconciler();

    // uid-keyed docs went, but the shared sweep failed -> record stays pending.
    expect(keysUnder(`users/${U}`)).toEqual([]);
    expect(store.get(RECORD)!.attempts).toBe(2);
    expect(store.get(RECORD)!.lastErrorCode).toBe("aborted");
    expect(store.get("debug_sessions/d1")).toEqual({ uid: U });

    sw.failBatchCommit = false;
    now = T0 + 30 * MIN;
    await runReconciler();

    expect(store.has(RECORD)).toBe(false);
    expect(store.get("coach_bookings/b1")).toEqual({
      clientUid: "deleted_user",
      coachUid: "coach_9",
    });
    expect(store.get("equipment_reports/r1")).toEqual({
      reporterUid: "deleted_user",
      fault: "cable",
    });
    expect(store.has("debug_sessions/d1")).toBe(false);
  });

  test("the due query failing logs the ERROR run_failed event, rethrows, and touches no record", async () => {
    seedUserData(U);
    seedRecord(U, { nextAttemptAt: T0 });
    const before = { ...store.get(RECORD)! };
    const boom = firestoreError("query needs an index for user@example.com", "failed-precondition");
    sw.failDueQuery = boom;

    await expect(runReconciler()).rejects.toBe(boom);

    const failed = logged("error", "account_deletion_reconcile_run_failed");
    expect(failed).toEqual([
      [
        "account_deletion_reconcile_run_failed",
        {
          event: "account_deletion_reconcile_run_failed",
          errorCode: "failed-precondition",
        },
      ],
    ]);
    expect(JSON.stringify(failed)).not.toContain("example.com");
    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(writes).toEqual([]);
    expect(store.get(RECORD)).toEqual(before);
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
  });
});

describe("reconcileAccountDeletions: claim before sweep (a crash or timeout still counts)", () => {
  test("the attempt is claimed durably BEFORE the sweep starts: a sweep that never returns has already used an attempt and pushed nextAttemptAt out", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 0, nextAttemptAt: T0 });
    sw.recursiveHang = true;

    // The run hangs inside the sweep (it is never awaited: this is the
    // timeout/kill case).
    void runReconciler();
    await new Promise((r) => setImmediate(r));

    expect(recursiveDeletedPaths.length).toBeGreaterThan(0);
    const rec = store.get(RECORD)!;
    expect(rec.attempts).toBe(1);
    expect(rec.status).toBe("pending");
    expect(rec.nextAttemptAt).toEqual(ts(T0 + 15 * MIN));
    // The data is still there: the sweep never finished.
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
  });

  test("a sweep that throws a timeout-like error every run reaches failed_terminal after exactly 12 runs, with one ERROR exhausted event", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 0, nextAttemptAt: T0 });
    sw.recursiveThrow = () =>
      Object.assign(new Error("4 DEADLINE_EXCEEDED for user@example.com"), {
        code: "deadline-exceeded",
      });

    for (let run = 1; run <= 12; run++) {
      const rec = store.get(RECORD)!;
      now = Math.max(now, rec.nextAttemptAt.__ts);
      await runReconciler();
      expect(store.get(RECORD)!.attempts).toBe(run);
      if (run < 12) {
        expect(store.get(RECORD)!.status).toBe("pending");
        expect(logged("error", "account_deletion_reconcile_exhausted")).toHaveLength(0);
      }
    }

    expect(store.get(RECORD)!.status).toBe("failed_terminal");
    expect(store.get(RECORD)!.lastErrorCode).toBe("deadline-exceeded");
    const exhausted = logged("error", "account_deletion_reconcile_exhausted");
    expect(exhausted).toEqual([
      [
        "account_deletion_reconcile_exhausted",
        { event: "account_deletion_reconcile_exhausted", uid: U, attempts: 12 },
      ],
    ]);
    // Far inside the 30-day TTL.
    expect(now - T0).toBeLessThan(5 * DAY);
    // Nothing picks it up again.
    recursiveDelete.mockClear();
    now += 2 * DAY;
    await runReconciler();
    expect(recursiveDelete).not.toHaveBeenCalled();
  });

  test("a pending record already at 12 attempts (the last attempt crashed) is terminated WITHOUT another sweep", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 12, nextAttemptAt: T0 });

    await runReconciler();

    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(getUser).not.toHaveBeenCalled();
    expect(store.get(RECORD)).toMatchObject({ status: "failed_terminal", attempts: 12 });
    expect(logged("error", "account_deletion_reconcile_exhausted")).toEqual([
      [
        "account_deletion_reconcile_exhausted",
        { event: "account_deletion_reconcile_exhausted", uid: U, attempts: 12 },
      ],
    ]);
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
  });

  test("a poison record cannot starve the queue: 50 failing records ahead of 5 good ones are pushed out, so the next run reaches the good ones", async () => {
    for (let i = 0; i < 50; i++) {
      const uid = `poison_${String(i).padStart(2, "0")}`;
      seedUserData(uid);
      seedRecord(uid, { attempts: 1, nextAttemptAt: T0 - 10_000 + i });
    }
    for (let i = 0; i < 5; i++) {
      seedUserData(`good_${i}`);
      seedRecord(`good_${i}`, { attempts: 1, nextAttemptAt: T0 - 1_000 + i });
    }
    sw.recursiveFails = (path) => path.includes("poison_");

    await runReconciler(); // takes the 50 oldest: all poison
    expect(store.has("accountDeletionRetries/good_0")).toBe(true);
    expect(store.get("accountDeletionRetries/poison_00")!.attempts).toBe(2);

    await runReconciler(); // same instant: poison is no longer due
    for (let i = 0; i < 5; i++) {
      expect(store.has(`accountDeletionRetries/good_${i}`)).toBe(false);
      expect(keysUnder(`users/good_${i}`)).toEqual([]);
    }
    expect(store.get("accountDeletionRetries/poison_00")!.attempts).toBe(2);
  });

  test("records after a failing one in the same run are still processed", async () => {
    seedUserData("bad");
    seedUserData("good_a");
    seedUserData("good_b");
    seedRecord("bad", { nextAttemptAt: T0 - 3 });
    seedRecord("good_a", { nextAttemptAt: T0 - 2 });
    seedRecord("good_b", { nextAttemptAt: T0 - 1 });
    sw.recursiveFails = (path) => path.endsWith("/bad");

    await runReconciler();

    expect(store.has("accountDeletionRetries/good_a")).toBe(false);
    expect(store.has("accountDeletionRetries/good_b")).toBe(false);
    expect(store.has("accountDeletionRetries/bad")).toBe(true);
  });

  test("per-run deadline: no new record is started after 240 s; the rest stay due for the next run", async () => {
    for (const uid of ["r1", "r2", "r3"]) {
      seedUserData(uid);
    }
    seedRecord("r1", { attempts: 1, nextAttemptAt: T0 - 3 });
    seedRecord("r2", { attempts: 1, nextAttemptAt: T0 - 2 });
    seedRecord("r3", { attempts: 1, nextAttemptAt: T0 - 1 });
    // The first sweep is slow: it eats the whole budget.
    let slowOnce = true;
    sw.onSweep = () => {
      if (slowOnce) {
        slowOnce = false;
        now += 241 * 1000;
      }
    };
    const r2Before = { ...store.get("accountDeletionRetries/r2")! };

    await runReconciler();

    expect(store.has("accountDeletionRetries/r1")).toBe(false); // finished
    expect(store.get("accountDeletionRetries/r2")).toEqual(r2Before); // not even claimed
    expect(keysUnder("users/r2").length).toBeGreaterThan(0);
    expect(logged("warn", "account_deletion_reconcile_deadline_reached")).toEqual([
      [
        "account_deletion_reconcile_deadline_reached",
        {
          event: "account_deletion_reconcile_deadline_reached",
          processed: 1,
          remaining: 2,
        },
      ],
    ]);

    await runReconciler();

    expect(recordKeys()).toEqual([]);
    expect(keysUnder("users/r3")).toEqual([]);
  });

  test("without a durable claim nothing is swept (the claim write fails)", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });
    sw.failRecordWrite = true;

    await runReconciler();

    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
    expect(store.get(RECORD)!.attempts).toBe(1);
    const failed = logged("error", "account_deletion_reconcile_attempt_failed");
    expect(failed).toHaveLength(1);
    expect(failed[0][1]).toMatchObject({ uid: U, stage: "claim" });
  });

  test("a record whose Auth user still exists (an aborted deletion) is dropped, never swept", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 0, nextAttemptAt: T0 });
    getUser.mockResolvedValue({ uid: U });

    await runReconciler();

    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(keysUnder(`users/${U}`).length).toBeGreaterThan(0);
    expect(store.has(RECORD)).toBe(false);
    expect(logged("warn", "account_deletion_reconcile_skipped_live_account")).toHaveLength(1);
  });

  test("an Auth lookup error other than user-not-found counts as a failed attempt and does not sweep", async () => {
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });
    getUser.mockRejectedValue(Object.assign(new Error("auth down"), { code: "auth/internal-error" }));

    await runReconciler();

    expect(recursiveDelete).not.toHaveBeenCalled();
    expect(store.get(RECORD)).toMatchObject({
      attempts: 2,
      status: "pending",
      lastErrorCode: "auth/internal-error",
    });
  });
});

describe("deleteAccount: the durable intent record", () => {
  test("pre-write failure: the Auth user is never deleted, the call aborts with an internal error, and the retry completes", async () => {
    seedUserData(U);
    sw.failRecordWrite = true;

    await expect(deleteAccount.run(callReq(U))).rejects.toMatchObject({ code: "internal" });

    expect(deleteUser).not.toHaveBeenCalled();
    expect(recordKeys()).toEqual([]);
    const failed = logged("error", "delete_account_intent_record_failed");
    expect(failed).toHaveLength(1);
    expect(failed[0][1]).toMatchObject({ uid: U });
    // The first wipe had already run; nothing was left half-closed.
    expect(store.has(`users/${U}/profile/main`)).toBe(false);

    sw.failRecordWrite = false;
    const res = await deleteAccount.run(callReq(U));
    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(deleteUser).toHaveBeenCalledTimes(1);
  });

  test("the record already exists when the Auth user is deleted, even if the final sweep then hangs forever (a crash or kill)", async () => {
    seedUserData(U);
    let recordAtDeleteUser: any;
    deleteUser.mockImplementation(async () => {
      recordAtDeleteUser = { ...store.get(RECORD)! };
      store.set(`users/${U}/subscription/main`, { stripeCustomerId: "cus_raced" });
      sw.recursiveHang = true; // every later sweep never returns
    });

    void deleteAccount.run(callReq(U)); // never settles
    await new Promise((r) => setImmediate(r));

    expect(deleteUser).toHaveBeenCalledWith(U);
    expect(recordAtDeleteUser).toEqual({
      uid: U,
      status: "pending",
      attempts: 0,
      createdAt: ts(T0),
      nextAttemptAt: ts(T0 + 15 * MIN),
      expireAt: ts(T0 + 30 * DAY),
    });
    expect(store.get(RECORD)).toEqual(recordAtDeleteUser);
    expect(store.has(`users/${U}/subscription/main`)).toBe(true);

    // 15 minutes later the reconciler finishes the job, unauthenticated.
    sw.recursiveHang = false;
    now = T0 + 15 * MIN;
    await runReconciler();
    expect(keysUnder(`users/${U}`)).toEqual([]);
    expect(store.has(RECORD)).toBe(false);
  });

  test("a final sweep that throws a non-Error value still leaves the record and reports scheduled", async () => {
    seedUserData(U);
    deleteUser.mockImplementation(async () => {
      sw.recursiveThrow = () => "plain string, not an Error";
    });

    const res = await deleteAccount.run(callReq(U));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(store.get(RECORD)).toMatchObject({
      status: "pending",
      attempts: 1,
      lastErrorCode: "unknown",
      nextAttemptAt: ts(T0 + 15 * MIN),
    });
  });

  test("a clean deleteAccount leaves no record behind", async () => {
    seedUserData(U);

    const res = await deleteAccount.run(callReq(U));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    expect(recordKeys()).toEqual([]);
  });

  test("a second deleteAccount for a uid with a pending record keeps its attempts and createdAt", async () => {
    seedUserData(U);
    seedRecord(U, {
      attempts: 5,
      createdAt: T0 - 3 * HOUR,
      nextAttemptAt: T0 + 2 * HOUR,
    });
    deleteUser.mockImplementation(async () => {
      sw.recursiveFails = () => true;
    });

    const res = await deleteAccount.run(callReq(U));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(store.get(RECORD)!.attempts).toBe(5);
    expect(store.get(RECORD)!.createdAt).toEqual(ts(T0 - 3 * HOUR));
    expect(store.get(RECORD)!.status).toBe("pending");
    expect(recordKeys()).toEqual([RECORD]);
  });

  test("a failed_terminal record is replaced by a fresh pending one", async () => {
    seedUserData(U);
    seedRecord(U, { status: "failed_terminal", attempts: 12, createdAt: T0 - 10 * DAY });

    const res = await deleteAccount.run(callReq(U));

    expect(res).toEqual({ success: true, finalCleanup: "complete" });
    // The fresh intent was written and then removed by the clean final sweep.
    expect(writes.some((w) => w.op === "set" && w.path === RECORD && !w.merge)).toBe(true);
    expect(recordKeys()).toEqual([]);
  });
});

// ---------------------------------------------------------------------------
// Booking sweep (F13): one transaction per booking, decided on a fresh read.
// ---------------------------------------------------------------------------

const A = "uid_a";
const B = "uid_b";
const bookingKeys = (): string[] =>
  [...store.keys()].filter((k) => k.startsWith("coach_bookings/"));

/**
 * Holds the first transaction read of `path` at its first attempt until two
 * transactions have read it, then lets them commit ONE AFTER THE OTHER from
 * those (now stale for the second) reads. `first` picks which arrival commits
 * first. One-shot: later reads (retries, final sweeps) pass straight through.
 */
function interleaveTwoReads(path: string, first: "first-arrival" | "last-arrival"): void {
  const resolvers: Array<() => void> = [];
  let done = false;
  sw.afterTxRead = async (p, attempt) => {
    if (p !== path || attempt !== 1 || done) return;
    const mine = new Promise<void>((r) => resolvers.push(r));
    if (resolvers.length < 2) return mine;
    done = true;
    const [r0, r1] = resolvers;
    const [one, two] = first === "first-arrival" ? [r0, r1] : [r1, r0];
    // Not awaited: this hook must return for its own transaction to proceed.
    void (async () => {
      one();
      while (txCommitted.length === 0) await new Promise((r) => setImmediate(r));
      two();
    })();
    return mine;
  };
}

describe("the transaction fake itself (instrument check)", () => {
  test("two interleaved read-modify-write transactions do not lose an update: the second retries on fresh state", async () => {
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const admin = require("firebase-admin");
    const db = admin.firestore();
    store.set("counters/c", { n: 0 });
    const ref = db.doc("counters/c");
    const resolvers: Array<() => void> = [];
    const hold = () => new Promise<void>((r) => resolvers.push(r));
    const incr = () =>
      db.runTransaction(async (tx: any) => {
        const snap = await tx.get(ref);
        // First attempts block until released; retries do not wait.
        if (resolvers.length < 2) await hold();
        tx.update(ref, { n: snap.data().n + 1 });
      });
    const both = Promise.all([incr(), incr()]);
    while (resolvers.length < 2) await new Promise((r) => setImmediate(r));
    resolvers[0]();
    while (txCommitted.length === 0) await new Promise((r) => setImmediate(r));
    resolvers[1]();
    await both;

    expect(store.get("counters/c")).toEqual({ n: 2 });
    expect(txRetries).toBe(1);
    expect(txCommitted.map((c) => c.attempt).sort()).toEqual([1, 2]);
  });
});

describe("booking sweep under concurrent deletions (F13)", () => {
  test.each(["first-arrival", "last-arrival"] as const)(
    "both parties delete at the same moment (%s commits first): the booking row ends DELETED, never with both sides deleted_user",
    async (first) => {
      seedUserData(A);
      seedUserData(B);
      store.set("coach_bookings/ab", { clientUid: A, coachUid: B, note: "shared" });
      // Rows with a third party must keep that party's side.
      store.set("coach_bookings/a_c", { clientUid: A, coachUid: "coach_c" });
      store.set("coach_bookings/c_b", { clientUid: "client_c", coachUid: B });
      store.set("coach_bookings/other", { clientUid: "x", coachUid: "y" });
      interleaveTwoReads("coach_bookings/ab", first);

      const [ra, rb] = await Promise.all([
        deleteAccount.run(callReq(A)),
        deleteAccount.run(callReq(B)),
      ]);

      expect(ra).toEqual({ success: true, finalCleanup: "complete" });
      expect(rb).toEqual({ success: true, finalCleanup: "complete" });
      // The interleaving really happened: exactly one transaction lost the
      // race and re-ran on the other's committed write.
      expect(txRetries).toBe(1);
      const onAb = txCommitted.filter((c) => c.path === "coach_bookings/ab");
      expect(onAb.map((c) => [c.op, c.attempt])).toEqual([
        ["update", 1],
        ["delete", 2],
      ]);
      // End state.
      expect(store.has("coach_bookings/ab")).toBe(false);
      expect(store.get("coach_bookings/a_c")).toEqual({
        clientUid: "deleted_user",
        coachUid: "coach_c",
      });
      expect(store.get("coach_bookings/c_b")).toEqual({
        clientUid: "client_c",
        coachUid: "deleted_user",
      });
      expect(store.get("coach_bookings/other")).toEqual({ clientUid: "x", coachUid: "y" });
      // No row anywhere has both sides gone.
      for (const k of bookingKeys()) {
        const d = store.get(k)!;
        expect(d.clientUid === "deleted_user" && d.coachUid === "deleted_user").toBe(false);
      }
    },
  );

  test("many shared bookings (more than one 450-row page) deleted concurrently by both parties: every row is deleted, others untouched", async () => {
    seedUserData(A);
    seedUserData(B);
    const N = 460; // one page (450) plus a remainder
    for (let i = 0; i < N; i++) {
      store.set(`coach_bookings/ab${i}`, { clientUid: i % 2 ? A : B, coachUid: i % 2 ? B : A });
    }
    store.set("coach_bookings/keep", { clientUid: "x", coachUid: "y" });

    await Promise.all([deleteAccount.run(callReq(A)), deleteAccount.run(callReq(B))]);

    expect(bookingKeys()).toEqual(["coach_bookings/keep"]);
    expect(txRetries).toBeLessThanOrEqual(N); // at most one lost race per row
  });

  test("a self-booking is deleted by one transaction, not anonymised", async () => {
    seedUserData(A);
    store.set("coach_bookings/self", { clientUid: A, coachUid: A });

    await deleteAccount.run(callReq(A));

    expect(store.has("coach_bookings/self")).toBe(false);
    const onSelf = txCommitted.filter((c) => c.path === "coach_bookings/self");
    expect(onSelf).toEqual([{ op: "delete", path: "coach_bookings/self", attempt: 1 }]);
  });

  test("a booking with another counterparty keeps the other side (client and coach roles)", async () => {
    seedUserData(A);
    store.set("coach_bookings/as_client", { clientUid: A, coachUid: "coach_c", price: 10 });
    store.set("coach_bookings/as_coach", { clientUid: "client_c", coachUid: A, price: 20 });

    await deleteAccount.run(callReq(A));

    expect(store.get("coach_bookings/as_client")).toEqual({
      clientUid: "deleted_user",
      coachUid: "coach_c",
      price: 10,
    });
    expect(store.get("coach_bookings/as_coach")).toEqual({
      clientUid: "client_c",
      coachUid: "deleted_user",
      price: 20,
    });
  });

  test("a booking whose other side is missing or already deleted is deleted", async () => {
    seedUserData(A);
    store.set("coach_bookings/gone_side", { clientUid: A, coachUid: "deleted_user" });
    store.set("coach_bookings/no_side", { clientUid: A });

    await deleteAccount.run(callReq(A));

    expect(bookingKeys()).toEqual([]);
  });

  test("more than one page for one user: 1000 bookings are settled, counterparties survive, other users untouched", async () => {
    seedUserData(A);
    for (let i = 0; i < 1000; i++) {
      store.set(`coach_bookings/p${i}`, {
        clientUid: i % 3 === 0 ? "deleted_user" : A,
        coachUid: i % 3 === 0 ? A : `coach_${i}`,
      });
    }
    store.set("coach_bookings/keep", { clientUid: "x", coachUid: "y" });

    await deleteAccount.run(callReq(A));

    // i % 3 === 0: the other side was already gone -> row deleted (334 rows).
    expect(bookingKeys()).toHaveLength(1000 - 334 + 1);
    for (let i = 0; i < 1000; i++) {
      if (i % 3 === 0) expect(store.has(`coach_bookings/p${i}`)).toBe(false);
      else {
        expect(store.get(`coach_bookings/p${i}`)).toEqual({
          clientUid: "deleted_user",
          coachUid: `coach_${i}`,
        });
      }
    }
    expect(store.get("coach_bookings/keep")).toEqual({ clientUid: "x", coachUid: "y" });
    expect(txRetries).toBe(0);
  });

  test("a failed booking transaction keeps the deletion record pending; the next reconciler run finishes the row", async () => {
    seedUserData(U);
    store.set("coach_bookings/b1", { clientUid: U, coachUid: "coach_9" });
    seedRecord(U, { nextAttemptAt: T0 });
    sw.failTxCommit = true;

    await runReconciler();

    expect(store.get(RECORD)!.attempts).toBe(2);
    expect(store.get(RECORD)!.lastErrorCode).toBe("aborted");
    expect(store.get("coach_bookings/b1")).toEqual({ clientUid: U, coachUid: "coach_9" });

    sw.failTxCommit = false;
    now = T0 + 30 * MIN;
    await runReconciler();

    expect(store.has(RECORD)).toBe(false);
    expect(store.get("coach_bookings/b1")).toEqual({
      clientUid: "deleted_user",
      coachUid: "coach_9",
    });
  });
});

describe("reconciler: body-scan storage sweep (C12, design s7.6, SD-6)", () => {
  const BUCKET = "body-scan-test-bucket";
  const gcsError = (code?: number): Error =>
    Object.assign(new Error(`gcs failure for users/${U}/scans/s1/front.jpg`), code === undefined ? {} : { code });

  test("bucket set: the due record's sweep also deletes users/<uid>/ with force: true, then the record is removed", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    seedUserData(U);
    seedRecord(U, { nextAttemptAt: T0 });

    await runReconciler();

    expect(storageBucket.mock.calls).toEqual([[BUCKET]]);
    expect(storageDeleteFiles.mock.calls).toEqual([[{ prefix: `users/${U}/`, force: true }]]);
    expect(keysUnder(`users/${U}`)).toEqual([]);
    expect(store.has(RECORD)).toBe(false);
    expect(logged("info", "account_deletion_reconciled")).toHaveLength(1);
  });

  test("bucket unset: storage is never touched and the record is still reconciled", async () => {
    seedUserData(U);
    seedRecord(U, { nextAttemptAt: T0 });
    await runReconciler();
    expect(storageBucket).not.toHaveBeenCalled();
    expect(storageDeleteFiles).not.toHaveBeenCalled();
    expect(store.has(RECORD)).toBe(false);
    expect(logged("info", "body_scan_storage_sweep_skipped_unconfigured")).toHaveLength(1);
  });

  test.each([
    ["a single 404", gcsError(404)],
    ["an array of 404s", [gcsError(404), gcsError(404)]],
  ])("%s is 'nothing to delete': the record is reconciled", async (_name, rejection) => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue(rejection);
    seedUserData(U);
    seedRecord(U, { nextAttemptAt: T0 });
    await runReconciler();
    expect(store.has(RECORD)).toBe(false);
    expect(keysUnder(`users/${U}`)).toEqual([]);
  });

  test("a 403 fails the attempt AFTER the Firestore data was swept: the record persists with the bare code and backoff, and the next run (storage recovered) finishes it", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue(gcsError(403));
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });

    await runReconciler();

    expect(keysUnder(`users/${U}`)).toEqual([]); // Firestore part completed first
    expect(store.has(`donor_wall/${U}`)).toBe(false);
    const rec = store.get(RECORD)!;
    expect(rec.status).toBe("pending");
    expect(rec.attempts).toBe(2);
    expect(rec.lastErrorCode).toBe("403");
    expect(rec.nextAttemptAt).toEqual(ts(T0 + 30 * MIN));
    expect(storageDeleteFiles).toHaveBeenCalledTimes(1);
    expect(JSON.stringify((logger.error as jest.Mock).mock.calls)).not.toContain("front.jpg");
    expect(JSON.stringify(rec)).not.toContain("front.jpg");

    // Not due yet: no second storage call.
    now = T0 + 29 * MIN;
    await runReconciler();
    expect(storageDeleteFiles).toHaveBeenCalledTimes(1);

    // IAM fixed; the retry completes and removes the record.
    storageDeleteFiles.mockResolvedValue(undefined);
    now = T0 + 30 * MIN;
    await runReconciler();
    expect(storageDeleteFiles).toHaveBeenCalledTimes(2);
    expect(store.has(RECORD)).toBe(false);
  });

  test("a mixed array [404, 500] is a real failure (one non-404 is enough) and records the first error's code", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue([gcsError(500), gcsError(404)]);
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });
    await runReconciler();
    expect(store.get(RECORD)!.lastErrorCode).toBe("500");
    expect(store.get(RECORD)!.attempts).toBe(2);
  });

  test("a storage failure with no error code is recorded as 'unknown'", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    storageDeleteFiles.mockRejectedValue(gcsError());
    seedUserData(U);
    seedRecord(U, { attempts: 1, nextAttemptAt: T0 });
    await runReconciler();
    expect(store.get(RECORD)!.lastErrorCode).toBe("unknown");
  });

  test("deleteAccount's final sweep failing on storage (403) leaves the record that this reconciler then finishes", async () => {
    process.env.BODY_SCAN_BUCKET = BUCKET;
    seedUserData(U);
    storageDeleteFiles
      .mockResolvedValueOnce(undefined) // Step 2 sweep
      .mockRejectedValueOnce(gcsError(403)); // final sweep, after the Auth user is gone

    const res = await deleteAccount.run(callReq(U));

    expect(res).toEqual({ success: true, finalCleanup: "scheduled" });
    expect(store.get(RECORD)).toMatchObject({ status: "pending", lastErrorCode: "403", attempts: 1 });

    now = T0 + 15 * MIN;
    await runReconciler();
    expect(store.has(RECORD)).toBe(false);
    expect(storageDeleteFiles).toHaveBeenCalledTimes(3);
  });
});
