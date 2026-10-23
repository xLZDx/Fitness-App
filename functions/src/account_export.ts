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

/**
 * C25 / D-61. Collections added by the body-scan and nutrition work are read
 * with an EXPLICIT newest-first order and paged by the app, instead of the
 * unordered `sub()` above (document-id order, which for random-UUID
 * `food_entries` silently exports a random subset and for date-keyed
 * `weight_entries` keeps the oldest rows and drops the newest).
 *
 * `order` null means "document id, descending" (date-keyed or week-keyed ids,
 * and `saved_foods`, whose `createdAt` is optional so an `orderBy` on it would
 * silently drop rows that lack it).
 */
const PAGE_ROWS = 500;
const MAX_CURSOR_LENGTH = 200;
const PAGED_COLLECTIONS = [
  { key: "bodyScans", path: "body_scans", order: "takenAt" },
  { key: "weightEntries", path: "weight_entries", order: null },
  { key: "foodEntries", path: "food_entries", order: "loggedAt" },
  { key: "savedFoods", path: "saved_foods", order: null },
  { key: "nutritionPlanReviews", path: "nutrition_plan_reviews", order: null },
  // S02-07 (design 7, 7.1): unified activity summaries and the stream INDEX rows
  // (never stream bytes, GPS-PRIV-052). Newest first; the first response carries
  // up to MAX_ROWS of each (see `CAPPED_FIRST_PAGE`), continuations page by PAGE_ROWS.
  { key: "activities", path: "activities", order: "startUtc" },
  { key: "activityStreams", path: "activity_streams", order: null },
  // V0 offline command protocol: the owner's canonical typed sessions (the
  // server-only source of truth behind `workout_sessions`) and the lifetime
  // per-operation outcomes kept by the replay fence (at most 256 shard
  // documents, paged by shard id), and the 90-day per-command receipts (a
  // rejected command such as DUPLICATE_LOGICAL_SET exists nowhere else). Policy
  // and counters are NOT exported.
  { key: "workoutTypedSessions", path: "workout_typed_sessions", order: null },
  { key: "workoutCommandOutcomes", path: "workout_command_fence", order: null },
  { key: "workoutCommandReceipts", path: "workout_command_receipts", order: null },
] as const;
type PagedKey = (typeof PAGED_COLLECTIONS)[number]["key"];

/**
 * Rows per page for sections that need more than [PAGE_ROWS]. Receipts are small
 * (a few hundred bytes) but can number 180,000 per account (2,000 a day for 90
 * days); 2,000 per page keeps a full receipts export near 90 pages, inside one
 * day of the continuation quota ([PAGE_QUOTA_LIMIT]) when it is the only section left.
 */
const SECTION_PAGE_ROWS: Partial<Record<PagedKey, number>> = {
  workoutCommandReceipts: 2000,
};
const pageRowsOf = (key: PagedKey): number => SECTION_PAGE_ROWS[key] ?? PAGE_ROWS;

/**
 * Paged sections whose FIRST response is read up to [MAX_ROWS] (not [PAGE_ROWS])
 * so the over-cap behaviour of every other section applies: reaching the cap is
 * named in `truncated` and the rest is delivered by continuation cursors.
 */
const CAPPED_FIRST_PAGE: ReadonlySet<PagedKey> = new Set<PagedKey>([
  "activities",
  "activityStreams",
]);

/**
 * What an activity stream index row exposes. An allow-list: the row's object
 * path, hashes and upload bookkeeping are internal and would turn the export
 * into a map of the private bucket. Samples are never in the row.
 */
const STREAM_ROW_FIELDS = ["id", "state", "bytes", "kinds", "expiresAt"] as const;

function streamRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const f of STREAM_ROW_FIELDS) {
    if (f in row) out[f] = row[f];
  }
  return out;
}

/**
 * Server-only controls of a typed workout session that must not leave the
 * server: `writerTokenHash` is the SHA-256 of the secret writer proof (material
 * a holder could use to test guesses, and a credential-derived value). Every
 * other field is the owner's own session content or its sync bookkeeping.
 */
const TYPED_SESSION_WITHHELD_FIELDS = ["writerTokenHash"] as const;

function typedSessionRow(row: Record<string, unknown>): Record<string, unknown> {
  const out = { ...row };
  for (const f of TYPED_SESSION_WITHHELD_FIELDS) delete out[f];
  return out;
}

/**
 * One replay-fence shard document as the owner's record of command outcomes.
 *
 * The stored shape is `{ e: { <operationKey>: <23-char value> } }` where the key
 * is base64url of the first 16 bytes of SHA-256("op1|" + operationId) and the
 * value is code (C committed, R rejected, S superseded) + 11 chars of session
 * digest + 11 chars of payload-hash prefix. The fence is kept for the life of
 * the account, so it is the only lifetime record of what happened to each
 * command; it is bounded at 256 shard documents per account.
 *
 * Fields exported, and why each is safe:
 *  - `id` (shard): two hex characters, a bucket name.
 *  - `operationKey`: a one-way digest of the client-generated operation id; it
 *    lets the owner match an outcome to a command they sent and is not a
 *    credential (the operation id cannot be recovered from it).
 *  - `code`: the outcome letter, the owner's own result.
 *  - `sessionDigest`: a truncated one-way digest of the session id; it groups
 *    outcomes by session and is not a credential.
 * Withheld: the payload-hash prefix. It is replay-protection bookkeeping (a
 * truncated hash of the command body) that tells the owner nothing the outcome
 * does not, and it would let a holder of the file test guesses of command
 * content. A malformed stored value is listed with null code and digest rather
 * than silently dropped.
 */
function outcomeRow(row: Record<string, unknown>): Record<string, unknown> {
  const e = row.e;
  if (typeof e !== "object" || e === null || Array.isArray(e)) {
    // R2-M03: a shard whose stored map is missing or not an object must not read
    // as a legitimately empty shard (a falsely complete export). It is listed
    // with an explicit status and reported through the response `warnings`.
    return { id: row.id, status: OUTCOME_STATUS_CORRUPT, entries: [] };
  }
  const map = e as Record<string, unknown>;
  const entries = Object.keys(map)
    .sort()
    .map((operationKey) => {
      const v = map[operationKey];
      const ok =
        typeof v === "string" &&
        v.length === 23 &&
        (v[0] === "C" || v[0] === "R" || v[0] === "S");
      return {
        operationKey,
        code: ok ? v[0] : null,
        sessionDigest: ok ? v.slice(1, 12) : null,
      };
    });
  return { id: row.id, status: "OK", entries };
}

/**
 * Receipt fields exported by `workoutCommandReceipts` (an allow-list). Stored by
 * workout_commands/apply.ts `writeOutcome`; each is the owner's own record of
 * what happened to one command they sent:
 *  - `id`: the operationId (document id), the client-generated command id.
 *  - `status`: COMMITTED or REJECTED.
 *  - `reasonCode`: why a command was rejected (e.g. DUPLICATE_LOGICAL_SET); null if committed.
 *  - `effect`: what a committed command did (e.g. APPENDED); null if rejected.
 *  - `sessionId`: the owner's typed session the command targeted.
 *  - `exerciseId`, `operation`, `logicalSetId`: which exercise, command kind and set.
 *  - `seq`: the client sequence number of the command.
 *  - `originDeviceInstallId`: the owner's own device install id that sent it.
 *  - `revisionBefore`, `revisionAfter`: session revision around the command.
 *  - `serverTimeMs`: server clock when it was resolved.
 *  - `performedAtClientMs`, `clockSuspect`: the client-reported time and its suspicion flag.
 *  - `expireAt`: when the 90-day receipt is deleted by TTL.
 * Withheld: `payloadHash` (a hash of the command body that would let a holder of
 * the file test guesses of command content). No writer proof or token material
 * is stored on a receipt, and none can be exported by this allow-list.
 */
const RECEIPT_ROW_FIELDS = [
  "id",
  "status",
  "reasonCode",
  "effect",
  "sessionId",
  "exerciseId",
  "operation",
  "logicalSetId",
  "seq",
  "originDeviceInstallId",
  "revisionBefore",
  "revisionAfter",
  "serverTimeMs",
  "performedAtClientMs",
  "clockSuspect",
  "expireAt",
] as const;

function receiptRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const f of RECEIPT_ROW_FIELDS) {
    if (f in row) out[f] = row[f];
  }
  return out;
}

/** Status of a replay-fence shard row whose stored map could not be read. */
const OUTCOME_STATUS_CORRUPT = "CORRUPT_ENTRY_MAP";

/**
 * Explicit incompleteness signal for rows that could not be exported faithfully:
 * one `{section, id, code}` per corrupt fence shard in the returned page.
 */
function corruptWarnings(
  sections: Partial<Record<PagedKey, Record<string, unknown>[]>>,
): Array<{ section: string; id: string; code: string }> {
  const out: Array<{ section: string; id: string; code: string }> = [];
  for (const r of sections.workoutCommandOutcomes ?? []) {
    if (r.status === OUTCOME_STATUS_CORRUPT) {
      out.push({ section: "workoutCommandOutcomes", id: String(r.id), code: OUTCOME_STATUS_CORRUPT });
    }
  }
  return out;
}

/** Docs materialised per server read by [boundedRead]. */
const READ_BATCH_DOCS = 20;

/** Sections read by [boundedRead]: their documents can be large (hundreds of KB). */
const BYTE_BOUNDED: ReadonlySet<PagedKey> = new Set<PagedKey>([
  "workoutTypedSessions",
  "workoutCommandOutcomes",
  "workoutCommandReceipts",
]);

function rowOf(
  key: PagedKey,
  d: { id: string; data(): unknown },
): Record<string, unknown> {
  const row = { id: d.id, ...(d.data() as object) } as Record<string, unknown>;
  if (key === "bodyScans") return scanRow(row);
  if (key === "workoutTypedSessions") return typedSessionRow(row);
  if (key === "workoutCommandOutcomes") return outcomeRow(row);
  if (key === "workoutCommandReceipts") return receiptRow(row);
  return key === "activityStreams" ? streamRow(row) : row;
}

/**
 * Reads a page in small server-side batches and stops as soon as the page row
 * limit or the serialized byte `budget` is reached, so memory never holds more
 * than the budget plus one batch ([READ_BATCH_DOCS] documents) regardless of
 * how large the stored documents are. `q` is the ordered (and, for a
 * continuation, already positioned) query; each batch continues with
 * `startAfter` on the last document read. The cursor is the id of the last
 * INCLUDED row. A single document larger than the whole budget is still
 * emitted alone (the first row is always taken), so the page always advances
 * and a continuation can never loop on the same document.
 */
async function boundedRead(
  q: FirebaseFirestore.Query,
  key: PagedKey,
  pageRows: number,
  budget: number,
): Promise<{ rows: Record<string, unknown>[]; info: PageInfo }> {
  const rows: Record<string, unknown>[] = [];
  let bytes = 2; // the enclosing brackets
  let hasMore = false;
  let query = q;
  for (;;) {
    // One extra document beyond the rows still needed proves "more exists".
    const want = Math.min(READ_BATCH_DOCS, pageRows - rows.length + 1);
    const snap = await query.limit(want).get();
    let last: FirebaseFirestore.QueryDocumentSnapshot | undefined;
    for (const d of snap.docs) {
      last = d;
      if (rows.length >= pageRows) {
        hasMore = true;
        break;
      }
      const row = rowOf(key, d);
      const size = jsonBytes(row) + 1; // plus the separating comma
      if (rows.length > 0 && bytes + size > budget) {
        hasMore = true;
        break;
      }
      rows.push(row);
      bytes += size;
    }
    if (hasMore || snap.docs.length < want || last === undefined) break;
    query = q.startAfter(last);
  }
  return {
    rows,
    info: {
      returned: rows.length,
      hasMore,
      nextCursor: hasMore ? String(rows[rows.length - 1].id) : null,
    },
  };
}

/** GPS-PRIV-053: the declared delivery of streams and the heart-rate exclusion. */
export const STREAM_EXPORT_NOTE =
  "GPS streams are not embedded in this file: each activityStreams row lists " +
  "its state, size and expiry, and the app requests short-lived download " +
  "links on demand; heart-rate streams are on your device only and are not " +
  "part of this export.";

/** Continuation pages are cheap but not free; own counter, never `accountExport`. */
/** A bare error code, never a message (messages can embed the uid or a path). */
function errorSlug(err: unknown): string {
  const code = (err as { code?: unknown } | null | undefined)?.code;
  const text = typeof code === "string" || typeof code === "number" ? String(code) : "";
  return /^[A-Za-z0-9_./-]{1,64}$/.test(text) ? text : "unknown";
}

const PAGE_QUOTA_ACTION = "accountExportPage";
const PAGE_QUOTA_LIMIT = 150;

interface PageInfo {
  returned: number;
  hasMore: boolean;
  nextCursor: string | null;
}

/** Fields that would turn the export into a bearer credential for a photo. */
const LINK_FIELD = /url|link|objectpath|storagepath/i;

/** A body-scan row without any link/path field, flagged when photos remain. */
function scanRow(row: Record<string, unknown>): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(row)) {
    if (!LINK_FIELD.test(k)) out[k] = v;
  }
  // Metadata only (D-61): links are minted for one hour by
  // `manageBodyScanData.exportLinks`, never embedded here.
  if (row.photosState === "stored") out.photoLinksAvailable = true;
  return out;
}

async function pagedRead(
  uid: string,
  spec: (typeof PAGED_COLLECTIONS)[number],
  cursor: string | undefined,
  pageRows: number = PAGE_ROWS,
): Promise<{ rows: Record<string, unknown>[]; info: PageInfo }> {
  const base = `users/${uid}/${spec.path}`;
  let q = db()
    .collection(base)
    .orderBy(spec.order ?? "__name__", "desc");
  if (cursor !== undefined) {
    const at = await db().doc(`${base}/${cursor}`).get();
    if (!at.exists) {
      throw new HttpsError(
        "failed-precondition",
        "The export position is no longer valid. Start the export again.",
      );
    }
    q = q.startAfter(at);
  }
  if (BYTE_BOUNDED.has(spec.key)) {
    return boundedRead(q, spec.key, pageRows, MAX_EXPORT_BYTES);
  }
  const snap = await q.limit(pageRows + 1).get();
  const hasMore = snap.docs.length > pageRows;
  const rows = snap.docs.slice(0, pageRows).map((d) => rowOf(spec.key, d));
  return {
    rows,
    info: {
      returned: rows.length,
      hasMore,
      nextCursor: hasMore ? String(rows[rows.length - 1].id) : null,
    },
  };
}

/** Halves the largest paged sections (keeping a valid cursor) until `budget` fits. */
function fitPaged(
  sections: Partial<Record<PagedKey, Record<string, unknown>[]>>,
  paging: Partial<Record<PagedKey, PageInfo>>,
  budget: number,
): void {
  let total = jsonBytes(sections);
  while (total > budget) {
    let key: PagedKey | undefined;
    let best = 0;
    for (const k of Object.keys(sections) as PagedKey[]) {
      const n = sections[k]!.length;
      if (n > 1 && jsonBytes(sections[k]) > best) {
        best = jsonBytes(sections[k]);
        key = k;
      }
    }
    if (!key) break;
    const kept = sections[key]!.slice(0, Math.ceil(sections[key]!.length / 2));
    sections[key] = kept;
    paging[key] = {
      returned: kept.length,
      hasMore: true,
      nextCursor: String(kept[kept.length - 1].id),
    };
    total = jsonBytes(sections);
  }
}

function parseCursors(data: unknown): Partial<Record<PagedKey, string>> {
  const raw = (data as { cursors?: unknown } | null | undefined)?.cursors;
  if (raw === undefined || raw === null) return {};
  if (typeof raw !== "object" || Array.isArray(raw)) {
    throw new HttpsError("invalid-argument", "cursors must be an object.");
  }
  const out: Partial<Record<PagedKey, string>> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    const known = PAGED_COLLECTIONS.some((c) => c.key === k);
    if (
      !known ||
      typeof v !== "string" ||
      v.length === 0 ||
      v.length > MAX_CURSOR_LENGTH ||
      v.includes("/")
    ) {
      throw new HttpsError("invalid-argument", "Invalid export cursor.");
    }
    out[k as PagedKey] = v;
  }
  return out;
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
  // C25. A request carrying cursors is a continuation page of the app's export
  // loop (any number of pages, resumable across days): it reads ONLY the named paged sections, so it is
  // charged to its own counter instead of burning the 3/day full-export quota.
  const cursors = parseCursors(request.data);
  const continuation = Object.keys(cursors).length > 0;
  if (continuation) {
    await enforceDailyQuota(uid, PAGE_QUOTA_ACTION, PAGE_QUOTA_LIMIT);
  } else {
    await enforceDailyQuota(uid, "accountExport", QUOTAS.accountExport);
  }

  const truncated: Truncation = [];

  try {
    const wanted = PAGED_COLLECTIONS.filter(
      (c) => !continuation || cursors[c.key] !== undefined,
    );
    const pagedResults = await Promise.all(
      wanted.map((c) =>
        pagedRead(
          uid,
          c,
          cursors[c.key],
          !continuation && CAPPED_FIRST_PAGE.has(c.key) ? MAX_ROWS : pageRowsOf(c.key),
        ),
      ),
    );
    const pagedSections: Partial<Record<PagedKey, Record<string, unknown>[]>> = {};
    const paging: Partial<Record<PagedKey, PageInfo>> = {};
    wanted.forEach((c, i) => {
      pagedSections[c.key] = pagedResults[i].rows;
      paging[c.key] = pagedResults[i].info;
      // Hitting the MAX_ROWS cap is named, like every other capped section.
      if (!continuation && CAPPED_FIRST_PAGE.has(c.key) && pagedResults[i].info.hasMore) {
        truncated.push(c.key);
      }
    });
    const photoNote =
      "Photos are not embedded and no photo links are included. Scans with " +
      "photoLinksAvailable still have photos in private cloud storage; the " +
      "app requests one-hour download links on demand. Originals and meal " +
      "thumbnails kept on your device are not part of this file.";

    if (continuation) {
      fitPaged(pagedSections, paging, MAX_EXPORT_BYTES);
      return {
        exportFormatVersion: 1,
        generatedAt: new Date().toISOString(),
        uid,
        ...pagedSections,
        paging,
        // Rows in THIS page that could not be exported faithfully (see outcomeRow).
        warnings: corruptWarnings(pagedSections),
        notes: [
          photoNote,
          ...(pagedSections.activityStreams !== undefined ? [STREAM_EXPORT_NOTE] : []),
        ],
      };
    }

    // Concurrent: sixteen independent reads, and a GDPR export that takes
    // sixteen sequential round trips is one a user cancels.
    const [
      profile,
      subscription,
      stats,
      workoutSessionStats,
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
      bodyScanSettings,
      nutritionPlan,
      activitySettings,
    ] = await Promise.all([
      one(`users/${uid}/profile/main`),
      one(`users/${uid}/subscription/main`),
      one(`users/${uid}/stats/workouts`),
      // Written by the mobile firestore_workout_session_repository (all-time
      // session totals). One bounded doc; was deletable but not exportable.
      one(`users/${uid}/stats/workout_sessions`),
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
      // C25: single `main` documents of the body-scan / nutrition features.
      one(`users/${uid}/body_scan_settings/main`),
      one(`users/${uid}/nutrition_plan/main`),
      // S02-07: cloud-stream consent and retention (activities and stream index
      // rows arrive through the paged sections above).
      one(`users/${uid}/activity_settings/main`),
    ]);

    const body = {
      exportFormatVersion: 1,
      generatedAt: new Date().toISOString(),
      uid,
      profile,
      subscription,
      stats,
      workoutSessionStats,
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
      bodyScanSettings,
      nutritionPlan,
      activitySettings,
      // Named, never silent. A capped read that did not say so would be the
      // same lie as a partial export claiming to be whole.
      truncated,
    };

    // After the row caps, so the byte guard only trims what they let through.
    fitToByteBudget(body, truncated);
    // Paged sections get what the legacy sections left (at least one row each);
    // a trimmed page keeps a cursor so nothing is dropped silently.
    const rowsBeforeFit = new Map<PagedKey, number>(
      [...CAPPED_FIRST_PAGE].map((k) => [k, pagedSections[k]?.length ?? 0]),
    );
    fitPaged(pagedSections, paging, MAX_EXPORT_BYTES - jsonBytes(body));
    // A byte-budget trim of an activity section is named too (rows are not lost:
    // `paging` keeps a cursor), so `truncated` is the one list of incomplete sections.
    for (const [k, before] of rowsBeforeFit) {
      if ((pagedSections[k]?.length ?? 0) < before && !truncated.includes(k)) truncated.push(k);
    }

    const response = {
      ...body,
      ...pagedSections,
      // Per-section paging state. The app repeats the call with
      // `cursors: {section: nextCursor}` while any `hasMore` is true.
      paging,
      // Rows that could not be exported faithfully, e.g. a corrupt fence shard
      // (status CORRUPT_ENTRY_MAP). Empty means every returned row is intact.
      warnings: corruptWarnings(pagedSections),
      notes: [
        photoNote,
        STREAM_EXPORT_NOTE,
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
    // A deliberate refusal (stale cursor) keeps its own code and message.
    if (err instanceof HttpsError) throw err;
    if (err instanceof ExportTooLarge) {
      logger.error(EXPORT_ACCOUNT_FAILED, {
        event: EXPORT_ACCOUNT_FAILED,
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
      // A bare code only: SDK messages can embed document paths and the uid (D-67).
      errorCode: errorSlug(err),
    });
    throw new HttpsError(
      "internal",
      "Could not assemble your data. Please try again.",
    );
  }
});
