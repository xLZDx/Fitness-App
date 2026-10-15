import * as admin from "firebase-admin";

/**
 * Global upstream token budget for Open Food Facts (design s17.4, D-64).
 *
 * Why this exists on top of the per-uid daily quota and the per-instance
 * breaker: Cloud Functions instances share egress IPs, Open Food Facts
 * rate-limits PER IP (product reads 15/min, searches 10/min, no
 * search-as-you-type), and a per-uid quota does not bind distinct valid
 * barcodes sent by many accounts. A cache MISS that would call OFF must
 * therefore first win a slot from a counter shared by all instances, set BELOW
 * the documented limits so we never get the shared IP blocked.
 *
 * The counters live in `nutrition_cache/budget_off_<kind>_<yyyyMMddHHmm>`
 * (UTC minute) with `{count, expireAt}` and a 1-day TTL (`firestore.indexes.json`
 * `nutrition_cache.expireAt`); the collection is Admin-SDK-only in the rules.
 * TTL deletion lags, so each minute has its own document and nothing relies on
 * an old one being gone.
 *
 * The constants and the document-id/expiry helpers are pure; `takeUpstreamBudget`
 * is the one function that touches Firestore. The per-uid per-minute burst limit
 * (5 misses/min, counter in the usage document) belongs to the callables (C20).
 */

/** Slots per UTC minute, BELOW OFF's documented 15 reads and 10 searches. */
export const OFF_READS_PER_MINUTE = 10;
export const OFF_SEARCHES_PER_MINUTE = 6;

/** Budget counters expire after one day (TTL on `expireAt`). */
export const BUDGET_TTL_MS = 24 * 60 * 60 * 1000;

export type BudgetKind = "read" | "search";

export function budgetLimit(kind: BudgetKind): number {
  return kind === "read" ? OFF_READS_PER_MINUTE : OFF_SEARCHES_PER_MINUTE;
}

/** `budget_off_read_202610151407` for 2026-10-15T14:07 UTC. */
export function budgetDocId(kind: BudgetKind, nowMs: number): string {
  const minute = new Date(nowMs).toISOString().slice(0, 16).replace(/[-:T]/g, "");
  return `budget_off_${kind}_${minute}`;
}

export function budgetExpireAt(nowMs: number): Date {
  return new Date(nowMs + BUDGET_TTL_MS);
}

/**
 * Tries to take one slot from the current minute's budget. Resolves `true` when
 * a slot was won, `false` when the minute's budget is exhausted (the caller
 * answers the calm `upstream-unavailable` and the client falls back to label
 * scan or manual entry). A Firestore failure rejects: the budget is fail-CLOSED,
 * a miss that cannot be counted must not reach the shared IP.
 */
export async function takeUpstreamBudget(
  kind: BudgetKind,
  nowMs: number = Date.now(),
  db: () => admin.firestore.Firestore = () => admin.firestore(),
): Promise<boolean> {
  const ref = db().collection("nutrition_cache").doc(budgetDocId(kind, nowMs));
  const limit = budgetLimit(kind);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const count = (snap.data()?.count as number | undefined) ?? 0;
    if (count >= limit) return false;
    tx.set(ref, { count: count + 1, expireAt: budgetExpireAt(nowMs) }, { merge: true });
    return true;
  });
}
