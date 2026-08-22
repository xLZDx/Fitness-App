# P1.G2 — Official P0 brand adapters

Status: CLOSED (pending push/remote-sync verification and `pm_set_gate` — see §8 below).

Purpose (per GPT-PM's P1 implementation prompt and
`SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P1.G2): build adapters for the 4 brand groups already registered in P0.G3's
`source_registry.json` (Technogym; Matrix Fitness; Life Fitness / Hammer
Strength; Core Health & Fitness / Nautilus), sourcing REAL official
manufacturer data, emitting `StagedEquipmentModelCandidate` records only
(P1.G1's contract) with full field-level provenance. Adapters never assign
an authoritative `primaryTypeId` (§5.8) — only non-binding `typeHints`.

## 1. What was built

| File | Role |
|---|---|
| `functions-equipment-identity/src/p1/adapters/contracts.ts` | `RawCaptureRecordSchema`, `SourceCaptureFixtureSchema` — the raw, honestly-labeled evidence shape an adapter consumes. |
| `functions-equipment-identity/src/p1/contracts.ts` (extended) | New `RetrievalMethodSchema` (`DIRECT_FETCH` \| `SEARCH_INDEX_SNIPPET`) and an optional `ProvenanceRef.retrievalMethod` field — additive, P1.G1-era provenance stays valid without migration. |
| `functions-equipment-identity/src/p1/adapters/source_capture.ts` | `loadSourceCaptureFixture` — validates a statically-imported fixture, computes a deterministic `fixtureSha256` over the re-serialized content. |
| `functions-equipment-identity/src/p1/adapters/registry_check.ts` | `assertRegisteredOfficialManufacturerSource` — structural guard: an adapter may only source from a real, registered `OFFICIAL_MANUFACTURER` entry. |
| `functions-equipment-identity/src/p1/adapters/source_drift.ts` | `detectRecordDrift` — flags a `typeHintsRaw` id absent from the P0 functional-type snapshot, and (added during review) a `lifecycleStatusRaw` value absent from the known lifecycle-phrase table. |
| `functions-equipment-identity/src/p1/adapters/candidate_mapper.ts` | `mapRecordToCandidate` — the raw-record → `StagedEquipmentModelCandidate` transform; the only file that touches `../contracts.ts`. |
| `functions-equipment-identity/src/p1/adapters/conflicts.ts` | `detectConflicts` — cross-candidate `modelCode` collision detection (same-brand vs cross-brand), never auto-resolved. |
| `functions-equipment-identity/src/p1/adapters/adapter_runner.ts` | `runAdapter` — the one shared execution path every per-brand adapter wraps. |
| `functions-equipment-identity/src/p1/adapters/{technogym,matrix,life_fitness_hammer_strength,nautilus}_adapter.ts` | Thin per-brand wrappers around `runAdapter`. |
| `functions-equipment-identity/src/p1/adapters/run_all.ts` | `runAllP0BrandAdapters` — runs all 4, assembles the combined candidate pool, conflict report, and capture manifest. |
| `functions-equipment-identity/scripts/sync_p1_generated.js` | `sync`/`--check` for two build-time inputs: `core/equipment_identity/p0/source_registry.json` and every `core/equipment_identity/p1/source_captures/*.json` fixture, mirrored into `src/generated/` (same pattern as P1.G1's `sync_p0_type_snapshot.js`). |
| `functions-equipment-identity/scripts/generate_p1_g2_artifacts.js` | Runs the built adapter pipeline once, writes deterministic output atomically (temp-file + rename per file). Renamed to `generate_p0_brand_candidates.js` in P1.G3 once a second gate's adapters started feeding the same shared pool — see `P1_G3_...md`. |
| `core/equipment_identity/p1/source_captures/*.json` | 4 real, hand-authored fixtures (48 records total) — see §3. |
| `core/equipment_identity/p1/candidates/{p0_brand_candidates,adapter_conflicts,capture_manifest}.json` | Generated output — 48 candidates, 0 conflicts, 0 drift issues. |
| `core/equipment_identity/p0/source_registry.json` (extended) | 4 new `UNREVIEWED` entries for the real product-catalog domains (see §2) — the 4 original P0.G3 entries (stale/wrong-purpose pages) are left completely untouched. |
| `scripts/equipment_identity/rights.py` | `load_registry` now rejects a duplicate `sourceId` (found during review — pre-existing gap, not introduced by this gate's new entries, which are confirmed unique). |
| `scripts/equipment_identity/verify_deployment_isolation.py` | P0.G6 isolation-probe fix (same class as P1.G1's own self-caught fix): the temp-copy build proof now also mirrors `source_registry.json` and the 4 P1 source-capture fixtures, since `npm run build` gained a second `check:p1-generated` step that reads them. |
| `functions-equipment-identity/src/__tests__/p1_g2_*.test.ts` | 6 new test files — see §6. |

`functions-equipment-identity/src/p1/catalog_repository.ts` (the
publication write-path) is never imported by anything under `adapters/` —
enforced by a dedicated structural test (`p1_g2_no_publish_import.test.ts`),
not just author discipline.

## 2. Source registry — new entries

The 4 original P0.G3 entries for these brands point at stale or
wrong-purpose pages (interior-design/planning microsites, not product
catalogs) — confirmed live during this gate (a `shop.corehandf.com` URL now
301-redirects). Per §7.2, the fix is to ADD a new registry entry, never edit
an existing P0.G3-closed one:

| New sourceId | canonicalUrl | Retrieval |
|---|---|---|
| `technogym_product_catalog` | `https://www.technogym.com/` | SEARCH_INDEX_SNIPPET only — technogym.com returned HTTP 403 on every direct attempt (product page, category page, a regional variant, robots.txt, a support-download endpoint) |
| `matrix_fitness_product_catalog` | `https://us.matrixfitness.com/` | SEARCH_INDEX_SNIPPET only — pages fetch (HTTP 200) but return an empty client-rendered JS shell with no retrievable body |
| `life_fitness_hammer_strength_product_catalog` | `https://www.lifefitness.com/en-us/catalog/strength-training` | DIRECT_FETCH — every product page fetched returned real server-rendered content |
| `core_health_fitness_nautilus_product_catalog` | `https://www.corehandf.com/collections/nautilus` | DIRECT_FETCH — real server-rendered content, including a Leverage-line listing table |

All 4 are `OFFICIAL_MANUFACTURER` / priority `P1`, `legalReviewState:
"UNREVIEWED"`, every permission boolean `false` (P0.G3's fail-closed
convention). `python -m pytest scripts/equipment_identity/test_rights.py -q`
— 32/32 passing (30 pre-existing + 2 new uniqueness tests).

## 3. Real candidate data gathered

48 `StagedEquipmentModelCandidate` records total, all with a real
manufacturer model code (`modelCodeRaw` is required, not optional — a
codeless record carries no exact-model identity per §5.7):

| Brand | brandId | Candidates | Source |
|---|---|---|---|
| Technogym | `technogym` | 9 | Selection line (900/700/MED variants) — leg press, chest press, lat pulldown |
| Matrix Fitness | `matrix` | 17 | Ultra/Go/Versa/Magnum/Aura lines — leg press, leg extension, lat pulldown, chest press |
| Life Fitness | `life-fitness` | 5 | Insignia + Axiom series — leg press, chest press, lat pulldown |
| Hammer Strength | `hammer-strength` | 4 | Plate-Loaded + Select lines — leg press, chest/back, lat pulldown, chest press |
| Nautilus | `nautilus` | 13 | Leverage + Instinct lines — chest/incline/decline press, lat pulldown, row, shoulder press, biceps curl, ab crunch, leg press, calf, leg extension |

5 distinct `brandId`s (Life Fitness and Hammer Strength are two brands
sharing one corporate `sourceId`, per P0.G3's own registry convention).
`typeHints` are drawn only from ids that actually exist in the frozen P0
functional-type snapshot (`leg_press`, `chest_press_machine`,
`lat_pulldown`, `leg_extension`, `seated_row_machine`,
`shoulder_press_machine`, `bicep_curl_machine`, `ab_crunch_machine`,
`calf_raise_machine`) — one record (Nautilus "Leverage Deadlift Shrug") has
no confident real-ontology match and correctly carries an empty
`typeHints` array rather than a guessed one.

No candidate carries a `primaryTypeId` field — structurally impossible
(`StagedEquipmentModelCandidateSchema.strict()`), not just author
discipline (P1.G1). `sourceConfidence` is `"OFFICIAL"` for every candidate
(source-class signal, independent of and never conflated with
`legalReviewState`, which stays `UNREVIEWED` on every underlying source).

## 4. Determinism & conflicts

`runAllP0BrandAdapters()` is a pure function of the 4 committed fixtures:
two independent runs against unchanged fixtures produce byte-identical
`candidates`/`captureManifest` output (`p1_g2_adapters.test.ts`).
`detectConflicts` found **0 conflicts** across the real 48-candidate pool
(verified, not merely assumed — `adapter_conflicts.json`'s
`conflictCount: 0`) and **0 drift issues** (`capture_manifest.json`'s
`driftIssueCount: 0` for every source).

## 5. Provenance & honesty invariants

- `retrievalMethod` (`DIRECT_FETCH` \| `SEARCH_INDEX_SNIPPET`) on every
  provenance ref honestly distinguishes a page an adapter's author actually
  fetched and read from one only located via a search-engine index — never
  claims a content hash (`sourceContentSha256`) for bytes that were never
  actually fetched (that field is never populated by this gate's adapters
  at all).
- `provenance[0].fields` lists only the candidate fields a specific mapping
  actually populated from real evidence. Fixed during review:
  `catalogStatusCandidate` is now listed only when the raw lifecycle string
  actually matched a known phrase — a raw value present but unrecognized
  still safely falls back to `catalogStatusCandidate: "UNKNOWN"` (never
  guessed) but is no longer claimed as sourced.
- `specsRaw` (captured technical spec sheets — dimensions, weight, stack)
  has no corresponding field on `StagedEquipmentModelCandidate` in P1 and
  is never referenced in `fields` — it stays evidence in the fixture, not
  modeled on the candidate yet.
- `candidateId` is `deriveCandidateId(sourceId + "::" + brandId,
  sourceStableKey)` (fixed during review — previously `sourceId` alone),
  so a multi-brand source (Life Fitness + Hammer Strength) can never
  collide two different brands' candidates onto the same id even if they
  happen to share a model-code string. The publicly-exposed
  `sourceStableKey`/`provenance.sourceId` fields are unaffected — they
  still carry the real, uncombined captured values.

## 6. Tests

`npm test` (`functions-equipment-identity`) — **213/213 passing** (up from
202 pre-review-fixes), including a new `pretest` hook (`check:p0-snapshot
&& check:p1-generated`, fixed during review — `npm test` used to silently
run against stale generated copies if a source file was edited without
re-syncing). 6 new test files:

- `p1_g2_source_capture.test.ts` — fixture validation, determinism,
  malformed-`capturedAt` rejection (added during review).
- `p1_g2_candidate_mapper.test.ts` — modelCode preservation, no
  `primaryTypeId`, provenance completeness/accuracy, lifecycle mapping,
  brand-scoped `candidateId` (added during review).
- `p1_g2_conflicts.test.ts` — same-brand/cross-brand duplicate detection,
  normalization, never-auto-resolved.
- `p1_g2_registry_check.test.ts` — unregistered sourceId rejected,
  non-`OFFICIAL_MANUFACTURER` source rejected (SEARCH_DISCOVERY,
  MARKETPLACE_3D, WGER).
- `p1_g2_adapter_runner.test.ts` (added during review) — brand-scoped
  duplicate detection, lifecycle drift detection.
- `p1_g2_adapters.test.ts` — per-brand candidate counts/brandIds/
  retrievalMethod, combined-pool determinism, uniqueness, 0 conflicts on
  real data.
- `p1_g2_no_publish_import.test.ts` — structural: no adapter file ever
  references `catalog_repository.ts`/`writeEquipmentModel`/
  `EquipmentModelStore`.

`scripts/equipment_identity/` (Python) — **106/106 passing** (was 104),
including 2 new `rights.py` duplicate-`sourceId` tests and the
`verify_deployment_isolation.py` fix's 10 tests, all still green.

## 7. Review record

4 independent parallel specialist reviews (type-design-analyzer,
silent-failure-hunter, python-reviewer, code-reviewer), each with no access
to the others' findings (round 1 independence per §6 of the operator's
global agent-routing contract). No BLOCKER found by any reviewer.

**Confirmed fixed (1 MAJOR, corroborated independently by two reviewers
from different angles):**
- Lifecycle-status drift was silently swallowed two ways: (a)
  `provenance[0].fields` claimed `catalogStatusCandidate` was populated
  from source evidence even when the raw value was unrecognized and
  silently fell back to `UNKNOWN`; (b) `detectRecordDrift`'s per-record
  detail (which record, which field, why) was computed and then discarded
  down to a bare integer (`driftIssueCount`) before ever reaching a
  persisted artifact. Fixed: `fields` only claims `catalogStatusCandidate`
  when the raw value actually matched; `source_drift.ts` now also flags an
  unrecognized `lifecycleStatusRaw`; `capture_manifest.json` now carries
  full per-issue detail (`candidateId`, `productNameRaw`, `field`,
  `reason`), not just a count.

**Confirmed fixed (4 MINOR):**
- `candidateId` could theoretically collide across two different brands
  sharing one multi-brand source if they happened to share a model-code
  string (latent, not triggered by real data) — fixed by folding `brandId`
  into the `deriveCandidateId` hash input (§5).
- The within-fixture duplicate-`modelCodeRaw` guard used exact-string
  comparison and was scoped to the whole fixture rather than per brand —
  fixed to normalize (trim + uppercase, matching `conflicts.ts`) and scope
  by `(brandId, modelCode)`, so a legitimate cross-brand model-code
  coincidence no longer hard-crashes the whole adapter run.
- `SourceCaptureFixtureSchema.capturedAt` was validated far more weakly
  (`z.string().min(1)`) than the `IsoTimestampSchema` it flows into
  downstream — fixed to use `IsoTimestampSchema` directly, so a malformed
  value fails at fixture-load time with a clear error, not deep inside
  candidate mapping.
- `generate_p1_g2_artifacts.js` (renamed to `generate_p0_brand_candidates.js`
  in P1.G3, see §1's note) wrote 3 related output files with 3
  separate non-atomic `fs.writeFileSync` calls — fixed to write via
  temp-file + rename per file.
- (`rights.py`, python-reviewer) No `sourceId` uniqueness check existed in
  `load_registry` — fixed; the 4 new entries this gate adds are confirmed
  unique against all pre-existing entries, so this was a latent gap, not a
  live defect in this gate's own data.
- (documentation only) `source_capture.ts`'s doc comment overclaimed that
  `JSON.parse` "preserves key order" — corrected to describe V8's actual
  spec-defined enumeration order (integer-index-like keys reorder ahead of
  insertion order); no functional change, since the hash only needs
  same-process-to-same-process determinism, which was never actually
  broken.

**Positive findings, explicitly confirmed clean by multiple reviewers
(not merely unchecked):**
- No adapter can ever emit a candidate carrying `primaryTypeId` —
  structurally impossible via `.strict()`, confirmed by 3 of 4 reviewers
  independently probing for a bypass.
- `UNREVIEWED` rights data is never read, upgraded, or treated as more
  trusted by any adapter file — `registry_check.ts` checks only
  `sourceId`/`sourceClass`, never `rights`.
- No swallowed exceptions anywhere in the pipeline — every thrown error
  (schema validation, unregistered source, unrecognized brand, duplicate
  key, sync/build failure) propagates to a nonzero exit; a partial-run
  failure in `generate_p1_g2_artifacts.js` happens before any file write,
  so prior artifacts are never left stale-but-claiming-fresh.
- `verify_deployment_isolation.py`'s extension is complete — traced
  against `tsconfig.json`'s actual `include` set, confirmed no remaining
  relative-path, repo-external build-time dependency is left uncovered.

## 8. Known residual items (not fixed this gate, documented per operator
convention — see P1.G1's own §"known residual items")

- `rights.py`'s validation is more permissive than the JSON Schemas it
  mirrors in two respects (python-reviewer, MINOR): it never rejects
  unknown/extra keys on a `rights`/source record (the schema declares
  `additionalProperties: false`), and it validates `canonicalUrl` only as
  "non-empty string," not as a real URI (the schema declares `"format":
  "uri"`). No live defect — this gate's 4 new entries have no extra keys
  and use well-formed URLs — but a real fix would mean running actual
  `jsonschema` validation as a supplement, out of scope for this gate.
- `typeHints` best-effort mapping (Technogym/Matrix line-name → functional
  type) is hand-authored per this gate's own research, not derived from
  any automated matcher — correct today (verified against the real P0
  snapshot, 0 drift issues) but will need re-verification if the P0
  ontology changes.
- 20 real Matrix product names beyond what was captured here exist on
  us.matrixfitness.com per search-snippet discovery, and the Nautilus
  Instinct line has 15 more product names known (from a listing page) but
  not yet resolved to individual model codes — not pursued further in this
  gate since the pilot only needs ≥4 models/brand with margin (§5.7); G5's
  reconciliation stage may want a larger candidate pool.

## 9. Close conditions

- [x] Real official-manufacturer data only, no fabrication (5 brands, 48
      candidates, every one with a real model code and honest
      `retrievalMethod`).
- [x] Adapters never assign `primaryTypeId` — structurally enforced, test
      confirmed.
- [x] Full field-level provenance, `fields` accurate to what was actually
      sourced (fixed during review).
- [x] Sources may stay `UNREVIEWED` (P0.G3 rights carry-forward posture
      preserved — no P1 process flips `legalReviewState`).
- [x] Existing P0.G3 registry entries left untouched.
- [x] `functions-equipment-identity/src/index.ts` still exports zero
      production Cloud Functions (unchanged by this gate).
- [x] `npm test` — 213/213. `python -m pytest scripts/equipment_identity/
      -q` — 106/106.
- [x] 4 independent reviews, 0 BLOCKER, 1 MAJOR + 8 MINOR all fixed or
      explicitly deferred with rationale.

## Rollback

Revert this gate's commit. No production data, no Firestore writes, no
deploy occurred — pure source-controlled TypeScript/JSON. The 4 new
`source_registry.json` entries are additive; removing them does not affect
any P0.G3-closed entry.
