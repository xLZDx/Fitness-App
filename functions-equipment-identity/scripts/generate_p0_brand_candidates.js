// P1.G2/P1.G3 -- deterministic artifact generation. Runs the built (lib/)
// adapter pipeline once (every official P0-registered-brand adapter, across
// however many P1 sub-gates have added one -- see run_all.ts's own header)
// and writes its output to the repo-owned evidence location:
//   core/equipment_identity/p1/candidates/p0_brand_candidates.json
//   core/equipment_identity/p1/candidates/adapter_conflicts.json
//   core/equipment_identity/p1/candidates/capture_manifest.json
//
// capture_manifest.json deliberately lives under candidates/, NOT under
// source_captures/ alongside the real hand-authored fixtures: it is a
// generated OUTPUT (like the other two files here), and
// scripts/sync_p1_generated.js treats every *.json file directly under
// source_captures/ as a real source fixture to sync into src/generated/ --
// a generated file with the same extension sitting in that directory would
// be indistinguishable from one, and the sync script's own --check would
// flag it as "missing from src/generated/" forever (caught live during this
// gate's own build).
//
// Deterministic: no wall-clock timestamp is embedded -- `generatedFrom
// CapturedAt` is derived from the fixtures' own `capturedAt` values (all
// "2026-08-22T00:00:00Z" today), not `Date.now()`, so re-running this
// script against unchanged fixtures produces byte-identical output.
//
// Written via a temp-file-then-rename per file (reviewer-found gap, P1.G2
// review, 2026-08-22): three sequential `fs.writeFileSync` calls with no
// rollback meant a write failure partway through the sequence (disk full,
// permissions change mid-run) could leave three related artifacts whose
// content no longer agreed with each other. `fs.renameSync` on the same
// filesystem is atomic, so each individual file update is now all-or-
// nothing (a genuinely atomic THREE-file transaction would need a lock/
// two-phase-commit this script doesn't have -- out of scope for a
// deterministic, single-writer dev-time generator).
//
//   npm run generate:p0-brand-candidates   # npm run build && node this script
"use strict";

const fs = require("fs");
const path = require("path");

const REPO_ROOT = path.resolve(__dirname, "..", "..");
const CANDIDATES_DIR = path.join(REPO_ROOT, "core", "equipment_identity", "p1", "candidates");

function writeJsonAtomic(filePath, data) {
  const tmpPath = `${filePath}.tmp-${process.pid}`;
  fs.writeFileSync(tmpPath, JSON.stringify(data, null, 2) + "\n");
  fs.renameSync(tmpPath, filePath);
}

function main() {
  // eslint-disable-next-line global-require -- must load AFTER `npm run build`
  const { runAllP0BrandAdapters } = require(path.join(__dirname, "..", "lib", "p1", "adapters", "run_all.js"));
  const result = runAllP0BrandAdapters();

  const generatedFromCapturedAt = result.captureManifest
    .map((e) => e.capturedAt)
    .sort()
    .slice(-1)[0];

  fs.mkdirSync(CANDIDATES_DIR, { recursive: true });

  writeJsonAtomic(path.join(CANDIDATES_DIR, "p0_brand_candidates.json"), {
    schemaVersion: 1,
    generatedFromCapturedAt,
    candidateCount: result.candidates.length,
    candidates: result.candidates,
  });

  writeJsonAtomic(path.join(CANDIDATES_DIR, "adapter_conflicts.json"), {
    schemaVersion: 1,
    generatedFromCapturedAt,
    conflictCount: result.conflicts.length,
    conflicts: result.conflicts,
  });

  writeJsonAtomic(path.join(CANDIDATES_DIR, "capture_manifest.json"), {
    schemaVersion: 1,
    sources: result.captureManifest,
  });

  const totalDriftIssues = result.captureManifest.reduce((sum, e) => sum + e.driftIssueCount, 0);
  console.log(
    `wrote ${result.candidates.length} candidate(s) from ${result.captureManifest.length} source(s), ` +
      `${result.conflicts.length} conflict(s), ${totalDriftIssues} drift issue(s)`,
  );
  if (totalDriftIssues > 0) {
    console.log("drift issue detail is recorded per-source in capture_manifest.json -- review before closing the gate");
  }
  return 0;
}

process.exit(main());
