import * as admin from "firebase-admin";
import { HttpsError, CallableRequest } from "firebase-functions/v2/https";
import * as logger from "firebase-functions/logger";

/**
 * A6-lite — the two cheap halves of abuse protection: see whether App Check is
 * actually being used, and stop one account draining a metered resource.
 *
 * Why this exists as its own module rather than inside `index.ts`: `video_urls`
 * needs it too, and that file is deliberately separate ("the one part that
 * exists to satisfy a contract rather than a feature request").
 *
 * ## What this is NOT
 *
 * It is not App Check enforcement. Enforcement is a live-console change plus
 * `enforceAppCheck: true` per callable, and turning it on before knowing how
 * many real installs would fail the check is how a working app is taken
 * offline by a security setting. That is A6-full. This module measures first:
 * every call records whether a valid App Check token arrived, so enforcement
 * can later be switched on against a number rather than a hope.
 */

/**
 * Resolved per call, not at module load.
 *
 * `video_urls.ts` imports this module and `video_urls.test.ts` imports that
 * one directly, without `index.ts` and therefore without
 * `admin.initializeApp()`. A module-scope `admin.firestore()` made merely
 * importing the module throw "The default Firebase app does not exist" — a
 * side effect on import is a dependency nobody declared.
 */
const db = () => admin.firestore();

/**
 * Logs whether this call carried a valid App Check token.
 *
 * `request.app` is populated by the runtime only when a token was sent AND it
 * verified — so an absent `app` means "unattested caller", which today is
 * allowed. The audit of 2026-08-11 found App Check `UNENFORCED` on every
 * service and `enforceAppCheck` absent from every function, so the true
 * proportion of unattested traffic is currently unknown. This is what makes it
 * knowable.
 *
 * Deliberately `logger.info`, not `warn`: at this stage an unattested call is
 * the expected state, and warning on the normal case trains the reader to
 * ignore the field. It becomes a warning when enforcement is staged.
 */
export function noteAppCheck(request: CallableRequest, fn: string): void {
  logger.info("appcheck", {
    fn,
    attested: request.app !== undefined,
    uid: request.auth?.uid ?? null,
  });
}

/**
 * Per-user, per-day ceiling on a metered action.
 *
 * Stored at `users/{uid}/usage/{yyyy-mm-dd}` — under the user document ON
 * PURPOSE, so `deleteAccount`'s `recursiveDelete(users/{uid})` already erases
 * it and `core/DATA_INVENTORY_2026-08-11.md` does not gain a new orphan the
 * day this ships. A top-level `usage/{uid}` collection would have been the
 * fourth entry on that list.
 *
 * A transaction, not `FieldValue.increment`: the limit has to be read and
 * compared in the same atomic step it is written, or two concurrent calls both
 * read 499 and both proceed.
 *
 * @throws HttpsError('resource-exhausted') when the day's limit is reached.
 */
export async function enforceDailyQuota(
  uid: string,
  action: string,
  limit: number,
  cost = 1,
): Promise<void> {
  // UTC day, not the caller's local day. A device clock is attacker-controlled
  // and a timezone is not worth a second read; the cost is that the window
  // rolls at midnight UTC rather than midnight local, which for a ceiling this
  // size nobody legitimate will ever notice.
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${day}`);

  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.data()?.[action] as number | undefined) ?? 0;
      if (used + cost > limit) {
        logger.warn("quota exceeded", { uid, action, used, cost, limit });
        throw new HttpsError(
          "resource-exhausted",
          "You have reached today's limit for this action. It resets tomorrow.",
        );
      }
      tx.set(
        ref,
        { [action]: used + cost, updatedAt: new Date().toISOString() },
        { merge: true },
      );
    });
  } catch (e) {
    // The quota refusal above is already logged with everything needed to read
    // it, so it passes through untouched. Anything else -- Firestore
    // unavailable, contention retries exhausted -- used to leave this module
    // with zero log lines carrying the uid or the action, which is the one
    // failure here nobody could diagnose afterwards. It stays fail-CLOSED: the
    // transaction is atomic, so nothing was charged, and the caller does not
    // get its metered resource.
    if (e instanceof HttpsError) throw e;
    logger.error("quota check failed", { uid, action, cost, limit, err: String(e) });
    throw new HttpsError("internal", "Could not check your usage limit.");
  }
}

/**
 * Gives back part of a charge that turned out not to be used.
 *
 * `clipUrls` has to charge before it signs -- charging afterwards would let a
 * caller consume IAM signing operations for free by requesting objects that
 * fail. But a batch where half the objects do not exist would then bill the
 * user for work that never happened. This returns the difference.
 *
 * Deliberately silent on failure: a refund that fails is a user who kept a
 * charge they should not have, which is a smaller harm than turning a
 * successful prefetch into an error.
 */
export async function refundQuota(
  uid: string,
  action: string,
  amount: number,
): Promise<void> {
  if (amount <= 0) return;
  const day = new Date().toISOString().slice(0, 10);
  const ref = db().doc(`users/${uid}/usage/${day}`);
  try {
    await db().runTransaction(async (tx) => {
      const snap = await tx.get(ref);
      const used = (snap.data()?.[action] as number | undefined) ?? 0;
      tx.set(
        ref,
        {
          // Never below zero: a refund racing the day boundary must not hand
          // out tomorrow's budget as a negative starting balance.
          [action]: Math.max(0, used - amount),
          updatedAt: new Date().toISOString(),
        },
        { merge: true },
      );
    });
  } catch (e) {
    logger.warn("quota refund failed", { uid, action, amount, err: String(e) });
  }
}

/**
 * The ceilings themselves, in one place so they can be read as a policy rather
 * than found one call site at a time.
 *
 * Sized against real use, not against a round number. A user working through a
 * planned session opens on the order of ten clips; a week's offline prefetch is
 * a handful of `clipUrls` calls of up to 60 objects each. Both limits sit an
 * order of magnitude above that, so a legitimate heavy user never meets them,
 * while a script looping the whole 2,539-clip library does — which is the
 * "public storage folder" the licence prohibits, spelled differently.
 */
export const QUOTAS = {
  /** Single signed clip URLs per user per day. */
  clipUrl: 400,
  /** Objects signed through the batch endpoint per user per day. */
  clipUrlsObjects: 1200,
  /**
   * Broken-equipment reports per user per day.
   *
   * N-04. This endpoint had no ceiling at all, and it writes a document whose
   * id the client chooses and whose free-text note it also supplies — so the
   * loop that fills a bucket with ~1 MB documents costs an attacker nothing.
   * Generous against real use: filing thirty faults in one day is already an
   * implausible gym visit.
   */
  equipmentReport: 30,
  /**
   * GDPR data exports per user per day.
   *
   * N-06. Each call fans out into sixteen concurrent collection reads, each
   * bounded at MAX_ROWS + 1, and the collections it reads are ones the client
   * may write freely — so a user who seeds their own tree turns one callable
   * invocation into tens of thousands of billed reads. An export is a
   * once-in-a-while action; three a day is already indulgent.
   */
  accountExport: 3,
} as const;

/**
 * The share of a quota an anonymous caller gets.
 *
 * N-05, and this is a MITIGATION rather than a fix — say so plainly.
 *
 * A per-uid quota binds only if a uid costs something. An anonymous uid costs
 * nothing: the Firebase Web API key ships in the app, Identity Toolkit will
 * mint another on request, and the counter starts again at zero. Three
 * throwaway accounts covered the entire clip library under the previous
 * limits, so the module's own stated goal — that a script looping the library
 * hits the ceiling — was not being met.
 *
 * What this does: raises the number of rotations needed by 8x. What it does
 * NOT do: make rotation expensive, because nothing here can.
 *
 * The control that actually binds a caller to a real install is App Check, and
 * `APP_CHECK_ENFORCED` defaults to off — an operator/deployment decision, not
 * a code one. Refusing anonymous callers outright was the other candidate and
 * was rejected here: anonymous sign-in is a first-class login button in this
 * app, and removing video from it is a product decision that belongs to the
 * operator too. Both are recorded in the decision log rather than silently
 * chosen.
 */
export const ANONYMOUS_QUOTA_DIVISOR = 8;

/** The quota `action` allows this caller, given how they signed in. */
export function quotaFor(
  limit: number,
  signInProvider: string | undefined,
): number {
  if (signInProvider !== "anonymous") return limit;
  return Math.max(1, Math.floor(limit / ANONYMOUS_QUOTA_DIVISOR));
}
