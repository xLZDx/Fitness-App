/**
 * P1.G2 — Technogym official brand adapter. technogym.com returned HTTP 403
 * on every direct WebFetch attempt made during this gate's research
 * (product page, category page, a regional variant, robots.txt, and a
 * support-download endpoint), so every record in this fixture is
 * SEARCH_INDEX_SNIPPET evidence, not DIRECT_FETCH -- see contracts.ts's
 * `retrievalMethod` doc for why that is still legitimate provenance under
 * §5.9.
 */
import rawFixture from "../../generated/source_captures/technogym_product_catalog.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "technogym-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "technogym_product_catalog";

export function runTechnogymAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: { Technogym: "technogym" },
  });
}
