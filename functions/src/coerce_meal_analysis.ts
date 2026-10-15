/**
 * `coerceMealAnalysis` -- the defensive parser for the model's meal answer
 * (design s17.3). The model's JSON is untrusted display data from an
 * untrusted source: every number is coerced and clamped, every string is
 * sanitised (D-66), unknown codes are dropped, the item count is capped and all
 * macro totals are RECOMPUTED here from `per100g x grams`; nothing the model
 * says about totals is ever read.
 *
 * Provenance (design s17.3): the idea of a server-side coercion step with
 * clamps and recomputed totals, and the "empty items when no food" rule, are
 * re-authored from the public `calorie-count` project's `coerceMealAnalysis`
 * and the per-item schema/source-tag idea from `calorie-tracker` (MIT). No code
 * was copied from either (`calorie-count`'s licence file is ambiguous).
 *
 * Pure: no I/O, no module state, never throws.
 */
import {
  MAX_KCAL_PER_100G,
  MAX_MACRO_PER_100G,
  MAX_MACRO_SUM_PER_100G,
  isFoodCheckCode,
  type FoodCheckCode,
  type MacroRanges,
  type Per100g,
  type Range,
} from "./food_types";
import { sanitiseDisplayText } from "./food_text";
import { isEnergyConsistent, round1, toFiniteNumber } from "./nutrition_normalise";

export const MAX_ITEMS = 12;
export const MIN_GRAMS = 1;
export const MAX_GRAMS = 3000;
/** `high / low` above this means the portion is not pinned down (design s17.3). */
export const PORTION_UNCLEAR_RATIO = 4;
const MAX_QUERY_TERMS = 5;
const MAX_TERM_LENGTH = 40;
const DEFAULT_MEAL_NAME = "Meal";
/** When the model gives only a mid portion, the range is +-30 % [OWN] and flagged. */
const DERIVED_SPREAD = 0.3;

/** One item after coercion, before database enrichment. */
export interface CoercedItem {
  name: string;
  queryTerms: string[];
  /** The model saw a packaged or brand-bearing product (routes enrichment to Open Food Facts). */
  packaged: boolean;
  grams: Range;
  /** Model confidence, clamped to 0..1. */
  confidence: number;
  checkCodes: FoodCheckCode[];
  /** The model's own per-100 g values; `null` when absent or rejected. */
  llmPer100g: Per100g | null;
}

export interface CoercedMeal {
  mealName: string;
  items: CoercedItem[];
  overallConfidence: number;
  assumptions: FoodCheckCode[];
  /** Recomputed from the items' `llmPer100g x grams`; items without values contribute 0. */
  totals: MacroRanges;
}

const clamp = (n: number, lo: number, hi: number): number => Math.min(hi, Math.max(lo, n));

/** A finite non-negative number, else `undefined` (negatives are dropped, not folded to 0). */
function nonNegative(value: unknown): number | undefined {
  const n = toFiniteNumber(value);
  return n !== undefined && n >= 0 ? n : undefined;
}

function asRecord(v: unknown): Record<string, unknown> | undefined {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
}

/** Parses the model text; tolerates ```json fences and prose around one JSON object. Never throws. */
export function parseModelJson(text: string): unknown {
  if (typeof text !== "string") return undefined;
  const trimmed = text.trim();
  if (trimmed === "") return undefined;
  const attempts: string[] = [trimmed];
  const fence = /```(?:json)?\s*([\s\S]*?)```/i.exec(trimmed);
  if (fence) attempts.push(fence[1].trim());
  const first = trimmed.indexOf("{");
  const last = trimmed.lastIndexOf("}");
  if (first >= 0 && last > first) attempts.push(trimmed.slice(first, last + 1));
  for (const a of attempts) {
    try {
      return JSON.parse(a);
    } catch {
      // try the next candidate
    }
  }
  return undefined;
}

/** Keeps only codes from the closed list, de-duplicated, in first-seen order. */
function closedCodes(value: unknown): FoodCheckCode[] {
  if (!Array.isArray(value)) return [];
  const out: FoodCheckCode[] = [];
  for (const v of value) {
    if (isFoodCheckCode(v) && !out.includes(v)) out.push(v);
  }
  return out;
}

/** Orders three portions, clamps each to 1..3000 and returns `{low <= mid <= high}`. */
function coerceGrams(raw: unknown, codes: Set<FoodCheckCode>): Range | undefined {
  const g = asRecord(raw);
  if (!g) return undefined;
  const mid = nonNegative(g.mid);
  let low = nonNegative(g.low);
  let high = nonNegative(g.high);
  if (mid === undefined) return undefined;
  if (low === undefined || high === undefined) {
    low = mid * (1 - DERIVED_SPREAD);
    high = mid * (1 + DERIVED_SPREAD);
    codes.add("portionUnclear");
  }
  const sorted = [low, mid, high].map((n) => clamp(n, MIN_GRAMS, MAX_GRAMS)).sort((a, b) => a - b);
  const range: Range = { low: round1(sorted[0]), mid: round1(sorted[1]), high: round1(sorted[2]) };
  if (range.high / range.low > PORTION_UNCLEAR_RATIO) codes.add("portionUnclear");
  return range;
}

/**
 * The model's per-100 g values with the design's clamps: kcal 0..900 and each
 * macro 0..100 are clamped and flagged; `protein + carbs + fat > 105` rejects
 * the whole record; an energy figure not explained by the macros (Atwater gap
 * over 25 %) keeps the record but flags `dataInconsistent`.
 */
function coercePer100g(raw: unknown, codes: Set<FoodCheckCode>): Per100g | null {
  const p = asRecord(raw);
  if (!p) return null;
  const kcal = nonNegative(p.kcal);
  const proteinG = nonNegative(p.proteinG);
  const carbsG = nonNegative(p.carbsG);
  const fatG = nonNegative(p.fatG);
  if (kcal === undefined || proteinG === undefined || carbsG === undefined || fatG === undefined) return null;
  const clampedFlag = kcal > MAX_KCAL_PER_100G || [proteinG, carbsG, fatG].some((n) => n > MAX_MACRO_PER_100G);
  if (clampedFlag) codes.add("dataInconsistent");
  const out: Per100g = {
    kcal: round1(Math.min(kcal, MAX_KCAL_PER_100G)),
    proteinG: round1(Math.min(proteinG, MAX_MACRO_PER_100G)),
    carbsG: round1(Math.min(carbsG, MAX_MACRO_PER_100G)),
    fatG: round1(Math.min(fatG, MAX_MACRO_PER_100G)),
  };
  if (out.proteinG + out.carbsG + out.fatG > MAX_MACRO_SUM_PER_100G) {
    codes.add("dataInconsistent");
    return null;
  }
  if (!isEnergyConsistent(out)) codes.add("dataInconsistent");
  return out;
}

function coerceQueryTerms(raw: unknown, fallbackName: string): string[] {
  const terms: string[] = [];
  if (Array.isArray(raw)) {
    for (const t of raw) {
      const s = sanitiseDisplayText(t, MAX_TERM_LENGTH).toLowerCase();
      if (s !== "" && !terms.includes(s)) terms.push(s);
      if (terms.length >= MAX_QUERY_TERMS) break;
    }
  }
  if (terms.length === 0) terms.push(sanitiseDisplayText(fallbackName, MAX_TERM_LENGTH).toLowerCase());
  return terms;
}

function coerceItem(raw: unknown): CoercedItem | undefined {
  const r = asRecord(raw);
  if (!r) return undefined;
  const name = sanitiseDisplayText(r.name);
  if (name === "") return undefined;
  const codes = new Set<FoodCheckCode>(closedCodes(r.uncertainties));
  const grams = coerceGrams(r.estimatedGrams, codes);
  if (!grams) return undefined;
  const confidenceRaw = toFiniteNumber(r.confidence);
  const confidence = confidenceRaw === undefined ? 0 : clamp(confidenceRaw, 0, 1);
  const llmPer100g = coercePer100g(r.llmPer100g, codes);
  return {
    name,
    queryTerms: coerceQueryTerms(r.queryTerms, name),
    packaged: r.packaged === true,
    grams,
    confidence: round2(confidence),
    checkCodes: [...codes],
    llmPer100g,
  };
}

const round2 = (n: number): number => Math.round(n * 100) / 100;

const ZERO_RANGE: Range = { low: 0, mid: 0, high: 0 };

/** `per100g x grams / 100` for each of low/mid/high (design s17.7: zero grams -> zero). */
export function itemMacros(per100g: Per100g | null, grams: Range): MacroRanges {
  if (!per100g) {
    return { kcal: { ...ZERO_RANGE }, proteinG: { ...ZERO_RANGE }, carbsG: { ...ZERO_RANGE }, fatG: { ...ZERO_RANGE } };
  }
  const scale = (per100: number): Range => ({
    low: round1((per100 * grams.low) / 100),
    mid: round1((per100 * grams.mid) / 100),
    high: round1((per100 * grams.high) / 100),
  });
  return {
    kcal: scale(per100g.kcal),
    proteinG: scale(per100g.proteinG),
    carbsG: scale(per100g.carbsG),
    fatG: scale(per100g.fatG),
  };
}

/** Sums per-item macro ranges (a plain sum of lows, mids and highs; the day view combines spreads differently). */
export function sumMacros(items: readonly MacroRanges[]): MacroRanges {
  const add = (pick: (m: MacroRanges) => Range): Range => ({
    low: round1(items.reduce((s, m) => s + pick(m).low, 0)),
    mid: round1(items.reduce((s, m) => s + pick(m).mid, 0)),
    high: round1(items.reduce((s, m) => s + pick(m).high, 0)),
  });
  return {
    kcal: add((m) => m.kcal),
    proteinG: add((m) => m.proteinG),
    carbsG: add((m) => m.carbsG),
    fatG: add((m) => m.fatG),
  };
}

/**
 * Parses and coerces the model's answer. Anything unusable (non-JSON, a JSON
 * array, an empty string, truncated JSON) yields an EMPTY meal, never a throw;
 * the client then shows "We could not find food in this photo".
 */
export function coerceMealAnalysis(rawText: string): CoercedMeal {
  const parsed = asRecord(parseModelJson(rawText));
  const empty: CoercedMeal = {
    mealName: DEFAULT_MEAL_NAME,
    items: [],
    overallConfidence: 0,
    assumptions: [],
    totals: sumMacros([]),
  };
  if (!parsed) return empty;

  const rawItems = Array.isArray(parsed.items) ? parsed.items : [];
  const items: CoercedItem[] = [];
  for (const raw of rawItems) {
    const item = coerceItem(raw);
    if (item) items.push(item);
    if (items.length >= MAX_ITEMS) break;
  }

  const overallRaw = toFiniteNumber(parsed.overallConfidence);
  const mealName = sanitiseDisplayText(parsed.mealName) || DEFAULT_MEAL_NAME;
  return {
    mealName,
    items,
    overallConfidence: items.length === 0 ? 0 : round2(clamp(overallRaw ?? 0, 0, 1)),
    assumptions: closedCodes(parsed.assumptions),
    totals: sumMacros(items.map((i) => itemMacros(i.llmPer100g, i.grams))),
  };
}
