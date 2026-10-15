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
import { bodyScanBucketName, bodyScanCloudEnabled } from "./flags";
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
  await enforceAiGatewayEnabled(fn);
  assertFeatureEnabled(bodyScanCloudEnabled());
  return request.auth.uid;
}

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
