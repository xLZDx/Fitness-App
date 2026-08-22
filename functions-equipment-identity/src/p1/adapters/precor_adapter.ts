/**
 * P1.G3 — Precor official brand adapter. `precor_spec_tables` (P0.G3) is
 * an official PDF spec-table document — genuinely DIRECT_FETCH: every
 * record here was extracted from the real, directly-fetched PDF text
 * (`static.precor.com/spec-tables/en-us/Precor-2022-NA-Spec-Tables.pdf`),
 * not a search snippet.
 */
import rawFixture from "../../generated/source_captures/precor_spec_tables.json";
import { runAdapter, AdapterRunResult } from "./adapter_runner";

export const ADAPTER_ID = "precor-adapter";
export const ADAPTER_VERSION = "1.0.0";
export const SOURCE_ID = "precor_spec_tables";

export function runPrecorAdapter(): AdapterRunResult {
  return runAdapter({
    sourceId: SOURCE_ID,
    adapterId: ADAPTER_ID,
    adapterVersion: ADAPTER_VERSION,
    rawFixture,
    brandIdByRawName: { Precor: "precor" },
  });
}
