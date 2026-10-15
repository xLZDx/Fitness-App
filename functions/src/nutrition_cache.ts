import * as admin from "firebase-admin";
import { createHash } from "crypto";

/**
 * Central cache of PUBLIC nutrition-database responses (design s5.9, s17.4).
 *
 * `nutrition_cache/{key}`, Admin-SDK-only (`allow read, write: if false`), no
 * uid, exempt from the lifecycle policy as shared reference data. It exists
 * because Open Food Facts rate-limits per IP and Functions instances share
 * egress IPs. Keys: `off_<barcode>`, `usda_<fdcId>`, `q_<sha1(lang|query|scope)>`.
 *
 * TTL: positive 30 days, negative (not found) 1 day, search 7 days, set on the
 * `expireAt` field (Firestore TTL policy in `firestore.indexes.json`). TTL
 * deletion lags up to a day or more, so `readCache` compares `expireAt` ITSELF
 * and never assumes an expired document is gone (design s5.9 [D13]).
 *
 * A cache read that fails is treated as a miss (the miss path is separately
 * budgeted and quota-charged); a cache WRITE that fails is swallowed -- the
 * caller already has its answer and a lost cache write only costs one more
 * upstream call later.
 */

export const CACHE_COLLECTION = "nutrition_cache";
export const CACHE_SCHEMA = 1;

const DAY_MS = 24 * 60 * 60 * 1000;
export const CACHE_TTL_MS = {
  /** A found product (OFF barcode, USDA food). */
  positive: 30 * DAY_MS,
  /** A barcode no source knows. Short, so a newly added product is picked up. */
  negative: 1 * DAY_MS,
  /** A search result list. */
  search: 7 * DAY_MS,
} as const;

export type SearchScope = "generic" | "packaged" | "both";

export const offCacheKey = (barcode: string): string => `off_${barcode}`;
export const usdaCacheKey = (fdcId: number | string): string => `usda_${fdcId}`;

/** `q_<sha1(lang|query|scope)>` over the lower-cased, trimmed query. */
export function searchCacheKey(lang: string, query: string, scope: SearchScope): string {
  const digest = createHash("sha1")
    .update(`${lang}|${query.trim().toLowerCase()}|${scope}`)
    .digest("hex");
  return `q_${digest}`;
}

export interface CacheEntry<T> {
  found: boolean;
  source: string;
  payload?: T;
  fetchedAtMs: number;
  expireAtMs: number;
}

type DbFactory = () => admin.firestore.Firestore;
const defaultDb: DbFactory = () => admin.firestore();

function millis(value: unknown): number | undefined {
  if (value instanceof Date) return value.getTime();
  const ts = value as { toMillis?: () => number } | null | undefined;
  if (ts && typeof ts.toMillis === "function") return ts.toMillis();
  return typeof value === "number" && Number.isFinite(value) ? value : undefined;
}

/** The live entry for `key`, or `null` on a miss, an expired entry or a failed read. */
export async function readCache<T>(
  key: string,
  nowMs: number,
  db: DbFactory = defaultDb,
): Promise<CacheEntry<T> | null> {
  try {
    const snap = await db().collection(CACHE_COLLECTION).doc(key).get();
    const data = snap.data();
    if (!snap.exists || !data) return null;
    const expireAtMs = millis(data.expireAt);
    if (expireAtMs === undefined || expireAtMs <= nowMs) return null;
    if (typeof data.found !== "boolean" || typeof data.source !== "string") return null;
    return {
      found: data.found,
      source: data.source,
      payload: data.payload as T | undefined,
      fetchedAtMs: millis(data.fetchedAt) ?? 0,
      expireAtMs,
    };
  } catch {
    return null;
  }
}

/** Writes an entry; never throws (see the module note). The payload is JSON-cloned: Firestore rejects `undefined`. */
export async function writeCache<T>(
  key: string,
  entry: { found: boolean; source: string; payload?: T },
  ttlMs: number,
  nowMs: number,
  db: DbFactory = defaultDb,
): Promise<void> {
  try {
    const doc: Record<string, unknown> = {
      schema: CACHE_SCHEMA,
      fetchedAt: new Date(nowMs),
      expireAt: new Date(nowMs + ttlMs),
      found: entry.found,
      source: entry.source,
    };
    if (entry.payload !== undefined) doc.payload = JSON.parse(JSON.stringify(entry.payload));
    await db().collection(CACHE_COLLECTION).doc(key).set(doc);
  } catch {
    // A lost cache write costs one more upstream call later; never fail the user for it.
  }
}
