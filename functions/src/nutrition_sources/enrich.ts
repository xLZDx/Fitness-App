/**
 * Meal-item enrichment (design s17.3): replace the model's per-100 g guesses
 * with database values where a candidate matches, and TAG where every number
 * came from.
 *
 * Chain per item: generic whole foods -> USDA FoodData Central (Foundation and
 * SR Legacy); packaged or brand-bearing items -> Open Food Facts; otherwise the
 * model's own `llmPer100g` tagged `llm_estimate` (match quality `none`, adds
 * `lowConfidenceItem`). An upstream failure, an open breaker, an exhausted
 * global budget or a missing USDA key all degrade to the next step; this
 * function NEVER throws and never logs item text (D-67: only a slug).
 *
 * Bounded parallelism 4 and an 8 s total budget; each upstream call gets at
 * most the time remaining. Lookups reuse the central cache and the breakers.
 */
import * as logger from "firebase-functions/logger";
import { itemMacros, type CoercedItem } from "../coerce_meal_analysis";
import type { FoodCheckCode, FoodSource, MacroRanges, MatchQuality, Per100g, Range } from "../food_types";
import { readCachedSearch, fetchAndCacheSearch, type SearchDeps } from "./search";
import { matchRank, scoreMatch } from "./match";
import { UpstreamError, DEFAULT_TIMEOUT_MS } from "../nutrition_http";
import type { FoodCandidate } from "./types";

export const ENRICH_TOTAL_BUDGET_MS = 8_000;
export const ENRICH_CONCURRENCY = 4;
/** An upstream call is not started with less than this left of the total budget. */
export const MIN_CALL_MS = 500;

/** Item confidence = model confidence x this factor (design s17.3) [OWN]. */
export const MATCH_FACTOR: Record<MatchQuality, number> = { exact: 1.0, close: 0.8, weak: 0.5, none: 0.35 };

export interface EnrichedItem {
  name: string;
  grams: Range;
  /** `null` only when nothing usable exists (no database match and no model values). */
  per100g: Per100g | null;
  source: FoodSource;
  sourceRef?: string;
  matchQuality: MatchQuality;
  confidence: number;
  checkCodes: FoodCheckCode[];
  /** Recomputed from `per100g x grams`; never read from the model. */
  macros: MacroRanges;
}

const round2 = (n: number): number => Math.round(n * 100) / 100;

function pickBest(item: CoercedItem, results: readonly FoodCandidate[]): { c: FoodCandidate; q: MatchQuality } | undefined {
  const phrases = [item.name, ...item.queryTerms];
  let best: { c: FoodCandidate; q: MatchQuality } | undefined;
  for (const c of results) {
    const q = scoreMatch(phrases, c.name);
    if (q === "none") continue;
    if (!best || matchRank(q) > matchRank(best.q)) best = { c, q };
  }
  return best;
}

async function lookupCandidates(item: CoercedItem, deadlineMs: number, deps: SearchDeps): Promise<FoodCandidate[]> {
  const now = deps.now ?? Date.now;
  const remaining = deadlineMs - now();
  const query = item.queryTerms.find((t) => t.length >= 3) ?? (item.name.length >= 3 ? item.name : "");
  if (query === "" || remaining < MIN_CALL_MS) return [];
  const scope = item.packaged ? "packaged" : "generic";
  try {
    const cached = await readCachedSearch("en", query, scope, now());
    if (cached) return cached;
    return await fetchAndCacheSearch("en", query, scope, {
      ...deps,
      timeoutMs: Math.min(DEFAULT_TIMEOUT_MS, remaining),
    });
  } catch (e) {
    logger.warn("food_enrichment_degraded", { scope, slug: e instanceof UpstreamError ? e.slug : "unexpected" });
    return [];
  }
}

async function enrichOne(item: CoercedItem, deadlineMs: number, deps: SearchDeps): Promise<EnrichedItem> {
  const best = pickBest(item, await lookupCandidates(item, deadlineMs, deps));
  const codes = new Set<FoodCheckCode>(item.checkCodes);

  let per100g: Per100g | null;
  let source: FoodSource;
  let sourceRef: string | undefined;
  let matchQuality: MatchQuality;
  let name = item.name;
  let confidence: number;

  if (best) {
    per100g = best.c.per100g;
    source = best.c.source;
    sourceRef = best.c.sourceRef;
    matchQuality = best.q;
    name = best.c.name; // prefer the database display name over the model's wording (D-66)
    confidence = item.confidence * MATCH_FACTOR[best.q];
    if (best.c.completeness === "inconsistent") codes.add("dataInconsistent");
    if (best.q === "weak") codes.add("lowConfidenceItem");
  } else if (item.llmPer100g) {
    per100g = item.llmPer100g;
    source = "llm_estimate";
    matchQuality = "none";
    confidence = item.confidence * MATCH_FACTOR.none;
    codes.add("lowConfidenceItem");
  } else {
    per100g = null;
    source = "llm_estimate";
    matchQuality = "none";
    confidence = 0;
    codes.add("foodNotMatched");
    codes.add("lowConfidenceItem");
  }

  return {
    name,
    grams: item.grams,
    per100g,
    source,
    ...(sourceRef !== undefined ? { sourceRef } : {}),
    matchQuality,
    confidence: round2(confidence),
    checkCodes: [...codes],
    macros: itemMacros(per100g, item.grams),
  };
}

/** Enriches every item (order preserved), at most `ENRICH_CONCURRENCY` at a time, within the total budget. */
export async function enrichItems(items: readonly CoercedItem[], deps: SearchDeps = {}): Promise<EnrichedItem[]> {
  const now = deps.now ?? Date.now;
  const deadlineMs = now() + ENRICH_TOTAL_BUDGET_MS;
  const out = new Array<EnrichedItem>(items.length);
  let next = 0;
  const worker = async (): Promise<void> => {
    for (;;) {
      const i = next++;
      if (i >= items.length) return;
      out[i] = await enrichOne(items[i], deadlineMs, deps);
    }
  };
  await Promise.all(Array.from({ length: Math.min(ENRICH_CONCURRENCY, items.length) }, worker));
  return out;
}

/**
 * Entry confidence (design s17.3) [OWN]: `high` when every item is >= 0.75 and
 * none carries an unresolved check code, `medium` when every item is >= 0.5,
 * otherwise `low`. An empty meal is `low`.
 */
export function entryConfidence(items: ReadonlyArray<Pick<EnrichedItem, "confidence" | "checkCodes">>): "high" | "medium" | "low" {
  if (items.length === 0) return "low";
  if (items.every((i) => i.confidence >= 0.75 && i.checkCodes.length === 0)) return "high";
  if (items.every((i) => i.confidence >= 0.5)) return "medium";
  return "low";
}
