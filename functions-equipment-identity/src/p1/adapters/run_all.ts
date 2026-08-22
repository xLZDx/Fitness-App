/**
 * P1.G2 — runs all four P0 brand adapters and assembles the combined
 * candidate pool + cross-source conflict report + capture manifest. Used
 * both by tests and by scripts/generate_p1_g2_artifacts.js (the
 * deterministic-output generator run against the compiled `lib/` tree).
 */
import { runTechnogymAdapter } from "./technogym_adapter";
import { runMatrixAdapter } from "./matrix_adapter";
import { runLifeFitnessHammerStrengthAdapter } from "./life_fitness_hammer_strength_adapter";
import { runNautilusAdapter } from "./nautilus_adapter";
import { detectConflicts, AdapterConflict } from "./conflicts";
import { AdapterRunResult } from "./adapter_runner";
import { DriftIssue } from "./source_drift";
import { StagedEquipmentModelCandidate } from "../contracts";

/** Linked to the specific candidate it pertains to (reviewer-found gap,
 * P1.G2 review, 2026-08-22): `AdapterRunResult.driftIssues` used to get
 * collapsed to a bare `driftIssueCount` before reaching any persisted
 * artifact, which made a real drift signal unusable by any consumer that
 * wasn't re-deriving it from the source fixture by hand -- exactly the
 * traceability `source_drift.ts` was built to provide to G5 reconciliation.
 * `recordIndex`/`candidates[index]` line up 1:1 inside `adapter_runner.ts`
 * (every record unconditionally produces exactly one candidate, in order),
 * so this lookup is always safe. */
export interface CaptureManifestDriftEntry {
  candidateId: string;
  productNameRaw: string;
  issues: DriftIssue[];
}

export interface CaptureManifestEntry {
  sourceId: string;
  fixtureSha256: string;
  capturedAt: string;
  candidateCount: number;
  driftIssueCount: number;
  driftIssues: CaptureManifestDriftEntry[];
}

export interface RunAllResult {
  candidates: StagedEquipmentModelCandidate[];
  conflicts: AdapterConflict[];
  captureManifest: CaptureManifestEntry[];
}

export function runAllP0BrandAdapters(): RunAllResult {
  const runs: AdapterRunResult[] = [
    runTechnogymAdapter(),
    runMatrixAdapter(),
    runLifeFitnessHammerStrengthAdapter(),
    runNautilusAdapter(),
  ];

  const candidates = runs.flatMap((r) => r.candidates);
  const conflicts = detectConflicts(candidates);
  const captureManifest: CaptureManifestEntry[] = runs.map((r) => ({
    sourceId: r.sourceId,
    fixtureSha256: r.fixtureSha256,
    capturedAt: r.capturedAt,
    candidateCount: r.candidates.length,
    driftIssueCount: r.driftIssues.length,
    driftIssues: r.driftIssues.map((report) => ({
      candidateId: r.candidates[report.recordIndex].candidateId,
      productNameRaw: report.productNameRaw,
      issues: report.issues,
    })),
  }));

  return { candidates, conflicts, captureManifest };
}
