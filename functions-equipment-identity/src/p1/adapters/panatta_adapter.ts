/**
 * P1.G3 — Panatta official brand adapter. panattasport.com returned HTTP
 * 403 on every direct WebFetch attempt made during this gate's research
 * (root domain and individual product pages alike), so every record here
 * is SEARCH_INDEX_SNIPPET evidence — the specific `sourceUrl` for each
 * record was itself returned by search-engine indexing of Panatta's own
 * domain (the model code is visible directly in the URL path, e.g.
 * `/en/product/1SC081.html`), never a page this adapter's author actually
 * read.
 */
import rawFixture from "../../generated/source_captures/panatta_official_product_pages.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "panatta-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "panatta_official_product_pages";

export function runPanattaAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: { Panatta: "panatta" },
  });
}
