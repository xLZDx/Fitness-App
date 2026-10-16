/**
 * `getActivityStreamDownloadUrls` -- short-lived V4 GET links for the owner's
 * stored GPS stream objects (S02 design 7, 7.1, 5.4; GPS-PRIV-052/094; story S02-07).
 *
 * Order (part of the contract): auth -> App Check note -> non-anonymous ->
 * validate -> feature (bucket configured) -> daily quota -> ONE read-only
 * transaction (account fence documents, Auth existence, then per id the
 * tombstone and the stream index row) -> V4 GET URLs signed AFTER the
 * transaction (a retry never signs twice).
 *
 * Per requested id (design 7.1): `stored` -> URL plus expiry; `expired` -> code
 * `expired`; `pending` -> `not_ready`; `deleted`, tombstoned, missing or not
 * owned -> the SAME `not_found` (no existence oracle: ids resolve only under
 * `users/{auth.uid}`, so another user's id is simply missing). A URL is never
 * issued for a non-`stored` row. The object path is read from the row but must
 * lie under `streams/{uid}/{activityId}/`, else the row is treated as
 * `not_found`; no client value ever forms a path.
 *
 * Logging (GPS-PRIV-094): closed outcome slugs and counts only, never a uid,
 * activity id, path or signed URL.
 */
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "../scaling";
import { QUOTAS, enforceDailyQuota, noteAppCheck, refundQuota } from "../abuse_guard";
import { assertFeatureEnabled } from "../feature_flags";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { activityTombstoned, checkAccountFence, defaultFenceDeps, type FenceDeps } from "./fence";
import { activityStreamRowPath, activityStreamsPrefix, activitySummaryPath, isActivityId } from "./paths";
import { activitySettingsPath, effectiveStreamRetentionDays, type StreamRetentionDays } from "./settings";
import { isExpiryDue, timestampMs, type RowData } from "./upload_common";

/** The quota action of this callable (design 5.4); also listed in `REDACTED_QUOTA_ACTIONS`. */
export const DOWNLOAD_QUOTA_ACTION = "activityDownloadUrls";

/** The one structured-log message of this callable. */
export const ACTIVITY_DOWNLOAD_EVENT = "activity_download_event";

/** Signed GET URL lifetime (design 7). */
export const DOWNLOAD_URL_TTL_MS = 15 * 60 * 1000;

/** Ids per call, after de-duplication (design 5.4). */
export const MAX_DOWNLOAD_IDS = 20;

/** Hard bound on the raw array so a hostile client cannot make de-duplication expensive. */
const MAX_RAW_IDS = 100;

export type DownloadRefusalCode =
  | "invalid_request"
  | "account_deleting"
  | "account_deleted"
  | "quota_exceeded"
  | "download_failed";

type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<DownloadRefusalCode, HttpsCode> = {
  invalid_request: "invalid-argument",
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  quota_exceeded: "resource-exhausted",
  download_failed: "internal",
};

/** A refusal with a bare code; the code is the only thing the client ever sees. */
export class DownloadRefusal extends Error {
  constructor(readonly code: DownloadRefusalCode) {
    super(code);
    this.name = "DownloadRefusal";
  }
}

/** Per-id answer. `not_found` carries no further detail by design. */
export type DownloadItem =
  | { activityId: string; status: "ok"; url: string; expiresAtMs: number }
  | { activityId: string; status: "unavailable"; code: "expired" | "not_ready" | "not_found" };

export interface DownloadResult {
  results: DownloadItem[];
  serverNowMs: number;
}

/** Injectable collaborators: the fence seam plus the stream bucket (`undefined` = feature off). */
export interface DownloadDeps extends FenceDeps {
  bucket(): StreamBucket | undefined;
}

export const defaultDownloadDeps: DownloadDeps = {
  ...defaultFenceDeps,
  bucket: () => activityStreamBucket(),
};

/** Parses `{activityIds}`: array of valid ids, de-duplicated (first occurrence wins), 1..20 distinct. */
export function parseDownloadRequest(data: unknown): string[] {
  const raw = (data as { activityIds?: unknown } | null | undefined)?.activityIds;
  if (!Array.isArray(raw) || raw.length === 0 || raw.length > MAX_RAW_IDS) {
    throw new DownloadRefusal("invalid_request");
  }
  const ids: string[] = [];
  const seen = new Set<string>();
  for (const v of raw) {
    if (!isActivityId(v)) throw new DownloadRefusal("invalid_request");
    if (!seen.has(v)) {
      seen.add(v);
      ids.push(v);
    }
  }
  if (ids.length > MAX_DOWNLOAD_IDS) throw new DownloadRefusal("invalid_request");
  return ids;
}

/** What the transaction decided for one id; the URL is signed later. */
type Plan = { activityId: string } & (
  | { kind: "sign"; objectPath: string }
  | { kind: "unavailable"; code: "expired" | "not_ready" | "not_found" }
);

/** Classifies an index row (pure; exported for tests). */
export function classifyRow(
  uid: string,
  activityId: string,
  tombstoned: boolean,
  row: Record<string, unknown> | undefined,
  expiry?: { startUtcMs: number; retentionDays: StreamRetentionDays; nowMs: number },
): Plan {
  const notFound: Plan = { activityId, kind: "unavailable", code: "not_found" };
  if (tombstoned || row === undefined) return notFound;
  switch (row.state) {
    case "stored": {
      if (expiry !== undefined && isExpiryDue(expiry.startUtcMs, expiry.retentionDays, expiry.nowMs)) {
        return { activityId, kind: "unavailable", code: "expired" };
      }
      const path = row.objectPath;
      const prefix = activityStreamsPrefix(uid, activityId);
      if (typeof path !== "string" || !path.startsWith(prefix) || path.length === prefix.length) {
        return notFound;
      }
      if (path.slice(prefix.length).includes("/")) return notFound;
      return { activityId, kind: "sign", objectPath: path };
    }
    case "expired":
      return { activityId, kind: "unavailable", code: "expired" };
    case "pending":
      return { activityId, kind: "unavailable", code: "not_ready" };
    default:
      // `deleted` and any unknown state: indistinguishable from a missing row.
      return notFound;
  }
}

/** The read-only fenced transaction. Throws `DownloadRefusal` on a fence refusal. */
export async function planDownloads(
  deps: FenceDeps,
  uid: string,
  activityIds: string[],
): Promise<Plan[]> {
  const fs = deps.firestore();
  return fs.runTransaction(async (tx) => {
    const fence = await checkAccountFence(tx, deps, uid);
    if (fence !== "clear") throw new DownloadRefusal(fence);
    return Promise.all(
      activityIds.map(async (activityId): Promise<Plan> => {
        const [tombstoned, rowSnap, summarySnap, settingsSnap] = await Promise.all([
          activityTombstoned(tx, deps, uid, activityId),
          tx.get(fs.doc(activityStreamRowPath(uid, activityId))),
          tx.get(fs.doc(activitySummaryPath(uid, activityId))),
          tx.get(fs.doc(activitySettingsPath(uid))),
        ]);
        // A stored row whose DERIVED expiry is already due is expired even if the purge has not
        // run yet (A7); the same arithmetic as the upload and commit callables.
        const startUtcMs = summarySnap.exists
          ? timestampMs((summarySnap.data() as RowData | undefined)?.startUtc)
          : undefined;
        const expiry =
          startUtcMs === undefined
            ? undefined
            : {
                startUtcMs,
                retentionDays: effectiveStreamRetentionDays(
                  settingsSnap.exists ? (settingsSnap.data() as RowData) : undefined,
                ),
                nowMs: deps.nowMs(),
              };
        return classifyRow(
          uid,
          activityId,
          tombstoned,
          rowSnap.exists ? (rowSnap.data() as Record<string, unknown>) : undefined,
          expiry,
        );
      }),
    );
  });
}

function toHttpsError(code: DownloadRefusalCode): HttpsError {
  return new HttpsError(HTTPS_CODE[code], code);
}

function log(level: "info" | "warn" | "error", fields: Record<string, string | number | boolean>): void {
  logger[level](ACTIVITY_DOWNLOAD_EVENT, { operation: "getActivityStreamDownloadUrls", ...fields });
}

/** A bare error code from a thrown value; never the message (it can embed a path and so the uid). */
function errorCodeOf(e: unknown): string {
  const code = (e as { code?: unknown } | null | undefined)?.code;
  const text = typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

/**
 * Whole request pipeline with injectable collaborators (testable without the
 * Functions runtime). `signInProvider` is `request.auth.token.firebase.sign_in_provider`.
 */
export async function handleGetActivityStreamDownloadUrls(
  deps: DownloadDeps,
  uid: string,
  signInProvider: string | undefined,
  data: unknown,
): Promise<DownloadResult> {
  if (signInProvider === "anonymous") {
    throw new HttpsError("permission-denied", "anonymous_not_allowed");
  }
  let ids: string[];
  try {
    ids = parseDownloadRequest(data);
  } catch {
    throw toHttpsError("invalid_request");
  }
  const bucket = deps.bucket();
  if (bucket === undefined) {
    // Feature off (ACTIVITY_STREAM_BUCKET unset): the shared feature-disabled answer.
    assertFeatureEnabled(false);
    throw toHttpsError("download_failed");
  }

  try {
    await enforceDailyQuota(uid, DOWNLOAD_QUOTA_ACTION, QUOTAS.activityDownloadUrls);
  } catch (e) {
    if ((e as { code?: unknown } | null)?.code === "resource-exhausted") {
      log("warn", { outcome: "quota_exceeded" });
      throw toHttpsError("quota_exceeded");
    }
    log("error", { outcome: "quota_check_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("download_failed");
  }

  let plans: Plan[];
  try {
    plans = await planDownloads(deps, uid, ids);
  } catch (e) {
    if (e instanceof DownloadRefusal) {
      // A fence refusal issued nothing: give the charge back.
      if (e.code === "account_deleting" || e.code === "account_deleted") {
        await refundQuota(uid, DOWNLOAD_QUOTA_ACTION, 1);
      }
      log("warn", { outcome: e.code });
      throw toHttpsError(e.code);
    }
    // Includes a transient Auth lookup error: fail closed with a bare code.
    log("error", { outcome: "download_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("download_failed");
  }

  const nowMs = deps.nowMs();
  const expiresAtMs = nowMs + DOWNLOAD_URL_TTL_MS;
  let signed = 0;
  const results: DownloadItem[] = [];
  try {
    for (const plan of plans) {
      if (plan.kind === "unavailable") {
        results.push({ activityId: plan.activityId, status: "unavailable", code: plan.code });
        continue;
      }
      const [url] = await bucket
        .file(plan.objectPath)
        .getSignedUrl({ version: "v4", action: "read", expires: expiresAtMs });
      signed += 1;
      results.push({ activityId: plan.activityId, status: "ok", url, expiresAtMs });
    }
  } catch (e) {
    // Slug only: the SDK error text can embed the object path. Nothing partial is returned.
    log("error", { outcome: "sign_failed", errorCode: errorCodeOf(e) });
    throw toHttpsError("download_failed");
  }
  log("info", { outcome: "issued", requested: ids.length, signed });
  return { results, serverNowMs: nowMs };
}

export const getActivityStreamDownloadUrls = onCall(RARE, async (request) => {
  if (!request.auth) throw new HttpsError("unauthenticated", "sign_in_required");
  noteAppCheck(request, "getActivityStreamDownloadUrls");
  return handleGetActivityStreamDownloadUrls(
    defaultDownloadDeps,
    request.auth.uid,
    request.auth.token?.firebase?.sign_in_provider,
    request.data,
  );
});
