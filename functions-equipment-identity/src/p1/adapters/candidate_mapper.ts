/**
 * P1.G2 — maps one validated `RawCaptureRecord` into a
 * `StagedEquipmentModelCandidate` (P1.G1's contract). This is the ONLY
 * place a P0 brand adapter touches `../contracts.ts` -- deliberately never
 * `EquipmentModelSchema`: an adapter emits a staged candidate only, never a
 * published model, and never assigns an authoritative `primaryTypeId`
 * (§5.8) -- there is no `primaryTypeId` field anywhere in this file.
 *
 * `provenance[0].fields` lists only the candidate fields this specific
 * mapping actually populated from the record -- never `specsRaw`, which has
 * no corresponding field on `StagedEquipmentModelCandidate` at all in P1
 * (raw manufacturer spec sheets are evidence kept in the fixture, not
 * modeled on the candidate yet). `catalogStatusCandidate` is listed only
 * when `lifecycleStatusRaw` actually matched a known lifecycle phrase
 * (reviewer-found gap, P1.G2 review, 2026-08-22): a raw value present but
 * NOT recognized still silently becomes `"UNKNOWN"` (never guessed), but
 * `fields` must not claim that value was "populated from source evidence"
 * when it was really a fallback -- `source_drift.ts` is what actually
 * surfaces the unrecognized-value signal.
 */
import { StagedEquipmentModelCandidateSchema, StagedEquipmentModelCandidate, ProvenanceRef } from "../contracts";
import { deriveCandidateId, buildProductLineId } from "../ids";
import { RawCaptureRecord } from "./contracts";

export const LIFECYCLE_MAP: Record<string, "ACTIVE" | "DISCONTINUED" | "LEGACY" | "RETIRED"> = {
  active: "ACTIVE",
  "active/current product": "ACTIVE",
  "new product": "ACTIVE",
  discontinued: "DISCONTINUED",
  legacy: "LEGACY",
  retired: "RETIRED",
};

/** Whether a raw lifecycle string matches a known phrase -- used by both
 * `mapLifecycle` below and `source_drift.ts`'s drift check, so the two stay
 * in sync by construction rather than by two hand-kept lists. */
export function isKnownLifecycleStatus(raw: string): boolean {
  return raw.trim().toLowerCase() in LIFECYCLE_MAP;
}

function mapLifecycle(
  raw: string | undefined,
): "ACTIVE" | "DISCONTINUED" | "LEGACY" | "RETIRED" | "UNKNOWN" {
  if (!raw) return "UNKNOWN";
  return LIFECYCLE_MAP[raw.trim().toLowerCase()] ?? "UNKNOWN";
}

export interface MapToCandidateOptions {
  sourceId: string;
  brandId: string;
  adapterId: string;
  adapterVersion: string;
  fixtureSha256: string;
  capturedAt: string;
}

export function mapRecordToCandidate(
  record: RawCaptureRecord,
  opts: MapToCandidateOptions,
): StagedEquipmentModelCandidate {
  const sourceStableKey = record.modelCodeRaw;
  // Reviewer-found gap (P1.G2 type-design review, 2026-08-22): a single
  // corporate source can legitimately carry more than one brand (Life
  // Fitness + Hammer Strength share one fixture/sourceId). Hashing on
  // sourceId+sourceStableKey alone means two different-brand records that
  // happen to share the same modelCode would silently collide onto the
  // same candidateId. Folding brandId into the hash INPUT (not into the
  // publicly-exposed sourceStableKey/provenance.sourceId, which stay the
  // real captured values) closes this without changing what those fields
  // mean. "::" is a safe separator: both sourceId and brandId are
  // SlugSchema-validated and can never contain it.
  const candidateId = deriveCandidateId(`${opts.sourceId}::${opts.brandId}`, sourceStableKey);
  const productLineCandidate = record.productLineRaw
    ? buildProductLineId(opts.brandId, record.productLineRaw)
    : undefined;

  const lifecycleRecognized = !!record.lifecycleStatusRaw && isKnownLifecycleStatus(record.lifecycleStatusRaw);

  const fields: [string, ...string[]] = ["canonicalNameCandidate", "modelCode", "brandId"];
  if (productLineCandidate) fields.push("productLineCandidate");
  if (lifecycleRecognized) fields.push("catalogStatusCandidate");
  if (record.typeHintsRaw.length > 0) fields.push("typeHints");

  const provenance: ProvenanceRef = {
    sourceId: opts.sourceId,
    sourceUrl: record.sourceUrl,
    retrievedAt: opts.capturedAt,
    fixtureSha256: opts.fixtureSha256,
    adapterId: opts.adapterId,
    adapterVersion: opts.adapterVersion,
    retrievalMethod: record.retrievalMethod,
    fields,
  };

  const candidate: StagedEquipmentModelCandidate = {
    schemaVersion: 1,
    candidateId,
    brandId: opts.brandId,
    ...(productLineCandidate ? { productLineCandidate } : {}),
    canonicalNameCandidate: record.productNameRaw,
    modelCode: record.modelCodeRaw,
    skuAliases: [],
    aliases: [],
    catalogStatusCandidate: mapLifecycle(record.lifecycleStatusRaw),
    sourceConfidence: "OFFICIAL",
    provenance: [provenance],
    typeHints: record.typeHintsRaw,
    sourceStableKey,
  };

  return StagedEquipmentModelCandidateSchema.parse(candidate);
}
