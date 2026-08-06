#!/usr/bin/env node
/**
 * F3.3 -- one-time, non-destructive backfill: copies every existing
 * WorkoutLogEntry (users/{uid}/workout_logs/{id}) into a corresponding
 * one-exercise WorkoutSession (users/{uid}/workout_sessions/{id}), so app
 * reads can converge to a single collection going forward.
 *
 * `users/{uid}/workout_logs` is NEVER written or deleted by this script --
 * read-only throughout. Rollback if anything looks wrong: delete
 * `workout_sessions`; `workout_logs` is untouched and nothing is lost.
 *
 * See core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md, sub-gate F3.3, and
 * its "Review trail" section for why this is a one-time backfill converging
 * to a single collection rather than a permanent two-collection union.
 *
 * IDEMPOTENT: session id is `legacy_${logId}`, deterministic from the
 * source log entry's own id. Re-running overwrites each doc with the same
 * computed content -- a no-op in effect, never a duplicate. Safe to re-run
 * after a partial failure.
 *
 * SAFE BY DEFAULT:
 *   - dry-run unless --write is passed. A dry run reads workout_logs and
 *     prints exactly what WOULD be written; it performs zero Firestore
 *     writes.
 *   - --uid=<uid> restricts to one user, for testing against a single
 *     account before running for everyone. --all is required to run
 *     against every user, and must be typed explicitly -- there is no
 *     default that touches every account.
 *
 * Credentials: Application Default Credentials via
 * GOOGLE_APPLICATION_CREDENTIALS, same convention as every other admin
 * script in this repo -- never embedded here, never read from argv.
 *
 * Usage:
 *   node functions/scripts/backfill_workout_sessions.mjs --uid=<uid>            (dry run, one user)
 *   node functions/scripts/backfill_workout_sessions.mjs --uid=<uid> --write    (real write, one user)
 *   node functions/scripts/backfill_workout_sessions.mjs --all                  (dry run, every user)
 *   node functions/scripts/backfill_workout_sessions.mjs --all --write          (real write, every user)
 */
import admin from "firebase-admin";

const args = process.argv.slice(2);
const write = args.includes("--write");
const all = args.includes("--all");
const uidArg = args.find((a) => a.startsWith("--uid="));
const uid = uidArg ? uidArg.split("=")[1] : null;

if (!all && !uid) {
  console.error(
    "usage: node backfill_workout_sessions.mjs --uid=<uid> [--write]\n" +
      "   or: node backfill_workout_sessions.mjs --all [--write]",
  );
  process.exit(2);
}
if (all && uid) {
  console.error("--all and --uid are mutually exclusive");
  process.exit(2);
}

admin.initializeApp();
const db = admin.firestore();

/** Firestore Timestamp or ISO string, both seen in the wild for this field
 * (see FirestoreWorkoutLogRepository._fromDoc's own defensive check) --
 * always resolved to an ISO string for the new document. */
function toIso(value) {
  return typeof value?.toDate === "function"
    ? value.toDate().toISOString()
    : value;
}

/** Builds the WorkoutSession document for one legacy log entry. Returns
 * null (and logs why) rather than throwing, so one malformed document
 * cannot abort the whole run for a user. */
function toSession(logDoc) {
  const log = logDoc.data();
  if (!log.completedAt || !log.exerciseId) {
    console.warn(`  skip ${logDoc.id}: missing completedAt or exerciseId`);
    return null;
  }
  const completedAtIso = toIso(log.completedAt);
  const sets = [];
  if (log.weightKg != null || log.repsCompleted != null) {
    sets.push({
      ...(log.weightKg != null ? { weightKg: log.weightKg } : {}),
      ...(log.repsCompleted != null ? { reps: log.repsCompleted } : {}),
    });
  }
  return {
    id: `legacy_${logDoc.id}`,
    title: log.exerciseTitle ?? log.exerciseId,
    exercises: [
      {
        exerciseId: log.exerciseId,
        exerciseTitle: log.exerciseTitle ?? log.exerciseId,
        sets,
        ...(log.difficulty != null ? { difficulty: log.difficulty } : {}),
      },
    ],
    startedAt: completedAtIso,
    completedAt: completedAtIso,
    status: "completed",
    ...(log.durationMinutes != null
      ? { durationMinutes: log.durationMinutes }
      : {}),
    ...(log.notes != null ? { notes: log.notes } : {}),
  };
}

async function backfillUser(userId) {
  const logsSnap = await db
    .collection("users")
    .doc(userId)
    .collection("workout_logs")
    .get();
  if (logsSnap.empty) return { userId, logs: 0, written: 0, skipped: 0 };

  let written = 0;
  let skipped = 0;
  const docs = logsSnap.docs;
  // 400, not Firestore's 500 batch cap -- same margin the Dart repos'
  // clear() already uses, kept identical rather than re-derived.
  for (let i = 0; i < docs.length; i += 400) {
    const chunk = docs.slice(i, i + 400);
    const batch = db.batch();
    let batchHasWrites = false;
    for (const logDoc of chunk) {
      const session = toSession(logDoc);
      if (session === null) {
        skipped++;
        continue;
      }
      written++;
      if (write) {
        const ref = db
          .collection("users")
          .doc(userId)
          .collection("workout_sessions")
          .doc(session.id);
        batch.set(ref, session);
        batchHasWrites = true;
      }
    }
    if (write && batchHasWrites) await batch.commit();
  }
  return { userId, logs: docs.length, written, skipped };
}

/** `users/{uid}` is never written directly -- only its subcollections are
 * (profile/main, workout_logs/*, etc.) -- so it never appears in
 * `db.collection("users").get()`; that query always returns zero docs, even
 * with real data underneath. Every uid that has anything to backfill has a
 * workout_logs doc by definition, so deriving the list from there is both
 * the fix and the correct scope for this script. */
async function listAllUids() {
  const snap = await db.collectionGroup("workout_logs").get();
  const uids = new Set();
  for (const doc of snap.docs) {
    // Guards against a future, unrelated collection also named
    // "workout_logs" at some other nesting depth -- collectionGroup matches
    // by name only, not by full path. `parent` is the workout_logs
    // collection, `parent.parent` should be the users/{uid} doc.
    const userDoc = doc.ref.parent.parent;
    if (!userDoc || userDoc.parent.id !== "users") {
      console.warn(`  skip unexpected path (not users/{uid}/workout_logs): ${doc.ref.path}`);
      continue;
    }
    uids.add(userDoc.id);
  }
  return [...uids];
}

async function main() {
  console.log(`mode: ${write ? "WRITE" : "DRY RUN"}`);
  const uids = uid ? [uid] : await listAllUids();
  console.log(`users to process: ${uids.length}`);

  const results = [];
  for (const u of uids) {
    const r = await backfillUser(u);
    results.push(r);
    if (r.logs > 0) {
      console.log(
        `${r.userId}: ${r.logs} logs -> ${write ? "wrote" : "would write"} ` +
          `${r.written} sessions${r.skipped ? `, skipped ${r.skipped}` : ""}`,
      );
    }
  }

  const totalLogs = results.reduce((s, r) => s + r.logs, 0);
  const totalWritten = results.reduce((s, r) => s + r.written, 0);
  const totalSkipped = results.reduce((s, r) => s + r.skipped, 0);
  console.log("---SUMMARY---");
  console.log(
    JSON.stringify(
      {
        mode: write ? "write" : "dry-run",
        users: uids.length,
        usersWithLogs: results.filter((r) => r.logs > 0).length,
        totalLogs,
        totalWritten,
        totalSkipped,
      },
      null,
      2,
    ),
  );
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
