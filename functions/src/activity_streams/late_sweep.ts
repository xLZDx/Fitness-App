/**
 * Late sweep job and fence lifetime (S02 design 6.1 steps 3, 5 and 6; story
 * S02-06b).
 *
 * The job IS the top-level server-only document `activity_account_state/{uid}`
 * that `deleteAccount` writes at its first step (`writeActivityAccountFence`,
 * fields `fenceAt` and `lateSweepAt`). It lives outside `users/{uid}`, so
 * `recursiveDelete(users/{uid})` cannot remove it, and it exists before any
 * sweep, so a kill at any later point (including right after Auth deletion)
 * still leaves it. Fields added here: `authDeletedAt`, `lateSweepDone`,
 * `lateSweepAttempts`, `lastErrorCode` (bare code).
 *
 * `sweepLateActivityStreams` runs every 5 minutes and, for every document whose
 * `lateSweepAt` is due:
 *  0. (not yet done) while the Auth user still EXISTS (an aborted deletion) NOTHING is erased and
 *     the job stays armed (`skippedLive`); a failing Auth lookup fails closed the same way.
 *  1. (not yet done, Auth user gone) sweeps `streams/<uid>/` and `quarantine/<uid>/` AND ends with
 *     the FINAL recursive delete of the activity collections of the user
 *     (`activities`, `activity_streams`, `activity_settings`,
 *     `activity_tombstones`). Every part is attempted independently; any failure
 *     records a bare `lastErrorCode`, leaves the job NOT done (it is retried at
 *     the next run) and `lateSweepDone` is set only after all parts succeeded.
 *  2. (done) removes the fence at
 *       removeFenceAfter = max(lateSweepDone + 1 h, authDeletedAt + 70 min)
 *     (ID token lifetime 1 h plus margin). If `authDeletedAt` was never recorded
 *     (the invocation died between Auth deletion and its write) the job derives
 *     it from Auth user ABSENCE at its first run and uses that run's time (the
 *     later, safe value). With the Auth user still PRESENT the fence is NOT
 *     removed at all and the job reports the stuck state.
 *
 * The removal is a compare-and-delete in a transaction: it only deletes the
 * document it read (same `lateSweepDone` and `authDeletedAt`). Idempotent: a done
 * job issues no storage deletes and writes nothing until the removal is due.
 *
 * Signals (design 6.3), ONE structured log entry per run: due jobs, completed
 * sweeps, failures, removed fences, jobs waiting for the Auth deletion and the
 * count and oldest age of stuck jobs (`lateSweepAt` more than 1 hour past and
 * `lateSweepDone` unset). Counts, ages and bare codes only; never a uid.
 */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { activityAccountStatePath, defaultFenceDeps, type FenceDeps } from "./fence";
import { UID_PATTERN } from "./paths";
import { sweepActivityStreamObjects } from "./sweep";
import { errorCodeOf, timestampMs, type RowData } from "./upload_common";

/** The one structured-log message of this job (GPS-PRIV-094: no uid, id or path in any field). */
export const ACTIVITY_LATE_SWEEP_EVENT = "activity_late_sweep_event";

const HOUR_MS = 60 * 60 * 1000;
const MINUTE_MS = 60 * 1000;

/** Fence lifetime after the sweep (design 6.1): one hour after `lateSweepDone`. */
export const FENCE_AFTER_SWEEP_MS = HOUR_MS;

/** Fence lifetime after the Auth deletion (design 6.1): ID token lifetime 1 h plus 10 min margin. */
export const FENCE_AFTER_AUTH_DELETE_MS = 70 * MINUTE_MS;

/** A job whose `lateSweepAt` is this far past and which is not done is reported as stuck (design 6.3). */
export const STUCK_AFTER_MS = HOUR_MS;

/** The user collections the FINAL recursive delete clears (design 6.1 step 5). */
export const ACTIVITY_USER_COLLECTIONS: readonly string[] = [
  "activities",
  "activity_streams",
  "activity_settings",
  "activity_tombstones",
];

/** Injectable collaborators of the job and of the `authDeletedAt` write. */
export interface LateSweepDeps extends FenceDeps {
  /** The stream bucket, or `undefined` when the feature is off (the storage part is a logged no-op). */
  bucket(): StreamBucket | undefined;
}

export const defaultLateSweepDeps: LateSweepDeps = {
  ...defaultFenceDeps,
  bucket: () => activityStreamBucket(),
};

/** Every size knob of a run, injectable so tests need not create hundreds of documents. */
export interface LateSweepLimits {
  /** Documents per page of the due query. */
  page: number;
  /** No new document is STARTED after this much time has passed in a run. */
  runBudgetMs: number;
}

export const DEFAULT_LATE_SWEEP_LIMITS: LateSweepLimits = {
  page: 50,
  runBudgetMs: 90 * 1000,
};

/**
 * `max(lateSweepDone + 1 h, authDeletedAt + 70 min)`: the earliest moment the
 * fence may be removed (design 6.1). Removal tied to only one of the two, or
 * earlier than the later of them, is a defect.
 */
export function removeFenceAfterMs(lateSweepDoneMs: number, authDeletedAtMs: number): number {
  return Math.max(lateSweepDoneMs + FENCE_AFTER_SWEEP_MS, authDeletedAtMs + FENCE_AFTER_AUTH_DELETE_MS);
}

/**
 * Records `authDeletedAt` on the fence document (design 6.1 step 3). Keeps the
 * EARLIEST value (idempotent), does nothing when the fence document does not
 * exist, and returns the effective value in millis (`undefined` when there is no
 * fence document). Admin SDK only.
 */
export async function recordAuthDeletedAt(
  deps: FenceDeps,
  uid: string,
): Promise<number | undefined> {
  const fs = deps.firestore();
  const ref = fs.doc(activityAccountStatePath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return undefined;
    const existing = timestampMs((snap.data() as RowData | undefined)?.authDeletedAt);
    if (existing !== undefined) return existing;
    const nowMs = deps.nowMs();
    tx.set(ref, { authDeletedAt: admin.firestore.Timestamp.fromMillis(nowMs) }, { merge: true });
    return nowMs;
  });
}

/** Counts of one run (also the shape of the structured log entry). */
export interface LateSweepRunResult {
  /** Documents whose `lateSweepAt` was due and which were looked at. */
  due: number;
  /** Jobs whose sweep completed in this run (`lateSweepDone` newly set). */
  swept: number;
  /** Jobs that failed (a part of the sweep, the removal or the document handling). */
  failures: number;
  /** Fence documents removed in this run. */
  removed: number;
  /** Done jobs whose Auth user still exists, or whose removal time has not come yet. */
  waiting: number;
  /** Done jobs whose Auth user still EXISTS (the fence is never removed; the stuck state of F95 (c)). */
  authPresent: number;
  /** Jobs not done more than `STUCK_AFTER_MS` after `lateSweepAt` (signal). */
  stuck: number;
  /** Age in millis of the oldest stuck job past `STUCK_AFTER_MS`, 0 when none. */
  oldestStuckAgeMs: number;
  /** Documents dropped because their id can never be a valid uid. */
  invalid: number;
  budgetExhausted: boolean;
  /** `false` when a query failed (for example a missing index) and the pass stopped. */
  queryFailed: boolean;
  /** Not-yet-done jobs skipped because the Auth user still EXISTS (aborted deletion; nothing was erased). */
  skippedLive: number;
}

function newResult(): LateSweepRunResult {
  return {
    due: 0,
    swept: 0,
    failures: 0,
    removed: 0,
    waiting: 0,
    authPresent: 0,
    stuck: 0,
    oldestStuckAgeMs: 0,
    invalid: 0,
    budgetExhausted: false,
    queryFailed: false,
    skippedLive: 0,
  };
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_LATE_SWEEP_EVENT, { operation: "sweepLateActivityStreams", ...fields });
}

/** Attempts the final recursive delete of every activity collection; returns the failures (never throws). */
async function finalRecursiveDelete(
  fs: FirebaseFirestore.Firestore,
  uid: string,
): Promise<unknown[]> {
  const failures: unknown[] = [];
  for (const name of ACTIVITY_USER_COLLECTIONS) {
    try {
      await fs.recursiveDelete(fs.collection(`users/${uid}/${name}`));
    } catch (e) {
      failures.push(e);
    }
  }
  return failures;
}

/**
 * Step 5 of design 6.1 for ONE job: the storage sweep and the final recursive
 * delete are both attempted. Resolves to the first failure's bare code, or
 * `undefined` when everything succeeded.
 */
export async function runLateSweepParts(
  deps: LateSweepDeps,
  uid: string,
): Promise<string | undefined> {
  const failures: unknown[] = [];
  try {
    await sweepActivityStreamObjects(uid, { bucket: () => deps.bucket() });
  } catch (e) {
    failures.push(e);
  }
  failures.push(...(await finalRecursiveDelete(deps.firestore(), uid)));
  return failures.length === 0 ? undefined : errorCodeOf(failures[0]);
}

/** Marks the job done (keeps the earliest `lateSweepDone`) and clears the failure bookkeeping. */
async function markDone(deps: LateSweepDeps, uid: string): Promise<number | undefined> {
  const fs = deps.firestore();
  const ref = fs.doc(activityAccountStatePath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return undefined;
    const existing = timestampMs((snap.data() as RowData | undefined)?.lateSweepDone);
    if (existing !== undefined) return existing;
    const nowMs = deps.nowMs();
    tx.set(
      ref,
      {
        lateSweepDone: admin.firestore.Timestamp.fromMillis(nowMs),
        lastErrorCode: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
    return nowMs;
  });
}

/** Records a failed attempt (bare code and counter); the job stays not done. */
async function noteFailure(deps: LateSweepDeps, uid: string, code: string): Promise<void> {
  const fs = deps.firestore();
  const ref = fs.doc(activityAccountStatePath(uid));
  await fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return;
    const attempts = (snap.data() as RowData | undefined)?.lateSweepAttempts;
    tx.set(
      ref,
      {
        lateSweepAttempts: (typeof attempts === "number" ? attempts : 0) + 1,
        lastErrorCode: code,
      },
      { merge: true },
    );
  });
}

/**
 * Deletes the fence document only when it is still the one this run read
 * (same `lateSweepDone` and `authDeletedAt`), so a newer state is never removed.
 */
async function removeFence(
  deps: LateSweepDeps,
  uid: string,
  doneMs: number,
  authMs: number,
): Promise<boolean> {
  const fs = deps.firestore();
  const ref = fs.doc(activityAccountStatePath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    if (!snap.exists) return false;
    const data = snap.data() as RowData | undefined;
    if (timestampMs(data?.lateSweepDone) !== doneMs || timestampMs(data?.authDeletedAt) !== authMs) {
      return false;
    }
    tx.delete(ref);
    return true;
  });
}

/** One due document; updates [result]. Never throws (failures are counted). */
async function processJob(
  deps: LateSweepDeps,
  uid: string,
  data: RowData,
  result: LateSweepRunResult,
): Promise<void> {
  try {
    let doneMs = timestampMs(data.lateSweepDone);
    if (doneMs === undefined) {
      // The destructive part must never touch a LIVE account: an aborted deletion leaves the
      // fence but the user (and their data) still exist. A failing Auth read throws and is
      // counted as a failure by the catch below (fail closed, nothing erased). The job stays
      // armed: the deletion intent keeps driving the account deletion, and the next run re-checks.
      if (await deps.authUserExists(uid)) {
        result.skippedLive += 1;
        result.waiting += 1;
        log("warn", { outcome: "skipped-live-account" });
        return;
      }
      const code = await runLateSweepParts(deps, uid);
      if (code !== undefined) {
        result.failures += 1;
        log("warn", { outcome: "sweep-failed", errorCode: code });
        await noteFailure(deps, uid, code);
        const lateAtMs = timestampMs(data.lateSweepAt) ?? 0;
        const ageMs = deps.nowMs() - lateAtMs;
        if (ageMs > STUCK_AFTER_MS) {
          result.stuck += 1;
          result.oldestStuckAgeMs = Math.max(result.oldestStuckAgeMs, ageMs);
        }
        return;
      }
      doneMs = await markDone(deps, uid);
      if (doneMs === undefined) return; // the document disappeared meanwhile
      result.swept += 1;
    }

    let authMs = timestampMs(data.authDeletedAt);
    if (authMs === undefined) {
      // The invocation died before it recorded the deletion: derive it from Auth absence.
      if (await deps.authUserExists(uid)) {
        result.authPresent += 1;
        result.waiting += 1;
        return;
      }
      authMs = await recordAuthDeletedAt(deps, uid);
      if (authMs === undefined) return;
    }

    if (deps.nowMs() < removeFenceAfterMs(doneMs, authMs)) {
      result.waiting += 1;
      return;
    }
    if (await removeFence(deps, uid, doneMs, authMs)) result.removed += 1;
  } catch (e) {
    result.failures += 1;
    log("warn", { outcome: "job-failed", errorCode: errorCodeOf(e) });
  }
}

/** One late-sweep run; exported so the schedule handler and the tests share it. */
export async function runActivityLateSweep(
  deps: LateSweepDeps = defaultLateSweepDeps,
  limits: LateSweepLimits = DEFAULT_LATE_SWEEP_LIMITS,
): Promise<LateSweepRunResult> {
  const result = newResult();
  const startMs = deps.nowMs();
  const deadlineMs = startMs + limits.runBudgetMs;
  const fs = deps.firestore();
  const seen = new Set<string>();

  try {
    let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    for (;;) {
      let query = fs
        .collection("activity_account_state")
        .where("lateSweepAt", "<=", admin.firestore.Timestamp.fromMillis(startMs))
        .orderBy("lateSweepAt")
        .limit(limits.page);
      if (last) query = query.startAfter(last);
      const page = await query.get();
      if (page.empty) break;
      for (const doc of page.docs) {
        if (deps.nowMs() >= deadlineMs) {
          result.budgetExhausted = true;
          break;
        }
        if (seen.has(doc.id)) continue;
        seen.add(doc.id);
        if (!UID_PATTERN.test(doc.id)) {
          // Can never be a uid the callables or the sweep could address: drop it, do not retry for ever.
          await doc.ref.delete();
          result.invalid += 1;
          continue;
        }
        result.due += 1;
        await processJob(deps, doc.id, doc.data() as RowData, result);
      }
      if (result.budgetExhausted || page.docs.length < limits.page) break;
      last = page.docs[page.docs.length - 1];
    }
  } catch (e) {
    result.failures += 1;
    result.queryFailed = true;
    log("error", { outcome: "pass-failed", errorCode: errorCodeOf(e) });
  }

  log(result.failures > 0 || result.stuck > 0 ? "error" : "info", {
    outcome: "run-complete",
    latencyMs: deps.nowMs() - startMs,
    due: result.due,
    swept: result.swept,
    failures: result.failures,
    removed: result.removed,
    waiting: result.waiting,
    authPresent: result.authPresent,
    stuck: result.stuck,
    oldestStuckAgeMs: result.oldestStuckAgeMs,
    invalid: result.invalid,
    skippedLive: result.skippedLive,
    budgetExhausted: result.budgetExhausted,
  });
  return result;
}

export const sweepLateActivityStreams = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "europe-west1",
    timeoutSeconds: 120,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
  },
  async () => {
    await runActivityLateSweep();
  },
);
