/**
 * P1.G2 — the one shared adapter execution path. Every per-brand adapter
 * file (technogym_adapter.ts, matrix_adapter.ts,
 * life_fitness_hammer_strength_adapter.ts, nautilus_adapter.ts) is a thin
 * wrapper around this function -- avoids four near-identical
 * implementations of "validate source is registered, validate fixture,
 * reject duplicate stable keys, detect drift, map each record" (P0's own
 * "fix the root cause, avoid parallel implementations" discipline applies
 * here just as much as anywhere else in this codebase).
 */
import { assertRegisteredOfficialManufacturerSource } from "./registry_check";
import { loadSourceCaptureFixture } from "./source_capture";
import { detectRecordDrift, DriftIssue } from "./source_drift";
import { mapRecordToCandidate } from "./candidate_mapper";
import { StagedEquipmentModelCandidate } from "../contracts";

export interface AdapterDriftReport {
  recordIndex: number;
  productNameRaw: string;
  issues: DriftIssue[];
}

export interface AdapterRunResult {
  sourceId: string;
  fixtureSha256: string;
  capturedAt: string;
  candidates: StagedEquipmentModelCandidate[];
  driftIssues: AdapterDriftReport[];
}

export interface RunAdapterOptions {
  sourceId: string;
  adapterId: string;
  adapterVersion: string;
  /** The statically-imported (compile-time) fixture JSON module. */
  rawFixture: unknown;
  /** Maps a record's raw brand name to this codebase's brandId slug. A
   * record whose brandNameRaw is not a key here is refused -- a
   * single-brand adapter passes a one-entry map; a multi-brand source
   * (e.g. Life Fitness + Hammer Strength share one corporate source)
   * passes one entry per brand it may legitimately emit. */
  brandIdByRawName: Record<string, string>;
}

export function runAdapter(opts: RunAdapterOptions): AdapterRunResult {
  assertRegisteredOfficialManufacturerSource(opts.sourceId);
  const { fixture, fixtureSha256 } = loadSourceCaptureFixture(opts.rawFixture);
  if (fixture.sourceId !== opts.sourceId) {
    throw new Error(
      `fixture sourceId ${JSON.stringify(fixture.sourceId)} does not match expected ` +
        `${JSON.stringify(opts.sourceId)} (adapter ${opts.adapterId})`,
    );
  }

  const candidates: StagedEquipmentModelCandidate[] = [];
  const driftIssues: AdapterDriftReport[] = [];
  const seenStableKeys = new Set<string>();

  fixture.records.forEach((record, index) => {
    const brandId = opts.brandIdByRawName[record.brandNameRaw];
    if (!brandId) {
      throw new Error(
        `${opts.sourceId} fixture record ${index} has unrecognized brandNameRaw ` +
          `${JSON.stringify(record.brandNameRaw)} -- expected one of ` +
          `${JSON.stringify(Object.keys(opts.brandIdByRawName))}`,
      );
    }
    // Duplicate stable keys within one BRAND would collide onto the same
    // candidateId (candidate_mapper.ts hashes sourceId+brandId+
    // sourceStableKey) -- a hard error here, not a warning, since it means
    // the raw capture itself has a data-integrity problem. Scoped to
    // (brandId, normalized modelCodeRaw), not modelCodeRaw alone
    // (reviewer-found gap, P1.G2 review, 2026-08-22): a shared corporate
    // source can legitimately carry more than one brand (Life Fitness +
    // Hammer Strength), and two different brands' products coincidentally
    // sharing a model-code string is not a data-integrity problem -- it
    // used to hard-crash the whole adapter run regardless of brand.
    // Normalized (trim + uppercase) to match conflicts.ts's cross-pool
    // comparison, so a same-brand case/whitespace variant is caught here
    // rather than silently downgrading into a softer cross-source conflict.
    const stableKeyGroup = JSON.stringify([brandId, record.modelCodeRaw.trim().toUpperCase()]);
    if (seenStableKeys.has(stableKeyGroup)) {
      throw new Error(
        `duplicate modelCodeRaw ${JSON.stringify(record.modelCodeRaw)} for brand ${JSON.stringify(brandId)} ` +
          `within fixture ${opts.sourceId}`,
      );
    }
    seenStableKeys.add(stableKeyGroup);

    const issues = detectRecordDrift(record);
    if (issues.length > 0) {
      driftIssues.push({ recordIndex: index, productNameRaw: record.productNameRaw, issues });
    }

    candidates.push(
      mapRecordToCandidate(record, {
        sourceId: opts.sourceId,
        brandId,
        adapterId: opts.adapterId,
        adapterVersion: opts.adapterVersion,
        fixtureSha256,
        capturedAt: fixture.capturedAt,
      }),
    );
  });

  return { sourceId: opts.sourceId, fixtureSha256, capturedAt: fixture.capturedAt, candidates, driftIssues };
}
