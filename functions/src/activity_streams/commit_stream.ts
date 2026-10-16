/**
 * `commitActivityStream` -- second half of the cloud stream upload
 * (S02 design 5.1, 5.1a, 5.2 item 2 and 3, 5.3, 5.4; story S02-04b).
 *
 * Order (part of the contract): auth -> App Check note -> non-anonymous ->
 * validate -> bucket configured -> daily quota -> then the idempotent commit:
 *
 *   T1  transaction: fence (documents + Auth existence), tombstone, summary,
 *       consent, "already stored" success, `uploadId` is the row's current id
 *       (else bare `superseded`), derived expiry not already due (else the
 *       pending marker is cleared in the same transaction and bare `expired`
 *       follows after the quarantine object is deleted);
 *   (b) read the quarantine object ONCE: metadata first, then the bytes pinned
 *       to that object generation, into memory; validate (S02-04a) and
 *       re-serialise canonically from those SAME bytes;
 *   (c) transaction: write `intendedStoredSha256` onto the row BEFORE promotion
 *       (the reconciler repairs a crash window by comparing against it), then
 *       write the canonical bytes to `streams/<uid>/<activityId>/<uploadId>.json.gz`;
 *   (d) T2 transaction: re-check fence, tombstone, consent and `uploadId`, then
 *       SELECT that path in one write (`objectPath`, `state = stored`, `bytes`,
 *       `kinds`, `storedSha256`, `expiresAt` hint, `settingsGeneration`) and
 *       clear the pending fields. The previous object is deleted only AFTER T2.
 *
 * Compensation: a refusal (a bare `UploadRefusal`) after the bytes were read
 * deletes this commit's OWN quarantine object and, when already promoted, its
 * OWN promoted object (paths contain this `uploadId`, so another commit's
 * object can never be touched). An infrastructure failure between (c) and (d)
 * deliberately leaves the promoted object: `intendedStoredSha256` lets the
 * reconciler repair the row instead of losing a good upload.
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid,
 * activity id, upload id, path or hash.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { ACTIVITY_COMMIT } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { assertFeatureEnabled } from "../feature_flags";
import { MAX_COMPRESSED_BYTES, STREAM_PAYLOAD_SCHEMA } from "./schema";
import type { StreamBucket } from "./bucket";
import {
  activityStreamRowPath,
  isActivityId,
  isUploadId,
  quarantineObjectPath,
  streamObjectPath,
} from "./paths";
import { validateUploadedStream } from "./upload_validate";
import {
  COMMIT_QUOTA_ACTION,
  STREAM_CONTENT_TYPE,
  UploadRefusal,
  activityDateMs,
  defaultUploadDeps,
  derivedExpiryMs,
  errorCodeOf,
  isExpiryDue,
  isNotFound,
  readUploadContext,
  strOf,
  toUploadHttpsError,
  type RowData,
  type UploadDeps,
} from "./upload_common";

/** The one structured-log message of this callable. */
export const ACTIVITY_COMMIT_EVENT = "activity_commit_event";

export interface CommitRequest {
  activityId: string;
  uploadId: string;
}

export interface CommitResult {
  /** `already_stored` = an earlier commit of the same upload id (or hash) finished first. */
  status: "stored" | "already_stored";
  bytes?: number;
  kinds?: string[];
  /** Expiry hint in epoch millis, `null` = never. */
  expiresAtMs?: number | null;
  serverNowMs: number;
}

/** Strict parse of `{activityId, uploadId}`; unknown client fields are ignored. */
export function parseCommitRequest(data: unknown): CommitRequest {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  if (!isActivityId(d.activityId) || !isUploadId(d.uploadId)) throw new UploadRefusal("invalid_request");
  return { activityId: d.activityId, uploadId: d.uploadId };
}

/** The pending upload id of a row: the re-upload marker first, else a never-stored row's own id. */
export function currentUploadId(row: RowData): string | undefined {
  return strOf(row.pendingUploadId) ?? (row.state === "pending" ? strOf(row.uploadId) : undefined);
}

/** The client hash the pending upload must match (design 5.2: the idempotency key). */
export function expectedHashOf(row: RowData): string | undefined {
  return strOf(row.pendingUploadId) !== undefined
    ? strOf(row.pendingContentSha256)
    : strOf(row.contentSha256);
}

/** True when `uploadId` is the upload that already produced this row's stored object. */
function alreadyStoredBy(row: RowData | undefined, uploadId: string): boolean {
  return row !== undefined && row.state === "stored" && strOf(row.uploadId) === uploadId;
}

type Precheck =
  | { kind: "already_stored"; row: RowData }
  | { kind: "expired" }
  | { kind: "proceed"; expectedSha256: string };

/** Transaction 1 (design 5.2 item 2a). */
export async function precheckCommit(
  deps: UploadDeps,
  uid: string,
  req: CommitRequest,
): Promise<Precheck> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, req.activityId));
  return fs.runTransaction(async (tx): Promise<Precheck> => {
    const ctx = await readUploadContext(tx, deps, uid, req.activityId);
    const row = ctx.row;
    if (row === undefined) throw new UploadRefusal("superseded");
    if (alreadyStoredBy(row, req.uploadId)) return { kind: "already_stored", row };
    if (currentUploadId(row) !== req.uploadId) throw new UploadRefusal("superseded");

    if (isExpiryDue(ctx.startUtcMs, ctx.retentionDays, deps.nowMs())) {
      // Writes happen here, so the refusal is returned (a throw would roll them back).
      if (row.state === "pending") {
        tx.delete(rowRef);
      } else {
        tx.update(rowRef, {
          pendingUploadId: admin.firestore.FieldValue.delete(),
          pendingContentSha256: admin.firestore.FieldValue.delete(),
          pendingSince: admin.firestore.FieldValue.delete(),
        });
      }
      return { kind: "expired" };
    }
    const expectedSha256 = expectedHashOf(row);
    if (expectedSha256 === undefined) throw new UploadRefusal("commit_failed");
    return { kind: "proceed", expectedSha256 };
  });
}

/**
 * Removes the pending marker of THIS upload after a validation failure: a
 * stored (or expired) row keeps its state and old object, a never-stored row is
 * removed. Does nothing when the upload is no longer the row's current one.
 */
export async function clearPendingUpload(
  deps: UploadDeps,
  uid: string,
  req: CommitRequest,
): Promise<void> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, req.activityId));
  await fs.runTransaction(async (tx) => {
    const snap = await tx.get(rowRef);
    if (!snap.exists) return;
    const row = snap.data() as RowData;
    if (currentUploadId(row) !== req.uploadId) return;
    if (row.state === "pending") {
      tx.delete(rowRef);
    } else {
      tx.update(rowRef, {
        pendingUploadId: admin.firestore.FieldValue.delete(),
        pendingContentSha256: admin.firestore.FieldValue.delete(),
        pendingSince: admin.firestore.FieldValue.delete(),
      });
    }
  });
}

/** Records the intended stored hash BEFORE promotion (design 5.2 item 2c). */
export async function writeIntendedHash(
  deps: UploadDeps,
  uid: string,
  req: CommitRequest,
  intendedStoredSha256: string,
): Promise<boolean> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, req.activityId));
  return fs.runTransaction(async (tx): Promise<boolean> => {
    const ctx = await readUploadContext(tx, deps, uid, req.activityId);
    // A concurrent commit of the SAME upload id already finished: nothing to promote (F47).
    if (alreadyStoredBy(ctx.row, req.uploadId)) return false;
    if (ctx.row === undefined || currentUploadId(ctx.row) !== req.uploadId) {
      throw new UploadRefusal("superseded");
    }
    tx.update(rowRef, { intendedStoredSha256 });
    return true;
  });
}

interface Selected {
  /** `true` when a competing commit of the SAME upload id already selected the object. */
  alreadySelected: boolean;
  previousPath?: string;
  expiresAtMs: number | null;
  /** `true` when the derived expiry was already due: nothing was stored, the pending marker is cleared. */
  expired?: boolean;
}

/** Transaction 2: selects the promoted path in ONE write (design 5.2 item 2d). */
export async function selectPromotedObject(
  deps: UploadDeps,
  uid: string,
  req: CommitRequest,
  stored: { bytes: number; kinds: string[]; storedSha256: string; contentSha256: string },
): Promise<Selected> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, req.activityId));
  const newPath = streamObjectPath(uid, req.activityId, req.uploadId);
  return fs.runTransaction(async (tx): Promise<Selected> => {
    const ctx = await readUploadContext(tx, deps, uid, req.activityId);
    const row = ctx.row;
    if (row === undefined) throw new UploadRefusal("superseded");
    if (alreadyStoredBy(row, req.uploadId)) {
      return { alreadySelected: true, expiresAtMs: null };
    }
    if (currentUploadId(row) !== req.uploadId) throw new UploadRefusal("superseded");

    const nowMs = deps.nowMs();
    if (isExpiryDue(ctx.startUtcMs, ctx.retentionDays, nowMs)) {
      // The expiry fell due between T1 and T2 (A7): never store an already-due object. Clear the
      // pending marker exactly like T1 and let the caller delete the promoted object.
      if (row.state === "pending") {
        tx.delete(rowRef);
      } else {
        tx.update(rowRef, {
          pendingUploadId: admin.firestore.FieldValue.delete(),
          pendingContentSha256: admin.firestore.FieldValue.delete(),
          pendingSince: admin.firestore.FieldValue.delete(),
        });
      }
      return { alreadySelected: false, expiresAtMs: null, expired: true };
    }
    const expiresAtMs = derivedExpiryMs(ctx.startUtcMs, ctx.retentionDays, nowMs);
    const ts =(ms: number) => admin.firestore.Timestamp.fromMillis(ms);
    const del = admin.firestore.FieldValue.delete();
    const previousPath = row.state === "stored" ? strOf(row.objectPath) : undefined;
    tx.set(
      rowRef,
      {
        state: "stored",
        uploadId: req.uploadId,
        objectPath: newPath,
        bytes: stored.bytes,
        kinds: stored.kinds,
        schema: STREAM_PAYLOAD_SCHEMA,
        contentSha256: stored.contentSha256,
        storedSha256: stored.storedSha256,
        activityDateUtc: ts(activityDateMs(ctx.startUtcMs, nowMs)),
        expiresAt: expiresAtMs === null ? null : ts(expiresAtMs),
        settingsGeneration: ctx.settingsGeneration,
        receivedAt: ts(nowMs),
        purgeAttempts: 0,
        lastErrorCode: del,
        lastPurgeAttemptAt: del,
        intendedStoredSha256: del,
        pendingUploadId: del,
        pendingContentSha256: del,
        pendingSince: del,
      },
      { merge: true },
    );
    return { alreadySelected: false, previousPath, expiresAtMs };
  });
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_COMMIT_EVENT, { operation: "commitActivityStream", ...fields });
}

/** Best-effort object delete; the reconciler and the lifecycle rule are the backstop. */
async function deleteQuietly(bucket: StreamBucket, path: string, slug: string): Promise<void> {
  try {
    await bucket.file(path).delete({ ignoreNotFound: true });
  } catch (e) {
    if (!isNotFound(e)) log("warn", { outcome: slug, errorCode: errorCodeOf(e) });
  }
}

/** Reads the quarantine object ONCE, pinned to the generation seen in its metadata. */
async function readQuarantineOnce(bucket: StreamBucket, path: string): Promise<Buffer> {
  let generation: string | number | undefined;
  let size: number;
  try {
    const [meta] = await bucket.file(path).getMetadata();
    generation = meta.generation;
    size = Number(meta.size);
  } catch (e) {
    if (isNotFound(e)) throw new UploadRefusal("upload_missing");
    throw e;
  }
  if (generation === undefined || generation === "") throw new UploadRefusal("generation_changed");
  // Refuse before downloading: a hostile object must not be pulled into memory.
  if (Number.isFinite(size) && size > MAX_COMPRESSED_BYTES) throw new UploadRefusal("too_large");
  try {
    const [bytes] = await bucket.file(path, { generation }).download();
    return bytes;
  } catch (e) {
    // A pinned read of a replaced generation answers 404.
    if (isNotFound(e)) throw new UploadRefusal("generation_changed");
    throw e;
  }
}

/** Codes after which the upload itself is bad (the pending marker is cleared), not the environment. */
const NON_UPLOAD_REFUSALS = new Set([
  "account_deleting",
  "account_deleted",
  "deleted",
  "no_summary",
  "consent_required",
  "consent_withdrawn",
  "expired",
  "superseded",
  "upload_missing",
  "commit_failed",
]);

/** The whole commit with injectable collaborators (testable without the Functions runtime). */
export async function applyCommitActivityStream(
  deps: UploadDeps,
  bucket: StreamBucket,
  uid: string,
  req: CommitRequest,
): Promise<CommitResult> {
  const quarantinePath = quarantineObjectPath(uid, req.activityId, req.uploadId);
  const promotedPath = streamObjectPath(uid, req.activityId, req.uploadId);

  const pre = await precheckCommit(deps, uid, req);
  if (pre.kind === "already_stored") {
    // A repeat of a finished commit: success, no write, no object touched.
    return {
      status: "already_stored",
      bytes: typeof pre.row.bytes === "number" ? pre.row.bytes : undefined,
      kinds: Array.isArray(pre.row.kinds) ? (pre.row.kinds as string[]) : undefined,
      serverNowMs: deps.nowMs(),
    };
  }
  if (pre.kind === "expired") {
    await deleteQuietly(bucket, quarantinePath, "expired_cleanup_failed");
    throw new UploadRefusal("expired");
  }

  let promoted = false;
  try {
    const bytes = await readQuarantineOnce(bucket, quarantinePath);
    const validated = await validateUploadedStream(
      bytes,
      pre.expectedSha256,
      deps.validationOptions?.(),
    );
    if (!validated.ok) {
      log("warn", { outcome: "validation_rejected", reason: validated.code });
      throw new UploadRefusal(validated.code);
    }

    if (!(await writeIntendedHash(deps, uid, req, validated.storedSha256))) {
      return {
        status: "already_stored",
        bytes: validated.storedBytes.length,
        kinds: validated.kinds,
        serverNowMs: deps.nowMs(),
      };
    }
    await bucket.file(promotedPath).save(validated.storedBytes, {
      contentType: STREAM_CONTENT_TYPE,
      resumable: false,
    });
    promoted = true;

    const selected = await selectPromotedObject(deps, uid, req, {
      bytes: validated.storedBytes.length,
      kinds: validated.kinds,
      storedSha256: validated.storedSha256,
      contentSha256: validated.contentSha256,
    });

    // The catch below deletes both of this commit's objects; the marker is already cleared.
    if (selected.expired === true) throw new UploadRefusal("expired");

    await deleteQuietly(bucket, quarantinePath, "quarantine_cleanup_failed");
    if (selected.previousPath !== undefined && selected.previousPath !== promotedPath) {
      // After T2 only: a failure leaves an orphan the reconciler removes.
      await deleteQuietly(bucket, selected.previousPath, "previous_object_cleanup_failed");
    }
    return {
      status: selected.alreadySelected ? "already_stored" : "stored",
      bytes: validated.storedBytes.length,
      kinds: validated.kinds,
      expiresAtMs: selected.alreadySelected ? undefined : selected.expiresAtMs,
      serverNowMs: deps.nowMs(),
    };
  } catch (e) {
    if (e instanceof UploadRefusal) {
      // Compensation touches only this commit's own uploadId paths.
      await deleteQuietly(bucket, quarantinePath, "quarantine_cleanup_failed");
      if (promoted) await deleteQuietly(bucket, promotedPath, "promoted_cleanup_failed");
      if (!NON_UPLOAD_REFUSALS.has(e.code)) {
        // Validation failure: clear the pending marker / remove the never-stored row.
        try {
          await clearPendingUpload(deps, uid, req);
        } catch (clearErr) {
          log("error", { outcome: "clear_pending_failed", errorCode: errorCodeOf(clearErr) });
        }
      }
    }
    throw e;
  }
}

/**
 * Whole request pipeline. `signInProvider` is
 * `request.auth.token.firebase.sign_in_provider`.
 */
export async function handleCommitActivityStream(
  deps: UploadDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<CommitResult> {
  const started = deps.nowMs();
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }
  let req: CommitRequest;
  try {
    req = parseCommitRequest(data);
  } catch {
    throw toUploadHttpsError("invalid_request");
  }
  const bucket = deps.bucket();
  if (bucket === undefined) {
    // Feature off (ACTIVITY_STREAM_BUCKET unset): the shared feature-disabled answer.
    assertFeatureEnabled(false);
    throw toUploadHttpsError("commit_failed");
  }

  try {
    await enforceDailyQuota(uid, COMMIT_QUOTA_ACTION, QUOTAS.activityStreamCommit);
  } catch (e) {
    if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
      log("warn", { outcome: "quota_exceeded" });
      throw toUploadHttpsError("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw toUploadHttpsError("commit_failed");
  }

  try {
    const result = await applyCommitActivityStream(deps, bucket, uid, req);
    log("info", { outcome: result.status, latencyMs: deps.nowMs() - started });
    return result;
  } catch (e) {
    if (e instanceof UploadRefusal) {
      if (e.code === "account_deleting" || e.code === "account_deleted") {
        await refundQuota(uid, COMMIT_QUOTA_ACTION, 1);
      }
      log("warn", { outcome: e.code });
      throw toUploadHttpsError(e.code);
    }
    // Includes a transient Auth lookup, Firestore or Storage error: fail closed with a bare code.
    log("error", { outcome: "commit_failed", errorCode: errorCodeOf(e) });
    throw toUploadHttpsError("commit_failed");
  }
}

export const commitActivityStream = onCall(ACTIVITY_COMMIT, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "commitActivityStream");
  return handleCommitActivityStream(
    defaultUploadDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
