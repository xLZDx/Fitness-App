# Pre-P1.G5 direct-corroboration pass

Status: CLOSED. Outcome: **P1.G5 BLOCKED_ON_SOURCE_EVIDENCE** (honest, computed
result -- not a lowered threshold or a padded count).

Per GPT-PM's own framing when it accepted P1.G4 as CLOSED: this is **not a
new gate** ("pre-G5 evidence remediation/corroboration pass under the
already-issued GO"). No `pm_set_gate` call for this pass; reported directly
back to GPT-PM instead.

## 1. The precondition (carried forward, not re-litigated)

Before P1.G5 canonical-50 pilot selection may start: Technogym, Matrix, and
Panatta must EACH independently reach >=4 directly-corroborated
(DIRECT_FETCH-class) official models, AND the total directly-corroborated
pool across all brands must reach >=50. SEARCH_INDEX_SNIPPET evidence alone
can never satisfy either floor. GPT-PM's explicit fallback: if unmet after
genuine effort, the correct state is P1.G5 BLOCKED_ON_SOURCE_EVIDENCE --
never a lowered bar or a padded count.

Starting point (after P1.G2-G4): Life Fitness 5, Hammer Strength 4,
Nautilus 13, Precor 14 direct = 36 total. Technogym 0/9, Matrix 0/17,
Panatta 0/12 direct (all SEARCH_INDEX_SNIPPET-only).

## 2. What this pass actually did

Real, direct attempts to fetch first-party official documentation for
Technogym, Matrix, and Panatta -- not a re-classification of existing
snippet evidence.

**Matrix: floor MET (4/4), 4 new real DIRECT_FETCH corroborations.**
`us.matrixfitness.com` product pages return HTTP 200 but only an empty
client-side-JS-rendered shell (already documented in P1.G2's registry
entry). `content.johnsonfit.com` -- Matrix Fitness is a brand of Johnson
Health Tech Co. -- is a genuinely reachable, first-party document CDN.
Downloaded and `pypdf`-parsed 2 real PDFs:
- **G7 Strength Service Manual** (187 pages, 48,735,275 bytes, sha256
  `7cc826fb...`): real printed spec tables for G7-S70 Leg Press (75"L x
  43"W x 52"H, 882 lbs), G7-S13 Chest Press (63"L x 57"W x 52"H, 827 lbs),
  G7-S33 Lat Pull Down (61"L x 47"W x 77"H, 858 lbs).
- **G3-S70 Leg Press Sell Sheet, Rev 2.0** (339,451 bytes, sha256
  `b0cefeda...`): real spec table (79"L x 42"W x 72"H, 920 lbs net,
  385 lbs weight stack), genuinely branded "matrixfitness.com".

All 4 model codes (G7-S70, G7-S13, G7-S33, G3-S70) match existing P1.G2
Matrix candidates exactly -- this is independent corroboration of
already-staged candidates, not new candidates.

**Technogym: floor NOT MET (0/4) after genuine, repeated attempts.**
`www.technogym.com` returns a blanket HTTP 403 from CloudFront on every
path tried: site root, `en-US`/`en-INT` product pages (including the exact
page multiple search results pointed at, with the real model code `MNAP`
in the URL), and 2 separate PDF download paths (`marketing-support/
services/DirectFileDownload.php`, `media/pdf-catalogues/...`).
`corporate.technogym.com` (investor relations) IS reachable but carries no
product specification content. Third-party dealer mirrors of
Technogym-authored documents were found (`innovativefit.com`,
`keystonefitness.ca`) but deliberately NOT counted -- the precondition
requires a directly-retrieved FIRST-PARTY document; a dealer's re-hosted
copy is not first-party retrieval even when the content originates from
the manufacturer.

**Panatta: floor NOT MET (0/4) after genuine, repeated attempts.**
`panattasport.com` returns a blanket HTTP 403 on every path (documented in
P1.G3; reconfirmed here). `panattafitness.com` (a plausible alternate
first-party domain, by analogy with Matrix's `johnsonfit.com` finding)
redirects to a dead 404 page rather than real content.

**Total direct pool: 40 (was 36, +4 from Matrix) -- still short of 50.**

## 3. What was built

| File | Role |
|---|---|
| `core/equipment_identity/p1/direct_corroboration/matrix_johnsonfit_pdf_corroboration.json` (NEW) | Real fixture: 4 corroboration records backed by 2 unique downloaded PDF documents (3 records share one document's sha256 -- G7-S70/G7-S13/G7-S33 all come from the same G7 manual; G3-S70 comes from a separate sell sheet), each with sourceUrl, the sha256 computed from the bytes downloaded during this pass (format-validated by test, not independently re-hashed from a second fetch), byte count, retrievedAt, page locator, and the actual extracted spec-table text. |
| `scripts/equipment_identity/canonical_selection_eligibility.py` (NEW) | Computes, per real candidate in the 74-candidate combined pool, a two-factor `canonicalSelectionEligible`: (1) the candidate itself has real DIRECT_FETCH evidence, AND (2) the pool-wide brand/total floors are met. Never assigns `primaryTypeId`/`modelId`, never resolves a conflict -- both stay P1.G5's own job. |
| `scripts/equipment_identity/test_canonical_selection_eligibility.py` (NEW) | 22 tests. |
| `core/equipment_identity/p1/candidates/canonical_selection_eligibility.json` (generated, committed) | The real, computed artifact GPT-PM asked for. |

## 4. Why "eligible" is fail-closed, not just "has evidence"

A candidate needs BOTH factors true. Even Matrix's 4 newly, genuinely
corroborated candidates are marked `canonicalSelectionEligible: false`
today, because the POOL-wide preconditions (Technogym/Panatta >=4,
total >=50) remain unmet -- one well-corroborated brand does not unlock
canonical selection on its own. This matches GPT-PM's own test scenario
almost verbatim: "direct official corroboration -> may become true,
ASSUMING remaining G5 conditions pass." Today they don't pass, so nothing
is eligible, and the artifact's own `p1G5Status` field says
`BLOCKED_ON_SOURCE_EVIDENCE` -- computed as data, not asserted as prose.

## 5. Tests

`python -m pytest scripts/equipment_identity/test_canonical_selection_eligibility.py -q`
-- **22/22 passing**. `python -m pytest scripts/equipment_identity/ -q`
(full namespace regression) -- **163/163 passing** (was 141 before this
pass).

## 6. Review record

2 independent parallel specialist reviews (silent-failure-hunter,
python-reviewer).

**1 MAJOR found and fixed (silent-failure-hunter):** every real-data test
ran against today's state where `overall_preconditions_met()` is always
`False` -- a future regression collapsing the two-factor
`eligible = has_direct and preconditions_met` down to just
`eligible = preconditions_met` would pass the entire suite silently,
undetectable until the pool genuinely clears 50, at which point every
candidate (including ones with zero real evidence) would incorrectly flip
eligible in one commit. Fixed: a new test monkeypatches
`overall_preconditions_met` to force the pool gate open and proves through
the real `build_eligibility_artifact()` pipeline that a candidate WITH
evidence becomes eligible while one WITHOUT evidence stays ineligible even
with the gate open.

**2 MINOR found and fixed (silent-failure-hunter):** an unmatched
PDF-corroboration fixture entry (a typo'd `modelCode`, or a candidate that
no longer exists upstream) previously failed silently -- the brand's
direct count would just quietly drop with no error and no trace of which
fixture entry was orphaned. Fixed: `build_eligibility_artifact()` now
asserts every fixture key matched a real candidate and raises
`EligibilityError` naming the orphaned entry/entries otherwise. A
`modelCode: null` fixture entry (which would collide with any real
candidate that itself has no modelCode, silently misattributing
corroboration) is now rejected outright at load time rather than accepted
as a wildcard key.

**2 MINOR found and fixed (python-reviewer):** `_original_direct_fetch_
provenance()` picked the first DIRECT_FETCH provenance record with no
uniqueness check, asymmetric with the PDF-corroboration loader's own
duplicate guard -- harmless today (every real candidate has exactly one
provenance record, confirmed by grep) but would have silently resolved a
future ambiguous case by picking whichever came first. Fixed to raise
`EligibilityError` if a candidate ever carries more than one DIRECT_FETCH
record. Also fixed a static-typing key-type mismatch (`dict[tuple[str,
str], ...]` declared vs. the actual `tuple[str, str | None]` lookup key,
harmless at runtime but a real contract violation) by widening the
declared type to match.

**Both reviewers independently confirmed clean:** no swallowed exceptions
anywhere in the module (one exception-related construct, `EligibilityError`,
only ever raised, never caught); `overall_preconditions_met()`'s returned
boolean and reason strings cannot contradict each other (the boolean is
mechanically `len(reasons) == 0`); the atomic-write pattern correctly
reuses the exact fix applied to the sibling `wger_ingestion.py` module
earlier this session (`canonical_json.dump_pretty` + `os.getpid()`-based
temp filename -- neither of that module's own 2 MAJOR bugs was
reintroduced here); all 4 real sha256 values in the corroboration fixture
are well-formed 64-character lowercase hex (verified by exact-length
regex, not eyeballed); `direct_corroboration_for()`'s precedence (original
adapter provenance checked before the PDF-corroboration fixture) is
correct and genuinely exercised by a dedicated test; `sort_keys=True`
fully neutralizes the one dict-insertion-order nondeterminism found
(`directCorroborationCountsByBrand`'s key order in the committed artifact
is alphabetical, confirmed against the real file).

## 6b. GPT-PM devil's-advocate review (round 1, via `review.js`)

Per the operator's same-session instruction that GPT-PM should take a
devil's-advocate stance on every request/response, `review.js`'s
commit/push prompt template was extended earlier this session to
explicitly ask for that -- this was the first real round to exercise it,
and it delivered: a genuine, evidence-grounded BLOCKER plus 5 MAJOR
findings, not a rubber stamp.

**BLOCKER, real, unresolved by fixing code:** the diff sent for review was
truncated (485,783 real chars, over `review.js`'s `MAX_DIFF_CHARS`) --
GPT-PM correctly refused to certify a change it could not fully see. This
round's receipt still satisfies the commit gate (an attempt was made,
truncated or not -- the same "attempt, not success" policy the gate always
uses), but does **not** satisfy `--final` for push. A follow-up round
scoped to the actual commit (`--scope commit`, a far smaller diff than the
whole uncommitted working tree) is required before push.

**3 MAJOR findings, real and fixed:**
- First-party status was asserted in prose, never mechanically enforced --
  `content.johnsonfit.com` was never registered in `source_registry.json`,
  so nothing actually checked it the way every P1.G2/G3 adapter source is
  required to. Fixed: registered `matrix_johnsonfit_pdf_corroboration` as
  an `OFFICIAL_MANUFACTURER`-class source (Matrix Fitness's status as a
  Johnson Health Tech brand independently re-confirmed via JHT's own
  "Our Brands" page and Matrix Fitness's corporate LinkedIn, not assumed),
  and added `_assert_registered_official_manufacturer_source()`, checked
  against the real registry via `rights.load_registry()` every time the
  fixture loads.
- The floor counts distinct corroborated MODELS, not candidate rows -- no
  dedup guard existed. Fixed: `direct_corroboration_counts_by_brand()` now
  raises `EligibilityError` on any duplicate `(brandId, modelCode)` rather
  than silently double-counting (today's real pool has zero duplicates,
  confirmed by direct count: 74 candidates, 74 distinct pairs).
- `direct_corroboration_for()` set the corroboration record's `sourceId`
  equal to `sourceUrl` -- not the fixture's real, stable `sourceId`, so
  `sourceId` was never actually a stable identifier. Fixed to use the
  fixture's own top-level `sourceId`.

**1 MAJOR finding, confabulated -- verified false, not fixed:** GPT-PM
claimed `matrix_johnsonfit_pdf_corroboration.json` stores `sourceUrl` as
Markdown link syntax (`[https://...](https://...)`). Directly grepped the
real committed file and the real generated artifact -- both contain clean,
unwrapped URL strings on every line, no brackets anywhere. Likely an
artifact of ChatGPT's own reply UI auto-linkifying the URL when echoing it
back, misread as if it were the file's actual content. Not fixed, because
there was nothing to fix; recorded here rather than silently dropped, per
this project's own "verify a citation before accepting it" discipline.

**1 MAJOR finding, real observation but not a defect in this commit:**
GPT-PM flagged the reviewed diff as containing unrelated stale
`reports/*.html` files (including a `.local-untracked-backup.html`).
True of what was SENT to GPT -- `review.js`'s `buildDiff()` runs
`git diff HEAD` plus an `untrackedFilesBlock()` that sweeps in every
untracked file in the whole repository, not just the ones staged for this
commit. Those report files are untracked leftovers from earlier/other
sessions and were never staged here -- confirmed directly via `git status
--porcelain` and `git diff --cached --stat` immediately before committing:
the staged set is exactly the 6 files this pass intended. A real,
worth-knowing limitation of the review tool's diff scope, not a defect in
the actual commit.

**1 MINOR finding, real and addressed (doc language, not code):** the
evidence doc's phrasing implied all 4 sha256 values were independently
re-verified; in fact 3 of the 4 corroboration records share one document's
hash (only 2 unique PDFs were downloaded), and the hashes are the ones
computed from the bytes downloaded during this pass, not re-hashed from an
independent second fetch. §3 reworded to say this precisely; the
generated-file/format tests (`test_matrix_pdf_corroboration_sha256_values_
are_well_formed`) were always honestly scoped to format validation only,
never claimed content re-verification.

## 6c. GPT-PM devil's-advocate review (round 2, commit-scoped, via `review.js --scope commit`)

Round 1's BLOCKER (diff truncation, 485,783 chars over `review.js`'s
`MAX_DIFF_CHARS`) required a smaller, commit-scoped follow-up before
`--final`/push. The automated Playwright transport failed repeatedly this
round (browser/tab issues, documented in
`feedback-pmbridge-never-more-than-one-tab.md`); the operator manually
pasted the prepared commit-scoped diff+prompt into the working ChatGPT tab,
and the reply was retrieved via the safe `clipboard` transport (no browser
interaction). Real, substantive review: 3 MAJOR, no BLOCKER, no rubber
stamp.

**3 MAJOR findings, all real, all fixed:**

- The PDF-corroboration fixture loader validated `sourceId`/`sourceClass`
  (registered, OFFICIAL_MANUFACTURER) but nothing about each individual
  corroboration ROW -- `direct_corroboration_for()` unconditionally
  stamped every matching row as `retrievalMethod: DIRECT_FETCH` regardless
  of what it actually contained. A future row added under the
  already-registered Matrix source with an unrelated/wrong-domain
  `sourceUrl` or no real hash/byte-count/timestamp/locator would still
  count toward the per-brand/50-model floors. Fixed:
  `_assert_valid_corroboration_entry()` now validates, per row, that
  `sourceUrl` is `https` and shares its origin with the registered
  source's own `canonicalUrl`; `documentSha256` is 64 lowercase hex chars;
  `documentBytes` is a positive integer; `retrievedAt` is a parseable
  timestamp; `locator` is non-empty. The fixture's own top-level
  `retrievalMethod` field is now also checked (`== "DIRECT_FETCH"`) before
  any of its rows can be treated as direct evidence at all.
- The ORIGINAL P1.G2/G3 adapter-provenance path (36 of the 40 real direct
  candidates) was never routed through the same
  `_assert_registered_official_manufacturer_source()` check the new PDF
  path got -- it trusted the literal string `retrievalMethod ==
  "DIRECT_FETCH"` alone. Today's real adapters already enforce this at
  generation time (`registry_check.ts`'s own
  `assertRegisteredOfficialManufacturerSource`, called by every adapter
  via `adapter_runner.ts` -- verified by reading both files), so no real
  candidate was actually exploitable today; the finding stands because
  this Python module is itself the eligibility gate and must not depend
  on a different layer having already checked what it claims to enforce.
  Fixed: `direct_corroboration_for()` now calls the same registry check on
  `original["sourceId"]` before returning it.
- `rejectionReasons` under-reported why a snippet-only candidate was
  ineligible while the pool gate was also closed -- the pool-precondition
  reasons were appended only when `has_direct` was already true, so a
  candidate with zero evidence got only `NO_DIRECT_FETCH_CORROBORATION`,
  with no mention that the pool-wide floors (which gate every candidate,
  per §4 above) were also unmet. Fixed: both reason classes are now
  recorded independently whenever they apply.

Re-ran `canonical_selection_eligibility.py` after the fix: real counts
unchanged (`matrix: 4, hammer-strength: 4, life-fitness: 5, nautilus: 13,
precor: 14`, total 40) -- the stricter validation rejects nothing in
today's real, already-well-formed data; it only closes the door on future
malformed/fabricated rows. 9 new tests added (negative cases for each
validation rule, plus the two new registry-check paths and the
rejection-reasons completeness fix).

**Tests**: `scripts/equipment_identity/` 177/177 (was 168; 9 new).

Round 2 verdict: no BLOCKER, no unresolved MAJOR after fixes -- `--final`
can be passed for this round's receipt, clearing the push gate.

## 7. Close conditions

- [x] Real, genuine attempts made for all 3 named brands (Technogym,
      Matrix, Panatta) -- not just a re-read of existing evidence.
- [x] Matrix's 4 new corroborations are genuinely DIRECT_FETCH: real PDFs
      downloaded, real sha256 computed, real spec-table text extracted.
- [x] Technogym/Panatta's continued 0/4 status is honestly reported with
      the specific URLs/paths attempted and why each failed (403/dead
      link), not silently omitted.
- [x] This pass assigns no `primaryTypeId`/`modelId` and resolves no
      conflict -- verified structurally (`assignsPrimaryTypeIdOrModelId:
      false`, `resolvesConflicts: false` in the artifact itself, plus a
      test asserting no entry carries either field).
- [x] `python -m pytest scripts/equipment_identity/ -q` -- 177/177.
- [x] 2 independent agent reviews (silent-failure-hunter, python-reviewer),
      1 MAJOR fixed, 4 MINOR fixed.
- [x] GPT-PM devil's-advocate review, round 1: 3 MAJOR real and fixed, 1
      MAJOR confabulated (verified false, not fixed), 1 MAJOR a review-tool
      diff-scope artifact (not a commit defect), 1 MINOR doc-language fix.
      BLOCKER (diff truncation) resolved by round 2 (commit-scoped diff).
- [x] GPT-PM devil's-advocate review, round 2 (commit-scoped): 3 MAJOR real
      and fixed (per-row corroboration-evidence validation, original-
      provenance registry enforcement, rejectionReasons completeness). No
      BLOCKER, no unresolved MAJOR -- receipt marked `--final`, clearing
      the push gate.
- [x] Decision log entry recorded (`core/DECISION_LOG.md`).
- [x] Outcome reported to GPT-PM directly (not via `pm_set_gate` -- this
      is not a gate).

## Rollback

Revert this pass's commit. No production data, no Firestore writes, no
deploy occurred, and no P1.G1-G4 file was modified -- this pass is purely
additive (1 new fixture, 1 new module, 1 new generated artifact).
