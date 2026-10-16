/**
 * `deleteAllActivityStreams` -- the seventh callable: resumable bulk "delete my
 * cloud streams" (S02 design 5.4, 6.1, 9.1; story S02-06b).
 *
 * Removes the stream OBJECTS and the stream index ROWS of every activity of the
 * caller and keeps every scalar summary (and the tombstones, settings and
 * consent). It is a RESUMABLE JOB so thousands of activities cannot hit the
 * callable timeout:
 *
 *  - the job state is on the settings document `users/{uid}/activity_settings/main`:
 *    `streamDeleteJobId`, `streamDeleteCursor` (last activity id handled) and
 *    `streamDeletePending = true` (what the scheduled reconciler queries);
 *  - each call processes at most `page` rows (50) inside the time budget, per row
 *    object FIRST (both prefixes of the activity, 404 = success, reused from
 *    `deleteActivity`) and THEN the row, advances the cursor and answers `more`
 *    or `done`; `done` clears the job fields, so a call after `done` starts a
 *    fresh job that finds nothing;
 *  - an interrupted call loses nothing: processed rows are gone, so the next call
 *    lists only what is left; the persisted cursor only skips ahead;
 *  - the scheduled reconciler (`bulkDeleteContinuationPass`) continues unfinished
 *    jobs without a caller, so a client that stops after one page is not the
 *    only thing that can finish the erasure.
 *
 * Hardening (design 5.4): auth, no anonymous users, the fence documents AND Auth
 * existence are checked inside the transaction that starts a page AND the one that
 * records its progress (so an account being deleted never gains a settings
 * document), no client value reaches a path (the request body is ignored; paths
 * come from `request.auth.uid` and ids read from our own rows), bare codes only.
 *
 * Quota: its OWN action `activityDeleteAll` (10 per user per day), independent of
 * the low `activityDelete` ceiling. Only a call that STARTS a job is charged; a
 * continuation of a started job is not (it is bounded by the rows that remain),
 * and a refused start gives the charge back.
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid or id.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { randomBytes } from "crypto";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import {
  DeleteRefusal,
  defaultDeleteActivityDeps,
  deleteActivityObjects,
  type DeleteActivityDeps,
} from "./delete_activity";
import { checkAccountFence } from "./fence";
import { isActivityId } from "./paths";
import type { ReconcileDeps, ReconcileExtraPass } from "./reconcile";
import { parseSettingsPath } from "./retention";
import { activitySettingsPath } from "./settings";
import { errorCodeOf, strOf, type RowData } from "./upload_common";

/** The quota action of this callable (design 5.4); also listed in `REDACTED_QUOTA_ACTIONS`. */
export const DELETE_ALL_QUOTA_ACTION = "activityDeleteAll";

/** The one structured-log message of this callable and its reconciler continuation. */
export const ACTIVITY_DELETE_ALL_EVENT = "activity_delete_all_event";

export interface DeleteAllDeps extends DeleteActivityDeps {
  /** A fresh server-generated job id. */
  newJobId(): string;
}

export const defaultDeleteAllDeps: DeleteAllDeps = {
  ...defaultDeleteActivityDeps,
  newJobId: () => `job_${randomBytes(16).toString("hex")}`,
};

export interface DeleteAllLimits {
  /** Rows per call (design 9.1: at most 50). */
  page: number;
  /** No new row is STARTED after this much time has passed in a call. */
  budgetMs: number;
}

export const DEFAULT_DELETE_ALL_LIMITS: DeleteAllLimits = { page: 50, budgetMs: 40 * 1000 };

export interface DeleteAllResult {
  status: "more" | "done";
  /** Rows (and their objects) removed by this call. */
  deleted: number;
  serverNowMs: number;
}

type RefusalCode = "account_deleting" | "account_deleted" | "quota_exceeded" | "delete_failed";
type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<RefusalCode, HttpsCode> = {
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  quota_exceeded: "resource-exhausted",
  delete_failed: "internal",
};

function toHttpsError(code: RefusalCode): HttpsError {
  return new HttpsError(HTTPS_CODE[code], code);
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_DELETE_ALL_EVENT, { operation: "deleteAllActivityStreams", ...fields });
}

/** True when the settings document carries an active (unfinished) job. */
export function hasActiveDeleteJob(settings: RowData | undefined): boolean {
  return settings?.streamDeletePending === true && strOf(settings.streamDeleteJobId) !== undefined;
}

/**
 * Step 1: fenced transaction that finds the active job or starts one. Returns the
 * cursor to resume from (`undefined` = from the beginning). A `continue` request
 * with no active job returns `null` (nothing to do).
 */
async function beginJob(
  deps: DeleteAllDeps,
  uid: string,
  mode: "start" | "continue",
): Promise<{ cursor: string | undefined } | null> {
  const fs = deps.firestore();
  const ref = fs.doc(activitySettingsPath(uid));
  return fs.runTransaction(async (tx) => {
    const fence = await checkAccountFence(tx, deps, uid);
    if (fence !== "clear") throw new DeleteRefusal(fence);
    const snap = await tx.get(ref);
    const settings = snap.exists ? (snap.data() as RowData) : undefined;
    if (hasActiveDeleteJob(settings)) {
      const cursor = strOf(settings?.streamDeleteCursor);
      return { cursor: cursor !== undefined && isActivityId(cursor) ? cursor : undefined };
    }
    if (mode === "continue") return null;
    tx.set(
      ref,
      {
        streamDeleteJobId: deps.newJobId(),
        streamDeletePending: true,
        streamDeleteCursor: admin.firestore.FieldValue.delete(),
      },
      { merge: true },
    );
    return { cursor: undefined };
  });
}

/** Step 3: fenced transaction that records progress (`done` clears the job fields). */
async function finishPage(
  deps: DeleteAllDeps,
  uid: string,
  done: boolean,
  cursor: string | undefined,
): Promise<void> {
  const fs = deps.firestore();
  const ref = fs.doc(activitySettingsPath(uid));
  const del = admin.firestore.FieldValue.delete();
  await fs.runTransaction(async (tx) => {
    const fence = await checkAccountFence(tx, deps, uid);
    if (fence !== "clear") throw new DeleteRefusal(fence);
    if (done) {
      tx.set(ref, { streamDeleteJobId: del, streamDeletePending: del, streamDeleteCursor: del }, { merge: true });
    } else if (cursor !== undefined) {
      tx.set(ref, { streamDeleteCursor: cursor }, { merge: true });
    }
  });
}

/**
 * One bounded page of the job. Throws `DeleteRefusal` (fence, `delete_failed`).
 * Progress made before a storage failure is persisted first, so a rerun resumes.
 */
export async function runBulkDeletePage(
  deps: DeleteAllDeps,
  uid: string,
  limits: DeleteAllLimits,
  mode: "start" | "continue",
): Promise<DeleteAllResult | null> {
  const begun = await beginJob(deps, uid, mode);
  if (begun === null) return null;
  const fs = deps.firestore();
  const startMs = deps.nowMs();

  let query = fs
    .collection(`users/${uid}/activity_streams`)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(limits.page);
  if (begun.cursor !== undefined) query = query.startAfter(begun.cursor);
  const page = await query.get();

  let deleted = 0;
  let lastId: string | undefined;
  let failed = false;
  let budgetStopped = false;
  for (const doc of page.docs) {
    if (deps.nowMs() - startMs >= limits.budgetMs) {
      budgetStopped = true;
      break;
    }
    if (!isActivityId(doc.id)) {
      lastId = doc.id; // not a row this feature wrote; never build a path from it
      continue;
    }
    try {
      await deleteActivityObjects(deps, uid, doc.id); // objects FIRST (404 = success)
      await doc.ref.delete(); // then the row
      deleted += 1;
      lastId = doc.id;
    } catch (e) {
      failed = true;
      log("warn", { outcome: "row-failed", errorCode: errorCodeOf(e) });
      break;
    }
  }

  const done = !failed && !budgetStopped && page.docs.length < limits.page;
  await finishPage(deps, uid, done, lastId);
  if (failed) throw new DeleteRefusal("delete_failed");
  return { status: done ? "done" : "more", deleted, serverNowMs: deps.nowMs() };
}

/** Whole request pipeline with injectable collaborators. */
export async function handleDeleteAllActivityStreams(
  deps: DeleteAllDeps,
  uid: string,
  signInProvider: string | undefined,
  limits: DeleteAllLimits = DEFAULT_DELETE_ALL_LIMITS,
): Promise<DeleteAllResult> {
  const started = deps.nowMs();
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }

  // Only the call that STARTS a job is charged (own quota, never the activityDelete ceiling).
  let charged = false;
  try {
    const snap = await deps.firestore().doc(activitySettingsPath(uid)).get();
    if (!hasActiveDeleteJob(snap.exists ? (snap.data() as RowData) : undefined)) {
      await enforceDailyQuota(uid, DELETE_ALL_QUOTA_ACTION, QUOTAS.activityDeleteAll);
      charged = true;
    }
  } catch (e) {
    if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
      log("warn", { outcome: "quota_exceeded" });
      throw toHttpsError("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("delete_failed");
  }

  try {
    const result = await runBulkDeletePage(deps, uid, limits, "start");
    if (result === null) throw new DeleteRefusal("delete_failed"); // unreachable in "start" mode
    log("info", { outcome: result.status, deleted: result.deleted, latencyMs: deps.nowMs() - started });
    return result;
  } catch (e) {
    if (e instanceof DeleteRefusal) {
      if (charged && (e.code === "account_deleting" || e.code === "account_deleted")) {
        await refundQuota(uid, DELETE_ALL_QUOTA_ACTION, 1);
      }
      log("warn", { outcome: e.code });
      throw toHttpsError(e.code as RefusalCode);
    }
    log("error", { outcome: "delete_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("delete_failed");
  }
}

/**
 * Reconciler pass: advances unfinished jobs (`streamDeletePending == true`, a
 * single-field collection-group override in `firestore.indexes.json`), at most 20
 * users per run, one page each. A fenced (deleting) account is skipped: the
 * late sweep owns it.
 */
export const bulkDeleteContinuationPass: ReconcileExtraPass = async (
  deps: ReconcileDeps,
  result,
) => {
  const bulkDeps: DeleteAllDeps = { ...deps, newJobId: defaultDeleteAllDeps.newJobId };
  const snap = await deps
    .firestore()
    .collectionGroup("activity_settings")
    .where("streamDeletePending", "==", true)
    .limit(20)
    .get();
  for (const doc of snap.docs) {
    const uid = parseSettingsPath(doc.ref.path);
    if (uid === undefined) continue;
    try {
      const r = await runBulkDeletePage(bulkDeps, uid, DEFAULT_DELETE_ALL_LIMITS, "continue");
      if (r !== null) result.bulkDeleteAdvanced += 1;
    } catch (e) {
      if (e instanceof DeleteRefusal && (e.code === "account_deleting" || e.code === "account_deleted")) continue;
      result.failures += 1;
      log("warn", { outcome: "continuation-failed", errorCode: errorCodeOf(e) });
    }
  }
};

export const deleteAllActivityStreams = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "deleteAllActivityStreams");
  // The request body is deliberately ignored: no client value reaches a path or a query.
  return handleDeleteAllActivityStreams(
    defaultDeleteAllDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
  );
});
