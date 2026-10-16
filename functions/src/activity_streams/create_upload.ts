/**
 * `createActivityStreamUpload` -- first half of the cloud stream upload
 * (S02 design 5.2 item 1, 5.4; story S02-04b).
 *
 * Order (part of the contract): auth -> App Check note -> non-anonymous ->
 * `expectedUid` binding (refusal `account_changed`) -> validate -> feature (bucket configured) -> daily quota -> ONE Firestore
 * transaction that checks the delete fence (documents + Auth existence), the
 * tombstone, the summary, the `cloudStreams` consent, the derived expiry and the
 * attempt cap and writes the upload intent -> (after the commit of that
 * transaction) the superseded quarantine object is deleted and a V4 PUT URL for
 * `quarantine/{uid}/{activityId}/{uploadId}` is signed.
 *
 * The row is a state machine (see `upload_common.ts`). A `stored` row KEEPS
 * `state = stored` and gains `pendingUploadId` / `pendingContentSha256` /
 * `pendingSince`; a row that is not stored is written `pending`. The signed URL
 * is minted AFTER the transaction so a transaction retry never signs twice.
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid,
 * activity id, upload id, path or signed URL.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { assertFeatureEnabled } from "../feature_flags";
import { MAX_COMPRESSED_BYTES } from "./schema";
import { isSha256Hex } from "./hash";
import { ExpectedUidError, verifyExpectedUid } from "./expected_uid";
import { activityStreamRowPath, isActivityId, quarantineObjectPath } from "./paths";
import {
  MAX_ATTEMPTS_PER_DAY,
  STREAM_CONTENT_TYPE,
  STREAM_LENGTH_HEADER,
  UPLOAD_QUOTA_ACTION,
  UPLOAD_URL_TTL_MS,
  UploadRefusal,
  defaultUploadDeps,
  errorCodeOf,
  isExpiryDue,
  readUploadContext,
  strOf,
  toUploadHttpsError,
  utcDayOf,
  type UploadDeps,
} from "./upload_common";

/** The one structured-log message of this callable. */
export const ACTIVITY_UPLOAD_EVENT = "activity_upload_event";

/** A parsed, validated request. Unknown client fields are ignored, never used. */
export interface CreateUploadRequest {
  activityId: string;
  bytes: number;
  /** Lowercase hex. */
  contentSha256: string;
}

export type CreateUploadResult =
  | { status: "already_stored"; serverNowMs: number }
  | {
      status: "upload";
      uploadId: string;
      url: string;
      /** Headers the PUT must carry for the signature to match. */
      headers: Record<string, string>;
      expiresAtMs: number;
      serverNowMs: number;
    };

/** Strict parse of `{activityId, bytes, contentSha256}` (design 5.4). */
export function parseCreateUploadRequest(data: unknown): CreateUploadRequest {
  const d = (typeof data === "object" && data !== null ? data : {}) as Record<string, unknown>;
  const { activityId, bytes, contentSha256 } = d;
  if (!isActivityId(activityId)) throw new UploadRefusal("invalid_request");
  if (typeof bytes !== "number" || !Number.isInteger(bytes) || bytes < 1 || bytes > MAX_COMPRESSED_BYTES) {
    throw new UploadRefusal("invalid_request");
  }
  if (!isSha256Hex(contentSha256)) throw new UploadRefusal("invalid_request");
  return { activityId, bytes, contentSha256: contentSha256.toLowerCase() };
}

/** What the transaction decided. */
type CreatePlan =
  | { kind: "already_stored" }
  | { kind: "upload"; uploadId: string; supersededUploadId?: string };

/**
 * The transaction. Reads first (fence, tombstone, summary, settings, row), then
 * at most one write. Throws `UploadRefusal` before any write.
 */
export async function planAndWriteUploadIntent(
  deps: UploadDeps,
  uid: string,
  req: CreateUploadRequest,
  uploadId: string,
): Promise<CreatePlan> {
  const fs = deps.firestore();
  const rowRef = fs.doc(activityStreamRowPath(uid, req.activityId));
  return fs.runTransaction(async (tx): Promise<CreatePlan> => {
    const ctx = await readUploadContext(tx, deps, uid, req.activityId);
    const nowMs = deps.nowMs();
    // The derived expiry (startUtc + current retention) is not already due: else no work, no URL.
    if (isExpiryDue(ctx.startUtcMs, ctx.retentionDays, nowMs)) throw new UploadRefusal("already_expired");

    const row = ctx.row;
    const stored = row?.state === "stored";
    if (stored && strOf(row?.contentSha256)?.toLowerCase() === req.contentSha256) {
      return { kind: "already_stored" };
    }

    const day = utcDayOf(nowMs);
    const previousAttempts =
      row !== undefined && row.attemptsDay === day && typeof row.attempts === "number" ? row.attempts : 0;
    if (previousAttempts >= MAX_ATTEMPTS_PER_DAY) throw new UploadRefusal("too_many_attempts");
    const attempts = previousAttempts + 1;
    const pendingSince = admin.firestore.Timestamp.fromMillis(nowMs);

    if (stored) {
      // Keep `state = stored` so the purge query still sees the old object (design 5.2).
      tx.update(rowRef, {
        pendingUploadId: uploadId,
        pendingContentSha256: req.contentSha256,
        pendingSince,
        attempts,
        attemptsDay: day,
      });
      return { kind: "upload", uploadId, supersededUploadId: strOf(row?.pendingUploadId) };
    }

    tx.set(rowRef, {
      state: "pending",
      uploadId,
      contentSha256: req.contentSha256,
      pendingSince,
      attempts,
      attemptsDay: day,
    });
    return {
      kind: "upload",
      uploadId,
      supersededUploadId: row?.state === "pending" ? strOf(row.uploadId) : undefined,
    };
  });
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_UPLOAD_EVENT, { operation: "createActivityStreamUpload", ...fields });
}

/**
 * Whole request pipeline with injectable collaborators (testable without the
 * Functions runtime). `signInProvider` is `request.auth.token.firebase.sign_in_provider`.
 */
export async function handleCreateActivityStreamUpload(
  deps: UploadDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<CreateUploadResult> {
  const started = deps.nowMs();
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }
  // Invocation-bound identity (design 17 item 25): before the parse, any quota, read or write.
  let bound: unknown;
  try {
    bound = verifyExpectedUid(uid, data);
  } catch (e) {
    if (e instanceof ExpectedUidError && e.code === "account_changed") {
      log("warn", { outcome: "account_changed" });
      throw new HttpsError("failed-precondition", "account_changed");
    }
    throw toUploadHttpsError("invalid_request");
  }
  let req: CreateUploadRequest;
  try {
    req = parseCreateUploadRequest(bound);
  } catch {
    throw toUploadHttpsError("invalid_request");
  }
  const bucket = deps.bucket();
  if (bucket === undefined) {
    // Feature off (ACTIVITY_STREAM_BUCKET unset): the shared feature-disabled answer.
    assertFeatureEnabled(false);
    throw toUploadHttpsError("upload_failed");
  }

  try {
    await enforceDailyQuota(uid, UPLOAD_QUOTA_ACTION, QUOTAS.activityStreamUpload);
  } catch (e) {
    if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
      log("warn", { outcome: "quota_exceeded" });
      throw toUploadHttpsError("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw toUploadHttpsError("upload_failed");
  }

  let plan: CreatePlan;
  try {
    plan = await planAndWriteUploadIntent(deps, uid, req, deps.newUploadId());
  } catch (e) {
    if (e instanceof UploadRefusal) {
      // A fence refusal wrote nothing: give the charge back.
      if (e.code === "account_deleting" || e.code === "account_deleted") {
        await refundQuota(uid, UPLOAD_QUOTA_ACTION, 1);
      }
      log("warn", { outcome: e.code });
      throw toUploadHttpsError(e.code);
    }
    // Includes a transient Auth lookup error: fail closed with a bare code.
    log("error", { outcome: "upload_failed", errorCode: errorCodeOf(e) });
    throw toUploadHttpsError("upload_failed");
  }

  if (plan.kind === "already_stored") {
    log("info", { outcome: "already_stored", latencyMs: deps.nowMs() - started });
    return { status: "already_stored", serverNowMs: deps.nowMs() };
  }

  // A new upload supersedes an older pending one: its quarantine object is removed
  // (best effort; a failure leaves an object for the reconciler / lifecycle backstop).
  if (plan.supersededUploadId !== undefined) {
    try {
      await bucket
        .file(quarantineObjectPath(uid, req.activityId, plan.supersededUploadId))
        .delete({ ignoreNotFound: true });
    } catch (e) {
      log("warn", { outcome: "supersede_cleanup_failed", errorCode: errorCodeOf(e) });
    }
  }

  const nowMs = deps.nowMs();
  const expiresAtMs = nowMs + UPLOAD_URL_TTL_MS;
  const range = `${req.bytes},${req.bytes}`;
  try {
    const [url] = await bucket
      .file(quarantineObjectPath(uid, req.activityId, plan.uploadId))
      .getSignedUrl({
        version: "v4",
        action: "write",
        expires: expiresAtMs,
        contentType: STREAM_CONTENT_TYPE,
        extensionHeaders: { [STREAM_LENGTH_HEADER]: range },
      });
    log("info", { outcome: "upload_issued", latencyMs: deps.nowMs() - started });
    return {
      status: "upload",
      uploadId: plan.uploadId,
      url,
      headers: { "Content-Type": STREAM_CONTENT_TYPE, [STREAM_LENGTH_HEADER]: range },
      expiresAtMs,
      serverNowMs: nowMs,
    };
  } catch (e) {
    // Slug only: the SDK error text can embed the object path.
    log("error", { outcome: "sign_failed", errorCode: errorCodeOf(e) });
    throw toUploadHttpsError("upload_url_failed");
  }
}

export const createActivityStreamUpload = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "createActivityStreamUpload");
  return handleCreateActivityStreamUpload(
    defaultUploadDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
