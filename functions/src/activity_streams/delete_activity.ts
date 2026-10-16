/**
 * `deleteActivity` -- erases one activity from the cloud (S02 design 6, 6.1, 6.2, 5.4).
 *
 * Order (part of the contract, test F20): auth -> App Check note -> non-anonymous
 * -> validate -> daily quota -> ONE transaction (fence documents, Auth existence,
 * then the TOMBSTONE written first) -> objects under `streams/` and `quarantine/`
 * for that id -> stream index row -> summary document LAST.
 *
 * Idempotent: the tombstone keeps its earliest `deletedAt`/`expireAt`, missing
 * objects (404) and missing documents are success, so a rerun after any failure
 * finishes the cascade. The summary is deleted last so an interrupted cascade
 * never leaves an orphan object or row that is unreachable from a summary.
 * No per-activity late job exists: a PUT to a still-valid signed URL can only land
 * in `quarantine/`, the tombstone makes any commit refuse, and the reconciler plus
 * the quarantine lifecycle rule remove the stray object (design 6).
 *
 * Deleting is an erasure-side action and is NOT gated by the feature flag; an
 * unset stream bucket makes the object step a no-op (nothing could be stored).
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid or id.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { checkAccountFence, defaultFenceDeps, type FenceDeps } from "./fence";
import {
  activityQuarantinePrefix,
  activityStreamRowPath,
  activityStreamsPrefix,
  activitySummaryPath,
  activityTombstonePath,
  isActivityId,
} from "./paths";

/** The quota action of this callable (design 5.4); also listed in `REDACTED_QUOTA_ACTIONS`. */
export const DELETE_QUOTA_ACTION = "activityDelete";

/** The one structured-log message of this callable. */
export const ACTIVITY_DELETE_EVENT = "activity_delete_event";

/** Tombstone lifetime (design 6.2, PROPOSED, OPEN): exceeds any realistic offline replay window. */
export const TOMBSTONE_TTL_DAYS = 400;
const DAY_MS = 24 * 60 * 60 * 1000;

export type DeleteRefusalCode =
  | "invalid_request"
  | "account_deleting"
  | "account_deleted"
  | "quota_exceeded"
  | "delete_failed";

type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<DeleteRefusalCode, HttpsCode> = {
  invalid_request: "invalid-argument",
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  quota_exceeded: "resource-exhausted",
  delete_failed: "internal",
};

/** A refusal with a bare code; the code is the only thing the client ever sees. */
export class DeleteRefusal extends Error {
  constructor(readonly code: DeleteRefusalCode) {
    super(code);
    this.name = "DeleteRefusal";
  }
}

export interface DeleteActivityResult {
  deleted: true;
  /** `true` when this call created the tombstone, `false` on a rerun. */
  tombstoneCreated: boolean;
  serverNowMs: number;
}

/** Injectable collaborators: the fence seam plus the stream bucket (`undefined` = feature off). */
export interface DeleteActivityDeps extends FenceDeps {
  bucket(): StreamBucket | undefined;
}

export const defaultDeleteActivityDeps: DeleteActivityDeps = {
  ...defaultFenceDeps,
  bucket: () => activityStreamBucket(),
};

/** Parses `{activityId}`; a bad id is refused before any path is built (design 5.4). */
export function parseDeleteRequest(data: unknown): { activityId: string } {
  const id = (data as { activityId?: unknown } | null | undefined)?.activityId;
  if (!isActivityId(id)) throw new DeleteRefusal("invalid_request");
  return { activityId: id };
}

/**
 * Step 1: the fenced transaction that writes the tombstone FIRST. Reads (fence
 * documents, Auth, existing tombstone) precede the single write. Returns whether
 * the tombstone was created by this call.
 */
export async function writeTombstone(
  deps: FenceDeps,
  uid: string,
  activityId: string,
): Promise<boolean> {
  const fs = deps.firestore();
  const ref = fs.doc(activityTombstonePath(uid, activityId));
  return fs.runTransaction(async (tx) => {
    const fence = await checkAccountFence(tx, deps, uid);
    if (fence !== "clear") throw new DeleteRefusal(fence);
    const snap = await tx.get(ref);
    if (snap.exists) return false;
    const nowMs = deps.nowMs();
    tx.set(ref, {
      deletedAt: admin.firestore.Timestamp.fromMillis(nowMs),
      expireAt: admin.firestore.Timestamp.fromMillis(nowMs + TOMBSTONE_TTL_DAYS * DAY_MS),
    });
    return true;
  });
}

function isNotFound(e: unknown): boolean {
  const code = (e as { code?: unknown } | null)?.code;
  return code === 404 || code === "404";
}

/**
 * Step 2: deletes both object prefixes of the activity. Both are ATTEMPTED even
 * when the first fails; 404 is success; any other failure throws ONE bare error
 * so the row and the summary are kept and a rerun completes the cascade.
 */
export async function deleteActivityObjects(
  deps: DeleteActivityDeps,
  uid: string,
  activityId: string,
): Promise<void> {
  const bucket = deps.bucket();
  if (bucket === undefined) {
    // An unset bucket is a no-op only when no stream row exists (A10). A stored or pending row
    // means objects may exist that cannot be reached: fail, keep the row, and say so loudly.
    const row = await deps.firestore().doc(activityStreamRowPath(uid, activityId)).get();
    if (row.exists) {
      log("error", { outcome: "bucket_unset_with_stream_row" });
      throw new DeleteRefusal("delete_failed");
    }
    return;
  }
  const prefixes = [activityStreamsPrefix(uid, activityId), activityQuarantinePrefix(uid, activityId)];
  let failed = false;
  for (const prefix of prefixes) {
    try {
      await bucket.deleteFiles({ prefix });
    } catch (e) {
      const errors: unknown[] = Array.isArray(e) ? e : [e];
      if (!(errors.length > 0 && errors.every(isNotFound))) failed = true;
    }
  }
  if (failed) throw new DeleteRefusal("delete_failed");
}

/** The whole cascade with injectable collaborators (testable without the Functions runtime). */
export async function applyDeleteActivity(
  deps: DeleteActivityDeps,
  uid: string,
  activityId: string,
): Promise<DeleteActivityResult> {
  const tombstoneCreated = await writeTombstone(deps, uid, activityId);
  await deleteActivityObjects(deps, uid, activityId);
  const fs = deps.firestore();
  // Index row before the summary; deleting a missing document is a no-op.
  await fs.doc(activityStreamRowPath(uid, activityId)).delete();
  await fs.doc(activitySummaryPath(uid, activityId)).delete();
  return { deleted: true, tombstoneCreated, serverNowMs: deps.nowMs() };
}

function toHttpsError(code: DeleteRefusalCode): HttpsError {
  return new HttpsError(HTTPS_CODE[code], code);
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_DELETE_EVENT, { operation: "deleteActivity", ...fields });
}

/** A bare error code from a thrown value; never the message (it can embed a document path and so the uid). */
function errorCodeOf(e: unknown): string {
  const code = (e as { code?: unknown } | null | undefined)?.code;
  const text = typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

/**
 * Whole request pipeline. `signInProvider` is
 * `request.auth.token.firebase.sign_in_provider`.
 */
export async function handleDeleteActivity(
  deps: DeleteActivityDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<DeleteActivityResult> {
  const started = deps.nowMs();
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }
  let activityId: string;
  try {
    activityId = parseDeleteRequest(data).activityId;
  } catch {
    throw toHttpsError("invalid_request");
  }

  try {
    await enforceDailyQuota(uid, DELETE_QUOTA_ACTION, QUOTAS.activityDelete);
  } catch (e) {
    if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
      log("warn", { outcome: "quota_exceeded" });
      throw toHttpsError("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("delete_failed");
  }

  try {
    const result = await applyDeleteActivity(deps, uid, activityId);
    log("info", {
      outcome: result.tombstoneCreated ? "deleted" : "already_deleted",
      latencyMs: deps.nowMs() - started,
    });
    return result;
  } catch (e) {
    if (e instanceof DeleteRefusal) {
      // A fence refusal wrote nothing: give the charge back. A cascade failure keeps it.
      if (e.code === "account_deleting" || e.code === "account_deleted") {
        await refundQuota(uid, DELETE_QUOTA_ACTION, 1);
      }
      log("warn", { outcome: e.code });
      throw toHttpsError(e.code);
    }
    // Includes a transient Auth lookup error: fail closed with a bare code.
    log("error", { outcome: "delete_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("delete_failed");
  }
}

export const deleteActivity = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "deleteActivity");
  return handleDeleteActivity(
    defaultDeleteActivityDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
