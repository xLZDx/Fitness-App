/**
 * P1.G2 — structural guard: a P0 brand adapter may only source from a
 * real, registered `OFFICIAL_MANUFACTURER` entry in
 * core/equipment_identity/p0/source_registry.json (Python-owned, P0.G3).
 * Consumed here via the same synced-generated-copy pattern as the P0
 * functional-type snapshot and the source-capture fixtures -- see
 * scripts/sync_p1_generated.js.
 *
 * This does not touch `rights` at all -- registry membership only proves a
 * sourceId is a real, tracked provenance record of the right class; P1
 * official metadata may legitimately exist here while
 * `legalReviewState=UNREVIEWED` (see the P1 rights carry-forward posture in
 * P1_G1_SCHEMA.md §6.8).
 */
import rawRegistry from "../../generated/source_registry.json";

interface RawRegistrySourceEntry {
  sourceId: string;
  sourceClass: string;
}

interface RawRegistryFile {
  sources: RawRegistrySourceEntry[];
}

const REGISTRY = rawRegistry as unknown as RawRegistryFile;

export class UnregisteredSourceError extends Error {}

/** Throws unless `sourceId` is present in the registry AND registered as
 * `OFFICIAL_MANUFACTURER` -- both a typo'd/unregistered id and a real id
 * registered under the wrong class (e.g. a MARKETPLACE_3D or
 * SEARCH_DISCOVERY source) are refused, structurally, not just by adapter
 * author discipline. */
export function assertRegisteredOfficialManufacturerSource(sourceId: string): void {
  const entry = REGISTRY.sources.find((s) => s.sourceId === sourceId);
  if (!entry) {
    throw new UnregisteredSourceError(
      `sourceId ${JSON.stringify(sourceId)} is not registered in ` +
        "core/equipment_identity/p0/source_registry.json -- a P0 brand " +
        "adapter may only reference a real, registered source",
    );
  }
  if (entry.sourceClass !== "OFFICIAL_MANUFACTURER") {
    throw new UnregisteredSourceError(
      `sourceId ${JSON.stringify(sourceId)} is registered with sourceClass ` +
        `${JSON.stringify(entry.sourceClass)}, not OFFICIAL_MANUFACTURER -- a ` +
        "P0 brand adapter may only source from an official manufacturer record",
    );
  }
}
