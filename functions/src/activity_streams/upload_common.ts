/**
 * Shared pieces of the two upload callables (S02 design 5.2, 5.3, 5.4; story
 * S02-04b): the bare refusal codes, the injectable dependency seam, the common
 * in-transaction precondition read (fence, tombstone, summary, consent) and the
 * derived-expiry arithmetic. Nothing here talks to the Functions runtime, so
 * test agents drive it with fake Firestore, bucket, Auth and clock.
 *
 * The row (`users/{uid}/activity_streams/{activityId}`) is a state machine:
 * `pending` -> `stored` -> `expired` | `deleted`. A stored row that is being
 * re-uploaded KEEPS `state = stored` and gains `pendingUploadId`,
 * `pendingContentSha256` and `pendingSince`, so the purge query (which selects
 * `state == stored`) still sees the old object and its expiry cannot be
 * outlived by a re-upload.
 */
import { randomBytes } from "crypto";
import { HttpsError } from "firebase-functions/v2/https";
import { activityStreamBucket, type StreamBucket } from "./bucket";
import { activityTombstoned, checkAccountFence, defaultFenceDeps, type FenceDeps } from "./fence";
import { activityStreamRowPath, activitySummaryPath } from "./paths";
import {
  activitySettingsPath,
  cloudStreamsConsentState,
  effectiveStreamRetentionDays,
  settingsGenerationOf,
  type StreamRetentionDays,
} from "./settings";
import type { UploadValidationOptions } from "./upload_validate";

/** Quota actions of the two callables (design 5.4); also listed in `REDACTED_QUOTA_ACTIONS`. */
export const UPLOAD_QUOTA_ACTION = "activityStreamUpload";
export const COMMIT_QUOTA_ACTION = "activityStreamCommit";

/** Signed-URL lifetime (design 5.2). */
export const UPLOAD_URL_TTL_MS = 10 * 60 * 1000;

/** Content type of the quarantine PUT and of the promoted object. */
export const STREAM_CONTENT_TYPE = "application/gzip";

/** Header that makes GCS enforce the object size on the signed PUT. */
export const STREAM_LENGTH_HEADER = "x-goog-content-length-range";

/** Upload attempts per activity per UTC day (design 5.2). */
export const MAX_ATTEMPTS_PER_DAY = 5;

/** Lower clamp of the activity date used for the derived expiry (design 5.3). */
export const ACTIVITY_DATE_FLOOR_MS = Date.UTC(2000, 0, 1);

const DAY_MS = 24 * 60 * 60 * 1000;

export type UploadRefusalCode =
  | "invalid_request"
  | "account_deleting"
  | "account_deleted"
  | "quota_exceeded"
  | "deleted"
  | "no_summary"
  | "consent_required"
  | "consent_withdrawn"
  | "already_expired"
  | "expired"
  | "too_many_attempts"
  | "superseded"
  | "upload_missing"
  | "generation_changed"
  | "upload_failed"
  | "upload_url_failed"
  | "commit_failed";

type HttpsCode = ConstructorParameters<typeof HttpsError>[0];

const HTTPS_CODE: Record<UploadRefusalCode, HttpsCode> = {
  invalid_request: "invalid-argument",
  account_deleting: "failed-precondition",
  account_deleted: "unauthenticated",
  quota_exceeded: "resource-exhausted",
  deleted: "failed-precondition",
  no_summary: "failed-precondition",
  consent_required: "failed-precondition",
  consent_withdrawn: "failed-precondition",
  already_expired: "failed-precondition",
  expired: "failed-precondition",
  too_many_attempts: "resource-exhausted",
  superseded: "aborted",
  upload_missing: "failed-precondition",
  generation_changed: "aborted",
  upload_failed: "internal",
  upload_url_failed: "internal",
  commit_failed: "internal",
};

/**
 * A refusal with a bare code. `code` is either one of the closed codes above or
 * a validator rejection code (`hr_kind`, `bomb`, ... from S02-04a); it is the
 * only thing the client ever sees and never embeds client input.
 */
export class UploadRefusal extends Error {
  constructor(readonly code: string) {
    super(code);
    this.name = "UploadRefusal";
  }
}

/** The HttpsError for a bare code; unknown (validator) codes are client errors. */
export function toUploadHttpsError(code: string): HttpsError {
  const mapped = (HTTPS_CODE as Record<string, HttpsCode | undefined>)[code] ?? "invalid-argument";
  return new HttpsError(mapped, code);
}

/** Injectable collaborators of both callables. */
export interface UploadDeps extends FenceDeps {
  /** The stream bucket, or `undefined` when the feature is off. */
  bucket(): StreamBucket | undefined;
  /** A fresh server-generated upload id (`up_` + 32 lowercase hex). */
  newUploadId(): string;
  /** Test overrides for the byte validator (clock, gunzip stream, boundary limits). */
  validationOptions?(): UploadValidationOptions;
}

export const defaultUploadDeps: UploadDeps = {
  ...defaultFenceDeps,
  bucket: () => activityStreamBucket(),
  newUploadId: () => `up_${randomBytes(16).toString("hex")}`,
};

export type RowData = Record<string, unknown>;

/** Epoch millis of a Firestore Timestamp-like value or a Date, else `undefined`. */
export function timestampMs(v: unknown): number | undefined {
  if (v instanceof Date) return v.getTime();
  const m = (v as { toMillis?: unknown } | null | undefined)?.toMillis;
  if (typeof m === "function") {
    const n = (m as () => unknown).call(v);
    return typeof n === "number" && Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

/** `YYYY-MM-DD` of the UTC day containing `nowMs` (the `attemptsDay` key). */
export function utcDayOf(nowMs: number): string {
  return new Date(nowMs).toISOString().slice(0, 10);
}

/**
 * The activity date used for retention: the summary `startUtc` clamped to
 * [2000-01-01, now] (design 5.3). Never a client parameter.
 */
export function activityDateMs(startUtcMs: number, nowMs: number): number {
  return Math.min(Math.max(startUtcMs, ACTIVITY_DATE_FLOOR_MS), nowMs);
}

/** Derived expiry in epoch millis, `null` when retention is "never". */
export function derivedExpiryMs(
  startUtcMs: number,
  retentionDays: StreamRetentionDays,
  nowMs: number,
): number | null {
  if (retentionDays === null) return null;
  return activityDateMs(startUtcMs, nowMs) + retentionDays * DAY_MS;
}

/** True when the derived expiry is at or before `nowMs` (design 5.2: "already due"). */
export function isExpiryDue(
  startUtcMs: number,
  retentionDays: StreamRetentionDays,
  nowMs: number,
): boolean {
  const expiry = derivedExpiryMs(startUtcMs, retentionDays, nowMs);
  return expiry !== null && expiry <= nowMs;
}

/** Everything both callables read inside their transaction once the fence is clear. */
export interface UploadContext {
  /** Summary `startUtc` in millis. */
  startUtcMs: number;
  settings: RowData | undefined;
  settingsGeneration: number;
  retentionDays: StreamRetentionDays;
  /** The existing stream index row, `undefined` when absent. */
  row: RowData | undefined;
}

/**
 * The common precondition read, in the order of the contract (design 5.2):
 * account fence (both documents plus Auth existence), tombstone, summary,
 * consent, then the settings values and the existing row. ALL reads happen
 * here, before the caller's first write. Throws `UploadRefusal` with a bare
 * code on any refusal (nothing was written yet, so throwing is safe).
 */
export async function readUploadContext(
  tx: FirebaseFirestore.Transaction,
  deps: UploadDeps,
  uid: string,
  activityId: string,
): Promise<UploadContext> {
  const fs = deps.firestore();
  const fence = await checkAccountFence(tx, deps, uid);
  if (fence !== "clear") throw new UploadRefusal(fence);
  if (await activityTombstoned(tx, deps, uid, activityId)) throw new UploadRefusal("deleted");

  const [summarySnap, settingsSnap, rowSnap] = await Promise.all([
    tx.get(fs.doc(activitySummaryPath(uid, activityId))),
    tx.get(fs.doc(activitySettingsPath(uid))),
    tx.get(fs.doc(activityStreamRowPath(uid, activityId))),
  ]);
  const startUtcMs = summarySnap.exists
    ? timestampMs((summarySnap.data() as RowData | undefined)?.startUtc)
    : undefined;
  if (startUtcMs === undefined) throw new UploadRefusal("no_summary");

  const settings = settingsSnap.exists ? (settingsSnap.data() as RowData) : undefined;
  const consent = cloudStreamsConsentState(settings);
  if (consent === "withdrawn") throw new UploadRefusal("consent_withdrawn");
  if (consent !== "granted") throw new UploadRefusal("consent_required");

  return {
    startUtcMs,
    settings,
    settingsGeneration: settingsGenerationOf(settings),
    retentionDays: effectiveStreamRetentionDays(settings),
    row: rowSnap.exists ? (rowSnap.data() as RowData) : undefined,
  };
}

/** A bare error code from a thrown value; never the message (it can embed a path and so the uid). */
export function errorCodeOf(e: unknown): string {
  const code = (e as { code?: unknown } | null | undefined)?.code;
  const text = typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

/** True for a Storage 404 (object or generation not found). */
export function isNotFound(e: unknown): boolean {
  const code = (e as { code?: unknown } | null)?.code;
  return code === 404 || code === "404";
}

/** String value of a row field, else `undefined`. */
export function strOf(v: unknown): string | undefined {
  return typeof v === "string" ? v : undefined;
}
