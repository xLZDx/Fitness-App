/**
 * Deterministic post-step for `parseNutritionLabel` (design s17.6, D-28).
 *
 * Gemini vision reads the label (ML Kit has no Cyrillic); the model's JSON is
 * never trusted as-is. This pure module turns it into per-100 g values the
 * client can confirm: decimal commas, kJ-only energy, per-serving-only labels
 * and Cyrillic unit words ("ккал", "г", "мл") are all normalised, the same
 * sanity bounds as the barcode path apply, and everything the model could not
 * read becomes a closed check code, never free text.
 *
 * Unit note: a serving given in millilitres is treated as grams (1 ml = 1 g).
 * That is exact for water and a close approximation for most drinks; the
 * client shows the per-100 g figure the user can edit before saving anything.
 */
import type { FoodCheckCode, Per100g } from "./food_types";
import {
  buildPer100g,
  kjToKcal,
  toFiniteNumber,
  type DataQuality,
  type NormalisedNutrition,
} from "./nutrition_normalise";

export interface NormalisedLabel {
  /** `null` when no usable per-100 g figure could be produced. */
  per100g: Per100g | null;
  perServing: Per100g | null;
  servingG?: number;
  servingsPerContainer?: number;
  dataQuality: DataQuality | "unusable";
  /** Closed codes only (`labelAmbiguous`, `dataInconsistent`, `scaleMissing`). */
  checkCodes: FoodCheckCode[];
}

const GRAM_UNITS = new Set(["g", "gr", "gram", "grams", "gramme", "grammes", "г", "гр", "грамм", "грамма", "граммов"]);
const ML_UNITS = new Set(["ml", "milliliter", "millilitre", "milliliters", "millilitres", "мл", "миллилитр", "миллилитров"]);
const KJ_UNITS = new Set(["kj", "kilojoule", "kilojoules", "кдж", "кдж."]);

const MAX_SERVING_G = 3000;
const MAX_SERVINGS = 100;

function asRecord(v: unknown): Record<string, unknown> | undefined {
  return typeof v === "object" && v !== null && !Array.isArray(v) ? (v as Record<string, unknown>) : undefined;
}

function unitWord(v: unknown): string {
  return typeof v === "string" ? v.trim().toLowerCase().replace(/\.$/, "") : "";
}

/** The serving weight in grams, or `undefined` when absent, non-positive, absurd or in an unknown unit. */
export function servingGrams(servingSize: unknown): number | undefined {
  const s = asRecord(servingSize);
  if (!s) return undefined;
  const value = toFiniteNumber(s.value);
  const unit = unitWord(s.unit);
  if (value === undefined || value <= 0 || value > MAX_SERVING_G) return undefined;
  if (GRAM_UNITS.has(unit) || ML_UNITS.has(unit)) return value;
  return undefined;
}

interface Block {
  /** Quality of the normalised block, or `null` when nothing usable. */
  result: NormalisedNutrition | null;
  /** True when the block carried at least one number (so a `null` result means "bad numbers"). */
  hadValues: boolean;
}

function readBlock(raw: unknown, energyIsKj: boolean): Block {
  const b = asRecord(raw);
  if (!b) return { result: null, hadValues: false };
  let kcal = toFiniteNumber(b.kcal);
  const kj = toFiniteNumber(b.kJ ?? b.kj);
  if (kcal === undefined && kj !== undefined) kcal = kjToKcal(kj);
  // The model sometimes puts a kJ figure in `kcal` when the label's energy unit is kJ.
  else if (kcal !== undefined && kj === undefined && energyIsKj) kcal = kjToKcal(kcal);
  const proteinG = toFiniteNumber(b.proteinG);
  const carbsG = toFiniteNumber(b.carbsG);
  const fatG = toFiniteNumber(b.fatG);
  const hadValues = [kcal, proteinG, carbsG, fatG].some((n) => n !== undefined);
  return { result: buildPer100g({ kcal, proteinG, carbsG, fatG }), hadValues };
}

/** Scales a per-serving record to per-100 g (`x * 100 / servingG`) and re-checks it. */
function scaleToPer100g(p: Per100g, servingG: number): NormalisedNutrition | null {
  const k = 100 / servingG;
  return buildPer100g({
    kcal: p.kcal * k,
    proteinG: p.proteinG * k,
    carbsG: p.carbsG * k,
    fatG: p.fatG * k,
  });
}

/**
 * Normalises the (already JSON-parsed) model answer. Never throws; a hostile
 * or malformed value degrades to `per100g: null` plus a closed code.
 */
export function normaliseLabel(raw: unknown): NormalisedLabel {
  const root = asRecord(raw) ?? {};
  const codes = new Set<FoodCheckCode>();
  const energyIsKj = KJ_UNITS.has(unitWord(root.energyUnit));

  const unreadable = Array.isArray(root.unreadableFields) ? root.unreadableFields : [];
  if (unreadable.length > 0) codes.add("labelAmbiguous");

  const servingG = servingGrams(root.servingSize);
  const servings = toFiniteNumber(root.servingsPerContainer);

  const perServingBlock = readBlock(root.perServing, energyIsKj);
  const per100Block = readBlock(root.per100g, energyIsKj);

  let per100g: NormalisedNutrition | null = per100Block.result;
  if (per100Block.hadValues && per100g === null) codes.add("dataInconsistent");

  if (per100g === null) {
    if (perServingBlock.result !== null) {
      if (servingG !== undefined) {
        per100g = scaleToPer100g(perServingBlock.result.per100g, servingG);
        if (per100g === null) codes.add("dataInconsistent");
      } else {
        codes.add("scaleMissing");
      }
    } else if (perServingBlock.hadValues) {
      codes.add("dataInconsistent");
    }
  }

  if (per100g === null) {
    if (!codes.has("dataInconsistent") && !codes.has("scaleMissing")) codes.add("labelAmbiguous");
  } else {
    if (per100g.dataQuality === "inconsistent") codes.add("dataInconsistent");
    if (per100g.missing.length > 0) codes.add("labelAmbiguous");
  }

  return {
    per100g: per100g?.per100g ?? null,
    perServing: perServingBlock.result?.per100g ?? null,
    ...(servingG !== undefined ? { servingG } : {}),
    ...(servings !== undefined && servings > 0 && servings <= MAX_SERVINGS ? { servingsPerContainer: servings } : {}),
    dataQuality: per100g?.dataQuality ?? "unusable",
    checkCodes: [...codes],
  };
}
