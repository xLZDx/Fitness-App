/**
 * `createBodyScan` -- idempotent scan creation and signed upload URL issuance
 * (design s7.1, D-53, D-58, D-59).
 *
 * Order (part of the contract): auth -> App Check note -> non-anonymous -> kill
 * switch -> feature flag (bucket configured) -> validate -> provider -> refuse
 * while the account is being deleted -> age and tier gate -> existing-document
 * lookup -> consent -> quota, charged ONLY when a document is created (or reset
 * from `failed`) -> create/reset in a transaction -> sign three PUT URLs.
 *
 * Idempotency: the scan id is the client's id, so a replay or an offline retry
 * finds the document it created. `done` returns the stored entry untouched;
 * `pending` re-issues URLs and charges nothing; `failed` is reset to `pending`
 * (charged again, the first charge was spent on the failure); a `cancelled`
 * tombstone answers `scan-cancelled` so the client rotates its remote id.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { BODY_SCAN } from "../scaling";
import { QUOTAS, enforceDailyQuota, refundQuota } from "../abuse_guard";
import { resolveEstimator, PROVIDER_NOT_CONFIGURED } from "./estimator";
import { assertScanTier, resolveAdultAge } from "./access";
import {
  BODY_SCAN_CLOUD_CONSENT_VERSION,
  DAY_MS,
  PENDING_TTL_MS,
  SCAN_ID_PATTERN,
  UPLOAD_CONTENT_TYPE,
  UPLOAD_LENGTH_HEADER,
  UPLOAD_LENGTH_RANGE,
  UPLOAD_URL_TTL_MS,
  authorizeBodyScanCall,
  consentVersionOf,
  db,
  deleteFenceActive,
  deleteFenceRef,
  errorSlug,
  logBodyScan,
  millisOf,
  poseObjectPath,
  readSettings,
  scanBucket,
  scanRef,
  tsFromMillis,
} from "./shared";
import {
  POSES,
  SEXES_AT_BIRTH,
  type BodyCompositionEstimator,
  type Pose,
  type SexAtBirth,
  type Subject,
} from "./types";

export interface CreateRequest {
  scanId: string;
  takenAtMs: number;
  sexAtBirth: SexAtBirth;
  heightCm: number;
  weightKg: number;
  manualOverride: Record<Pose, boolean>;
}

const TAKEN_AT_PAST_MS = 7 * DAY_MS;
const TAKEN_AT_FUTURE_MS = 5 * 60 * 1000;
const ALREADY_EXISTS = 6;

function bad(slug: string): never {
  throw new HttpsError("invalid-argument", slug);
}

function asRecord(value: unknown): Record<string, unknown> | undefined {
  return typeof value === "object" && value !== null && !Array.isArray(value)
    ? (value as Record<string, unknown>)
    : undefined;
}

/**
 * Strict validation (design s7.1): exact types, closed enums, bounded numbers;
 * unknown keys are ignored and `subject.ageYears` is never read (D-58).
 */
export function parseCreateRequest(data: unknown, nowMs: number): CreateRequest {
  const root = asRecord(data);
  if (!root) bad("invalid-request");
  const r = root as Record<string, unknown>;

  const scanId = r.scanId;
  if (typeof scanId !== "string" || !SCAN_ID_PATTERN.test(scanId)) {
    bad("invalid-scan-id");
  }
  const takenAtMs = r.takenAtMs;
  if (
    typeof takenAtMs !== "number" ||
    !Number.isFinite(takenAtMs) ||
    takenAtMs < nowMs - TAKEN_AT_PAST_MS ||
    takenAtMs > nowMs + TAKEN_AT_FUTURE_MS
  ) {
    bad("invalid-taken-at");
  }

  const subject = asRecord(r.subject);
  if (!subject) bad("invalid-subject");
  const s = subject as Record<string, unknown>;
  const sex = s.sexAtBirth;
  if (typeof sex !== "string" || !(SEXES_AT_BIRTH as readonly string[]).includes(sex)) {
    bad("invalid-subject");
  }
  const heightCm = s.heightCm;
  if (
    typeof heightCm !== "number" ||
    !Number.isInteger(heightCm) ||
    heightCm < 120 ||
    heightCm > 230
  ) {
    bad("invalid-subject");
  }
  const weightKg = s.weightKg;
  if (
    typeof weightKg !== "number" ||
    !Number.isFinite(weightKg) ||
    weightKg < 30 ||
    weightKg > 300
  ) {
    bad("invalid-subject");
  }

  const capture = asRecord(r.capture);
  const override = asRecord(capture?.manualOverride);
  if (!override) bad("invalid-capture");
  const o = override as Record<string, unknown>;
  for (const pose of POSES) {
    if (typeof o[pose] !== "boolean") bad("invalid-capture");
  }

  return {
    scanId: scanId as string,
    takenAtMs: takenAtMs as number,
    sexAtBirth: sex as SexAtBirth,
    heightCm: heightCm as number,
    weightKg: weightKg as number,
    manualOverride: {
      front: o.front as boolean,
      side: o.side as boolean,
      back: o.back as boolean,
    },
  };
}

/** The `provider` map stored on the document and returned to the client. */
export function providerMap(provider: BodyCompositionEstimator) {
  return {
    id: provider.id,
    version: provider.version,
    provisional: provider.provisional,
    requiresPhotos: provider.requiresPhotos,
  };
}

/** A stored estimate in its client-facing shape (`estimatedAt` as epoch millis). */
export function publicEstimate(estimate: FirebaseFirestore.DocumentData | undefined) {
  if (!estimate) return undefined;
  return {
    bodyFatPct: estimate.bodyFatPct,
    rangeLowPct: estimate.rangeLowPct,
    rangeHighPct: estimate.rangeHighPct,
    confidence: estimate.confidence,
    checkCodes: estimate.checkCodes,
    modelId: estimate.modelId,
    modelVersion: estimate.modelVersion,
    estimatedAtMs: millisOf(estimate.estimatedAt),
  };
}

/** The refusal while a deletion is in flight (D-59): no new objects may appear. */
async function refuseWhileDeleting(uid: string): Promise<void> {
  const retry = await db().doc(`accountDeletionRetries/${uid}`).get();
  if (retry.exists) throw new HttpsError("failed-precondition", "account-deleting");
}

type Uploads = Record<
  Pose,
  { url: string; headers: Record<string, string>; expiresAtMs: number }
>;

async function signUploads(uid: string, scanId: string, nowMs: number): Promise<Uploads> {
  const bucket = scanBucket();
  const expiresAtMs = nowMs + UPLOAD_URL_TTL_MS;
  try {
    const entries = await Promise.all(
      POSES.map(async (pose) => {
        const [url] = await bucket.file(poseObjectPath(uid, scanId, pose)).getSignedUrl({
          version: "v4",
          action: "write",
          expires: expiresAtMs,
          contentType: UPLOAD_CONTENT_TYPE,
          extensionHeaders: { [UPLOAD_LENGTH_HEADER]: UPLOAD_LENGTH_RANGE },
        });
        return [
          pose,
          {
            url,
            headers: {
              "Content-Type": UPLOAD_CONTENT_TYPE,
              [UPLOAD_LENGTH_HEADER]: UPLOAD_LENGTH_RANGE,
            },
            expiresAtMs,
          },
        ] as const;
      }),
    );
    return Object.fromEntries(entries) as unknown as Uploads;
  } catch (e) {
    // Slug only: the SDK error text can embed the object path (D-67).
    logBodyScan("error", "bodyScanCreate", {
      outcome: "sign-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "upload-url-failed");
  }
}

type Decision = "created" | "reset" | "reissue" | "done" | "cancelled" | "capped" | "deleting";

/** Signed-URL reissues one scan may get (P-5); a fresh create/reset starts at 0. */
export const MAX_UPLOAD_REISSUES = 5;

export const createBodyScan = onCall(BODY_SCAN, async (request) => {
  const started = Date.now();
  const uid = await authorizeBodyScanCall(request, "createBodyScan");
  const input = parseCreateRequest(request.data, started);
  const provider = resolveEstimator();
  if (!provider.requiresPhotos) {
    throw new HttpsError("failed-precondition", PROVIDER_NOT_CONFIGURED);
  }

  await refuseWhileDeleting(uid);
  // The client-sent age is never read; the server value is stored (D-58).
  const ageYears = await resolveAdultAge(uid, started);
  await assertScanTier(uid, started);

  const ref = scanRef(uid, input.scanId);
  const existing = await ref.get();
  const existingStatus: unknown = existing.exists ? existing.data()?.status : undefined;

  if (existingStatus === "cancelled") {
    throw new HttpsError("failed-precondition", "scan-cancelled");
  }
  if (existingStatus === "done") {
    const data = existing.data() ?? {};
    logBodyScan("info", "bodyScanCreate", {
      outcome: "done-replay",
      latencyMs: Date.now() - started,
    });
    return {
      scanId: input.scanId,
      status: "done",
      provider: data.provider,
      estimate: publicEstimate(data.estimate),
      serverNowMs: Date.now(),
    };
  }

  const settings = await readSettings(uid);
  if (consentVersionOf(settings) < BODY_SCAN_CLOUD_CONSENT_VERSION) {
    throw new HttpsError("failed-precondition", "consent-required");
  }

  const subject: Subject = {
    sexAtBirth: input.sexAtBirth,
    ageYears,
    heightCm: input.heightCm,
    weightKg: input.weightKg,
  };
  // Clamp the client capture time into [createdAt - 7 d, createdAt] (design s5.1).
  const takenAtMs = Math.min(
    Math.max(input.takenAtMs, started - TAKEN_AT_PAST_MS),
    started,
  );

  // Quota is charged ONLY when a document is about to be created or reset; an
  // idempotent replay or an offline retry of a pending scan charges nothing.
  const needsCharge = !existing.exists || existingStatus === "failed";
  if (needsCharge) {
    await enforceDailyQuota(uid, "bodyScanCreate", QUOTAS.bodyScanCreate);
  }

  let decision: Decision;
  try {
    decision = await db().runTransaction(async (tx): Promise<Decision> => {
      const snap = await tx.get(ref);
      const status: unknown = snap.exists ? snap.data()?.status : undefined;
      // A bulk delete-all is walking this user's scans: no new scan work may
      // start (a scan created behind its cursor would survive it). Terminal
      // replays (`done`, `cancelled`) are unaffected. The fence is read in the
      // transaction, so a fence written after this read forces a retry.
      if (status !== "done" && status !== "cancelled") {
        const fence = await tx.get(deleteFenceRef(uid));
        if (deleteFenceActive(fence.data(), Date.now())) return "deleting";
      }
      const fresh = {
        status: "pending",
        pendingExpiresAt: tsFromMillis(started + PENDING_TTL_MS),
        subject,
        capture: { manualOverride: input.manualOverride, poses: [...POSES] },
        provider: providerMap(provider),
        photosState: "awaiting_upload",
        purgeAttempts: 0,
      };
      if (!snap.exists) {
        tx.create(ref, {
          schema: 1,
          createdAt: tsFromMillis(started),
          takenAt: tsFromMillis(takenAtMs),
          weightKg: input.weightKg,
          ...fresh,
        });
        return "created";
      }
      if (status === "failed") {
        tx.update(ref, {
          ...fresh,
          estimateLeaseUntil: admin.firestore.FieldValue.delete(),
          estimateAttempts: admin.firestore.FieldValue.delete(),
          uploadReissues: admin.firestore.FieldValue.delete(),
        });
        return "reset";
      }
      if (status === "cancelled") return "cancelled";
      if (status === "done") return "done";
      if ((Number(snap.data()?.uploadReissues) || 0) >= MAX_UPLOAD_REISSUES) return "capped";
      // A fresh URL set means the user is still uploading: the purge must not
      // tombstone the scan mid-upload (DB-F8).
      tx.update(ref, {
        pendingExpiresAt: tsFromMillis(started + PENDING_TTL_MS),
        uploadReissues: admin.firestore.FieldValue.increment(1),
      });
      return "reissue";
    });
  } catch (e) {
    // The pre-read said "absent" but another call created it first: the charge
    // did not buy a new document, so it is given back and the caller retries.
    if (needsCharge) await refundQuota(uid, "bodyScanCreate", 1);
    if ((e as { code?: unknown } | null)?.code === ALREADY_EXISTS) {
      throw new HttpsError("aborted", "scan-create-conflict");
    }
    logBodyScan("error", "bodyScanCreate", {
      outcome: "firestore-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-create-failed");
  }

  if (decision === "cancelled") {
    if (needsCharge) await refundQuota(uid, "bodyScanCreate", 1);
    throw new HttpsError("failed-precondition", "scan-cancelled");
  }
  if (decision === "deleting") {
    if (needsCharge) await refundQuota(uid, "bodyScanCreate", 1);
    throw new HttpsError("failed-precondition", "delete-in-progress");
  }
  if (decision === "capped") {
    if (needsCharge) await refundQuota(uid, "bodyScanCreate", 1);
    throw new HttpsError("resource-exhausted", "upload-url-limit");
  }
  if (decision === "done") {
    // A concurrent estimate finished between the lookup and the transaction.
    if (needsCharge) await refundQuota(uid, "bodyScanCreate", 1);
    const latest = (await ref.get()).data() ?? {};
    return {
      scanId: input.scanId,
      status: "done",
      provider: latest.provider,
      estimate: publicEstimate(latest.estimate),
      serverNowMs: Date.now(),
    };
  }
  if (decision === "reissue" && needsCharge) {
    // Created by a concurrent call after our lookup: nothing new was created here.
    await refundQuota(uid, "bodyScanCreate", 1);
  }

  const uploads = await signUploads(uid, input.scanId, Date.now());
  logBodyScan("info", "bodyScanCreate", {
    outcome: decision,
    latencyMs: Date.now() - started,
    providerId: provider.id,
    providerVersion: provider.version,
  });
  return {
    scanId: input.scanId,
    status: "pending",
    provider: providerMap(provider),
    uploads,
    serverNowMs: Date.now(),
  };
});
