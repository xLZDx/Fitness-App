/**
 * P2.G3 T2 -- the identity-scan quota class, ported into this package's
 * own atomic store rather than imported from `functions/src/abuse_guard.ts`
 * (P0.G6 deliberately isolates this codebase's dependency tree/compilation
 * unit from `functions/`'s -- importing across the two packages would
 * reintroduce exactly the coupling that gate exists to prevent).
 *
 * GPT-PM's binding ruling on this exact question (P2.G3 plan review,
 * round 1, 2026-09-10): a local compatibility PORT is acceptable as "the
 * existing mechanism, not a new competing store" ONLY if it is
 * mechanically identical to `enforceDailyQuota` -- same UTC-day key, the
 * EXACT SAME Firestore path `users/{uid}/usage/{yyyy-mm-dd}`, the same
 * transactional read-compare-merged-write shape, the same fail-closed
 * semantics, `resource-exhausted` on limit, uid only from the caller's own
 * auth context, and a distinct field (`identityTextLookup`) in the SAME
 * document -- never a new collection/store. This file is deliberately the
 * MINIMAL primitive that satisfies that, not a copy of the whole
 * unrelated abuse_guard.ts file (App Check measurement, the AI Gateway
 * kill switch, refunds, anonymous-quota division -- none of that is part
 * of what T2 asks for).
 *
 * Every comment in `enforceDailyQuota` below explaining WHY a choice was
 * made is preserved verbatim from abuse_guard.ts's own version, because
 * the reasoning is identical, not merely the code shape.
 */
import * as admin from "firebase-admin";
import { HttpsError } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";
import { db } from "./firestore_admin";

const QUOTA_EXCEEDED_EVENT = "equipment_identity_quota_exceeded";
const QUOTA_CHECK_FAILED_EVENT = "equipment_identity_quota_check_failed";

export interface QuotaDecision {
  allowed: boolean;
  newUsed: number;
}

/**
 * The pure read-compare-decide step, shared by every atomic consumer of the
 * `users/{uid}/usage/{day}` document -- `enforceDailyQuota` below, AND
 * `session_repository.ts`'s `admitSessionClaim`, which must charge this
 * SAME quota inside its OWN transaction (also touching the session-claim
 * and latest-session-pointer documents), not this function's transaction
 * (GPT-PM MAJOR, P2.G3 pre-commit review round 3, 2026-09-11: quota
 * admission must be linearized in the SAME Firestore transaction as
 * session-ownership/latest-session-ordering, so a genuinely concurrent
 * duplicate request cannot pass the same "not yet claimed" window twice and
 * charge quota for what is really one logical request). Firestore
 * transactions cannot compose across separate `runTransaction` calls, so
 * the actual `tx.get`/`tx.set` against the usage document has to live in
 * whichever transaction is doing the atomic write -- this function is the
 * one place the DECISION itself (not the I/O) is expressed, so the two
 * write sites can never silently diverge on what "over limit" means.
 */
export function decideQuota(usedSoFar: number, limit: number, cost = 1): QuotaDecision {
  return { allowed: usedSoFar + cost <= limit, newUsed: usedSoFar + cost };
}

/**
 * Per-user, per-day ceiling on a metered action.
 *
 * Stored at `users/{uid}/usage/{yyyy-mm-dd}` -- the EXACT SAME path
 * `functions/src/abuse_guard.ts`'s `enforceDailyQuota` uses, and this is
 * the load-bearing property of the whole port: two independent modules
 * writing the identical Firestore document shape is one atomic store, not
 * two competing ones. Under the user document ON PURPOSE, so
 * `deleteAccount`'s `recursiveDelete(users/{uid})` (in the default
 * codebase) already erases it -- this package adds no new orphan to
 * `core/DATA_INVENTORY_2026-08-11.md`.
 *
 * A transaction, not `FieldValue.increment`: the limit has to be read and
 * compared in the same atomic step it is written, or two concurrent calls
 * both read 499 and both proceed.
 *
 * @throws HttpsError('resource-exhausted') when the day's limit is reached.
 */
export async function enforceDailyQuota(
  uid: string,
  action: string,
  limit: number,
  cost = 1,
): Promise<void> {
  // UTC day, not the caller's local day -- same reasoning as
  // abuse_guard.ts: a device clock is attacker-controlled and a timezone
  // is not worth a second read.
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${day}`);

  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.data()?.[action] as number | undefined) ?? 0;
      const decision = decideQuota(used, limit, cost);
      if (!decision.allowed) {
        logger.warn(QUOTA_EXCEEDED_EVENT, { uid, action, used, cost, limit });
        throw new HttpsError(
          "resource-exhausted",
          "You have reached today's limit for this action. It resets tomorrow.",
        );
      }
      tx.set(
        ref,
        { [action]: decision.newUsed, updatedAt: new Date().toISOString() },
        { merge: true },
      );
    });
  } catch (e) {
    // The quota refusal above is already logged with everything needed to
    // read it, so it passes through untouched. Anything else (Firestore
    // unavailable, contention retries exhausted) stays fail-CLOSED: the
    // transaction is atomic, so nothing was charged, and the caller does not
    // get its metered resource -- same posture as abuse_guard.ts's own catch
    // block. This log line was missing from the original port of this
    // function (silent-failure-hunter + code-reviewer finding, P2.G3
    // pre-commit review, 2026-09-11): the real cause was discarded before
    // the generic HttpsError('internal', ...) was thrown, so the caller in
    // orchestrator.ts could only ever log the already-generic replacement
    // message, never the actual Firestore/transaction failure. Restored to
    // match abuse_guard.ts's own catch block exactly, per GPT-PM's "must be
    // mechanically identical" ruling on this port.
    if (e instanceof HttpsError) throw e;
    logger.error(QUOTA_CHECK_FAILED_EVENT, {
      uid,
      action,
      cost,
      limit,
      err: e instanceof Error ? (e.stack ?? e.message) : String(e),
    });
    throw new HttpsError("internal", "Could not check your usage limit.");
  }
}

/**
 * The one new quota class this gate adds. Sized the same as
 * `abuse_guard.ts`'s `aiEquipmentRecognition` (60/day) -- this action is
 * the text-evidence analogue of that one (a per-scan resolution attempt),
 * and there is no usage data yet to size it independently of that
 * precedent.
 */
export const IDENTITY_TEXT_LOOKUP_DAILY_LIMIT = 60;

export const IDENTITY_TEXT_LOOKUP_ACTION = "identityTextLookup";

export async function enforceIdentityTextLookupQuota(uid: string): Promise<void> {
  await enforceDailyQuota(uid, IDENTITY_TEXT_LOOKUP_ACTION, IDENTITY_TEXT_LOOKUP_DAILY_LIMIT);
}

/**
 * The SAME `users/{uid}/usage/{day}` document path `enforceDailyQuota`
 * itself resolves internally -- exported so `admitSessionClaim` writes
 * against the identical document from within its own transaction (never a
 * second store), and so tests can inspect/seed it directly.
 */
export function usageDocRef(uid: string, day: string): admin.firestore.DocumentReference {
  return db().doc(`users/${uid}/usage/${day}`);
}
