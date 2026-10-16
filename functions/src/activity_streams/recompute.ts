/**
 * Recompute continuation (S02 design 5.3; story S02-05b): rewrites the expiry
 * HINT (and `settingsGeneration`) of a user's stream rows after the retention
 * setting changed. It is run at the start of every `purgeExpiredActivityStreams`
 * run (no separate scheduler, no 5-minute cadence).
 *
 * Shape:
 *  1. Discovery: collection group `activity_settings` where `recomputePending ==
 *     true` (index 2), at most `recomputeUsersPerRun` users per run.
 *  2. Per user: pages of `recomputePage` rows ordered by id from `recomputeCursor`
 *     (honoured only for the current `recomputeGeneration`). Each row is rewritten
 *     in its own transaction that re-reads the settings, so a setting changed
 *     mid-run is respected; an unchanged row is not written at all, so a rerun
 *     after a crash never double-writes. The cursor is advanced per page by a
 *     compare-and-set on the generation, so a setting change during the run
 *     makes the user restart from the beginning at the next run.
 *  3. A user may use at most `recomputePagesPerUser` pages per run; the cursor is
 *     persisted, so the next run resumes after it and a heavy user cannot starve
 *     the others for ever.
 *  4. Final pass for the user: `activity_streams` where `settingsGeneration <
 *     current` (a single-field range with a constant; `state` is filtered in
 *     memory, so no composite index is needed) catches rows committed with an
 *     older generation. `recomputePending` becomes `false` only when that pass
 *     finds nothing, by a compare-and-set on the generation.
 *
 * The hint is only a query accelerator: purge re-derives expiry, so a stale hint
 * can never extend retention. Logs and results carry counts and ages only.
 */
import * as admin from "firebase-admin";
import { activityStreamRowPath, activitySummaryPath } from "./paths";
import {
  backlogAgeMs,
  budgetExhausted,
  effectiveRecomputeCursor,
  isLastPage,
  nextCursor,
  parseSettingsPath,
  planRecomputeRow,
  type RetentionDeps,
  type RetentionLimits,
} from "./retention";
import { activitySettingsPath, settingsGenerationOf } from "./settings";
import { timestampMs, type RowData } from "./upload_common";

export type RowRewriteOutcome = "written" | "stamped" | "unchanged";

/**
 * Rewrites ONE row inside a transaction that re-reads the row, the settings and
 * the summary. Reads precede the single write.
 */
export async function recomputeRow(
  deps: RetentionDeps,
  uid: string,
  activityId: string,
  nowMs: number,
): Promise<RowRewriteOutcome> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, activityId));
  const settingsRef = fs.doc(activitySettingsPath(uid));
  const summaryRef = fs.doc(activitySummaryPath(uid, activityId));
  return fs.runTransaction(async (tx): Promise<RowRewriteOutcome> => {
    const [rowSnap, settingsSnap, summarySnap] = await Promise.all([
      tx.get(rowRef),
      tx.get(settingsRef),
      tx.get(summaryRef),
    ]);
    const settings = settingsSnap.exists ? (settingsSnap.data() as RowData) : undefined;
    const summaryStartMs = summarySnap.exists
      ? timestampMs((summarySnap.data() as RowData | undefined)?.startUtc)
      : undefined;
    const plan = planRecomputeRow(
      rowSnap.exists ? (rowSnap.data() as RowData) : undefined,
      settings,
      summaryStartMs,
      nowMs,
    );
    const generation = settingsGenerationOf(settings);
    if (plan.kind === "hint") {
      tx.set(
        rowRef,
        {
          expiresAt: plan.expiryMs === null ? null : admin.firestore.Timestamp.fromMillis(plan.expiryMs),
          settingsGeneration: generation,
        },
        { merge: true },
      );
      return "written";
    }
    if (plan.kind === "stamp") {
      tx.set(rowRef, { settingsGeneration: generation }, { merge: true });
      return "stamped";
    }
    return "unchanged";
  });
}

/**
 * Persists the cursor after a page, only while the user's settings still carry
 * the generation this walk started with and are still pending. `false` means
 * the setting changed (or was cleared) and the walk must stop.
 */
export async function advanceRecomputeCursor(
  deps: RetentionDeps,
  uid: string,
  generation: number,
  cursor: string,
): Promise<boolean> {
  const fs = deps.firestore();
  const ref = fs.doc(activitySettingsPath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? (snap.data() as RowData) : undefined;
    if (!data || data.recomputePending !== true || settingsGenerationOf(data) !== generation) return false;
    tx.set(ref, { recomputeCursor: cursor, recomputeGeneration: generation }, { merge: true });
    return true;
  });
}

/**
 * Clears `recomputePending` (and the cursor) once the final pass found nothing,
 * only if the generation is still the one the pass ran against. `false` means a
 * newer setting change arrived: the flag stays true and the next run restarts.
 */
export async function clearRecomputePending(
  deps: RetentionDeps,
  uid: string,
  generation: number,
): Promise<boolean> {
  const fs = deps.firestore();
  const ref = fs.doc(activitySettingsPath(uid));
  return fs.runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.exists ? (snap.data() as RowData) : undefined;
    if (!data) return false;
    if (settingsGenerationOf(data) !== generation) return false;
    tx.set(ref, { recomputePending: false, recomputeCursor: null, recomputeGeneration: null }, { merge: true });
    return true;
  });
}

export interface UserRecomputeResult {
  /** Rows written (hint or generation stamp) for this user in this run. */
  rowsWritten: number;
  /** `true` when `recomputePending` was cleared by this call (or was already false). */
  completed: boolean;
}

/**
 * Advances one user's recompute within the page cap and the deadline. Never
 * throws for an unfinished walk: an unfinished user simply stays pending.
 */
export async function recomputeUser(
  deps: RetentionDeps,
  limits: RetentionLimits,
  uid: string,
  nowMs: number,
  deadlineMs: number,
): Promise<UserRecomputeResult> {
  const fs = deps.firestore();
  const settingsRef = fs.doc(activitySettingsPath(uid));
  const result: UserRecomputeResult = { rowsWritten: 0, completed: false };

  const settingsSnap = await settingsRef.get();
  const settings = settingsSnap.exists ? (settingsSnap.data() as RowData) : undefined;
  if (!settings || settings.recomputePending !== true) return { rowsWritten: 0, completed: true };
  const generation = settingsGenerationOf(settings);
  let cursor = effectiveRecomputeCursor(settings);
  let exhausted = false;

  for (let page = 0; page < limits.recomputePagesPerUser; page++) {
    if (budgetExhausted(deps.nowMs(), deadlineMs)) return result;
    let query = fs
      .collection(`users/${uid}/activity_streams`)
      .orderBy("__name__")
      .limit(limits.recomputePage);
    if (cursor !== undefined) query = query.startAfter(cursor);
    const snap = await query.get();
    const ids: string[] = [];
    for (const doc of snap.docs) {
      if (budgetExhausted(deps.nowMs(), deadlineMs)) return result;
      const outcome = await recomputeRow(deps, uid, doc.id, nowMs);
      if (outcome !== "unchanged") result.rowsWritten += 1;
      ids.push(doc.id);
    }
    if (isLastPage(snap.docs.length, limits.recomputePage)) {
      exhausted = true;
      break;
    }
    cursor = nextCursor(ids, cursor);
    // Cursor advance is one compare-and-set; a changed generation ends this walk.
    if (cursor === undefined || !(await advanceRecomputeCursor(deps, uid, generation, cursor))) {
      return result;
    }
  }
  if (!exhausted) return result;

  // Final pass: rows committed with an older generation. Loops until it finds nothing.
  for (let pass = 0; pass < limits.recomputePagesPerUser; pass++) {
    if (budgetExhausted(deps.nowMs(), deadlineMs)) return result;
    const freshSnap = await settingsRef.get();
    const fresh = freshSnap.exists ? (freshSnap.data() as RowData) : undefined;
    const current = settingsGenerationOf(fresh);
    const stale = await fs
      .collection(`users/${uid}/activity_streams`)
      .where("settingsGeneration", "<", current)
      .limit(limits.recomputePage)
      .get();
    if (stale.empty) {
      result.completed = await clearRecomputePending(deps, uid, current);
      return result;
    }
    for (const doc of stale.docs) {
      if (budgetExhausted(deps.nowMs(), deadlineMs)) return result;
      const outcome = await recomputeRow(deps, uid, doc.id, nowMs);
      if (outcome !== "unchanged") result.rowsWritten += 1;
    }
  }
  return result;
}

export interface RecomputeRunResult {
  usersSelected: number;
  usersCompleted: number;
  rowsWritten: number;
  /** Users still pending after this run (count of the signal in design 6.3). */
  backlogUsers: number;
  /** Age of the oldest still-pending user's last settings change in millis, 0 when none. */
  backlogAgeMs: number;
  failures: number;
}

/**
 * The continuation a purge run starts with. A failing user is counted and the
 * next user is still processed; a query failure is rethrown so the caller can
 * raise the missing-index signal.
 */
export async function runRecomputeContinuation(
  deps: RetentionDeps,
  limits: RetentionLimits,
  nowMs: number,
  deadlineMs: number,
  onUserFailure: (e: unknown) => void,
): Promise<RecomputeRunResult> {
  const out: RecomputeRunResult = {
    usersSelected: 0,
    usersCompleted: 0,
    rowsWritten: 0,
    backlogUsers: 0,
    backlogAgeMs: 0,
    failures: 0,
  };
  const pending = await deps
    .firestore()
    .collectionGroup("activity_settings")
    .where("recomputePending", "==", true)
    .limit(limits.recomputeUsersPerRun)
    .get();

  const stillPendingSince: number[] = [];
  for (const doc of pending.docs) {
    const uid = parseSettingsPath(doc.ref.path);
    if (uid === undefined) continue;
    out.usersSelected += 1;
    if (budgetExhausted(deps.nowMs(), deadlineMs)) {
      stillPendingSince.push(timestampMs((doc.data() as RowData).updatedAt) ?? nowMs);
      continue;
    }
    try {
      const r = await recomputeUser(deps, limits, uid, nowMs, deadlineMs);
      out.rowsWritten += r.rowsWritten;
      if (r.completed) {
        out.usersCompleted += 1;
      } else {
        stillPendingSince.push(timestampMs((doc.data() as RowData).updatedAt) ?? nowMs);
      }
    } catch (e) {
      out.failures += 1;
      stillPendingSince.push(timestampMs((doc.data() as RowData).updatedAt) ?? nowMs);
      onUserFailure(e);
    }
  }
  out.backlogUsers = stillPendingSince.length;
  out.backlogAgeMs = backlogAgeMs(stillPendingSince, nowMs);
  return out;
}
