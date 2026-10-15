/**
 * `lookupBarcode` and `searchFoods` -- the two Open Food Facts / USDA callables
 * (design s17.4, s17.5, D-64, D-65, D-67). Both run on the capped `FOOD_LOOKUP`
 * profile (fail-closed App Check, `fn-data`).
 *
 * ORDER: auth -> `noteAppCheck` -> `enforceNonAnonymousForAi` ->
 * `assertFeatureEnabled(FOOD_LOOKUP_ENABLED)` -> parse -> cache read -> (miss
 * only) per-uid burst slot -> daily quota -> global OFF budget (inside the
 * source) -> upstream. The flag runs BEFORE any quota charge; a cache HIT
 * charges nothing; a MISS (including a negative result) is charged; a miss
 * that ends in an upstream failure is refunded and NEVER negative-cached.
 *
 * `enforceAiGatewayEnabled` is deliberately NOT called: that kill switch guards
 * paid Vertex calls, `fn-data` holds no grant on its secret (the check would
 * fail closed with `unavailable` forever), and these callables spend only a
 * shared upstream budget that `FOOD_LOOKUP_ENABLED` and the budget itself
 * already control. Recorded as a deviation in the C20 change record.
 *
 * Logging (D-67): nothing here logs a uid, barcode, query or upstream URL.
 */
import * as admin from "firebase-admin";
import { onCall, HttpsError, CallableRequest } from "firebase-functions/v2/https";
import { FOOD_LOOKUP } from "./scaling";
import {
  QUOTAS,
  enforceDailyQuota,
  enforceNonAnonymousForAi,
  noteAppCheck,
  quotaFor,
  refundQuota,
} from "./abuse_guard";
import { assertFeatureEnabled } from "./feature_flags";
import { foodLookupEnabled } from "./food_flags";
import { isValidGtin } from "./gtin_validator";
import { sanitiseDisplayText } from "./food_text";
import { CACHE_TTL_MS, offCacheKey, readCache, writeCache, type SearchScope } from "./nutrition_cache";
import { UpstreamError } from "./nutrition_http";
import type { DataQuality } from "./nutrition_normalise";
import type { Per100g } from "./food_types";
import { fetchOffProduct, OFF_ATTRIBUTION } from "./nutrition_sources/open_food_facts";
import { getUsdaApiKey, lookupUsdaByGtin, USDA_ATTRIBUTION } from "./nutrition_sources/usda_fdc";
import { fetchAndCacheSearch, needsUsdaKey, readCachedSearch, MAX_RESULTS, type SearchDeps } from "./nutrition_sources/search";
import type { FoodCandidate } from "./nutrition_sources/types";

/** Closed machine-readable slugs this module answers with (the client maps them to l10n). */
export const FOOD_LOOKUP_SLUGS = {
  invalidBarcode: "invalid-barcode",
  invalidQuery: "invalid-query",
  upstreamUnavailable: "upstream-unavailable",
  rateLimited: "rate-limited",
  sourceNotConfigured: "source-not-configured",
} as const;

/** Cache MISSES a single uid may take per UTC minute (design s17.4, D-64). */
export const MISS_BURST_PER_MINUTE = 5;

export const QUERY_MIN = 3;
export const QUERY_MAX = 60;
export const DEFAULT_LIMIT = MAX_RESULTS;

function signInProvider(request: CallableRequest): string | undefined {
  return request.auth?.token?.firebase?.sign_in_provider;
}

type DbFactory = () => admin.firestore.Firestore;
const defaultDb: DbFactory = () => admin.firestore();

/**
 * Takes one of the uid's per-minute miss slots. The counter lives in the usage
 * document (`users/{uid}/usage/{day}`, server-only, erased with the account):
 * `offMissWindow` is the UTC minute (`yyyyMMddHHmm` as a number) and
 * `offMissCount` the misses taken in it. `false` = burst limit reached.
 */
export async function takeMissSlot(uid: string, nowMs: number, db: DbFactory = defaultDb): Promise<boolean> {
  const iso = new Date(nowMs).toISOString();
  const day = iso.slice(0, 10);
  const window = Number(iso.slice(0, 16).replace(/[-:T]/g, ""));
  const ref = db().doc(`users/${uid}/usage/${day}`);
  return db().runTransaction(async (tx) => {
    const snap = await tx.get(ref);
    const data = snap.data();
    const sameWindow = data?.offMissWindow === window;
    const count = sameWindow && typeof data?.offMissCount === "number" ? data.offMissCount : 0;
    if (count >= MISS_BURST_PER_MINUTE) return false;
    tx.set(ref, { offMissWindow: window, offMissCount: count + 1 }, { merge: true });
    return true;
  });
}

interface MissAccounting {
  uid: string;
  action: "barcodeLookup" | "foodSearch";
  limit: number;
  nowMs: number;
}

/** Burst slot, then the daily quota. Throws the calm `rate-limited` or the quota's `resource-exhausted`. */
async function chargeMiss(a: MissAccounting): Promise<void> {
  if (!(await takeMissSlot(a.uid, a.nowMs))) {
    throw new HttpsError("unavailable", FOOD_LOOKUP_SLUGS.rateLimited);
  }
  await enforceDailyQuota(a.uid, a.action, a.limit);
}

function unavailable(): HttpsError {
  return new HttpsError("unavailable", FOOD_LOOKUP_SLUGS.upstreamUnavailable);
}

// ---------------------------------------------------------------------------
// lookupBarcode
// ---------------------------------------------------------------------------

export interface BarcodeProduct {
  name: string;
  brand?: string;
  per100g: Per100g;
  servingG?: number;
}

interface BarcodePayload {
  product: BarcodeProduct;
  dataQuality: DataQuality;
  source: "open_food_facts" | "usda_fdc";
}

export type BarcodeResponse =
  | {
      found: true;
      product: BarcodeProduct;
      dataQuality: DataQuality;
      source: "open_food_facts" | "usda_fdc";
      attribution: { source: string; licence: string; url: string };
    }
  | { found: false };

function toPayload(c: FoodCandidate): BarcodePayload {
  return {
    product: {
      name: c.name,
      ...(c.brand !== undefined ? { brand: c.brand } : {}),
      per100g: c.per100g,
      ...(c.servingG !== undefined ? { servingG: c.servingG } : {}),
    },
    dataQuality: c.completeness,
    source: c.source,
  };
}

function toBarcodeResponse(p: BarcodePayload | undefined, barcode: string): BarcodeResponse {
  if (!p) return { found: false };
  const attribution =
    p.source === "open_food_facts"
      ? { ...OFF_ATTRIBUTION, url: `https://world.openfoodfacts.org/product/${barcode}` }
      : { ...USDA_ATTRIBUTION };
  return { found: true, product: p.product, dataQuality: p.dataQuality, source: p.source, attribution };
}

export function parseBarcode(data: unknown): string {
  const barcode = (data as { barcode?: unknown } | null | undefined)?.barcode;
  if (typeof barcode !== "string" || !isValidGtin(barcode)) {
    throw new HttpsError("invalid-argument", FOOD_LOOKUP_SLUGS.invalidBarcode);
  }
  return barcode;
}

/** The whole barcode flow after the callable preamble. Exported for tests (no auth/App Check here). */
export async function lookupBarcodeCore(
  uid: string,
  signIn: string | undefined,
  barcode: string,
  deps: SearchDeps = {},
): Promise<BarcodeResponse> {
  const now = deps.now ?? Date.now;
  const cached = await readCache<BarcodePayload>(offCacheKey(barcode), now());
  if (cached) return toBarcodeResponse(cached.found ? cached.payload : undefined, barcode);

  const limit = quotaFor(QUOTAS.barcodeLookup, signIn);
  await chargeMiss({ uid, action: "barcodeLookup", limit, nowMs: now() });

  let completed = false;
  try {
    let upstreamFailed = false;
    let found: FoodCandidate | undefined;

    try {
      const off = await fetchOffProduct(barcode, deps);
      if (off.status === "found") found = off.candidate;
    } catch (e) {
      if (!(e instanceof UpstreamError)) throw e;
      upstreamFailed = true;
    }

    if (!found) {
      const key = await (deps.getUsdaKey ?? (() => getUsdaApiKey(now())))();
      if (key) {
        try {
          found = (await lookupUsdaByGtin(key, barcode, deps)) ?? undefined;
        } catch (e) {
          if (!(e instanceof UpstreamError)) throw e;
          upstreamFailed = true;
        }
      }
    }

    if (found) {
      const payload = toPayload(found);
      await writeCache(offCacheKey(barcode), { found: true, source: found.source, payload }, CACHE_TTL_MS.positive, now());
      completed = true;
      return toBarcodeResponse(payload, barcode);
    }
    // A source that FAILED did not say "not found": never negative-cache that.
    if (upstreamFailed) throw new UpstreamError("upstream-unavailable");
    await writeCache(offCacheKey(barcode), { found: false, source: "none" }, CACHE_TTL_MS.negative, now());
    completed = true;
    return { found: false };
  } catch (e) {
    if (e instanceof UpstreamError) throw unavailable();
    throw e;
  } finally {
    // An upstream failure gave the user nothing: give the daily charge back.
    if (!completed) await refundQuota(uid, "barcodeLookup", 1);
  }
}

export const lookupBarcode = onCall(FOOD_LOOKUP, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to look up a product.");
  }
  noteAppCheck(request, "lookupBarcode");
  enforceNonAnonymousForAi(signInProvider(request));
  // Flag check BEFORE the quota charge: a flag-off call must cost nothing (design s7.5).
  assertFeatureEnabled(foodLookupEnabled());
  const barcode = parseBarcode(request.data);
  return lookupBarcodeCore(request.auth.uid, signInProvider(request), barcode);
});

// ---------------------------------------------------------------------------
// searchFoods
// ---------------------------------------------------------------------------

export interface SearchRequest {
  query: string;
  languageCode: "en" | "ru";
  scope: SearchScope;
  limit: number;
}

export function parseSearchRequest(data: unknown): SearchRequest {
  const d = (data ?? {}) as Record<string, unknown>;
  if (typeof d.query !== "string") throw new HttpsError("invalid-argument", FOOD_LOOKUP_SLUGS.invalidQuery);
  const trimmed = d.query.trim();
  const length = Array.from(trimmed).length;
  if (length < QUERY_MIN || length > QUERY_MAX) throw new HttpsError("invalid-argument", FOOD_LOOKUP_SLUGS.invalidQuery);
  // Strip markup, URLs and punctuation noise; what is left is what is searched AND cache-keyed.
  const query = sanitiseDisplayText(trimmed, QUERY_MAX).toLowerCase();
  if (Array.from(query).length < QUERY_MIN) throw new HttpsError("invalid-argument", FOOD_LOOKUP_SLUGS.invalidQuery);

  if (d.languageCode !== undefined && d.languageCode !== "en" && d.languageCode !== "ru") {
    throw new HttpsError("invalid-argument", "languageCode must be en or ru.");
  }
  const scopeRaw = d.scope ?? "both";
  if (scopeRaw !== "generic" && scopeRaw !== "packaged" && scopeRaw !== "both") {
    throw new HttpsError("invalid-argument", "scope must be generic, packaged or both.");
  }
  const limitRaw = typeof d.limit === "number" && Number.isFinite(d.limit) ? Math.floor(d.limit) : DEFAULT_LIMIT;
  return {
    query,
    languageCode: d.languageCode === "ru" ? "ru" : "en",
    scope: scopeRaw,
    limit: Math.min(MAX_RESULTS, Math.max(1, limitRaw)),
  };
}

export interface SearchResponse {
  results: FoodCandidate[];
  attributions: Array<{ source: string; licence: string; url: string }>;
}

function toSearchResponse(results: FoodCandidate[], limit: number): SearchResponse {
  const capped = results.slice(0, limit);
  const attributions: SearchResponse["attributions"] = [];
  if (capped.some((r) => r.source === "usda_fdc")) attributions.push({ ...USDA_ATTRIBUTION });
  if (capped.some((r) => r.source === "open_food_facts")) attributions.push({ ...OFF_ATTRIBUTION });
  return { results: capped, attributions };
}

/** The whole search flow after the callable preamble. Exported for tests. */
export async function searchFoodsCore(
  uid: string,
  signIn: string | undefined,
  req: SearchRequest,
  deps: SearchDeps = {},
): Promise<SearchResponse> {
  const now = deps.now ?? Date.now;
  const cached = await readCachedSearch(req.languageCode, req.query, req.scope, now());
  if (cached) return toSearchResponse(cached, req.limit);

  // Generic search IS the USDA key; refuse before charging when it is not configured (never DEMO_KEY).
  if (needsUsdaKey(req.scope) && !(await (deps.getUsdaKey ?? (() => getUsdaApiKey(now())))())) {
    throw new HttpsError("failed-precondition", FOOD_LOOKUP_SLUGS.sourceNotConfigured);
  }

  await chargeMiss({ uid, action: "foodSearch", limit: quotaFor(QUOTAS.foodSearch, signIn), nowMs: now() });
  let completed = false;
  try {
    const results = await fetchAndCacheSearch(req.languageCode, req.query, req.scope, deps);
    completed = true;
    return toSearchResponse(results, req.limit);
  } catch (e) {
    if (e instanceof UpstreamError) throw unavailable();
    throw e;
  } finally {
    if (!completed) await refundQuota(uid, "foodSearch", 1);
  }
}

export const searchFoods = onCall(FOOD_LOOKUP, async (request) => {
  if (!request.auth) {
    throw new HttpsError("unauthenticated", "Sign in to search foods.");
  }
  noteAppCheck(request, "searchFoods");
  enforceNonAnonymousForAi(signInProvider(request));
  assertFeatureEnabled(foodLookupEnabled());
  const req = parseSearchRequest(request.data);
  return searchFoodsCore(request.auth.uid, signInProvider(request), req);
});
