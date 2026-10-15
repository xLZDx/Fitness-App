/**
 * Shared value types and closed code sets for the food callables (design s17).
 * Pure: no imports, no I/O.
 */

/**
 * The closed "check these" codes (design s17.10). Anything else a model or an
 * upstream source produces is DROPPED, never passed through, so free text can
 * never reach the client as a code.
 */
export const FOOD_CHECK_CODES = [
  "portionUnclear",
  "hiddenIngredients",
  "liquidUnknown",
  "cookingMethod",
  "multipleItems",
  "brandUnknown",
  "foodNotMatched",
  "lowConfidenceItem",
  "labelAmbiguous",
  "dataInconsistent",
  "scaleMissing",
] as const;
export type FoodCheckCode = (typeof FOOD_CHECK_CODES)[number];

const CHECK_CODE_SET: ReadonlySet<string> = new Set(FOOD_CHECK_CODES);

export function isFoodCheckCode(value: unknown): value is FoodCheckCode {
  return typeof value === "string" && CHECK_CODE_SET.has(value);
}

/** Where an item's per-100 g values came from (design s17.3). */
export const FOOD_SOURCES = ["usda_fdc", "open_food_facts", "llm_estimate", "user"] as const;
export type FoodSource = (typeof FOOD_SOURCES)[number];

/** How well a database candidate matched the item (design s17.3). */
export const MATCH_QUALITIES = ["exact", "close", "weak", "none"] as const;
export type MatchQuality = (typeof MATCH_QUALITIES)[number];

/** Per-100 g macros. `kcal` is energy in kilocalories; the rest are grams. */
export interface Per100g {
  kcal: number;
  proteinG: number;
  carbsG: number;
  fatG: number;
}

/** A low / mid / high estimate (grams or a macro amount). Always `low <= mid <= high`. */
export interface Range {
  low: number;
  mid: number;
  high: number;
}

/** Per-item macro amounts, each a `Range` (design s17.7). */
export interface MacroRanges {
  kcal: Range;
  proteinG: Range;
  carbsG: Range;
  fatG: Range;
}

/** Hard bounds shared by every per-100 g sanity check (design s17.3, s17.4). */
export const MAX_KCAL_PER_100G = 900;
export const MAX_MACRO_PER_100G = 100;
/** `protein + carbs + fat` cannot physically exceed 100 g; 5 g of slack for rounding. */
export const MAX_MACRO_SUM_PER_100G = 105;
