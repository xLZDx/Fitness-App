/**
 * P1.G2 — visible-conflict detection across the whole candidate pool.
 * Mirrors §5.6's rule for canonicalSlug at the model layer: a collision is
 * surfaced, never silently auto-resolved (no source-priority tiebreak, no
 * `-2`/`-3` suffixing). Candidate-stage conflicts feed G5 reconciliation as
 * input, not something this gate resolves.
 */
import { StagedEquipmentModelCandidate } from "../contracts";

export type AdapterConflictKind =
  | "DUPLICATE_MODEL_CODE_SAME_BRAND"
  | "DUPLICATE_MODEL_CODE_CROSS_BRAND";

export interface AdapterConflict {
  kind: AdapterConflictKind;
  modelCode: string;
  brandIds: string[];
  candidateIds: string[];
}

/** Detects candidates whose `modelCode` normalizes to the same value
 * (case/whitespace-insensitive). A same-brand collision usually means two
 * source records for the same physical model; a cross-brand collision
 * means two different manufacturers happen to reuse an identical model
 * code string -- both are real conflicts a human must resolve, not a bug in
 * this detector to paper over. */
export function detectConflicts(candidates: StagedEquipmentModelCandidate[]): AdapterConflict[] {
  const byCode = new Map<string, StagedEquipmentModelCandidate[]>();
  for (const candidate of candidates) {
    // A candidate with no modelCode at all carries no exact-model
    // identifier to collide on -- see mapRecordToCandidate: this codebase's
    // own adapters never emit one (RawCaptureRecordSchema requires a
    // modelCodeRaw), but the candidate schema itself leaves modelCode
    // optional for a future adapter that might not have one.
    if (!candidate.modelCode) continue;
    const key = candidate.modelCode.trim().toUpperCase();
    const group = byCode.get(key);
    if (group) {
      group.push(candidate);
    } else {
      byCode.set(key, [candidate]);
    }
  }

  const conflicts: AdapterConflict[] = [];
  for (const [modelCode, group] of byCode) {
    if (group.length < 2) continue;
    const brandIds = [...new Set(group.map((c) => c.brandId))].sort();
    conflicts.push({
      kind: brandIds.length > 1 ? "DUPLICATE_MODEL_CODE_CROSS_BRAND" : "DUPLICATE_MODEL_CODE_SAME_BRAND",
      modelCode,
      brandIds,
      candidateIds: group.map((c) => c.candidateId).sort(),
    });
  }
  return conflicts.sort((a, b) => a.modelCode.localeCompare(b.modelCode));
}
