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
import { randomBytes } from "crypto";
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
  DELETE_FENCE_MS,
  FENCE_TOKEN,
  LATE_SWEEP_DELAY_MS,
  activeFenceRuns,
  db,
  deleteFenceRef,
  deleteScanObjects,
  errorSlug,
  logBodyScan,
  millisOf,
  poseObjectPath,
  scanBucket,
  lateSweepRef,
  tombstoneScrub,
  tsFromMillis,
  userScansPrefix,
} from "./shared";
import { POSES } from "./types";

const ACTIONS = ["applyRetention", "deleteAllPhotos", "deleteAllScans", "exportLinks"] as const;
type Action = (typeof ACTIONS)[number];

/** Scans handled per call by the paged actions (design s7.8). */
const PAGE = 200;
/** Straggler re-query passes after the final page of a delete-all. */
const STRAGGLER_PASSES = 3;
/** Concurrent object deletes inside one page. */
const CHUNK = 10;
/** Scans per `exportLinks` page: 20 scans x 3 poses = at most 60 links. */
const EXPORT_PAGE_SCANS = 20;

const CURSOR_ID = /^[A-Za-z0-9_-]{8,64}$/;
/** `exportLinks` cursor: `<takenAt ms>:<scan id>` so equal timestamps cannot skip scans. */
const CURSOR_EXPORT = /^([0-9]{1,16}):([A-Za-z0-9_-]{8,64})$/;

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
    | { action?: unknown; retentionDays?: unknown; cursor?: unknown; fenceToken?: unknown }
    | null
    | undefined;
  const action = data?.action;
  if (typeof action !== "string" || !(ACTIONS as readonly string[]).includes(action)) {
    bad("invalid-action");
  }
  const cursor = data?.cursor;
  if (cursor !== undefined && typeof cursor !== "string") bad("invalid-cursor");
  const fenceToken = data?.fenceToken;
  if (fenceToken !== undefined && (typeof fenceToken !== "string" || !FENCE_TOKEN.test(fenceToken))) {
    bad("invalid-cursor");
  }
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
        : await pagedAction(
            uid,
            action as Exclude<Action, "exportLinks">,
            retentionDays,
            cursor as string | undefined,
            fenceToken as string | undefined,
          );
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
  /** Delete-all only, with `nextCursor`: the operation's opaque fence token; send it back with the cursor. */
  fenceToken?: string;
}

/** The per-scan work of one paged action (shared by the walk and the straggler pass). */
async function processScan(
  uid: string,
  action: Exclude<Action, "exportLinks">,
  retentionDays: number,
  doc: FirebaseFirestore.QueryDocumentSnapshot,
  nowMs: number,
): Promise<void> {
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
    // Objects first: a "deleted" marker over surviving objects would hide them
    // from every pass that keys on photosState (DB-F7).
    await deleteScanObjects(uid, doc.id);
    await doc.ref.update({
      photosState: "deleted",
      photosDeletedAt: tsFromMillis(nowMs),
      photosExpireAt: admin.firestore.FieldValue.delete(),
    });
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
}

/** True when a delete-all still has work to do on this scan. */
function needsDeleteWork(action: Exclude<Action, "exportLinks">, d: FirebaseFirestore.DocumentData): boolean {
  if (action === "deleteAllPhotos") return d.photosState !== "deleted" && d.photosState !== "none";
  return d.status !== "cancelled";
}

/**
 * Final page of a delete-all: the id-ordered walk cannot see a scan created
 * behind its cursor, so re-query by `createdAt` (single-field index) over the
 * fence window and process whatever still needs work. Bounded: at most
 * `STRAGGLER_PASSES` passes; work remaining after the last one is an error
 * (the fence stays and expires), never a silent "done".
 */
async function sweepStragglers(
  uid: string,
  action: Exclude<Action, "exportLinks">,
  windowStartMs: number,
): Promise<number> {
  let total = 0;
  for (let pass = 1; pass <= STRAGGLER_PASSES; pass++) {
    let found = 0;
    let after: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    for (;;) {
      let q = db()
        .collection(`users/${uid}/body_scans`)
        .where("createdAt", ">=", tsFromMillis(windowStartMs))
        .orderBy("createdAt")
        .limit(PAGE);
      if (after) q = q.startAfter(after);
      const page = await q.get();
      const todo = page.docs.filter((doc) => needsDeleteWork(action, doc.data()));
      found += todo.length;
      await inChunks(todo, (doc) => processScan(uid, action, 0, doc, Date.now()));
      if (page.docs.length < PAGE) break;
      after = page.docs[page.docs.length - 1];
    }
    total += found;
    if (found === 0) return total;
  }
  throw new HttpsError("aborted", "delete-incomplete");
}

/**
 * Registers (first page) or refreshes (continuation) THIS operation's run in the
 * fence document, in a transaction so concurrent operations of the same user
 * cannot clobber each other's entries. A continuation whose run is unknown or
 * lapsed re-registers under its own token and reports `resumed: false` (the
 * walk then re-checks every scan).
 */
async function raiseFence(
  uid: string,
  action: string,
  cursor: string | undefined,
  requested: string | undefined,
  nowMs: number,
): Promise<{ token: string; resumed: boolean; startedAtMs: number }> {
  const ref = deleteFenceRef(uid);
  return db().runTransaction(async (tx) => {
    const runs = activeFenceRuns((await tx.get(ref)).data(), nowMs);
    const own = cursor !== undefined && requested !== undefined ? runs[requested] : undefined;
    const resumedRun = own !== undefined && own.action === action ? own : undefined;
    const resumed = resumedRun !== undefined;
    const token = cursor !== undefined && requested !== undefined ? requested : randomBytes(16).toString("hex");
    const startedAtMs = resumedRun ? resumedRun.startedAtMs : nowMs;
    runs[token] = { action, startedAtMs, activeUntilMs: nowMs + DELETE_FENCE_MS };
    tx.set(ref, { runs });
    return { token, resumed, startedAtMs };
  });
}

/**
 * Final page: removes ONLY this operation's run (other operations of the user
 * keep their protection) and, in the same transaction, records the late-sweep
 * due time for uploads that were authorized before the delete (their signed PUT
 * URLs stay valid until they expire and cannot be revoked).
 */
async function completeFence(uid: string, action: string, token: string, nowMs: number): Promise<void> {
  const ref = deleteFenceRef(uid);
  const late = lateSweepRef(uid);
  await db().runTransaction(async (tx) => {
    const runs = activeFenceRuns((await tx.get(ref)).data(), nowMs);
    const lateData = (await tx.get(late)).data();
    delete runs[token];
    if (Object.keys(runs).length > 0) tx.set(ref, { runs });
    else tx.delete(ref);
    const prior = typeof lateData?.dueAtMs === "number" ? lateData.dueAtMs : 0;
    // A whole-document (non-merge) set: it also drops the sweep's listing
    // `cursor`, so a new operation is always swept from the beginning.
    // `rev` changes on EVERY write: the late sweep deletes a record only if the
    // rev it read before sweeping is still current (compare-and-delete).
    tx.set(late, {
      uid,
      action,
      dueAtMs: Math.max(prior, nowMs + LATE_SWEEP_DELAY_MS),
      rev: randomBytes(8).toString("hex"),
    });
  });
}

async function pagedAction(
  uid: string,
  action: Exclude<Action, "exportLinks">,
  retentionDays: number,
  cursor: string | undefined,
  requestedToken: string | undefined,
): Promise<PageResult> {
  if (cursor !== undefined && !CURSOR_ID.test(cursor)) bad("invalid-cursor");
  const isDelete = action !== "applyRetention";
  let windowStartMs = 0;
  let token = "";
  if (isDelete) {
    // Raise this operation's fence entry BEFORE the first read so no create can
    // slip in behind the walk; every page refreshes it, the first page starts
    // the window.
    const nowFence = Date.now();
    const run = await raiseFence(uid, action, cursor, requestedToken, nowFence);
    token = run.token;
    // A resumed walk whose run lapsed (or arrived without its token) lost its
    // guarantee: re-check everything.
    windowStartMs =
      cursor === undefined ? nowFence - DELETE_FENCE_MS : run.resumed ? run.startedAtMs - DELETE_FENCE_MS : 0;
  }
  let query = db()
    .collection(`users/${uid}/body_scans`)
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(PAGE);
  if (cursor !== undefined) query = query.startAfter(cursor);
  const page = await query.get();
  const nowMs = Date.now();

  await inChunks(page.docs, (doc) => processScan(uid, action, retentionDays, doc, nowMs));

  const last = page.docs[page.docs.length - 1];
  const hasMore = page.docs.length === PAGE;
  let processed = page.docs.length;
  if (!hasMore && isDelete) {
    processed += await sweepStragglers(uid, action as Exclude<Action, "exportLinks">, windowStartMs);
    // Final page of a delete-all: also clear anything under the user's prefix
    // that no document accounts for (a document-less object).
    await scanBucket().deleteFiles({ prefix: userScansPrefix(uid) });
    // Privacy contract: completion guarantees removal of everything uploaded
    // BEFORE this call. A signed PUT URL issued earlier stays valid until its
    // TTL, so an object may still arrive afterwards; the scheduled late sweep
    // (purge.ts, due = completion + URL TTL + margin) removes it.
    await completeFence(uid, action, token, Date.now());
  }
  return {
    processed,
    ...(hasMore && last ? { nextCursor: last.id } : {}),
    ...(hasMore && isDelete ? { fenceToken: token } : {}),
  };
}

interface LinksResult extends PageResult {
  links: { scanId: string; pose: string; url: string; expiresAtMs: number }[];
}

async function exportLinks(uid: string, cursor: string | undefined): Promise<LinksResult> {
  const parsed = cursor === undefined ? undefined : CURSOR_EXPORT.exec(cursor);
  if (cursor !== undefined && !parsed) bad("invalid-cursor");
  let query = db()
    .collection(`users/${uid}/body_scans`)
    .orderBy("takenAt", "desc")
    .orderBy(admin.firestore.FieldPath.documentId(), "desc")
    .limit(EXPORT_PAGE_SCANS);
  if (parsed) query = query.startAfter(tsFromMillis(Number(parsed[1])), parsed[2]);
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
    ...(hasMore && last ? { nextCursor: `${lastMs}:${last.id}` } : {}),
  };
}
