# P1.G3 — Precor / Panatta official brand adapters

Status: CLOSED (pending push/remote-sync verification and `pm_set_gate` — see §6 below).

Purpose (per GPT-PM's guidance following P1.G2's close): extend the shared
P1.G2 adapter pipeline with the remaining 2 P0.G3-registered brands
(Precor, Panatta), sourcing REAL official manufacturer data, emitting
`StagedEquipmentModelCandidate` records only. Per GPT-PM's explicit steer:
prioritize direct first-party evidence over maximizing candidate count —
"15-20 well-corroborated records beat 40 where half is snippet-only."

This gate is a small, additive extension of P1.G2's already-reviewed
shared infrastructure (`contracts.ts`, `source_capture.ts`,
`registry_check.ts`, `source_drift.ts`, `candidate_mapper.ts`,
`conflicts.ts`, `adapter_runner.ts`, `run_all.ts`) — none of that
infrastructure changed in this gate.

## 1. What was built

| File | Role |
|---|---|
| `functions-equipment-identity/src/p1/adapters/precor_adapter.ts` (NEW) | Thin wrapper around the shared `runAdapter()`, brandId `precor`. |
| `functions-equipment-identity/src/p1/adapters/panatta_adapter.ts` (NEW) | Thin wrapper around the shared `runAdapter()`, brandId `panatta`. |
| `functions-equipment-identity/src/p1/adapters/run_all.ts` (extended) | `runAllP0BrandAdapters` now runs 6 adapters, not 4 — see its own header comment on why the name stays gate-neutral. |
| `functions-equipment-identity/scripts/generate_p0_brand_candidates.js` (renamed from `generate_p1_g2_artifacts.js`) | Same deterministic, atomic-write generator — renamed because its output now spans 2 P1 sub-gates' adapters, not just P1.G2's. |
| `core/equipment_identity/p1/source_captures/precor_spec_tables.json` (NEW) | 14 real records — see §3. |
| `core/equipment_identity/p1/source_captures/panatta_official_product_pages.json` (NEW) | 12 real records — see §3. |
| `functions-equipment-identity/src/__tests__/p1_g3_adapters.test.ts` (NEW) | Per-adapter tests for Precor/Panatta. |
| `functions-equipment-identity/src/__tests__/p1_g2_adapters.test.ts` (extended) | Combined-pool assertions updated from 48/4-sources/5-brands to 74/6-sources/7-brands. |

No new `source_registry.json` entries were needed — unlike P1.G2, the two
P0.G3-seeded entries for these brands (`precor_spec_tables`,
`panatta_official_product_pages`) already point at the real, correct
official locations; confirmed live during this gate (the Precor entry's
`canonicalUrl` is the exact PDF this gate fetched and parsed; the Panatta
entry's `canonicalUrl` is the domain root, a reasonable "official product
pages" reference for a domain-wide-blocked site whose specific product
pages were located via search).

## 2. Real candidate data gathered

26 new candidates, both brands well above the ≥4/brand pilot minimum
(§5.7):

| Brand | brandId | Candidates | Retrieval | Source |
|---|---|---|---|---|
| Precor | `precor` | 14 | **DIRECT_FETCH** | Genuinely fetched and parsed (via `pypdf`, installed for this gate's research) the real official spec-table PDF at `static.precor.com/spec-tables/en-us/Precor-2022-NA-Spec-Tables.pdf` — Resolute™ Strength Selectorized, Vitality™ Series Selectorized, and Discovery™ Plate Loaded lines: leg press ×3, leg extension ×2, chest press ×2, lat pulldown/row ×4, shoulder press ×1, biceps curl ×1, hack squat ×1 |
| Panatta | `panatta` | 12 | SEARCH_INDEX_SNIPPET | panattasport.com returned HTTP 403 on every direct fetch attempt (root domain and individual product pages alike) — located via WebSearch only; every `sourceUrl` is a specific, real product page whose own model code is visible directly in the URL path (`/en/product/{CODE}.html`), self-verifying against fabrication: chest press ×2, leg press ×2, leg extension ×1, leg curl ×1, lat pulldown ×4, row ×1 |

Per GPT-PM's own instruction, `productLineRaw` is deliberately omitted on
every Panatta record: the code-prefix-to-product-line correlation (e.g.
`1SC` vs `1MTH` vs `1FE`) was visible but not confidently verifiable from
search snippets alone — left blank rather than guessed, honoring the
"never fabricate to reach a target" invariant even at the cost of a
slightly less complete record.

Combined pool after this gate: **74 candidates across 7 brands, 6 sources,
0 conflicts, 0 drift issues** (verified by regenerating
`core/equipment_identity/p1/candidates/*.json` after this gate's changes,
not merely computed on paper).

## 3. Precor PDF extraction note

`static.precor.com/.../Precor-2022-NA-Spec-Tables.pdf` could not be read
via `WebFetch`'s own text extraction (it returned only PDF stream/metadata
noise, no legible text) — the PDF itself, however, downloads successfully
and contains real, well-structured spec tables once parsed properly. This
gate installed `pypdf` (`pip install --user pypdf`, a local research tool,
not a project dependency — `functions-equipment-identity`'s own
`package.json`/`requirements` are untouched) and extracted real page text
directly, e.g.:

```
RSL0602  LEG PRESS
Product Weight  826 lb / 375 kg
Weight Stack    400 lb / 182 kg
Dimensions      77 x 48 x 58 in
```

This is why Precor's 14 records are honestly DIRECT_FETCH — real,
directly-fetched-and-parsed manufacturer data, not a search snippet.

## 4. Tests

`npm test` (`functions-equipment-identity`) — **218/218 passing** (up from
213 after P1.G2's fixes). New: `p1_g3_adapters.test.ts` (per-adapter
candidate counts/brandIds/retrievalMethod, `primaryTypeId` absence,
Panatta's sourceUrl-contains-modelCode self-consistency check).

`scripts/equipment_identity/` (Python) — **106/106 passing**, unchanged
count — `verify_deployment_isolation.py`'s isolation-probe fix from P1.G2
globs `core/equipment_identity/p1/source_captures/*.json`, so it picked up
both new fixtures automatically with zero code change needed.

## 5. Review record

2 independent parallel specialist reviews (silent-failure-hunter,
code-reviewer), proportionate to this gate's smaller, purely-additive
surface (R1–R2: reuses already-reviewed P1.G2 shared infrastructure
unchanged). No BLOCKER/MAJOR/MINOR code or data defect found by either
reviewer. Two disclosed reviewer-tool limitations (no shell/WebFetch
access in the delegated review sessions) were independently already
covered by this session's own direct verification (test suites actually
executed; the Precor PDF actually fetched and parsed; the Panatta URLs
actually returned by live WebSearch calls, not fabricated).

**1 MINOR fixed:** a `git mv` rename left 3 stale filename references in
this gate's own predecessor evidence doc
(`P1_G2_OFFICIAL_P0_ADAPTERS.md`) — fixed to reference the current
filename with a note explaining the rename, while leaving the doc's
review-record prose (which narrates what happened AT THE TIME of P1.G2's
own review, when the file was still named `generate_p1_g2_artifacts.js`)
historically accurate rather than rewritten.

**1 MINOR explicitly deferred, documented as known residual:**
`source_drift.ts` has no drift signal for a fixture that omits
`productLineRaw` on every single record (Panatta's case) — the detector
was designed to catch unrecognized values, not absent optional ones, and
this is explicitly out of this gate's scope (shared P1.G2 infrastructure,
not touched here). A future drift-detector enhancement could add a
low-severity "source never claims a product line" signal; not pursued now.

**Confirmed clean by both reviewers independently:** the `run_all.ts`
extension is a plain unconditional array addition (no filter/dedup/
try-catch that could drop or miscount a run); the script rename left no
dangling reference inside `functions-equipment-identity/` itself (only in
prose docs, fixed above); both fixtures' internal consistency holds
(distinct model codes, no duplicate-key collisions, Panatta's URL-contains-
code self-verification); the two pre-existing `source_registry.json`
entries were correctly left untouched and their `canonicalUrl`s genuinely
match what this gate's fixtures cite.

## 6. Close conditions

- [x] Real official-manufacturer data only (14 DIRECT_FETCH Precor records
      from an actually-parsed PDF, 12 SEARCH_INDEX_SNIPPET Panatta records
      with self-verifying URLs).
- [x] No new candidate ever assigns `primaryTypeId`.
- [x] No new `source_registry.json` entries needed; existing P0.G3 entries
      confirmed accurate, left untouched.
- [x] `npm test` — 218/218. `python -m pytest scripts/equipment_identity/
      -q` — 106/106.
- [x] Combined pool re-verified after this gate's changes: 74 candidates,
      7 brands, 0 conflicts, 0 drift issues.
- [x] 2 independent reviews, 0 BLOCKER/MAJOR, 1 MINOR fixed, 1 MINOR
      explicitly deferred with rationale.
- [x] GPT-PM's forward requirement for P1.G5 (SEARCH_INDEX_SNIPPET alone
      cannot select a model into the canonical 50) applies to Panatta's 12
      records the same way it applies to Technogym/Matrix's — carried
      forward, not re-litigated here.

## Rollback

Revert this gate's commit. No production data, no Firestore writes, no
deploy occurred. `run_all.ts`'s extension and the script rename are both
easily reversible without affecting P1.G2's own closed state.
