/**
 * `deleteBodyScan` -- erases one scan's photos, and optionally the scan itself
 * (design s7.3, D-59).
 *
 * `photosOnly: true` keeps the document and its estimate and marks the photos
 * deleted. `photosOnly: false` writes a 48 h `cancelled` TOMBSTONE instead of
 * removing the document: an estimate that raced the delete sees it and writes
 * nothing, a repeated create answers `scan-cancelled`, and a late signed-URL PUT
 * that lands after the delete stays discoverable by the purge job (it finds the
 * object under a `cancelled` scan) instead of being orphaned for 400 days.
 *
 * The document is written BEFORE the objects are deleted so a racing estimate
 * can never resurrect the scan; if the object delete then fails the call fails
 * (retriable, idempotent) and the purge removes the leftovers.
 *
 * Quota `bodyScanDelete` applies to single-scan deletes only; "delete all" goes
 * through `manageBodyScanData` so a daily limit can never stop an erasure.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { BODY_SCAN } from "../scaling";
import { QUOTAS, enforceDailyQuota } from "../abuse_guard";
import {
  SCAN_ID_PATTERN,
  TOMBSTONE_TTL_MS,
  authorizeBodyScanCall,
  db,
  deleteScanObjects,
  errorSlug,
  logBodyScan,
  scanRef,
  tombstoneScrub,
  tsFromMillis,
} from "./shared";

export const deleteBodyScan = onCall(BODY_SCAN, async (request) => {
  const started = Date.now();
  const uid = await authorizeBodyScanCall(request, "deleteBodyScan");
  const data = request.data as { scanId?: unknown; photosOnly?: unknown } | null | undefined;
  const scanId = data?.scanId;
  if (typeof scanId !== "string" || !SCAN_ID_PATTERN.test(scanId)) {
    throw new HttpsError("invalid-argument", "invalid-scan-id");
  }
  if (typeof data?.photosOnly !== "boolean") {
    throw new HttpsError("invalid-argument", "invalid-photos-only");
  }
  const photosOnly = data.photosOnly;

  await enforceDailyQuota(uid, "bodyScanDelete", QUOTAS.bodyScanDelete);

  const ref = scanRef(uid, scanId);
  const nowMs = Date.now();
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      if (photosOnly) {
        // Nothing to mark when the document never existed; the object delete
        // below is still idempotent.
        if (snap.exists) {
          tx.update(ref, {
            photosState: "deleted",
            photosDeletedAt: tsFromMillis(nowMs),
            photosExpireAt: admin.firestore.FieldValue.delete(),
          });
        }
        return;
      }
      const tombstone = {
        status: "cancelled",
        photosState: "deleted",
        photosDeletedAt: tsFromMillis(nowMs),
        pendingExpiresAt: tsFromMillis(nowMs + TOMBSTONE_TTL_MS),
      };
      if (snap.exists) {
        // Scrubbed: the tombstone keeps no metric, estimate or note.
        tx.update(ref, { ...tombstone, ...tombstoneScrub() });
      } else {
        // A delete for a scan the server never saw (an offline-queued delete
        // that outran its create) still blocks a later create of that id.
        tx.set(ref, {
          schema: 1,
          createdAt: tsFromMillis(nowMs),
          purgeAttempts: 0,
          ...tombstone,
        });
      }
    });
    await deleteScanObjects(uid, scanId);
  } catch (e) {
    logBodyScan("error", "bodyScanDelete", {
      outcome: "failed",
      photosOnly,
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-delete-failed");
  }

  logBodyScan("info", "bodyScanDelete", {
    outcome: photosOnly ? "photos-deleted" : "tombstoned",
    latencyMs: Date.now() - started,
  });
  return { scanId, deleted: true, serverNowMs: Date.now() };
});
