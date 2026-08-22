/**
 * P1.G2 — Life Fitness / Hammer Strength official brand adapter. One
 * corporate source (matching P0.G3's combined registry entry), two
 * distinct product brands -- `brandIdByRawName` maps each raw brand name to
 * its own brandId, so downstream Equipment Brand records stay per-brand.
 * lifefitness.com is the strongest of the four P0 brand domains for direct
 * retrieval: every product page fetched during this gate's research
 * returned real server-rendered content (DIRECT_FETCH), including full
 * technical specifications, model codes, and lifecycle status.
 */
import rawFixture from "../../generated/source_captures/life_fitness_hammer_strength_product_catalog.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "life-fitness-hammer-strength-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "life_fitness_hammer_strength_product_catalog";

export function runLifeFitnessHammerStrengthAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: {
      "Life Fitness": "life-fitness",
      "Hammer Strength": "hammer-strength",
    },
  });
}
