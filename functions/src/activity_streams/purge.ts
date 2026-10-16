/**
 * `purgeExpiredActivityStreams` -- the scheduled retention enforcer for cloud
 * activity streams (S02 design 5.3, 6.3; story S02-05b).
 *
 * Each run:
 *  1. Starts the recompute continuation (`recompute.ts`) for users whose
 *     retention setting changed, inside half of the run budget.
 *  2. Walks the collection group `activity_streams` where `state == stored` and
 *     `expiresAt <= now` (index 1) in pages. `expiresAt` is only a HINT. For every
 *     candidate ONE transaction re-reads the row, the settings and the summary,
 *     re-derives the expiry (`decidePurge`) and then
 *       - not stored any more: nothing;
 *       - not due: only rewrites the hint (and generation) when it is stale;
 *       - due: deletes the object FIRST (a missing object, 404, is success), then
 *         sets `state = expired` in the same transaction. The summary document is
 *         never touched and the row is kept so the app can show "stream expired".
 *     A storage failure other than 404 leaves the row `stored` and records
 *     `purgeAttempts + 1`, a bare `lastErrorCode` and `lastPurgeAttemptAt`.
 *  3. NO GIVE-UP STATE: after `maxPurgeAttempts` the row is still retried on
 *     every run; it is only counted as capped in the signal (GPS kept past its
 *     expiry is a privacy defect, a cap may slow alerts but never abandon a row).
 *  4. Emits the design 6.3 signals as ONE structured log entry: purge failures,
 *     capped rows, oldest overdue age, recompute backlog count and age, and the
 *     missing-index flag. Counts, ages and bare codes only; never a uid, id or path.
 *
 * A second run finds no `stored` row that is due and writes nothing. An unset
 * `ACTIVITY_STREAM_BUCKET` makes the whole run a logged no-op (nothing could ever
 * have been stored).
 */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { activityStreamRowPath, activityStreamsPrefix, activitySummaryPath } from "./paths";
import { runRecomputeContinuation, type RecomputeRunResult } from "./recompute";
import {
  budgetExhausted,
  DEFAULT_RETENTION_LIMITS,
  decidePurge,
  hintMsOf,
  isLastPage,
  isMissingIndexError,
  maxAgeMs,
  overdueAgeMs,
  parseStreamRowPath,
  recomputeDeadlineMs,
  type RetentionDeps,
  type RetentionLimits,
} from "./retention";
import { activitySettingsPath, settingsGenerationOf } from "./settings";
import { errorCodeOf, isNotFound, strOf, timestampMs, type RowData } from "./upload_common";

/** The one structured-log message of this job (GPS-PRIV-094: no uid, id or path in any field). */
export const ACTIVITY_PURGE_EVENT = "activity_purge_event";

export const defaultRetentionDeps: RetentionDeps = {
  firestore: () => admin.firestore(),
  bucket: () => activityStreamBucket(),
  nowMs: () => Date.now(),
};

export type PurgeRowOutcome = "purged" | "rehinted" | "kept" | "skipped" | "failed";

export interface PurgeRowResult {
  outcome: PurgeRowOutcome;
  /** `purgeAttempts` after a failure, `0` otherwise. */
  attempts: number;
  /** Bare code of a storage failure, else `undefined`. */
  errorCode?: string;
  /** Derived expiry of the row in millis (for the overdue age of a failed row), `null` = never. */
  expiryMs?: number | null;
}

/** Deletes the object of a due row; the whole activity prefix when the recorded path is not trustworthy. */
async function deleteStreamObject(
  bucket: StreamBucket,
  uid: string,
  activityId: string,
  objectPath: string | undefined,
): Promise<void> {
  const prefix = activityStreamsPrefix(uid, activityId);
  try {
    if (objectPath !== undefined && objectPath.startsWith(prefix)) {
      await bucket.file(objectPath).delete({ ignoreNotFound: true });
    } else {
      await bucket.deleteFiles({ prefix });
    }
  } catch (e) {
    if (!isNotFound(e)) throw e;
  }
}

/**
 * One candidate: ONE transaction that re-reads the row, the settings and the
 * summary, decides with `decidePurge`, and for a due row deletes the object
 * BEFORE it writes `state = expired`. A transaction retry repeats the delete,
 * which is idempotent, and re-derives from fresh reads.
 */
export async function purgeRow(
  deps: RetentionDeps,
  limits: RetentionLimits,
  bucket: StreamBucket,
  uid: string,
  activityId: string,
  nowMs: number,
): Promise<PurgeRowResult> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, activityId));
  const settingsRef = fs.doc(activitySettingsPath(uid));
  const summaryRef = fs.doc(activitySummaryPath(uid, activityId));
  const ts = (ms: number) => admin.firestore.Timestamp.fromMillis(ms);
  const del = admin.firestore.FieldValue.delete();

  return fs.runTransaction(async (tx): Promise<PurgeRowResult> => {
    const [rowSnap, settingsSnap, summarySnap] = await Promise.all([
      tx.get(rowRef),
      tx.get(settingsRef),
      tx.get(summaryRef),
    ]);
    if (!rowSnap.exists) return { outcome: "skipped", attempts: 0 };
    const row = rowSnap.data() as RowData;
    const settings = settingsSnap.exists ? (settingsSnap.data() as RowData) : undefined;
    const summaryStartMs = summarySnap.exists
      ? timestampMs((summarySnap.data() as RowData | undefined)?.startUtc)
      : undefined;

    const decision = decidePurge(row, settings, summaryStartMs, nowMs);
    if (decision.kind === "skip") return { outcome: "skipped", attempts: 0 };

    if (decision.kind === "keep") {
      if (!decision.rewriteHint) return { outcome: "kept", attempts: 0, expiryMs: decision.expiryMs };
      const generation = settingsGenerationOf(settings);
      tx.set(
        rowRef,
        {
          expiresAt: decision.expiryMs === null ? null : ts(decision.expiryMs),
          settingsGeneration: generation,
        },
        { merge: true },
      );
      return { outcome: "rehinted", attempts: 0, expiryMs: decision.expiryMs };
    }

    // Due: the object goes FIRST, the row is marked expired only after it is gone.
    try {
      await deleteStreamObject(bucket, uid, activityId, strOf(row.objectPath));
    } catch (e) {
      const attempts = (typeof row.purgeAttempts === "number" ? row.purgeAttempts : 0) + 1;
      const errorCode = errorCodeOf(e);
      tx.set(
        rowRef,
        { purgeAttempts: attempts, lastErrorCode: errorCode, lastPurgeAttemptAt: ts(deps.nowMs()) },
        { merge: true },
      );
      return { outcome: "failed", attempts, errorCode, expiryMs: decision.expiryMs };
    }
    tx.set(
      rowRef,
      {
        state: "expired",
        expiredAt: ts(deps.nowMs()),
        purgeAttempts: 0,
        lastErrorCode: del,
        lastPurgeAttemptAt: del,
      },
      { merge: true },
    );
    return { outcome: "purged", attempts: 0, expiryMs: decision.expiryMs };
  });
}

export interface PurgeRunResult {
  purged: number;
  rehinted: number;
  kept: number;
  skipped: number;
  /** Rows whose purge failed this run (storage error or exhausted transaction). */
  failures: number;
  /** Rows at or beyond `maxPurgeAttempts` that were still retried (signal: any capped row). */
  cappedRows: number;
  /** Age of the oldest still-overdue stream in millis, 0 when none (signal: overdue > 2 days). */
  oldestOverdueAgeMs: number;
  /** The recompute continuation result; `undefined` when it could not run. */
  recompute?: RecomputeRunResult;
  /** A query failed with FAILED_PRECONDITION: the composite index is missing (design 6.3). */
  missingIndex: boolean;
  /** The run budget ran out before the candidate walk finished. */
  budgetExhausted: boolean;
  /** `false` when the bucket is not configured and the run did nothing. */
  bucketConfigured: boolean;
}

function newResult(): PurgeRunResult {
  return {
    purged: 0,
    rehinted: 0,
    kept: 0,
    skipped: 0,
    failures: 0,
    cappedRows: 0,
    oldestOverdueAgeMs: 0,
    missingIndex: false,
    budgetExhausted: false,
    bucketConfigured: true,
  };
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_PURGE_EVENT, { operation: "purgeExpiredActivityStreams", ...fields });
}

/** Walks the due candidates page by page until exhausted or the deadline passes. */
async function walkCandidates(
  deps: RetentionDeps,
  limits: RetentionLimits,
  bucket: StreamBucket,
  nowMs: number,
  deadlineMs: number,
  result: PurgeRunResult,
  failedAges: number[],
): Promise<void> {
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let query = deps
      .firestore()
      .collectionGroup("activity_streams")
      .where("state", "==", "stored")
      .where("expiresAt", "<=", admin.firestore.Timestamp.fromMillis(nowMs))
      .orderBy("expiresAt")
      .limit(limits.purgePage);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) return;
    for (const doc of page.docs) {
      if (budgetExhausted(deps.nowMs(), deadlineMs)) {
        result.budgetExhausted = true;
        return;
      }
      const ids = parseStreamRowPath(doc.ref.path);
      if (ids === undefined) continue; // not exactly users/{uid}/activity_streams/{id}
      try {
        const r = await purgeRow(deps, limits, bucket, ids.uid, ids.activityId, nowMs);
        if (r.outcome === "purged") result.purged += 1;
        else if (r.outcome === "rehinted") result.rehinted += 1;
        else if (r.outcome === "kept") result.kept += 1;
        else if (r.outcome === "skipped") result.skipped += 1;
        else {
          result.failures += 1;
          if (r.attempts >= limits.maxPurgeAttempts) result.cappedRows += 1;
          failedAges.push(overdueAgeMs(r.expiryMs ?? null, nowMs));
          log(r.attempts >= limits.maxPurgeAttempts ? "error" : "warn", {
            outcome: r.attempts >= limits.maxPurgeAttempts ? "purge-capped" : "purge-failed",
            attempts: r.attempts,
            errorCode: r.errorCode ?? "unknown",
          });
        }
      } catch (e) {
        // The transaction itself failed (contention, outage): the row is retried next run.
        result.failures += 1;
        failedAges.push(overdueAgeMs(hintMsOf(doc.data() as RowData), nowMs));
        log("warn", { outcome: "purge-failed", errorCode: errorCodeOf(e) });
      }
    }
    if (isLastPage(page.docs.length, limits.purgePage)) return;
    last = page.docs[page.docs.length - 1];
  }
}

/** Age of the oldest row still `stored` whose hint is due (rows left by failures or the budget). */
async function oldestDueHintAgeMs(deps: RetentionDeps, nowMs: number): Promise<number> {
  const snap = await deps
    .firestore()
    .collectionGroup("activity_streams")
    .where("state", "==", "stored")
    .where("expiresAt", "<=", admin.firestore.Timestamp.fromMillis(nowMs))
    .orderBy("expiresAt")
    .limit(1)
    .get();
  if (snap.empty) return 0;
  return overdueAgeMs(hintMsOf(snap.docs[0].data() as RowData), nowMs);
}

/** One purge run; exported so the schedule handler and the tests share it. */
export async function runActivityStreamPurge(
  deps: RetentionDeps = defaultRetentionDeps,
  limits: RetentionLimits = DEFAULT_RETENTION_LIMITS,
): Promise<PurgeRunResult> {
  const result = newResult();
  const bucket = deps.bucket();
  if (bucket === undefined) {
    result.bucketConfigured = false;
    log("info", { outcome: "bucket-unset" });
    return result;
  }
  const nowMs = deps.nowMs();
  const deadlineMs = nowMs + limits.runBudgetMs;
  const failedAges: number[] = [];

  try {
    result.recompute = await runRecomputeContinuation(
      deps,
      limits,
      nowMs,
      recomputeDeadlineMs(nowMs, limits.runBudgetMs),
      (e) => {
        result.failures += 1;
        log("warn", { outcome: "recompute-failed", errorCode: errorCodeOf(e) });
      },
    );
  } catch (e) {
    // A broken recompute (for example a missing index) must not stop the purge.
    result.failures += 1;
    if (isMissingIndexError(e)) result.missingIndex = true;
    log("error", {
      outcome: "recompute-pass-failed",
      errorCode: errorCodeOf(e),
      missingIndex: isMissingIndexError(e),
    });
  }

  try {
    await walkCandidates(deps, limits, bucket, nowMs, deadlineMs, result, failedAges);
  } catch (e) {
    result.failures += 1;
    if (isMissingIndexError(e)) result.missingIndex = true;
    log("error", {
      outcome: "purge-pass-failed",
      errorCode: errorCodeOf(e),
      missingIndex: isMissingIndexError(e),
    });
  }

  let queryAge = 0;
  try {
    queryAge = await oldestDueHintAgeMs(deps, nowMs);
  } catch (e) {
    if (isMissingIndexError(e)) result.missingIndex = true;
    log("error", { outcome: "overdue-query-failed", errorCode: errorCodeOf(e) });
  }
  result.oldestOverdueAgeMs = maxAgeMs([queryAge, ...failedAges]);

  log(result.missingIndex || result.cappedRows > 0 ? "error" : "info", {
    outcome: "run-complete",
    latencyMs: deps.nowMs() - nowMs,
    purged: result.purged,
    rehinted: result.rehinted,
    kept: result.kept,
    skipped: result.skipped,
    failures: result.failures,
    cappedRows: result.cappedRows,
    oldestOverdueAgeMs: result.oldestOverdueAgeMs,
    recomputeBacklogUsers: result.recompute?.backlogUsers ?? 0,
    recomputeBacklogAgeMs: result.recompute?.backlogAgeMs ?? 0,
    recomputeRowsWritten: result.recompute?.rowsWritten ?? 0,
    missingIndex: result.missingIndex,
    budgetExhausted: result.budgetExhausted,
  });
  return result;
}

export const purgeExpiredActivityStreams = onSchedule(
  {
    schedule: "45 3 * * *",
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
  },
  async () => {
    await runActivityStreamPurge();
  },
);
