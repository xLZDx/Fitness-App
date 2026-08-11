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
} as const;
