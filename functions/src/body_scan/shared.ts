/**
 * Helpers shared by the Body Scan callables and the purge job (design s7).
 *
 * Everything that must be identical across `createBodyScan`, `estimateBodyScan`,
 * `deleteBodyScan`, `manageBodyScanData` and `purgeExpiredBodyScanPhotos` lives
 * here: the guard preamble (so the order auth -> App Check note -> non-anonymous
 * -> kill switch -> feature flag cannot drift between callables), the object
 * path scheme, the timing constants and the log helper.
 *
 * Logging rule (D-67): nothing in this module, or any caller of it, logs a uid,
 * an object path, a signed URL or a body metric. Cloud Logging sits outside
 * `users/{uid}` and is never erased by `deleteAccount`, so a log line that names
 * the user would outlive the account. Events carry a closed operation name, a
 * closed outcome slug and numbers about the call itself (latency, counts).
 */
import { createHash } from "crypto";
import * as admin from "firebase-admin";
import { getStorage } from "firebase-admin/storage";
import { HttpsError, type CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import {
  enforceAiGatewayEnabled,
  enforceNonAnonymousForAi,
  noteAppCheck,
} from "../abuse_guard";
import { assertFeatureEnabled, FEATURE_DISABLED_MESSAGE } from "../feature_flags";
import { bodyScanAcceptUploads, bodyScanBucketName, bodyScanCloudEnabled } from "./flags";
import { POSES, type Pose } from "./types";

/** `scanId` = the client's scan id; the same regex bounds the object prefix. */
export const SCAN_ID_PATTERN = /^[A-Za-z0-9_-]{8,64}$/;

/** What `body_scan_settings/main.cloudConsent.version` must reach (design s7.1). */
export const BODY_SCAN_CLOUD_CONSENT_VERSION = 1;

/** Signed PUT URL lifetime (design s7.1). */
export const UPLOAD_URL_TTL_MS = 10 * 60 * 1000;
/** Signed READ URL lifetime for `manageBodyScanData.exportLinks` (design s7.8). */
export const EXPORT_LINK_TTL_MS = 60 * 60 * 1000;

/** Object size bounds, enforced at PUT time by the signed header and re-checked at read. */
export const MIN_PHOTO_BYTES = 1024;
export const MAX_PHOTO_BYTES = 3 * 1024 * 1024;
export const UPLOAD_CONTENT_TYPE = "image/jpeg";
export const UPLOAD_LENGTH_HEADER = "x-goog-content-length-range";
export const UPLOAD_LENGTH_RANGE = `${MIN_PHOTO_BYTES},${MAX_PHOTO_BYTES}`;

/** A pending scan (awaiting upload/estimate) is cancelled after this long (design s5.1). */
export const PENDING_TTL_MS = 48 * 60 * 60 * 1000;
/** A `cancelled` tombstone is kept this long so late uploads stay discoverable (D-59). */
export const TOMBSTONE_TTL_MS = 48 * 60 * 60 * 1000;
/** The processing lease an estimate takes (design s7.2, D-53). */
export const ESTIMATE_LEASE_MS = 60 * 1000;
/** An unmatched object is only judged once it is this old (design s7.4 pass 4). */
export const UNMATCHED_OBJECT_MIN_AGE_MS = 60 * 60 * 1000;

/** Retention choices a client may store (design s5.2). */
export const RETENTION_DAYS = [0, 30, 90, 365] as const;
export type RetentionDays = (typeof RETENTION_DAYS)[number];
export const DAY_MS = 24 * 60 * 60 * 1000;

/** The callable names the guard and the structured log accept (closed set). */
export type BodyScanCallable =
  | "createBodyScan"
  | "estimateBodyScan"
  | "deleteBodyScan"
  | "manageBodyScanData";

/** Resolved per call, not at module load (same reasoning as `abuse_guard.ts`). */
export const db = (): FirebaseFirestore.Firestore => admin.firestore();

export function tsFromMillis(ms: number): FirebaseFirestore.Timestamp {
  return admin.firestore.Timestamp.fromMillis(ms);
}

/** Epoch millis of a Firestore Timestamp / Date value, or `undefined` for anything else. */
export function millisOf(value: unknown): number | undefined {
  if (value instanceof admin.firestore.Timestamp) return value.toMillis();
  if (value instanceof Date) return value.getTime();
  return undefined;
}

export function scanRef(
  uid: string,
  scanId: string,
): FirebaseFirestore.DocumentReference {
  return db().doc(`users/${uid}/body_scans/${scanId}`);
}

/**
 * The shared preamble of every body-scan callable (design s7). Order matters and
 * is part of the contract: an unauthenticated or anonymous caller is refused
 * before the kill switch is read, and a flag-off or kill-switched call is
 * refused BEFORE any quota is charged (the caller charges quota afterwards).
 *
 * @returns the caller's uid.
 */
export async function authorizeBodyScanCall(
  request: CallableRequest,
  fn: BodyScanCallable,
): Promise<string> {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "sign-in-required");
  }
  noteAppCheck(request, fn);
  enforceNonAnonymousForAi(request.auth.token?.firebase?.sign_in_provider);
  if (ERASE_CALLABLES.has(fn)) {
    // Erasure must keep working with the AI kill switch thrown and with intake
    // switched off: it needs only the bucket name (P-2, DB-F2).
    assertFeatureEnabled(bodyScanCloudEnabled());
    return request.auth.uid;
  }
  await enforceAiGatewayEnabled(fn);
  assertFeatureEnabled(bodyScanAcceptUploads());
  return request.auth.uid;
}

/** Callables that erase or export the caller's own data; gated by the bucket only. */
const ERASE_CALLABLES: ReadonlySet<BodyScanCallable> = new Set<BodyScanCallable>([
  "deleteBodyScan",
  "manageBodyScanData",
]);

/** How long a bulk-delete fence refuses new scan work; refreshed on every page. */
export const DELETE_FENCE_MS = 15 * 60 * 1000;

/**
 * The per-user bulk-delete fence: `body_scan_purge_state/delete_fence_<hash>`.
 * That collection is deny-all for clients (Admin SDK only) and the fence id is a
 * hash of the uid. The document holds one entry PER OPERATION (run):
 * `{ runs: { <opToken>: { action, startedAtMs, activeUntilMs } } }`.
 * `manageBodyScanData` `deleteAll*` registers its own run on the first page
 * (random `opToken`, returned to the client as `fenceToken` and echoed back on
 * continuation pages), refreshes only that run on every page and removes only
 * that run on the final page, all in a transaction (read-modify-write), so two
 * overlapping operations can neither replace nor clear each other's protection.
 * `createBodyScan` reads the document inside its transaction and refuses while
 * ANY run is active (a scan created behind a delete walk's cursor would
 * otherwise survive its "done" page).
 */
export function deleteFenceRef(uid: string): FirebaseFirestore.DocumentReference {
  return db().doc(`body_scan_purge_state/delete_fence_${uidKey(uid)}`);
}

function uidKey(uid: string): string {
  return createHash("sha256").update(uid).digest("hex").slice(0, 32);
}

/** One registered bulk-delete operation inside the fence document. */
export interface FenceRun {
  action: string;
  startedAtMs: number;
  activeUntilMs: number;
}

/** The opaque per-operation token (`fenceToken`): 128 random bits, hex. */
export const FENCE_TOKEN = /^[0-9a-f]{32}$/;

/** The registered runs of a fence document that are still active at `nowMs` (expired and malformed entries dropped). */
export function activeFenceRuns(
  data: FirebaseFirestore.DocumentData | undefined,
  nowMs: number,
): Record<string, FenceRun> {
  const out: Record<string, FenceRun> = {};
  const runs: unknown = data?.runs;
  if (!runs || typeof runs !== "object") return out;
  for (const [token, raw] of Object.entries(runs as Record<string, unknown>)) {
    const r = raw as Partial<FenceRun> | null;
    if (
      FENCE_TOKEN.test(token) &&
      r &&
      typeof r.action === "string" &&
      typeof r.startedAtMs === "number" &&
      typeof r.activeUntilMs === "number" &&
      r.activeUntilMs > nowMs
    ) {
      out[token] = { action: r.action, startedAtMs: r.startedAtMs, activeUntilMs: r.activeUntilMs };
    }
  }
  return out;
}

/** True while ANY registered bulk delete is still walking this user's scans. */
export function deleteFenceActive(
  data: FirebaseFirestore.DocumentData | undefined,
  nowMs: number,
): boolean {
  return Object.keys(activeFenceRuns(data, nowMs)).length > 0;
}

/** Slack added to the upload-URL lifetime before the late sweep may run. */
export const LATE_SWEEP_MARGIN_MS = 2 * 60 * 1000;
/** Signed PUT URLs issued before a bulk delete stay valid up to this long after it completes. */
export const LATE_SWEEP_DELAY_MS = UPLOAD_URL_TTL_MS + LATE_SWEEP_MARGIN_MS;

/**
 * `body_scan_purge_state/late_sweep_<hash>`: written when a bulk delete
 * completes, `{ uid, action, dueAtMs }` with `dueAtMs = completion +
 * UPLOAD_URL_TTL_MS + margin`. It is NOT the fence and never blocks a create.
 * The scheduled late sweep needs the uid to list the user's prefix, so this
 * server-only record is the one purge-state document that carries it; it lives
 * until the sweep has run (minutes), then is deleted.
 */
export function lateSweepRef(uid: string): FirebaseFirestore.DocumentReference {
  return db().doc(`body_scan_purge_state/late_sweep_${uidKey(uid)}`);
}

/** The purge path guard (P-1): only `users/{uid}/body_scans/{scanId}` is a scan. */
export const SCAN_DOC_PATH = /^users\/[^/]+\/body_scans\/[^/]+$/;

/** `users/{uid}/scans/{scanId}/` -- every object of one scan. */
export function scanPrefix(uid: string, scanId: string): string {
  return `users/${uid}/scans/${scanId}/`;
}

/** `users/{uid}/scans/` -- every object of one user. */
export function userScansPrefix(uid: string): string {
  return `users/${uid}/scans/`;
}

export function poseObjectPath(uid: string, scanId: string, pose: Pose): string {
  return `${scanPrefix(uid, scanId)}${pose}.jpg`;
}

/** The configured bucket, or `failed-precondition: feature-disabled` when none is. */
export function scanBucket() {
  const name = bodyScanBucketName();
  if (!name) throw new HttpsError("failed-precondition", FEATURE_DISABLED_MESSAGE);
  return getStorage().bucket(name);
}

/** Deletes every object of one scan; idempotent (an empty prefix is a no-op). */
export async function deleteScanObjects(uid: string, scanId: string): Promise<void> {
  await scanBucket().deleteFiles({ prefix: scanPrefix(uid, scanId) });
}

/**
 * A bare error code, never a message: GCS and Firestore messages can embed the
 * object path or document path and therefore the uid (D-67).
 */
export function errorSlug(err: unknown): string {
  const code = (err as { code?: unknown } | null | undefined)?.code;
  const text =
    typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

/** The one structured-log message of this feature; the `operation` field discriminates. */
export const BODY_SCAN_EVENT = "body_scan_event";

type LogValue = string | number | boolean | undefined;

/**
 * One structured log line. `fields` may carry only closed slugs and numbers about
 * the call (operation, outcome, latencyMs, counts, provider id/version, a scan
 * id for the purge `purge-stuck` event) -- never a uid, path, URL or metric.
 */
export function logBodyScan(
  level: "info" | "warn" | "error",
  operation: string,
  fields: Record<string, LogValue>,
): void {
  logger[level](BODY_SCAN_EVENT, { operation, ...fields });
}

/**
 * The fields a `cancelled` tombstone must NOT keep: it exists only so late
 * uploads stay discoverable, so no body metric, estimate or note survives it.
 * Removing `takenAt` also drops it from the `takenAt`-ordered history query.
 * For use in `update()` only (a `FieldValue.delete()` is invalid in `create`).
 */
export function tombstoneScrub(): Record<string, FirebaseFirestore.FieldValue> {
  const gone = admin.firestore.FieldValue.delete();
  return {
    subject: gone,
    estimate: gone,
    weightKg: gone,
    capture: gone,
    clientNote: gone,
    takenAt: gone,
    photosExpireAt: gone,
    estimateLeaseUntil: gone,
    estimateCharged: gone,
    estimateAttempts: gone,
    uploadReissues: gone,
  };
}

/** All three pose names, for loops that must cover every pose. */
export const ALL_POSES: readonly Pose[] = POSES;

/**
 * Validated retention from a settings document, `0` (delete after analysis)
 * when absent or malformed -- the privacy-protective default.
 */
export function retentionDaysOf(settings: FirebaseFirestore.DocumentData | undefined): RetentionDays {
  const raw = settings?.retentionDays;
  return (RETENTION_DAYS as readonly unknown[]).includes(raw)
    ? (raw as RetentionDays)
    : 0;
}

/** `body_scan_settings/main.cloudConsent.version`, `0` when no consent is recorded. */
export function consentVersionOf(settings: FirebaseFirestore.DocumentData | undefined): number {
  const v = settings?.cloudConsent?.version;
  return typeof v === "number" && Number.isInteger(v) && v > 0 ? v : 0;
}

export async function readSettings(
  uid: string,
): Promise<FirebaseFirestore.DocumentData | undefined> {
  const snap = await db().doc(`users/${uid}/body_scan_settings/main`).get();
  return snap.data();
}
