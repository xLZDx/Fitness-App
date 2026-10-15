/**
 * Pure normalisation of nutrition-database values (design s17.4, FINDINGS).
 *
 * Open Food Facts and USDA carry values in different shapes (kJ-only energy,
 * sodium instead of salt, strings instead of numbers, per-serving next to
 * per-100 g). Everything the callables return goes through here so the client
 * sees ONE shape: per-100 g `{kcal, proteinG, carbsG, fatG}` plus a quality
 * label. No I/O, no module state.
 */
import {
  MAX_KCAL_PER_100G,
  MAX_MACRO_PER_100G,
  MAX_MACRO_SUM_PER_100G,
  type Per100g,
} from "./food_types";

export const KJ_PER_KCAL = 4.184;
/** Salt (NaCl) in grams per gram of sodium. */
export const SALT_PER_SODIUM = 2.5;

export type DataQuality = "complete" | "partial" | "inconsistent";

/** A finite non-negative number from a number or a numeric string ("12,5" is 12.5), else `undefined`. */
export function toFiniteNumber(value: unknown): number | undefined {
  if (typeof value === "number") return Number.isFinite(value) ? value : undefined;
  if (typeof value === "string") {
    const s = value.trim().replace(",", ".");
    if (s === "" || !/^[+-]?(\d+\.?\d*|\.\d+)$/.test(s)) return undefined;
    const n = Number(s);
    return Number.isFinite(n) ? n : undefined;
  }
  return undefined;
}

export const round1 = (n: number): number => Math.round(n * 10) / 10;

/** kJ to kcal, one decimal (2252 kJ -> 538.2). */
export function kjToKcal(kj: number): number {
  return round1(kj / KJ_PER_KCAL);
}

/** `4P + 4C + 9F`. */
export function atwaterKcal(p: Pick<Per100g, "proteinG" | "carbsG" | "fatG">): number {
  return 4 * p.proteinG + 4 * p.carbsG + 9 * p.fatG;
}

/**
 * True when the macros explain the energy: `|atwater - kcal| <= max(25 % of
 * kcal, 10 kcal)` (design s17.7). Small gaps (fibre, rounding) must not raise
 * `dataInconsistent`; a 25 %+ gap does. The 10 kcal floor keeps very-low-energy
 * foods (a diet drink at 1 kcal) from being flagged for a rounding artefact.
 */
export function isEnergyConsistent(p: Per100g): boolean {
  const gap = Math.abs(atwaterKcal(p) - p.kcal);
  return gap <= Math.max(0.25 * p.kcal, 10);
}

/** Bounds every per-100 g record must satisfy to be shown at all. */
export function isWithinBounds(p: Per100g): boolean {
  const all = [p.kcal, p.proteinG, p.carbsG, p.fatG];
  if (!all.every((n) => Number.isFinite(n) && n >= 0)) return false;
  return (
    p.kcal <= MAX_KCAL_PER_100G &&
    p.proteinG <= MAX_MACRO_PER_100G &&
    p.carbsG <= MAX_MACRO_PER_100G &&
    p.fatG <= MAX_MACRO_PER_100G &&
    p.proteinG + p.carbsG + p.fatG <= MAX_MACRO_SUM_PER_100G
  );
}

export interface NormalisedNutrition {
  per100g: Per100g;
  dataQuality: DataQuality;
  /** Energy was derived from the macros (Atwater) because the source had none. */
  derivedEnergy: boolean;
  /** Macro names the source did not carry (their value in `per100g` is 0). */
  missing: Array<"proteinG" | "carbsG" | "fatG">;
  /** Salt in grams per 100 g when the source carried salt or sodium. */
  saltG?: number;
}

/** Classifies a record that already passed `isWithinBounds`. */
function classify(p: Per100g, derivedEnergy: boolean, missing: string[]): DataQuality {
  if (!derivedEnergy && missing.length === 0) {
    return isEnergyConsistent(p) ? "complete" : "inconsistent";
  }
  // Energy derived from macros, or a macro absent: usable but not complete.
  return derivedEnergy || isEnergyConsistent(p) ? "partial" : "inconsistent";
}

/**
 * Builds a record from already-resolved per-100 g candidates (`undefined` =
 * absent). `null` when nothing usable remains: no energy and no macro at all,
 * or a value outside the physical bounds.
 */
export function buildPer100g(input: {
  kcal?: number;
  proteinG?: number;
  carbsG?: number;
  fatG?: number;
  saltG?: number;
}): NormalisedNutrition | null {
  const { kcal, proteinG, carbsG, fatG } = input;
  const macrosPresent = [proteinG, carbsG, fatG].filter((n) => n !== undefined).length;
  if (kcal === undefined && macrosPresent === 0) return null;
  if (kcal === undefined && macrosPresent < 3) return null; // cannot derive energy honestly

  const missing: Array<"proteinG" | "carbsG" | "fatG"> = [];
  if (proteinG === undefined) missing.push("proteinG");
  if (carbsG === undefined) missing.push("carbsG");
  if (fatG === undefined) missing.push("fatG");

  const macros = { proteinG: proteinG ?? 0, carbsG: carbsG ?? 0, fatG: fatG ?? 0 };
  const derivedEnergy = kcal === undefined;
  const per100g: Per100g = {
    kcal: round1(kcal ?? atwaterKcal(macros)),
    proteinG: round1(macros.proteinG),
    carbsG: round1(macros.carbsG),
    fatG: round1(macros.fatG),
  };
  if (!isWithinBounds(per100g)) return null;
  const out: NormalisedNutrition = {
    per100g,
    dataQuality: classify(per100g, derivedEnergy, missing),
    derivedEnergy,
    missing,
  };
  if (input.saltG !== undefined && input.saltG >= 0) out.saltG = Math.round(input.saltG * 100) / 100;
  return out;
}

/**
 * Open Food Facts `nutriments` -> normalised per-100 g. Only `<nutrient>_100g`
 * keys are read (per-serving values are never mistaken for per-100 g); kcal
 * comes from `energy-kcal_100g`, else `energy_100g` (always kJ in OFF) / 4.184;
 * salt from `salt_100g`, else `sodium_100g * 2.5`.
 */
export function normaliseOffNutriments(nutriments: unknown): NormalisedNutrition | null {
  if (typeof nutriments !== "object" || nutriments === null) return null;
  const n = nutriments as Record<string, unknown>;
  let kcal = toFiniteNumber(n["energy-kcal_100g"]);
  if (kcal === undefined) {
    const kj = toFiniteNumber(n["energy-kj_100g"]) ?? toFiniteNumber(n["energy_100g"]);
    if (kj !== undefined) kcal = kjToKcal(kj);
  }
  const salt = toFiniteNumber(n["salt_100g"]);
  const sodium = toFiniteNumber(n["sodium_100g"]);
  return buildPer100g({
    kcal,
    proteinG: toFiniteNumber(n["proteins_100g"]),
    carbsG: toFiniteNumber(n["carbohydrates_100g"]),
    fatG: toFiniteNumber(n["fat_100g"]),
    saltG: salt ?? (sodium !== undefined ? sodium * SALT_PER_SODIUM : undefined),
  });
}

/** USDA FoodData Central nutrient ids used here. */
export const USDA_NUTRIENT = { kcal: 1008, protein: 1003, fat: 1004, carbs: 1005 } as const;

interface UsdaNutrientRow {
  nutrientId?: unknown;
  value?: unknown;
  unitName?: unknown;
}

/**
 * USDA `foodNutrients` (values are per 100 g for Foundation and SR Legacy; for
 * Branded the search API reports per-100 g `value` too) -> normalised per-100 g.
 * Energy is nutrient 1008 in KCAL; some foods lack it and energy is then
 * derived by Atwater and flagged `derivedEnergy`.
 */
export function normaliseUsdaNutrients(rows: unknown): NormalisedNutrition | null {
  if (!Array.isArray(rows)) return null;
  const byId = new Map<number, number>();
  for (const raw of rows as UsdaNutrientRow[]) {
    if (typeof raw !== "object" || raw === null) continue;
    const id = toFiniteNumber(raw.nutrientId);
    const value = toFiniteNumber(raw.value);
    if (id === undefined || value === undefined) continue;
    // 1008 is kcal; some feeds also list kJ as 1062 - never read that as kcal.
    if (id === USDA_NUTRIENT.kcal && typeof raw.unitName === "string" && raw.unitName.toUpperCase() !== "KCAL") continue;
    if (!byId.has(id)) byId.set(id, value);
  }
  return buildPer100g({
    kcal: byId.get(USDA_NUTRIENT.kcal),
    proteinG: byId.get(USDA_NUTRIENT.protein),
    carbsG: byId.get(USDA_NUTRIENT.carbs),
    fatG: byId.get(USDA_NUTRIENT.fat),
  });
}
