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

/**
 * Rows read per collection.
 *
 * Every read here was unbounded, and one of them is attacker-shaped:
 * `firestore.rules:82-87` lets any signed-in user create `debug_sessions`
 * without limit, and a Firestore document goes up to 1 MB. ~260 such rows
 * exhaust the 256 MiB this function runs in, while fifteen other reads are
 * landing in the same `Promise.all` -- so the export dies exactly for the
 * users who have the most data to export.
 *
 * A cap that silently drops rows would be the worse bug, so `truncated`
 * below names every collection that hit it, and the client's own export
 * already knows how to declare an incomplete section.
 */
const MAX_ROWS = 2000;

/** Collections that hit [MAX_ROWS] on this run. */
type Truncation = string[];

/** Every document in a subcollection under `users/{uid}`, id included. */
async function sub(
  uid: string,
  name: string,
  truncated: Truncation,
): Promise<unknown[]> {
  const snap = await db()
    .collection(`users/${uid}/${name}`)
    .limit(MAX_ROWS + 1)
    .get();
  return capped(snap.docs, name, truncated);
}

/** Shared tail of [sub] and [owned]: cap, record, map. */
function capped(
  docs: FirebaseFirestore.QueryDocumentSnapshot[],
  name: string,
  truncated: Truncation,
): unknown[] {
  // Read one MORE than the cap, so hitting it is distinguishable from having
  // exactly that many rows -- otherwise a user with precisely 2000 sessions
  // is told their export is incomplete when it is not.
  const over = docs.length > MAX_ROWS;
  if (over) truncated.push(name);
  return docs
    .slice(0, MAX_ROWS)
    .map((d) => ({ id: d.id, ...d.data() }));
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
  truncated: Truncation,
): Promise<unknown[]> {
  const snap = await db()
    .collection(collection)
    .where(field, "==", uid)
    .limit(MAX_ROWS + 1)
    .get();
  return capped(snap.docs, `${collection}.${field}`, truncated);
}

/**
 * A booking with the OTHER person removed.
 *
 * A booking names both parties and carries payment identifiers
 * (`index.ts:1154-1164`: `clientUid`, `coachUid`, `stripePaymentIntentId`).
 * Exporting it whole means a coach with 200 bookings downloads 200 real
 * Firebase uids belonging to clients who never asked to be in anyone's export,
 * plus a payment-intent id per session -- third-party personal data inside a
 * file the recipient can forward anywhere.
 *
 * The user's own side stays: what they booked, when, and what it cost is their
 * data and the reason the export exists.
 */
function redactBooking(row: Record<string, unknown>, uid: string): unknown {
  const {
    clientUid,
    coachUid,
    stripePaymentIntentId: _intent,
    ...rest
  } = row as Record<string, unknown>;
  return {
    ...rest,
    // Which side this user was on is meaningful; who the other person is is
    // not theirs to receive.
    yourRole: clientUid === uid ? "client" : "coach",
  };
}

export const exportAccountData = onCall(RARE, async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  noteAppCheck(request, "exportAccountData");
  const uid = auth.uid;

  const truncated: Truncation = [];

  try {
    // Concurrent: sixteen independent reads, and a GDPR export that takes
    // sixteen sequential round trips is one a user cancels.
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
      sub(uid, "workout_logs", truncated),
      sub(uid, "workout_sessions", truncated),
      sub(uid, "scheduled_sessions", truncated),
      sub(uid, "programmes", truncated),
      sub(uid, "machine_cards", truncated),
      sub(uid, "recognised_equipment", truncated),
      sub(uid, "generated_exercises", truncated),
      one(`donor_wall/${uid}`),
      one(`coach_listings/${uid}`),
      owned("coach_bookings", "clientUid", uid, truncated),
      owned("coach_bookings", "coachUid", uid, truncated),
      owned("equipment_reports", "reporterUid", uid, truncated),
      owned("debug_sessions", "uid", uid, truncated),
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
      coachBookings: [...bookingsAsClient, ...bookingsAsCoach].map((b) =>
        redactBooking(b as Record<string, unknown>, uid),
      ),
      equipmentReports,
      debugSessions,
      // Named, never silent. A capped read that did not say so would be the
      // same lie as a partial export claiming to be whole.
      truncated,
      notes: [
        ...(truncated.length
          ? [
              "Some sections were capped at " +
                `${MAX_ROWS} rows: ${truncated.join(", ")}. ` +
                "Contact support if you need the remainder.",
            ]
          : []),
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
