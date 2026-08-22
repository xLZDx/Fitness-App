/**
 * P1.G2 — Core Health & Fitness (Nautilus) official brand adapter.
 * www.corehandf.com pages fetch with real server-rendered content
 * (DIRECT_FETCH), including a Leverage-line listing table with model codes
 * and an individually-fetched Instinct-line product page with full
 * specifications.
 */
import rawFixture from "../../generated/source_captures/core_health_fitness_nautilus_product_catalog.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "nautilus-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "core_health_fitness_nautilus_product_catalog";

export function runNautilusAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: { Nautilus: "nautilus" },
  });
}
