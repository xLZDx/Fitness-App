/**
 * Food server flags (sprint plan section 4, SD-2, SD-10).
 *
 * `FOOD_AI_ENABLED` gates `analyzeMealPhoto` and `parseNutritionLabel` (the
 * Vertex AI posture, Q-6); `FOOD_LOOKUP_ENABLED` gates `lookupBarcode` and
 * `searchFoods` (Open Food Facts / USDA, Q-4). Both default OFF, and the
 * pattern is the one `scaling.ts` uses for its fail-open stage flags: only the
 * exact string `true` turns a flag on, so unset, empty or a typo all stay off.
 * Read per call, not at module load, so tests can toggle them.
 *
 * A callable behind a flag checks it with `assertFeatureEnabled` BEFORE any
 * quota charge (see `feature_flags.ts`).
 */

/** Meal photo, describe-in-text and label OCR (paid Vertex AI calls). */
export function foodAiEnabled(): boolean {
  return process.env.FOOD_AI_ENABLED === "true";
}

/** Barcode lookup and server-side food search (shared upstream budget). */
export function foodLookupEnabled(): boolean {
  return process.env.FOOD_LOOKUP_ENABLED === "true";
}
