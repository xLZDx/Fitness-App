/**
 * `estimateBodyScan` -- runs the configured provider over the uploaded photos
 * (design s7.2, D-53).
 *
 * Race handling, in order:
 *  1. `done` -> return the stored entry: no provider call, no quota, no writes.
 *  2. ONE transaction takes a 60 s processing lease (and records that the quota
 *     was charged), so two concurrent calls make exactly one provider call; the
 *     loser answers `estimate-in-progress` (retriable).
 *  3. Object metadata and the first bytes are checked at READ time (a repeated
 *     PUT can overwrite an object while its URL lives).
 *  4. The provider runs under a 25 s timeout; its output goes through
 *     `validateEstimate`.
 *  5. ONE final transaction re-reads the document and requires `pending` +
 *     `awaiting_upload`: a delete that raced the estimate wins and nothing is
 *     written (`scan-cancelled`).
 *
 * The quota is charged once, at first processing. `estimateCharged` (a
 * server-only marker on the document) keeps a retry after `missing-upload` from
 * charging again; a provider failure refunds the charge and clears the marker.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { BODY_SCAN } from "../scaling";
import { QUOTAS, enforceDailyQuota, refundQuota } from "../abuse_guard";
import { sniffImageMimeType } from "../image_validation";
import { EstimatorTerminalError, resolveEstimator } from "./estimator";
import { providerMap, publicEstimate } from "./create";
import { validateEstimate } from "./validate_estimate";
import {
  BODY_SCAN_CLOUD_CONSENT_VERSION,
  DAY_MS,
  ESTIMATE_LEASE_MS,
  MAX_PHOTO_BYTES,
  MIN_PHOTO_BYTES,
  SCAN_ID_PATTERN,
  UPLOAD_CONTENT_TYPE,
  authorizeBodyScanCall,
  consentVersionOf,
  db,
  deleteScanObjects,
  errorSlug,
  logBodyScan,
  millisOf,
  poseObjectPath,
  readSettings,
  retentionDaysOf,
  scanBucket,
  scanRef,
  tsFromMillis,
} from "./shared";
import {
  POSES,
  type BodyCompositionEstimator,
  type EstimatorOutput,
  type Pose,
  type StoredEstimate,
  type Subject,
} from "./types";

/** The provider call budget (design s7.2 step 5). */
export const ESTIMATE_TIMEOUT_MS = 25 * 1000;

class EstimatorTimeout extends Error {}

function withTimeout<T>(work: Promise<T>, ms: number): Promise<T> {
  let timer: NodeJS.Timeout | undefined;
  const timeout = new Promise<never>((_, reject) => {
    timer = setTimeout(() => reject(new EstimatorTimeout("estimator-timeout")), ms);
  });
  return Promise.race([work, timeout]).finally(() => {
    if (timer) clearTimeout(timer);
  });
}

function doneResponse(scanId: string, data: FirebaseFirestore.DocumentData) {
  return {
    scanId,
    status: "done",
    provider: data.provider,
    estimate: publicEstimate(data.estimate),
    serverNowMs: Date.now(),
  };
}

type LeaseOutcome =
  | "leased"
  | "in-progress"
  | "done"
  | "cancelled"
  | "failed"
  | "not-ready"
  | "exhausted";

/** Provider calls one scan may cause, refunds notwithstanding (P-8). */
export const MAX_ESTIMATE_ATTEMPTS = 3;

/**
 * Clears the lease (and, when `clearCharged`, the charge marker) after a
 * non-final outcome. Returns whether the update landed.
 */
async function releaseLease(
  uid: string,
  scanId: string,
  clearCharged: boolean,
): Promise<boolean> {
  try {
    await scanRef(uid, scanId).update({
      estimateLeaseUntil: admin.firestore.FieldValue.delete(),
      ...(clearCharged ? { estimateCharged: admin.firestore.FieldValue.delete() } : {}),
    });
    return true;
  } catch (e) {
    // A lease that cannot be cleared simply expires after 60 s.
    logBodyScan("warn", "bodyScanEstimate", {
      outcome: "lease-release-failed",
      errorCode: errorSlug(e),
    });
    return false;
  }
}

/**
 * Gives the work back: clears the lease AND the charge marker, then refunds the
 * quota -- but only when the marker really was cleared. A marker that stays
 * `true` while the quota is refunded would let the next call run the provider
 * for free (SF-F7), so on a failed release the charge simply stays on the scan.
 */
async function releaseAndRefund(uid: string, scanId: string, refund: boolean): Promise<void> {
  const cleared = await releaseLease(uid, scanId, true);
  if (cleared && refund) await refundQuota(uid, "bodyScanEstimate", 1);
}

/**
 * Reads every pose's metadata and first bytes. Returns the buffers when all
 * three pass, otherwise the poses that are missing or invalid.
 */
async function readUploads(
  uid: string,
  scanId: string,
): Promise<{ photos: Record<Pose, Buffer> } | { missing: Pose[] }> {
  const bucket = scanBucket();
  const missing: Pose[] = [];
  const photos: Partial<Record<Pose, Buffer>> = {};
  await Promise.all(
    POSES.map(async (pose) => {
      const file = bucket.file(poseObjectPath(uid, scanId, pose));
      try {
        const [meta] = await file.getMetadata();
        const size = Number(meta.size);
        if (
          meta.contentType !== UPLOAD_CONTENT_TYPE ||
          !Number.isFinite(size) ||
          size < MIN_PHOTO_BYTES ||
          size > MAX_PHOTO_BYTES
        ) {
          missing.push(pose);
          return;
        }
        const [bytes] = await file.download();
        if (sniffImageMimeType(bytes) !== UPLOAD_CONTENT_TYPE) {
          missing.push(pose);
          return;
        }
        photos[pose] = bytes;
      } catch (e) {
        // 404 = never uploaded; any other storage failure is infrastructure.
        if ((e as { code?: unknown } | null)?.code === 404) {
          missing.push(pose);
          return;
        }
        throw e;
      }
    }),
  );
  if (missing.length > 0) {
    return { missing: POSES.filter((p) => missing.includes(p)) };
  }
  return { photos: photos as Record<Pose, Buffer> };
}

export const estimateBodyScan = onCall(BODY_SCAN, async (request) => {
  const started = Date.now();
  const uid = await authorizeBodyScanCall(request, "estimateBodyScan");
  const scanId: unknown = (request.data as { scanId?: unknown } | null | undefined)?.scanId;
  if (typeof scanId !== "string" || !SCAN_ID_PATTERN.test(scanId)) {
    throw new HttpsError("invalid-argument", "invalid-scan-id");
  }

  const ref = scanRef(uid, scanId);
  const first = await ref.get();
  if (!first.exists) throw new HttpsError("not-found", "scan-not-found");
  const firstData = first.data() ?? {};
  if (firstData.status === "done") return doneResponse(scanId, firstData);
  if (firstData.status === "cancelled") {
    throw new HttpsError("failed-precondition", "scan-cancelled");
  }
  if (firstData.status === "failed") {
    throw new HttpsError("failed-precondition", "scan-failed");
  }

  const provider: BodyCompositionEstimator = resolveEstimator();

  // Charge once, at first processing. A concurrent loser gets it back below.
  const needsCharge = firstData.estimateCharged !== true;
  if (needsCharge) await enforceDailyQuota(uid, "bodyScanEstimate", QUOTAS.bodyScanEstimate);

  let lease: LeaseOutcome;
  // Filled inside the lease transaction; a holder object (not `let`s) so the
  // closure assignment is visible to the type checker at the use below.
  const claimed: { subject?: Subject; manualOverride?: Record<Pose, boolean> } = {};
  try {
    lease = await db().runTransaction(async (tx): Promise<LeaseOutcome> => {
      const snap = await tx.get(ref);
      const d = snap.data();
      if (!snap.exists || !d) return "cancelled";
      if (d.status === "done") return "done";
      if (d.status === "cancelled") return "cancelled";
      if (d.status === "failed") return "failed";
      if (d.status !== "pending" || d.photosState !== "awaiting_upload") return "not-ready";
      const leaseUntil = millisOf(d.estimateLeaseUntil);
      if (leaseUntil !== undefined && leaseUntil > Date.now()) return "in-progress";
      if ((Number(d.estimateAttempts) || 0) >= MAX_ESTIMATE_ATTEMPTS) return "exhausted";
      claimed.subject = d.subject as Subject;
      claimed.manualOverride = d.capture?.manualOverride as Record<Pose, boolean>;
      tx.update(ref, {
        estimateLeaseUntil: tsFromMillis(Date.now() + ESTIMATE_LEASE_MS),
        estimateCharged: true,
      });
      return "leased";
    });
  } catch (e) {
    if (needsCharge) await refundQuota(uid, "bodyScanEstimate", 1);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "firestore-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-estimate-failed");
  }

  if (lease !== "leased") {
    // Nothing was processed by this call, so any charge it made is returned.
    if (needsCharge) await refundQuota(uid, "bodyScanEstimate", 1);
    if (lease === "done") return doneResponse(scanId, (await ref.get()).data() ?? {});
    if (lease === "in-progress") {
      throw new HttpsError("failed-precondition", "estimate-in-progress");
    }
    if (lease === "failed") throw new HttpsError("failed-precondition", "scan-failed");
    if (lease === "exhausted") {
      throw new HttpsError("resource-exhausted", "estimate-attempts-exceeded");
    }
    if (lease === "not-ready") {
      throw new HttpsError("failed-precondition", "scan-not-ready");
    }
    throw new HttpsError("failed-precondition", "scan-cancelled");
  }

  // From here on this call holds the lease and (if it charged) the quota.
  let uploads: Awaited<ReturnType<typeof readUploads>>;
  try {
    uploads = await readUploads(uid, scanId);
  } catch (e) {
    await releaseAndRefund(uid, scanId, needsCharge);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "storage-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-estimate-failed");
  }
  if ("missing" in uploads) {
    // The charge stays on the scan (estimateCharged): the user re-uploads and
    // calls again without paying twice.
    await releaseLease(uid, scanId, false);
    logBodyScan("info", "bodyScanEstimate", {
      outcome: "missing-upload",
      latencyMs: Date.now() - started,
      providerId: provider.id,
      providerVersion: provider.version,
    });
    throw new HttpsError("failed-precondition", `missing-upload:${uploads.missing.join(",")}`);
  }

  // Consent is re-checked HERE, right before the paid call: it may have been
  // withdrawn since `createBodyScan` (P-4). Nothing is delivered, so give back.
  let consented: boolean;
  try {
    consented = consentVersionOf(await readSettings(uid)) >= BODY_SCAN_CLOUD_CONSENT_VERSION;
  } catch (e) {
    await releaseAndRefund(uid, scanId, needsCharge);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "settings-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-estimate-failed");
  }
  if (!consented) {
    await releaseAndRefund(uid, scanId, needsCharge);
    logBodyScan("info", "bodyScanEstimate", { outcome: "consent-required" });
    throw new HttpsError("failed-precondition", "consent-required");
  }

  // Count the provider call on the scan BEFORE making it; a refund never resets
  // this, so a loop of failing calls is bounded per scan (P-8).
  try {
    await ref.update({ estimateAttempts: admin.firestore.FieldValue.increment(1) });
  } catch (e) {
    await releaseAndRefund(uid, scanId, needsCharge);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "firestore-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-estimate-failed");
  }

  // The provider call. A failure BEFORE output refunds the charge and leaves
  // the scan retryable (`pending`), or terminal (`failed`) for a vendor
  // rejection that no retry can fix.
  let output: EstimatorOutput;
  try {
    output = await withTimeout(
      provider.estimate({
        scanId,
        subject: claimed.subject as Subject,
        photos: uploads.photos,
        capture: { manualOverride: claimed.manualOverride as Record<Pose, boolean> },
      }),
      ESTIMATE_TIMEOUT_MS,
    );
  } catch (e) {
    const terminal = e instanceof EstimatorTerminalError;
    const slug = e instanceof EstimatorTimeout ? "timeout" : terminal ? "terminal" : "error";
    if (terminal) {
      let marked = false;
      try {
        await db().runTransaction(async (tx) => {
          const snap = await tx.get(ref);
          if (snap.data()?.status !== "pending") return;
          tx.update(ref, {
            status: "failed",
            estimateLeaseUntil: admin.firestore.FieldValue.delete(),
            estimateCharged: admin.firestore.FieldValue.delete(),
          });
        });
        marked = true;
      } catch {
        await releaseAndRefund(uid, scanId, needsCharge);
      }
      if (marked && needsCharge) await refundQuota(uid, "bodyScanEstimate", 1);
    } else {
      await releaseAndRefund(uid, scanId, needsCharge);
    }
    logBodyScan("warn", "bodyScanEstimate", {
      outcome: `provider-${slug}`,
      latencyMs: Date.now() - started,
      providerId: provider.id,
      providerVersion: provider.version,
    });
    throw new HttpsError(
      terminal ? "failed-precondition" : "unavailable",
      terminal ? "scan-failed" : "provider-unavailable",
    );
  }

  let estimate: StoredEstimate;
  try {
    estimate = validateEstimate(output, provider.id, provider.version);
  } catch (e) {
    await releaseAndRefund(uid, scanId, needsCharge);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "provider-output-invalid",
      latencyMs: Date.now() - started,
      providerId: provider.id,
      providerVersion: provider.version,
    });
    throw e;
  }

  // Retention comes from the user's settings; absent/malformed means 0.
  let retentionDays = 0;
  try {
    retentionDays = retentionDaysOf(await readSettings(uid));
  } catch {
    retentionDays = 0;
  }

  const nowMs = Date.now();
  // Retention 0 deletes the objects right after success; until that delete is
  // confirmed the state is `stored` with an already-due expiry so a crash or a
  // failed delete is picked up by the purge instead of leaving an orphan.
  const photosExpireAtMs = retentionDays === 0 ? nowMs : nowMs + retentionDays * DAY_MS;
  let finalOutcome: "written" | "done" | "cancelled";
  try {
    finalOutcome = await db().runTransaction(async (tx): Promise<"written" | "done" | "cancelled"> => {
      const snap = await tx.get(ref);
      const d = snap.data();
      if (snap.exists && d?.status === "done") return "done";
      if (!snap.exists || !d || d.status !== "pending" || d.photosState !== "awaiting_upload") {
        return "cancelled";
      }
      tx.update(ref, {
        estimate: { ...estimate, estimatedAt: tsFromMillis(nowMs) },
        status: "done",
        pendingExpiresAt: admin.firestore.FieldValue.delete(),
        estimateLeaseUntil: admin.firestore.FieldValue.delete(),
        estimateCharged: admin.firestore.FieldValue.delete(),
        photosState: "stored",
        photosExpireAt: tsFromMillis(photosExpireAtMs),
      });
      return "written";
    });
  } catch (e) {
    await releaseLease(uid, scanId, false);
    logBodyScan("error", "bodyScanEstimate", {
      outcome: "firestore-failed",
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-estimate-failed");
  }
  if (finalOutcome === "cancelled") {
    // A delete raced the estimate and won: nothing was written, the work is
    // not delivered, so the charge is returned.
    if (needsCharge) await refundQuota(uid, "bodyScanEstimate", 1);
    logBodyScan("info", "bodyScanEstimate", {
      outcome: "raced-delete",
      latencyMs: Date.now() - started,
    });
    throw new HttpsError("failed-precondition", "scan-cancelled");
  }
  if (finalOutcome === "done") {
    return doneResponse(scanId, (await ref.get()).data() ?? {});
  }

  if (retentionDays === 0) {
    try {
      await deleteScanObjects(uid, scanId);
      await ref.update({
        photosState: "deleted",
        photosDeletedAt: tsFromMillis(Date.now()),
        photosExpireAt: admin.firestore.FieldValue.delete(),
      });
    } catch (e) {
      // photosExpireAt is already `now`: the next purge run retries at once.
      logBodyScan("warn", "bodyScanEstimate", {
        outcome: "inline-delete-failed",
        errorCode: errorSlug(e),
      });
    }
  }

  logBodyScan("info", "bodyScanEstimate", {
    outcome: "done",
    latencyMs: Date.now() - started,
    providerId: provider.id,
    providerVersion: provider.version,
  });
  return {
    scanId,
    status: "done",
    provider: providerMap(provider),
    estimate: publicEstimate({ ...estimate, estimatedAt: tsFromMillis(nowMs) }),
    serverNowMs: Date.now(),
  };
});
