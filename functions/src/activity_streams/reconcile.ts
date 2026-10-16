/**
 * Orphan reconciler for cloud activity streams (S02 design 5.2, 6, 6.1, 6.3;
 * story S02-06b). Scheduled every 5 minutes (pattern of `sweepLateBodyScanUploads`).
 *
 * Three independent passes, each in its own try/catch so a failure of one never
 * stops the others (design 6.1 positive cleanup invariant):
 *
 *  1. PENDING rows beyond a bound. Collection group `activity_streams` where
 *     `pendingSince <= now - 1 h` (covers a never-stored `pending` row AND a
 *     `stored` row with `pendingUploadId`; single-field collection-group
 *     override in `firestore.indexes.json`). Repair rule: when the promoted object
 *     at the upload's path hashes to the row's `intendedStoredSha256` (recorded
 *     BEFORE promotion; the client `contentSha256` would never match), the repair
 *     runs through `selectPromotedObject`, whose transaction re-checks fence,
 *     Auth, tombstone, summary, consent and the current `uploadId`; a refusal
 *     there, a hash mismatch, a missing object or an unreadable object makes the
 *     reconciler DELETE the upload's objects and clear the pending marker instead
 *     (`clearPendingUpload`: a never-stored row is removed, a stored row keeps its
 *     old object). A good upload interrupted between promotion and the `stored`
 *     write is therefore never lost.
 *  2. STORED rows (cursor walk over `state == stored` ordered by `expiresAt`, the
 *     purge index): a row without a summary is removed together with its
 *     objects; a row whose object is missing becomes `deleted` with
 *     `lastErrorCode = object_missing` (signal). A healthy row is NOT written.
 *  3. OBJECTS (cursor walk over `streams/` and `quarantine/`): an object older
 *     than the upload TTL that no row references (no row, row not stored at that
 *     path, or not the current pending upload) is deleted. This also removes the
 *     previous object after a path switch. Unrecognised names are counted and
 *     left alone.
 *
 * Cursors live in the server-only document `activity_reconcile_state/main` (no
 * client rule; default deny), so a bucket larger than one run's budget is still
 * covered over several runs. Signals (design 6.3) are ONE structured log entry
 * per run: counts, ages and bare codes only; never a uid, id or path.
 */
import * as admin from "firebase-admin";
import * as logger from "firebase-functions/logger";
import { gunzipSync } from "zlib";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { activityStreamListingBucket, type StreamListingBucket } from "./bucket";
import { clearPendingUpload, currentUploadId, expectedHashOf, selectPromotedObject } from "./commit_stream";
import { sha256Equal, sha256Hex } from "./hash";
import {
  ACTIVITY_ID_PATTERN,
  UID_PATTERN,
  UPLOAD_ID_PATTERN,
  activityQuarantinePrefix,
  activityStreamRowPath,
  activityStreamsPrefix,
  activitySummaryPath,
  quarantineObjectPath,
  streamObjectPath,
} from "./paths";
import { parseStreamRowPath } from "./retention";
import {
  UPLOAD_URL_TTL_MS,
  UploadRefusal,
  defaultUploadDeps,
  errorCodeOf,
  isNotFound,
  strOf,
  timestampMs,
  type RowData,
  type UploadDeps,
} from "./upload_common";

/** The one structured-log message of this job (GPS-PRIV-094: no uid, id or path in any field). */
export const ACTIVITY_RECONCILE_EVENT = "activity_reconcile_event";

/** A `pending` row (or a pending re-upload marker) older than this is reconciled (design 6). */
export const PENDING_BOUND_MS = 60 * 60 * 1000;

/** An unreferenced object younger than this is left alone (it may be mid-commit): the upload TTL. */
export const ORPHAN_MIN_AGE_MS = UPLOAD_URL_TTL_MS;

/** The decompressed size cap of the validator (design 5.1); also bounds the repair parse. */
const MAX_DECOMPRESSED_BYTES = 32 * 1024 * 1024;

/** Cursor document of the reconciler (server-only). */
export const RECONCILE_STATE_PATH = "activity_reconcile_state/main";

/** Injectable collaborators: the upload seam (Firestore, Auth, clock, bucket) plus a listing bucket. */
export interface ReconcileDeps extends UploadDeps {
  listing(): StreamListingBucket | undefined;
}

export const defaultReconcileDeps: ReconcileDeps = {
  ...defaultUploadDeps,
  listing: () => activityStreamListingBucket(),
};

export interface ReconcileLimits {
  pendingPage: number;
  rowsPerRun: number;
  objectPage: number;
  objectPagesPerRun: number;
  runBudgetMs: number;
}

export const DEFAULT_RECONCILE_LIMITS: ReconcileLimits = {
  pendingPage: 50,
  rowsPerRun: 100,
  objectPage: 200,
  objectPagesPerRun: 5,
  runBudgetMs: 240 * 1000,
};

export interface ReconcileRunResult {
  pendingRepaired: number;
  pendingAborted: number;
  pendingKept: number;
  /** Age in millis of the oldest still-pending row seen (signal: oldest > 1 h), 0 when none. */
  oldestPendingAgeMs: number;
  rowsWithoutSummary: number;
  /** Stored rows whose object was missing (signal). */
  storedObjectMissing: number;
  orphansDeleted: number;
  unrecognised: number;
  /** Age in millis of the oldest quarantine object seen (signal: oldest > 1 day), 0 when none. */
  oldestQuarantineAgeMs: number;
  failures: number;
  budgetExhausted: boolean;
  bucketConfigured: boolean;
  /** Bulk-delete jobs advanced in this run (filled by the bulk-delete continuation, if present). */
  bulkDeleteAdvanced: number;
}

export function newReconcileResult(): ReconcileRunResult {
  return {
    pendingRepaired: 0,
    pendingAborted: 0,
    pendingKept: 0,
    oldestPendingAgeMs: 0,
    rowsWithoutSummary: 0,
    storedObjectMissing: 0,
    orphansDeleted: 0,
    unrecognised: 0,
    oldestQuarantineAgeMs: 0,
    failures: 0,
    budgetExhausted: false,
    bucketConfigured: true,
    bulkDeleteAdvanced: 0,
  };
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_RECONCILE_EVENT, { operation: "reconcileActivityStreams", ...fields });
}

/** The `kinds` of a canonical stored object, or `undefined` when it cannot be parsed. */
export function kindsOfCanonicalObject(bytes: Buffer): string[] | undefined {
  try {
    const parsed = JSON.parse(gunzipSync(bytes, { maxOutputLength: MAX_DECOMPRESSED_BYTES }).toString("utf8")) as {
      kinds?: unknown;
    };
    const kinds = parsed.kinds;
    if (typeof kinds !== "object" || kinds === null || Array.isArray(kinds)) return undefined;
    return Object.keys(kinds);
  } catch {
    return undefined;
  }
}

/** Best-effort delete of one object; a Storage failure is rethrown so the row is retried next run. */
async function deleteObject(bucket: StreamListingBucket, path: string): Promise<void> {
  try {
    await bucket.file(path).delete({ ignoreNotFound: true });
  } catch (e) {
    if (!isNotFound(e)) throw e;
  }
}

/** Deletes all objects under a prefix (404 = success); failures are rethrown. */
async function deletePrefixQuietly(bucket: StreamListingBucket, prefix: string): Promise<void> {
  try {
    await bucket.deleteFiles({ prefix, force: true });
  } catch (e) {
    const errors: unknown[] = Array.isArray(e) ? e : [e];
    if (!(errors.length > 0 && errors.every(isNotFound))) throw errors[0] ?? e;
  }
}

export type PendingOutcome = "repaired" | "aborted" | "kept";

/**
 * One pending row (design 6 repair rule). Reads the row, then the promoted
 * object once; the repair itself re-checks everything inside its transaction.
 */
export async function reconcilePendingRow(
  deps: ReconcileDeps,
  bucket: StreamListingBucket,
  uid: string,
  activityId: string,
): Promise<PendingOutcome> {
  const fs = deps.firestore();
  const rowSnap = await fs.doc(activityStreamRowPath(uid, activityId)).get();
  if (!rowSnap.exists) return "kept";
  const row = rowSnap.data() as RowData;
  const uploadId = currentUploadId(row);
  if (uploadId === undefined) return "kept"; // no longer pending: nothing to do
  const req = { activityId, uploadId };
  const promotedPath = streamObjectPath(uid, activityId, uploadId);

  let bytes: Buffer | undefined;
  try {
    [bytes] = await bucket.file(promotedPath).download();
  } catch (e) {
    if (!isNotFound(e)) throw e;
  }

  const intended = strOf(row.intendedStoredSha256);
  const contentSha256 = expectedHashOf(row);
  if (bytes !== undefined && intended !== undefined && contentSha256 !== undefined) {
    const storedSha256 = sha256Hex(bytes);
    const kinds = sha256Equal(storedSha256, intended) ? kindsOfCanonicalObject(bytes) : undefined;
    if (kinds !== undefined) {
      try {
        const selected = await selectPromotedObject(deps, uid, req, {
          bytes: bytes.length,
          kinds,
          storedSha256,
          contentSha256,
        });
        if (selected.alreadySelected) return "kept";
        if (selected.previousPath !== undefined && selected.previousPath !== promotedPath) {
          await deleteObject(bucket, selected.previousPath).catch(() => undefined);
        }
        return "repaired";
      } catch (e) {
        // Fence, tombstone, summary, consent or supersession refused the repair: delete instead.
        if (!(e instanceof UploadRefusal)) throw e;
      }
    }
  }

  // Abort: remove only THIS upload's own objects, then the pending marker.
  await deleteObject(bucket, promotedPath);
  await deleteObject(bucket, quarantineObjectPath(uid, activityId, uploadId));
  await clearPendingUpload(deps, uid, req);
  return "aborted";
}

async function readCursors(fs: FirebaseFirestore.Firestore): Promise<RowData> {
  const snap = await fs.doc(RECONCILE_STATE_PATH).get();
  return snap.exists ? (snap.data() as RowData) : {};
}

async function writeCursors(fs: FirebaseFirestore.Firestore, patch: Record<string, unknown>): Promise<void> {
  await fs.doc(RECONCILE_STATE_PATH).set(patch, { merge: true });
}

async function pendingPass(
  deps: ReconcileDeps,
  limits: ReconcileLimits,
  bucket: StreamListingBucket,
  deadlineMs: number,
  result: ReconcileRunResult,
): Promise<void> {
  const nowMs = deps.nowMs();
  const cutoff = admin.firestore.Timestamp.fromMillis(nowMs - PENDING_BOUND_MS);
  let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
  for (;;) {
    let query = deps
      .firestore()
      .collectionGroup("activity_streams")
      .where("pendingSince", "<=", cutoff)
      .orderBy("pendingSince")
      .limit(limits.pendingPage);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) return;
    for (const doc of page.docs) {
      if (deps.nowMs() >= deadlineMs) {
        result.budgetExhausted = true;
        return;
      }
      const ids = parseStreamRowPath(doc.ref.path);
      if (ids === undefined) continue;
      try {
        const outcome = await reconcilePendingRow(deps, bucket, ids.uid, ids.activityId);
        if (outcome === "repaired") result.pendingRepaired += 1;
        else if (outcome === "aborted") result.pendingAborted += 1;
        else result.pendingKept += 1;
        if (outcome === "kept") {
          const since = timestampMs((doc.data() as RowData).pendingSince);
          if (since !== undefined) result.oldestPendingAgeMs = Math.max(result.oldestPendingAgeMs, nowMs - since);
        }
      } catch (e) {
        result.failures += 1;
        log("warn", { outcome: "pending-failed", errorCode: errorCodeOf(e) });
      }
    }
    if (page.docs.length < limits.pendingPage) return;
    last = page.docs[page.docs.length - 1];
  }
}

/** One stored row: summary gone -> remove objects and row; object gone -> `deleted`. Healthy rows are not written. */
async function checkStoredRow(
  deps: ReconcileDeps,
  bucket: StreamListingBucket,
  uid: string,
  activityId: string,
  result: ReconcileRunResult,
): Promise<void> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, activityId));
  const [rowSnap, summarySnap] = await Promise.all([rowRef.get(), fs.doc(activitySummaryPath(uid, activityId)).get()]);
  if (!rowSnap.exists) return;
  const row = rowSnap.data() as RowData;
  if (row.state !== "stored") return;

  if (!summarySnap.exists) {
    await deletePrefixQuietly(bucket, activityStreamsPrefix(uid, activityId));
    await deletePrefixQuietly(bucket, activityQuarantinePrefix(uid, activityId));
    await rowRef.delete();
    result.rowsWithoutSummary += 1;
    return;
  }

  const objectPath = strOf(row.objectPath);
  if (objectPath === undefined || !objectPath.startsWith(activityStreamsPrefix(uid, activityId))) return;
  let missing = false;
  try {
    await bucket.file(objectPath).getMetadata();
  } catch (e) {
    if (!isNotFound(e)) throw e;
    missing = true;
  }
  if (!missing) return;
  const marked = await fs.runTransaction(async (tx) => {
    const snap = await tx.get(rowRef);
    const cur = snap.exists ? (snap.data() as RowData) : undefined;
    if (cur === undefined || cur.state !== "stored" || cur.objectPath !== objectPath) return false;
    tx.set(
      rowRef,
      {
        state: "deleted",
        deletedAt: admin.firestore.Timestamp.fromMillis(deps.nowMs()),
        lastErrorCode: "object_missing",
      },
      { merge: true },
    );
    return true;
  });
  if (marked) result.storedObjectMissing += 1;
}

async function storedRowPass(
  deps: ReconcileDeps,
  limits: ReconcileLimits,
  bucket: StreamListingBucket,
  deadlineMs: number,
  result: ReconcileRunResult,
): Promise<void> {
  const fs = deps.firestore();
  const cursors = await readCursors(fs);
  let query = fs
    .collectionGroup("activity_streams")
    .where("state", "==", "stored")
    .orderBy("expiresAt")
    .limit(limits.rowsPerRun);
  const cursorPath = strOf(cursors.rowCursor);
  if (cursorPath !== undefined && parseStreamRowPath(cursorPath) !== undefined) {
    const snap = await fs.doc(cursorPath).get();
    if (snap.exists) query = query.startAfter(snap);
  }
  const page = await query.get();
  let lastPath: string | undefined;
  for (const doc of page.docs) {
    if (deps.nowMs() >= deadlineMs) {
      result.budgetExhausted = true;
      break;
    }
    lastPath = doc.ref.path;
    const ids = parseStreamRowPath(doc.ref.path);
    if (ids === undefined) continue;
    try {
      await checkStoredRow(deps, bucket, ids.uid, ids.activityId, result);
    } catch (e) {
      result.failures += 1;
      log("warn", { outcome: "stored-row-failed", errorCode: errorCodeOf(e) });
    }
  }
  const finished = page.docs.length < limits.rowsPerRun && !result.budgetExhausted;
  await writeCursors(fs, {
    rowCursor: finished || lastPath === undefined ? admin.firestore.FieldValue.delete() : lastPath,
  });
}

const STREAM_NAME = new RegExp(
  `^streams/(${UID_PATTERN.source.slice(1, -1)})/(${ACTIVITY_ID_PATTERN.source.slice(1, -1)})/(${UPLOAD_ID_PATTERN.source.slice(1, -1)})\\.json\\.gz$`,
);
const QUARANTINE_NAME = new RegExp(
  `^quarantine/(${UID_PATTERN.source.slice(1, -1)})/(${ACTIVITY_ID_PATTERN.source.slice(1, -1)})/(${UPLOAD_ID_PATTERN.source.slice(1, -1)})$`,
);

/** True when a row still references the object `name` (so it is not an orphan). */
export function rowReferencesObject(
  row: RowData | undefined,
  kind: "streams" | "quarantine",
  uid: string,
  activityId: string,
  uploadId: string,
): boolean {
  if (row === undefined) return false;
  const current = currentUploadId(row);
  if (kind === "streams") {
    if (row.state === "stored" && row.objectPath === streamObjectPath(uid, activityId, uploadId)) return true;
    return current === uploadId;
  }
  return current === uploadId;
}

async function objectPass(
  deps: ReconcileDeps,
  limits: ReconcileLimits,
  bucket: StreamListingBucket,
  kind: "streams" | "quarantine",
  deadlineMs: number,
  result: ReconcileRunResult,
): Promise<void> {
  const fs = deps.firestore();
  const field = kind === "streams" ? "streamsCursor" : "quarantineCursor";
  const pattern = kind === "streams" ? STREAM_NAME : QUARANTINE_NAME;
  const cursors = await readCursors(fs);
  const stored = strOf(cursors[field]);
  let startOffset = stored !== undefined && stored.startsWith(`${kind}/`) ? stored : undefined;
  let lastName: string | undefined;
  let more = false;

  for (let p = 0; p < limits.objectPagesPerRun; p++) {
    const [files, next] = await bucket.getFiles({
      prefix: `${kind}/`,
      autoPaginate: false,
      maxResults: limits.objectPage,
      ...(startOffset ? { startOffset } : {}),
    });
    for (const file of files) {
      if (deps.nowMs() >= deadlineMs) {
        result.budgetExhausted = true;
        more = true;
        break;
      }
      lastName = file.name;
      const m = pattern.exec(file.name);
      if (!m) {
        result.unrecognised += 1;
        continue;
      }
      const createdMs = Date.parse(file.metadata?.timeCreated ?? "");
      if (!Number.isFinite(createdMs)) continue;
      const ageMs = deps.nowMs() - createdMs;
      if (kind === "quarantine") result.oldestQuarantineAgeMs = Math.max(result.oldestQuarantineAgeMs, ageMs);
      if (ageMs < ORPHAN_MIN_AGE_MS) continue;
      try {
        const rowSnap = await fs.doc(activityStreamRowPath(m[1], m[2])).get();
        const row = rowSnap.exists ? (rowSnap.data() as RowData) : undefined;
        if (rowReferencesObject(row, kind, m[1], m[2], m[3])) continue;
        await file.delete({ ignoreNotFound: true });
        result.orphansDeleted += 1;
      } catch (e) {
        result.failures += 1;
        log("warn", { outcome: "orphan-failed", errorCode: errorCodeOf(e) });
      }
    }
    if (result.budgetExhausted) break;
    more = next !== undefined && next !== null && files.length > 0;
    if (!more) break;
    startOffset = lastName;
  }
  await writeCursors(fs, { [field]: more && lastName !== undefined ? lastName : admin.firestore.FieldValue.delete() });
}

/** Extra passes appended by later pieces of the story (the bulk-delete continuation). */
export type ReconcileExtraPass = (deps: ReconcileDeps, result: ReconcileRunResult) => Promise<void>;

/** One reconciler run; exported so the schedule handler and the tests share it. */
export async function runActivityReconcile(
  deps: ReconcileDeps = defaultReconcileDeps,
  limits: ReconcileLimits = DEFAULT_RECONCILE_LIMITS,
  extraPasses: readonly ReconcileExtraPass[] = [],
): Promise<ReconcileRunResult> {
  const result = newReconcileResult();
  const startMs = deps.nowMs();
  const deadlineMs = startMs + limits.runBudgetMs;
  const bucket = deps.listing();
  if (bucket === undefined) {
    result.bucketConfigured = false;
    log("info", { outcome: "bucket-unset" });
    return result;
  }
  const passes: Array<[string, () => Promise<void>]> = [
    ["pending", () => pendingPass(deps, limits, bucket, deadlineMs, result)],
    ["stored-rows", () => storedRowPass(deps, limits, bucket, deadlineMs, result)],
    ["streams-objects", () => objectPass(deps, limits, bucket, "streams", deadlineMs, result)],
    ["quarantine-objects", () => objectPass(deps, limits, bucket, "quarantine", deadlineMs, result)],
    ...extraPasses.map((p): [string, () => Promise<void>] => ["extra", () => p(deps, result)]),
  ];
  for (const [name, run] of passes) {
    try {
      await run();
    } catch (e) {
      result.failures += 1;
      log("error", { outcome: "pass-failed", pass: name, errorCode: errorCodeOf(e) });
    }
  }
  log(result.failures > 0 ? "error" : "info", {
    outcome: "run-complete",
    latencyMs: deps.nowMs() - startMs,
    pendingRepaired: result.pendingRepaired,
    pendingAborted: result.pendingAborted,
    pendingKept: result.pendingKept,
    oldestPendingAgeMs: result.oldestPendingAgeMs,
    rowsWithoutSummary: result.rowsWithoutSummary,
    storedObjectMissing: result.storedObjectMissing,
    orphansDeleted: result.orphansDeleted,
    unrecognised: result.unrecognised,
    oldestQuarantineAgeMs: result.oldestQuarantineAgeMs,
    failures: result.failures,
    bulkDeleteAdvanced: result.bulkDeleteAdvanced,
    budgetExhausted: result.budgetExhausted,
  });
  return result;
}

export const reconcileActivityStreams = onSchedule(
  {
    schedule: "every 5 minutes",
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
  },
  async () => {
    await runActivityReconcile();
  },
);
