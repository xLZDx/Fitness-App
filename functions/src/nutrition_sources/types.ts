/**
 * Shared types for the nutrition source clients (design s17.4, s17.5).
 */
import type { FoodSource, Per100g } from "../food_types";
import type { DataQuality } from "../nutrition_normalise";

/** One normalised food from a database; the unit every source returns. */
export interface FoodCandidate {
  /** `off:<barcode>` or `usda:<fdcId>`. */
  foodRef: string;
  /** Sanitised display name (<= 80 chars, no markup, URLs, e-mail or phone patterns). */
  name: string;
  brand?: string;
  per100g: Per100g;
  servingG?: number;
  source: Extract<FoodSource, "usda_fdc" | "open_food_facts">;
  /** The source's own reference: the barcode (OFF) or the fdcId (USDA). */
  sourceRef: string;
  completeness: DataQuality;
  /** Energy was derived from the macros (Atwater) because the source had none. */
  derivedEnergy?: boolean;
}

/** Injectable collaborators; every default is the real implementation. */
export interface SourceDeps {
  fetchImpl?: typeof fetch;
  now?: () => number;
  /** Takes one slot from the global Open Food Facts budget; `false` = exhausted. */
  takeBudget?: (kind: "read" | "search") => Promise<boolean>;
  /** Per-request timeout override (the enrichment total budget shrinks it). */
  timeoutMs?: number;
}
