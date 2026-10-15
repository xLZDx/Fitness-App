/**
 * Search across the nutrition sources, with the central cache (design s17.5).
 *
 * `readCachedSearch` and `fetchAndCacheSearch` are separate on purpose: the
 * `searchFoods` callable must know whether a call is a cache MISS before it
 * charges quota and the per-minute burst slot; `analyzeMealPhoto` enrichment
 * simply uses both back to back (its own daily quota covers it).
 *
 * Scope: `generic` = USDA (Foundation and SR Legacy); `packaged` = Open Food
 * Facts; `both` = both in parallel. With no USDA key the USDA half is skipped.
 */
import { readCache, searchCacheKey, writeCache, CACHE_TTL_MS, type SearchScope } from "../nutrition_cache";
import { UpstreamError } from "../nutrition_http";
import { scoreMatch, matchRank } from "./match";
import { searchOff } from "./open_food_facts";
import { getUsdaApiKey, searchUsda } from "./usda_fdc";
import type { FoodCandidate, SourceDeps } from "./types";

export const MAX_RESULTS = 20;

export interface SearchDeps extends SourceDeps {
  /** Resolves the USDA key (default: Secret Manager). `null` = not configured. */
  getUsdaKey?: () => Promise<string | null>;
}

const SEARCH_SOURCE_TAG = "search";

export async function readCachedSearch(
  lang: string,
  query: string,
  scope: SearchScope,
  nowMs: number,
): Promise<FoodCandidate[] | null> {
  const hit = await readCache<FoodCandidate[]>(searchCacheKey(lang, query, scope), nowMs);
  if (!hit || !Array.isArray(hit.payload)) return null;
  return hit.payload;
}

const COMPLETENESS_RANK = { complete: 2, partial: 1, inconsistent: 0 } as const;

/** De-duplicates by `name|brand`, then ranks by match quality against the query, then completeness (stable). */
export function rankAndCap(query: string, candidates: readonly FoodCandidate[], limit: number = MAX_RESULTS): FoodCandidate[] {
  const seen = new Set<string>();
  const unique: FoodCandidate[] = [];
  for (const c of candidates) {
    const key = `${c.name.toLowerCase()}|${(c.brand ?? "").toLowerCase()}`;
    if (seen.has(key)) continue;
    seen.add(key);
    unique.push(c);
  }
  const scored = unique.map((c, index) => ({
    c,
    index,
    match: matchRank(scoreMatch([query], c.name)),
    completeness: COMPLETENESS_RANK[c.completeness],
  }));
  scored.sort((a, b) => b.match - a.match || b.completeness - a.completeness || a.index - b.index);
  return scored.slice(0, limit).map((s) => s.c);
}

/**
 * Queries the sources for `scope`, merges and ranks the answers and writes the
 * cache (search TTL, or the short negative TTL for an empty list). Throws
 * `UpstreamError` only when EVERY consulted source failed; if one failed and
 * another answered, the partial list is returned and NOT cached (a half answer
 * must not be served for 7 days).
 */
export async function fetchAndCacheSearch(
  lang: string,
  query: string,
  scope: SearchScope,
  deps: SearchDeps = {},
): Promise<FoodCandidate[]> {
  const now = deps.now ?? Date.now;
  const key = scope === "packaged" ? null : await (deps.getUsdaKey ?? (() => getUsdaApiKey(now())))();

  const jobs: Array<Promise<FoodCandidate[]>> = [];
  if (scope !== "packaged" && key) jobs.push(searchUsda(key, query, deps));
  if (scope !== "generic") jobs.push(searchOff(query, lang, deps));

  // Nothing to ask (generic scope without a USDA key): an empty, UNCACHED answer.
  if (jobs.length === 0) return [];

  const settled = await Promise.allSettled(jobs);
  const failures = settled.filter((s): s is PromiseRejectedResult => s.status === "rejected");
  const answers = settled.flatMap((s) => (s.status === "fulfilled" ? [s.value] : []));
  if (answers.length === 0) {
    const first = failures[0]?.reason;
    throw first instanceof UpstreamError ? first : new UpstreamError("upstream-unavailable");
  }

  const results = rankAndCap(query, answers.flat());
  if (failures.length === 0) {
    await writeCache(
      searchCacheKey(lang, query, scope),
      { found: results.length > 0, source: SEARCH_SOURCE_TAG, payload: results },
      results.length > 0 ? CACHE_TTL_MS.search : CACHE_TTL_MS.negative,
      now(),
    );
  }
  return results;
}

/** Whether `scope` can be served at all without the USDA key (`generic` cannot). */
export function needsUsdaKey(scope: SearchScope): boolean {
  return scope === "generic";
}
