/**
 * P1.G2 — Matrix Fitness official brand adapter. us.matrixfitness.com
 * fetches (HTTP 200) but returns only an empty client-side-JS-rendered
 * shell with no retrievable body content, so every record in this fixture
 * is SEARCH_INDEX_SNIPPET evidence, not DIRECT_FETCH.
 * cpo.matrixfitness.com (Certified Pre-Owned) IS directly fetchable but is
 * a REFURBISHED_USED sourceClass, not usable for this OFFICIAL_MANUFACTURER
 * adapter.
 */
import rawFixture from "../../generated/source_captures/matrix_fitness_product_catalog.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "matrix-fitness-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "matrix_fitness_product_catalog";

export function runMatrixAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: { "Matrix Fitness": "matrix" },
  });
}
