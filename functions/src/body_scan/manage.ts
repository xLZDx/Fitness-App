/**
 * `manageBodyScanData` -- bulk privacy actions (design s7.8, D-62).
 *
 * One callable, four actions, its own quota (`bodyScanManage`) so that "delete
 * all" can never be blocked by the per-scan delete limit:
 *
 *  - `applyRetention`: makes a LOWERED retention retroactive on request
 *    (`photosExpireAt = min(photosExpireAt, takenAt + retentionDays)`, objects
 *    already past it are deleted).
 *  - `deleteAllPhotos`: deletes the objects of every scan and marks them deleted.
 *  - `deleteAllScans`: the same, and turns each scan into a scrubbed `cancelled`
 *    tombstone (the purge job removes it after 48 h).
 *  - `exportLinks`: 1-hour V4 READ URLs for stored photos, newest first, at most
 *    60 links per call with a cursor; the export itself carries metadata only, so
 *    `fn-data` never needs read access to the bucket.
 *
 * Paging: scans are walked in document-id order (`deleteAll*`, `applyRetention`)
 * so no composite index is needed; the caller loops while `nextCursor` is set.
 * `exportLinks` pages newest-first by `takenAt` (single-field index).
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { BODY_SCAN } from "../scaling";
import { QUOTAS, enforceDailyQuota } from "../abuse_guard";
import {
  DAY_MS,
  EXPORT_LINK_TTL_MS,
  RETENTION_DAYS,
  TOMBSTONE_TTL_MS,
  authorizeBodyScanCall,
  db,
  deleteScanObjects,
  errorSlug,
  logBodyScan,
  millisOf,
  poseObjectPath,
  scanBucket,
  tombstoneScrub,
  tsFromMillis,
  userScansPrefix,
} from "./shared";
import { POSES } from "./types";

const ACTIONS = ["applyRetention", "deleteAllPhotos", "deleteAllScans", "exportLinks"] as const;
type Action = (typeof ACTIONS)[number];

/** Scans handled per call by the paged actions (design s7.8). */
const PAGE = 200;
/** Concurrent object deletes inside one page. */
const CHUNK = 10;
/** Scans per `exportLinks` page: 20 scans x 3 poses = at most 60 links. */
const EXPORT_PAGE_SCANS = 20;

const CURSOR_ID = /^[A-Za-z0-9_-]{8,64}$/;
const CURSOR_MS = /^[0-9]{1,16}$/;

function bad(slug: string): never {
  throw new HttpsError("invalid-argument", slug);
}

async function inChunks<T>(items: readonly T[], work: (item: T) => Promise<void>): Promise<void> {
  for (let i = 0; i < items.length; i += CHUNK) {
    await Promise.all(items.slice(i, i + CHUNK).map(work));
  }
}

export const manageBodyScanData = onCall(BODY_SCAN, async (request) => {
  const started = Date.now();
  const uid = await authorizeBodyScanCall(request, "manageBodyScanData");
  const data = request.data as
    | { action?: unknown; retentionDays?: unknown; cursor?: unknown }
    | null
    | undefined;
  const action = data?.action;
  if (typeof action !== "string" || !(ACTIONS as readonly string[]).includes(action)) {
    bad("invalid-action");
  }
  const cursor = data?.cursor;
  if (cursor !== undefined && typeof cursor !== "string") bad("invalid-cursor");
  let retentionDays = 0;
  if (action === "applyRetention") {
    const raw = data?.retentionDays;
    if (typeof raw !== "number" || !(RETENTION_DAYS as readonly number[]).includes(raw)) {
      bad("invalid-retention");
    }
    retentionDays = raw as number;
  }

  await enforceDailyQuota(uid, "bodyScanManage", QUOTAS.bodyScanManage);

  try {
    const result =
      (action as Action) === "exportLinks"
        ? await exportLinks(uid, cursor as string | undefined)
        : await pagedAction(uid, action as Action, retentionDays, cursor as string | undefined);
    logBodyScan("info", "bodyScanManage", {
      outcome: action as string,
      latencyMs: Date.now() - started,
      processed: result.processed,
    });
    return { action, ...result, serverNowMs: Date.now() };
  } catch (e) {
    if (e instanceof HttpsError) throw e;
    logBodyScan("error", "bodyScanManage", {
      outcome: "failed",
      action: action as string,
      errorCode: errorSlug(e),
    });
    throw new HttpsError("internal", "scan-manage-failed");
  }
});

interface PageResult {
  processed: number;
  nextCursor?: string;
}

async function pagedAction(
  uid: string,
  action: Exclude<Action, "exportLinks">,
  retentionDays: number,
  cursor: string | undefined,
): Promise<PageResult> {
  if (cursor !== undefined && !CURSOR_ID.test(cursor)) bad("invalid-cursor");
  let query = db()
    .collection(`users/${uid}/body_scans`)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(PAGE);
  if (cursor !== undefined) query = query.startAfter(cursor);
  const page = await query.get();
  const nowMs = Date.now();

  await inChunks(page.docs, async (doc) => {
    const d = doc.data();
    if (action === "applyRetention") {
      if (d.photosState !== "stored") return;
      const takenAt = millisOf(d.takenAt);
      if (takenAt === undefined) return;
      const current = millisOf(d.photosExpireAt) ?? Number.POSITIVE_INFINITY;
      const expireAt = Math.min(current, takenAt + retentionDays * DAY_MS);
      if (expireAt <= nowMs) {
        await deleteScanObjects(uid, doc.id);
        await doc.ref.update({
          photosState: "deleted",
          photosDeletedAt: tsFromMillis(nowMs),
          photosExpireAt: admin.firestore.FieldValue.delete(),
        });
      } else if (expireAt < current) {
        await doc.ref.update({ photosExpireAt: tsFromMillis(expireAt) });
      }
      return;
    }
    if (action === "deleteAllPhotos") {
      if (d.photosState === "deleted" || d.photosState === "none") return;
      await doc.ref.update({
        photosState: "deleted",
        photosDeletedAt: tsFromMillis(nowMs),
        photosExpireAt: admin.firestore.FieldValue.delete(),
      });
      await deleteScanObjects(uid, doc.id);
      return;
    }
    // deleteAllScans: an existing tombstone only needs its objects re-swept.
    if (d.status === "cancelled") {
      await deleteScanObjects(uid, doc.id);
      return;
    }
    await doc.ref.update({
      status: "cancelled",
      photosState: "deleted",
      photosDeletedAt: tsFromMillis(nowMs),
      pendingExpiresAt: tsFromMillis(nowMs + TOMBSTONE_TTL_MS),
      ...tombstoneScrub(),
    });
    await deleteScanObjects(uid, doc.id);
  });

  const last = page.docs[page.docs.length - 1];
  const hasMore = page.docs.length === PAGE;
  if (!hasMore && action !== "applyRetention") {
    // Final page of a delete-all: also clear anything under the user's prefix
    // that no document accounts for (a late PUT, a document-less object).
    await scanBucket().deleteFiles({ prefix: userScansPrefix(uid) });
  }
  return { processed: page.docs.length, ...(hasMore && last ? { nextCursor: last.id } : {}) };
}

interface LinksResult extends PageResult {
  links: { scanId: string; pose: string; url: string; expiresAtMs: number }[];
}

async function exportLinks(uid: string, cursor: string | undefined): Promise<LinksResult> {
  if (cursor !== undefined && !CURSOR_MS.test(cursor)) bad("invalid-cursor");
  let query = db()
    .collection(`users/${uid}/body_scans`)
    .orderBy("takenAt", "desc")
    .limit(EXPORT_PAGE_SCANS);
  if (cursor !== undefined) query = query.startAfter(tsFromMillis(Number(cursor)));
  const page = await query.get();

  const nowMs = Date.now();
  const expiresAtMs = nowMs + EXPORT_LINK_TTL_MS;
  const bucket = scanBucket();
  const links: LinksResult["links"] = [];
  await inChunks(
    page.docs.filter((doc) => doc.data().photosState === "stored"),
    async (doc) => {
      for (const pose of POSES) {
        const [url] = await bucket.file(poseObjectPath(uid, doc.id, pose)).getSignedUrl({
          version: "v4",
          action: "read",
          expires: expiresAtMs,
        });
        links.push({ scanId: doc.id, pose, url, expiresAtMs });
      }
    },
  );
  // Chunks finish in any order; present newest first as documented.
  const order = new Map(page.docs.map((doc, i) => [doc.id, i] as const));
  links.sort(
    (a, b) =>
      (order.get(a.scanId) ?? 0) - (order.get(b.scanId) ?? 0) ||
      POSES.indexOf(a.pose as (typeof POSES)[number]) -
        POSES.indexOf(b.pose as (typeof POSES)[number]),
  );

  const last = page.docs[page.docs.length - 1];
  const lastMs = last ? millisOf(last.data().takenAt) : undefined;
  const hasMore = page.docs.length === EXPORT_PAGE_SCANS && lastMs !== undefined;
  return {
    processed: links.length,
    links,
    ...(hasMore ? { nextCursor: String(lastMs) } : {}),
  };
}
