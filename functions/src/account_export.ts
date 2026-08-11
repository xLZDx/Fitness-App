import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE } from "./scaling";
import { noteAppCheck } from "./abuse_guard";

/**
 * A3 — everything the product stores about one user, assembled server-side.
 *
 * ## Why this is a Cloud Function and not more fields in the client's export
 *
 * `public/privacy.html:89` promises deletion "erases every document under your
 * account", and the export is the other half of the same contract. The client
 * could not keep it: three of the collections that name a user are top-level
 * and unreadable from a phone. `firestore.rules:82-87` sets
 * `allow read: if false` on `debug_sessions` outright; `coach_bookings` has no
 * client read rule at all; `equipment_reports` is readable only in ways that
 * do not include "all of mine". So a client-side export cannot become complete
 * by adding fields — the data is out of its reach by design, and correctly so.
 *
 * The Admin SDK bypasses rules, which is exactly the capability this needs and
 * exactly why the function is authenticated and reads only `request.auth.uid`,
 * never a uid from the request body.
 *
 * ## What is deliberately NOT here
 *
 * Progress-photo BYTES. They never leave the device — they are AES-GCM
 * envelopes in the app's private directory with a key in local storage — so
 * the server has nothing to send. The client's own export already lists their
 * metadata, and `data_export.dart` states the exclusion in the file the user
 * downloads. Whoever moves photos to a backend adds them here in the same
 * change.
 */

const db = () => admin.firestore();

/** Every document in a subcollection under `users/{uid}`, id included. */
async function sub(uid: string, name: string): Promise<unknown[]> {
  const snap = await db().collection(`users/${uid}/${name}`).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

/** One document, or null when it was never written. */
async function one(path: string): Promise<unknown> {
  const snap = await db().doc(path).get();
  return snap.exists ? { id: snap.id, ...snap.data() } : null;
}

/** Every document in a top-level collection where `field` names this user. */
async function owned(
  collection: string,
  field: string,
  uid: string,
): Promise<unknown[]> {
  const snap = await db().collection(collection).where(field, "==", uid).get();
  return snap.docs.map((d) => ({ id: d.id, ...d.data() }));
}

export const exportAccountData = onCall(RARE, async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  noteAppCheck(request, "exportAccountData");
  const uid = auth.uid;

  try {
    // Concurrent: fourteen independent reads, and a GDPR export that takes
    // fourteen sequential round trips is one a user cancels.
    const [
      profile,
      subscription,
      stats,
      workoutLogs,
      workoutSessions,
      scheduledSessions,
      programmes,
      machineCards,
      recognisedEquipment,
      generatedExercises,
      donorWall,
      coachListing,
      bookingsAsClient,
      bookingsAsCoach,
      equipmentReports,
      debugSessions,
    ] = await Promise.all([
      one(`users/${uid}/profile/main`),
      one(`users/${uid}/subscription/main`),
      one(`users/${uid}/stats/workouts`),
      sub(uid, "workout_logs"),
      sub(uid, "workout_sessions"),
      sub(uid, "scheduled_sessions"),
      sub(uid, "programmes"),
      sub(uid, "machine_cards"),
      sub(uid, "recognised_equipment"),
      sub(uid, "generated_exercises"),
      one(`donor_wall/${uid}`),
      one(`coach_listings/${uid}`),
      owned("coach_bookings", "clientUid", uid),
      owned("coach_bookings", "coachUid", uid),
      owned("equipment_reports", "reporterUid", uid),
      owned("debug_sessions", "uid", uid),
    ]);

    return {
      exportFormatVersion: 1,
      generatedAt: new Date().toISOString(),
      uid,
      profile,
      subscription,
      stats,
      workoutLogs,
      workoutSessions,
      scheduledSessions,
      programmes,
      machineCards,
      recognisedEquipment,
      generatedExercises,
      donorWall,
      coachListing,
      // Both sides in one list rather than two keys: a booking is one event
      // whichever end of it this user was, and splitting it would make a
      // reader reconcile two lists to answer "how many sessions did I have".
      coachBookings: [...bookingsAsClient, ...bookingsAsCoach],
      equipmentReports,
      debugSessions,
      notes: [
        "Progress photo image data is not included: those files never leave " +
          "your device, so this server has no copy to send. Their details " +
          "are listed in the app's own export.",
      ],
    };
  } catch (err) {
    // Surfaced, never partially returned. An export missing a collection
    // because one read failed is worse than no export: it reads as "this is
    // everything" while being silently short, which is the precise failure
    // `data_export.dart` already guards with `progressPhotosIncomplete`.
    logger.error("account export failed", { uid, err: String(err) });
    throw new HttpsError(
      "internal",
      "Could not assemble your data. Please try again.",
    );
  }
});
