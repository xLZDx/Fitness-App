/**
 * `purgeExpiredBodyScanPhotos` -- the scheduled retention enforcer (design s7.4,
 * D-59).
 *
 * Four passes, each walked in pages of 200 with `startAfter(lastDoc)` so a
 * document that keeps failing cannot starve the ones behind it:
 *
 *  1. photos past `photosExpireAt` (`photosState == stored`): delete the
 *     objects, mark `photosState = deleted`.
 *  2. pending scans past `pendingExpiresAt`: delete the objects, write the
 *     48 h `cancelled` tombstone.
 *  3. tombstones past `pendingExpiresAt`: delete leftover objects once more,
 *     then delete the document.
 *  3b. FAILED scans past `pendingExpiresAt` (a terminal vendor rejection leaves
 *     the objects behind): delete the objects, mark `photosState = deleted`.
 *  4. UNMATCHED-OBJECT SWEEP: list the bucket prefix `users/`; an object older
 *     than one hour whose scan document is missing, `cancelled`, or has
 *     `photosState` in `{none, deleted}` is deleted. The listing page token is
 *     persisted in `body_scan_purge_state/main` and resumed next run.
 *
 * A failing document increments `purgeAttempts`; at 10 the job logs a
 * `purge-stuck` event (scan id only) and stops retrying it. Everything is
 * idempotent and retried by the next run. Logs carry scan ids and counts only:
 * never a uid or an object path (D-67).
 *
 * A bucket lifecycle rule for "pending" objects was REJECTED (design s7.4):
 * lifecycle conditions are age and prefix, not Firestore state, and every scan
 * object shares one prefix, so a short rule would delete retained photos.
 */
import * as admin from "firebase-admin";
import { onSchedule } from "firebase-functions/v2/scheduler";
import { RUNTIME_SA } from "../scaling";
import { bodyScanCloudEnabled } from "./flags";
import {
  SCAN_DOC_PATH,
  TOMBSTONE_TTL_MS,
  UNMATCHED_OBJECT_MIN_AGE_MS,
  db,
  deleteScanObjects,
  errorSlug,
  logBodyScan,
  millisOf,
  scanBucket,
  tombstoneScrub,
  tsFromMillis,
} from "./shared";

/** Documents per page of every pass. */
const PAGE = 200;
/** Objects per page of the unmatched-object listing. */
const LIST_PAGE = 500;
/** After this many failed purges of one document the job stops retrying it. */
export const MAX_PURGE_ATTEMPTS = 10;
/** The function timeout is 300 s; stop STARTING new work after 240 s. */
export const PURGE_RUN_BUDGET_MS = 240 * 1000;

const OBJECT_NAME = /^users\/([^/]+)\/scans\/([^/]+)\/(?:front|side|back)\.jpg$/;

export interface Counts {
  expired: number;
  pending: number;
  tombstones: number;
  unmatched: number;
  failures: number;
}

type ScanDoc = FirebaseFirestore.QueryDocumentSnapshot;

/**
 * The owning uid, or `undefined` for any document that is not exactly
 * `users/{uid}/body_scans/{scanId}`. The collection-group query also matches a
 * `body_scans` collection nested anywhere a client may write (P-1); such a
 * document is skipped, never counted and never gets a `deleteFiles`.
 */
function uidOf(doc: ScanDoc): string | undefined {
  if (!SCAN_DOC_PATH.test(doc.ref.path)) return undefined;
  return doc.ref.parent.parent?.id;
}

/** Documents skipped in this run because they used up their purge attempts (DB-F4). */
let stuckInRun = 0;

/** Records one failed purge of a document; logs `purge-stuck` when it reaches the cap. */
async function noteFailure(doc: ScanDoc, counts: Counts, err: unknown): Promise<void> {
  counts.failures += 1;
  const attempts = (Number(doc.data().purgeAttempts) || 0) + 1;
  try {
    await doc.ref.update({ purgeAttempts: admin.firestore.FieldValue.increment(1) });
  } catch {
    // The next run retries the document either way.
  }
  logBodyScan(attempts >= MAX_PURGE_ATTEMPTS ? "error" : "warn", "bodyScanPurge", {
    outcome: attempts >= MAX_PURGE_ATTEMPTS ? "purge-stuck" : "purge-failed",
    scanId: doc.id,
    attempts,
    errorCode: errorSlug(err),
  });
}

/** True when the document has already used up its purge attempts. */
function isStuck(doc: ScanDoc): boolean {
  const stuck = (Number(doc.data().purgeAttempts) || 0) >= MAX_PURGE_ATTEMPTS;
  if (stuck) stuckInRun += 1;
  return stuck;
}

/** Walks a query page by page until it is exhausted or the deadline passes. */
async function walk(
  build: () => FirebaseFirestore.Query,
  deadline: number,
  handle: (doc: ScanDoc) => Promise<void>,
): Promise<void> {
  let last: ScanDoc | undefined;
  for (;;) {
    let query = build().limit(PAGE);
    if (last) query = query.startAfter(last);
    const page = await query.get();
    if (page.empty) return;
    for (const doc of page.docs) {
      if (Date.now() >= deadline) return;
      await handle(doc);
    }
    if (page.docs.length < PAGE) return;
    last = page.docs[page.docs.length - 1];
  }
}

async function purgeExpiredPhotos(nowMs: number, deadline: number, counts: Counts) {
  await walk(
    () =>
      db()
        .collectionGroup("body_scans")
        .where("photosState", "==", "stored")
        .where("photosExpireAt", "<=", tsFromMillis(nowMs))
        .orderBy("photosExpireAt"),
    deadline,
    async (doc) => {
      const uid = uidOf(doc);
      if (!uid || isStuck(doc)) return;
      try {
        await deleteScanObjects(uid, doc.id);
        await doc.ref.update({
          photosState: "deleted",
          photosDeletedAt: tsFromMillis(Date.now()),
          photosExpireAt: admin.firestore.FieldValue.delete(),
        });
        counts.expired += 1;
      } catch (e) {
        await noteFailure(doc, counts, e);
      }
    },
  );
}

async function cancelExpiredPending(nowMs: number, deadline: number, counts: Counts) {
  await walk(
    () =>
      db()
        .collectionGroup("body_scans")
        .where("status", "==", "pending")
        .where("pendingExpiresAt", "<=", tsFromMillis(nowMs))
        .orderBy("pendingExpiresAt"),
    deadline,
    async (doc) => {
      const uid = uidOf(doc);
      if (!uid || isStuck(doc)) return;
      // A live processing lease means an estimate is running right now.
      const lease = millisOf(doc.data().estimateLeaseUntil);
      if (lease !== undefined && lease > nowMs) return;
      try {
        await deleteScanObjects(uid, doc.id);
        await doc.ref.update({
          status: "cancelled",
          photosState: "deleted",
          photosDeletedAt: tsFromMillis(Date.now()),
          pendingExpiresAt: tsFromMillis(Date.now() + TOMBSTONE_TTL_MS),
          ...tombstoneScrub(),
        });
        counts.pending += 1;
      } catch (e) {
        await noteFailure(doc, counts, e);
      }
    },
  );
}

async function removeTombstones(nowMs: number, deadline: number, counts: Counts) {
  await walk(
    () =>
      db()
        .collectionGroup("body_scans")
        .where("status", "==", "cancelled")
        .where("pendingExpiresAt", "<=", tsFromMillis(nowMs))
        .orderBy("pendingExpiresAt"),
    deadline,
    async (doc) => {
      const uid = uidOf(doc);
      if (!uid || isStuck(doc)) return;
      try {
        // A last look for objects a late PUT left behind, then the document.
        await deleteScanObjects(uid, doc.id);
        await doc.ref.delete();
        counts.tombstones += 1;
      } catch (e) {
        await noteFailure(doc, counts, e);
      }
    },
  );
}

async function purgeFailedScans(nowMs: number, deadline: number, counts: Counts) {
  await walk(
    () =>
      db()
        .collectionGroup("body_scans")
        .where("status", "==", "failed")
        .where("pendingExpiresAt", "<=", tsFromMillis(nowMs))
        .orderBy("pendingExpiresAt"),
    deadline,
    async (doc) => {
      const uid = uidOf(doc);
      if (!uid || isStuck(doc)) return;
      // A live processing lease means an estimate is still running.
      const lease = millisOf(doc.data().estimateLeaseUntil);
      if (lease !== undefined && lease > nowMs) return;
      try {
        await deleteScanObjects(uid, doc.id);
        await doc.ref.update({
          photosState: "deleted",
          photosDeletedAt: tsFromMillis(Date.now()),
          photosExpireAt: admin.firestore.FieldValue.delete(),
          pendingExpiresAt: admin.firestore.FieldValue.delete(),
          estimateLeaseUntil: admin.firestore.FieldValue.delete(),
        });
        counts.pending += 1; // pending and failed scans share one counter
      } catch (e) {
        await noteFailure(doc, counts, e);
      }
    },
  );
}

/** Whether a scan document means "no object under this scan may exist". */
function objectsAreOrphans(data: FirebaseFirestore.DocumentData | undefined): boolean {
  if (!data) return true;
  if (data.status === "cancelled") return true;
  return data.photosState === "none" || data.photosState === "deleted";
}

async function sweepUnmatchedObjects(nowMs: number, deadline: number, counts: Counts) {
  const stateRef = db().doc("body_scan_purge_state/main");
  let pageToken: string | undefined;
  try {
    const state = await stateRef.get();
    const token: unknown = state.data()?.pageToken;
    pageToken = typeof token === "string" && token.length > 0 ? token : undefined;
  } catch {
    pageToken = undefined;
  }

  const bucket = scanBucket();
  while (Date.now() < deadline) {
    const [files, next] = await bucket.getFiles({
      prefix: "users/",
      autoPaginate: false,
      maxResults: LIST_PAGE,
      ...(pageToken ? { pageToken } : {}),
    });

    const verdicts = new Map<string, boolean>();
    let interrupted = false;
    for (const file of files) {
      if (Date.now() >= deadline) {
        interrupted = true;
        break;
      }
      const match = OBJECT_NAME.exec(file.name);
      if (!match) continue;
      const created = Date.parse(String(file.metadata?.timeCreated ?? ""));
      if (Number.isNaN(created) || nowMs - created < UNMATCHED_OBJECT_MIN_AGE_MS) continue;
      const [, uid, scanId] = match;
      const key = `${uid}/${scanId}`;
      let orphan = verdicts.get(key);
      if (orphan === undefined) {
        const snap = await db().doc(`users/${uid}/body_scans/${scanId}`).get();
        orphan = objectsAreOrphans(snap.data());
        verdicts.set(key, orphan);
      }
      if (!orphan) continue;
      try {
        await file.delete({ ignoreNotFound: true });
        counts.unmatched += 1;
      } catch (e) {
        counts.failures += 1;
        logBodyScan("warn", "bodyScanPurge", {
          outcome: "unmatched-delete-failed",
          errorCode: errorSlug(e),
        });
      }
    }

    if (interrupted) {
      // The deadline hit mid-page: keep the token that STARTS this page so the
      // next run re-reads it; persisting `next` would skip the unvisited rest.
      await stateRef.set({ pageToken: pageToken ?? "", updatedAt: tsFromMillis(Date.now()) });
      return;
    }
    pageToken = next?.pageToken;
    // Persist the position after every page so a timeout resumes, not restarts.
    await stateRef.set({ pageToken: pageToken ?? "", updatedAt: tsFromMillis(Date.now()) });
    if (!pageToken) return;
  }
}

/** One purge run; exported so the schedule handler and the tests share it. */
export async function runBodyScanPurge(
  nowMs: number = Date.now(),
  budgetMs: number = PURGE_RUN_BUDGET_MS,
): Promise<Counts> {
  const counts: Counts = { expired: 0, pending: 0, tombstones: 0, unmatched: 0, failures: 0 };
  // Unset bucket: nothing could ever have been stored (SD-6).
  if (!bodyScanCloudEnabled()) return counts;
  const deadline = nowMs + budgetMs;
  stuckInRun = 0;
  const passes = [
    purgeExpiredPhotos,
    cancelExpiredPending,
    purgeFailedScans,
    removeTombstones,
    sweepUnmatchedObjects,
  ];
  for (const pass of passes) {
    if (Date.now() >= deadline) break;
    try {
      await pass(nowMs, deadline, counts);
    } catch (e) {
      // One broken pass (a missing index, a storage outage) must not stop the others.
      counts.failures += 1;
      logBodyScan("error", "bodyScanPurge", {
        outcome: "pass-failed",
        pass: pass.name,
        errorCode: errorSlug(e),
      });
    }
  }
  if (stuckInRun > 0) {
    // Abandoned documents are otherwise silent: surface the count every run.
    logBodyScan("error", "bodyScanPurge", { outcome: "purge-abandoned", stuck: stuckInRun });
  }
  logBodyScan("info", "bodyScanPurge", {
    outcome: "run-complete",
    latencyMs: Date.now() - nowMs,
    expired: counts.expired,
    pending: counts.pending,
    tombstones: counts.tombstones,
    unmatched: counts.unmatched,
    failures: counts.failures,
  });
  return counts;
}

export const purgeExpiredBodyScanPhotos = onSchedule(
  {
    schedule: "30 3 * * *",
    region: "europe-west1",
    timeoutSeconds: 300,
    memory: "256MiB",
    maxInstances: 1,
    concurrency: 1,
    serviceAccount: RUNTIME_SA.bodyScan,
  },
  async () => {
    await runBodyScanPurge();
  },
);
