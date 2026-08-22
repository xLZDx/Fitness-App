/**
 * P1.G2 — source-drift detection for one raw captured record. "Drift" here
 * means the captured evidence no longer honestly lines up with something
 * this codebase already treats as ground truth:
 *   - a `typeHintsRaw` id must actually exist in the frozen P0 functional-
 *     type snapshot -- a hint that doesn't is either a fixture typo or a
 *     sign the P0 ontology moved out from under this fixture;
 *   - a `lifecycleStatusRaw` value, when present, must match one of the
 *     phrases `candidate_mapper.ts`'s `LIFECYCLE_MAP` actually recognizes --
 *     an unrecognized value still safely becomes `catalogStatusCandidate:
 *     "UNKNOWN"` (never guessed), but that silent fallback is itself worth
 *     flagging (reviewer-found gap, P1.G2 review, 2026-08-22): a status the
 *     manufacturer DID provide, that this codebase failed to parse, is a
 *     different and more actionable signal than a status that was simply
 *     never given.
 *
 * This never blocks candidate emission: both hints and lifecycle status are
 * non-binding/best-effort (§5.8), so a drifted value is reported, not
 * fatal -- G5 reconciliation decides what to do with a candidate carrying a
 * suspect or missing hint/status.
 */
import { RawCaptureRecord } from "./contracts";
import { loadGeneratedSnapshot } from "../type_snapshot";
import { isKnownLifecycleStatus } from "./candidate_mapper";

export interface DriftIssue {
  field: string;
  reason: string;
}

export function detectRecordDrift(record: RawCaptureRecord): DriftIssue[] {
  const issues: DriftIssue[] = [];
  const snapshot = loadGeneratedSnapshot();
  const knownIds = new Set(snapshot.types.map((t) => t.id));
  for (const hint of record.typeHintsRaw) {
    if (!knownIds.has(hint)) {
      issues.push({
        field: "typeHintsRaw",
        reason:
          `typeHint ${JSON.stringify(hint)} does not match any id in the P0 ` +
          "functional-type snapshot -- likely a fixture typo or upstream " +
          "ontology drift, not a real hint",
      });
    }
  }
  if (record.lifecycleStatusRaw && !isKnownLifecycleStatus(record.lifecycleStatusRaw)) {
    issues.push({
      field: "lifecycleStatusRaw",
      reason:
        `lifecycleStatusRaw ${JSON.stringify(record.lifecycleStatusRaw)} does not match any ` +
        "phrase in candidate_mapper.ts's LIFECYCLE_MAP -- the candidate silently falls back to " +
        "catalogStatusCandidate=UNKNOWN, which is indistinguishable from a status that was never " +
        "given at all unless this drift issue is read",
    });
  }
  return issues;
}
