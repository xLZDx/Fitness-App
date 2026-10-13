import * as admin from "firebase-admin";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { RARE, RUNTIME_SA } from "./scaling";
import { noteAppCheck, enforceDailyQuota, QUOTAS } from "./abuse_guard";
import { EXPORT_ACCOUNT_FAILED } from "./monitoring/log_signals";

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

/** Serialized-size ceiling, kept well under the 10 MiB callable response limit. */
export const MAX_EXPORT_BYTES = 8 * 1024 * 1024;

/** Last-resort ceiling on the final response, notes included. */
export const HARD_RESPONSE_BYTES = 9 * 1024 * 1024 + 512 * 1024;

class ExportTooLarge extends Error {}

const jsonBytes = (v: unknown): number =>
  Buffer.byteLength(JSON.stringify(v) ?? "", "utf8");

/**
 * Drops trailing rows from the largest array sections until the serialized
 * body fits [MAX_EXPORT_BYTES], recording each trimmed section in `truncated`.
 */
function fitToByteBudget(
  body: Record<string, unknown>,
  truncated: Truncation,
): void {
  let total = jsonBytes(body);
  if (total <= MAX_EXPORT_BYTES) return;
  const sizes = new Map<string, number>();
  for (const [k, v] of Object.entries(body)) {
    if (Array.isArray(v) && k !== "truncated") sizes.set(k, jsonBytes(v));
  }
  while (total > MAX_EXPORT_BYTES) {
    let key: string | undefined;
    for (const [k, size] of sizes) {
      if ((body[k] as unknown[]).length > 0 && (!key || size > sizes.get(key)!)) {
        key = k;
      }
    }
    if (!key) break;
    const rows = body[key] as unknown[];
    const kept = rows.slice(0, Math.floor(rows.length / 2));
    body[key] = kept;
    const next = jsonBytes(kept);
    total -= sizes.get(key)! - next;
    sizes.set(key, next);
    if (!truncated.includes(key)) truncated.push(key);
  }
}

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
 * The booking fields that belong to the user asking for their data.
 *
 * ## Why an allow-list, and why this is the second version
 *
 * A booking names both parties and carries payment identifiers. Exporting it
 * whole means a coach with 200 bookings downloads 200 real Firebase uids
 * belonging to clients who never asked to be in anyone's export, plus a
 * payment-intent id per session -- third-party personal data inside a file the
 * recipient can forward anywhere.
 *
 * The first version removed `clientUid`, `coachUid` and `stripePaymentIntentId`
 * and spread the rest. That is a DENY-list, and it was complete for the fields
 * `bookCoachSession` writes today -- traced field by field, not assumed. What
 * it is not is stable: a field added to the booking writer flows into the
 * export untouched, and nothing anywhere says so.
 *
 * That is the failure mode this codebase has now produced four times -- a
 * field that reaches the writer and the serialiser and not the guard. It cost
 * F014 twice, N-02 once, and N-01 once. The version that cannot fail that way
 * names what may leave rather than what may not, so a new field is withheld
 * until somebody classifies it, and `booking_export_parity.test.ts` fails
 * until they do.
 *
 * `id` is included because the export lists rows by id everywhere else and a
 * booking id is the user's own reference for a session they attended.
 */
const BOOKING_SELF_FIELDS = [
  "id",
  "startsAt",
  "durationMinutes",
  "priceCents",
  "platformFeeCents",
  "status",
  "createdAt",
  "confirmedAt",
] as const;

/**
 * Fields deliberately WITHHELD, listed so the omission is a decision.
 *
 * Read by `booking_export_parity.test.ts`: every key `bookCoachSession` writes
 * must appear in one list or the other, so a new field cannot be neither.
 */
const BOOKING_WITHHELD_FIELDS = [
  // The other party. Which side this user was on is meaningful; who the other
  // person is is not theirs to receive.
  "clientUid",
  "coachUid",
  // A payment-intent id is a live Stripe handle, not a receipt.
  "stripePaymentIntentId",
  // CR-08. The digest `bookCoachSession` uses to tell a retry of the same
  // request from a different one wearing its id. Internal bookkeeping; a hash
  // of the other party's uid and the payout target is not the user's data.
  "requestFingerprint",
] as const;

/** A booking reduced to the part that is this user's own data. */
function redactBooking(row: Record<string, unknown>, uid: string): unknown {
  const out: Record<string, unknown> = {};
  for (const field of BOOKING_SELF_FIELDS) {
    if (field in row) out[field] = row[field];
  }
  const isClient = row.clientUid === uid;
  out.yourRole = isClient ? "client" : "coach";
  // The booking id is the CLIENT's own reference. Legacy ids were
  // `bk_<ms>_<clientUid>`, so handing the row id to the coach hands over the
  // client's uid; newer ids are a hash a coach could test candidate uids
  // against. A coach identifies a session by when it was and what it cost.
  if (!isClient) delete out.id;
  return out;
}

export const __bookingExportContract = {
  self: BOOKING_SELF_FIELDS,
  withheld: BOOKING_WITHHELD_FIELDS,
};

export const exportAccountData = onCall(
  { ...RARE, serviceAccount: RUNTIME_SA.data },
  async (request) => {
  const auth = request.auth;
  if (!auth) {
    throw new HttpsError("unauthenticated", "Sign in first.");
  }
  noteAppCheck(request, "exportAccountData");
  const uid = auth.uid;
  // N-06. Sixteen concurrent reads per call, each bounded at MAX_ROWS + 1, over
  // collections the client may write freely — so a user who seeds their own
  // tree turns one invocation into tens of thousands of billed reads, with no
  // ceiling anywhere. The quota mechanism already existed and was applied to
  // the video endpoints and not to this, the heaviest read path in the
  // backend.
  //
  // Placed after the auth guard and before the reads, so a refusal costs
  // nothing. A GDPR request is not made three times a day by anyone acting in
  // good faith, and the right to the data is not a right to it on demand at
  // any rate.
  await enforceDailyQuota(uid, "accountExport", QUOTAS.accountExport);

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
      equipmentSetupNotes,
      receipts,
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
      // MVP1.G3-CI-8: was missing entirely -- deleteAccount's recursiveDelete
      // already covered this subcollection (it sweeps everything under
      // users/{uid}), but exportAccountData did not, so a user's own setup
      // notes were deletable but not retrievable on request. Found by
      // building the data-lifecycle coverage drift guard, not by inspection.
      sub(uid, "equipment_setup_notes", truncated),
      // MVP1.G3-CI-8: also missing entirely, and the more serious of the two
      // -- `index.ts:1225`'s own comment calls this "the one document a user
      // might hand to a tax authority". `firestore.rules:63-77` closes both
      // `usage` and `receipts` to client reads with the SAME stated reason
      // ("the callable's own response is what the UI renders") that
      // `account_export.ts`'s own top-of-file doc comment gives for reaching
      // `debug_sessions`/`coach_bookings`/`equipment_reports` via the Admin
      // SDK specifically BECAUSE a client cannot read them directly -- that
      // reasoning applies here just as directly, and nothing had applied it.
      // `usage` (daily rate-limit counters) is deliberately NOT added here:
      // operational-only, regenerated daily, no content a user would
      // recognise as their own -- classified EXEMPT-from-export in
      // scripts/ci/data_lifecycle_policy.json, unlike this one.
      sub(uid, "receipts", truncated),
      one(`donor_wall/${uid}`),
      one(`coach_listings/${uid}`),
      owned("coach_bookings", "clientUid", uid, truncated),
      owned("coach_bookings", "coachUid", uid, truncated),
      owned("equipment_reports", "reporterUid", uid, truncated),
      owned("debug_sessions", "uid", uid, truncated),
    ]);

    const body = {
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
      equipmentSetupNotes,
      receipts,
      donorWall,
      coachListing,
      // Both sides in one list rather than two keys: a booking is one event
      // whichever end of it this user was, and splitting it would make a
      // reader reconcile two lists to answer "how many sessions did I have".
      //
      // De-duplicated by id: `bookCoachSession` does not refuse a coach who
      // books themselves, so one document can satisfy BOTH queries and be
      // listed twice. Whether self-booking should be possible at all is a
      // payments/product question and is recorded as open rather than decided
      // here; counting one session twice in someone's data export is not, and
      // is fixed where the two lists meet.
      coachBookings: [
        ...new Map(
          [...bookingsAsClient, ...bookingsAsCoach].map((b) => [
            (b as Record<string, unknown>).id,
            b,
          ]),
        ).values(),
      ].map((b) => redactBooking(b as Record<string, unknown>, uid)),
      equipmentReports,
      debugSessions,
      // Named, never silent. A capped read that did not say so would be the
      // same lie as a partial export claiming to be whole.
      truncated,
    };

    // After the row caps, so the byte guard only trims what they let through.
    fitToByteBudget(body, truncated);

    const response = {
      ...body,
      notes: [
        ...(truncated.length
          ? [
              "Some sections were capped at " +
                `${MAX_ROWS} rows or ${MAX_EXPORT_BYTES} bytes: ` +
                `${truncated.join(", ")}. ` +
                "Contact support if you need the remainder.",
            ]
          : []),
        "Progress photo image data is not included: those files never leave " +
          "your device, so this server has no copy to send. Their details " +
          "are listed in the app's own export.",
      ],
    };

    // Measured on the object actually returned (notes included). The byte guard
    // above only trims array sections, so a single oversized non-array field
    // could still leave the body over the transport limit; that must fail
    // loudly here rather than as an opaque transport error on the client.
    if (jsonBytes(response) > HARD_RESPONSE_BYTES) {
      throw new ExportTooLarge();
    }
    return response;
  } catch (err) {
    if (err instanceof ExportTooLarge) {
      logger.error(EXPORT_ACCOUNT_FAILED, {
        event: EXPORT_ACCOUNT_FAILED,
        uid,
        err: "export exceeds the response size limit after trimming",
      });
      throw new HttpsError(
        "resource-exhausted",
        "Your data is too large to export in one response. Contact support.",
      );
    }
    // Surfaced, never partially returned. An export missing a collection
    // because one read failed is worse than no export: it reads as "this is
    // everything" while being silently short, which is the precise failure
    // `data_export.dart` already guards with `progressPhotosIncomplete`.
    logger.error(EXPORT_ACCOUNT_FAILED, {
      event: EXPORT_ACCOUNT_FAILED,
      uid,
      err: String(err),
    });
    throw new HttpsError(
      "internal",
      "Could not assemble your data. Please try again.",
    );
  }
});
