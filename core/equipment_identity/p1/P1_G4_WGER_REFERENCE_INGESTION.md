# P1.G4 -- WGER_REFERENCE_INGESTION

Status: CLOSED (real ingestion built and closed, not deferred -- see §7).

Purpose (per the gate contract, `core/design/sptr_equipment_recognition_v4_1/
SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`,
lines 441-474): build a read-only exercise-enrichment staging area and a
mapping report from real wger public-API data, with per-object provenance
and license preserved. Classified POST_MVP_HIGH/ENRICHMENT -- explicitly
optional/parallel; does not block P2 or P1's own Epic exit. The gate's own
Story DoD sanctions closing this as `DEFERRED_NOT_REQUIRED` if genuine
ingestion cannot be closed honestly within reasonable effort. That escape
hatch was not needed: real wger data was genuinely reachable and a genuine
mapping was genuinely producible, so this gate closes for real.

## 1. What was built

| File | Role |
|---|---|
| `core/equipment_identity/p1/wger_staging/wger_equipment_raw.json` (NEW) | Real, fully-captured wger equipment vocabulary (12 entries). |
| `core/equipment_identity/p1/wger_staging/wger_muscle_raw.json` (NEW) | Real, fully-captured wger muscle vocabulary (15 entries). |
| `core/equipment_identity/p1/wger_staging/wger_license_raw.json` (NEW) | Real, fully-captured wger site-wide license vocabulary (5 entries). |
| `core/equipment_identity/p1/wger_staging/wger_exercise_translation_sample_raw.json` (NEW) | Real 57-entry English-language sample of wger's exercise-translation table (3323 real entries total -- a bounded staging sample, not exhaustive ingestion). |
| `scripts/equipment_identity/wger_ingestion.py` (NEW) | Pure function of the 4 raw fixtures above plus 2 already-committed repo files -- builds the T1 staging snapshot and the T2 4-dimension mapping report. No network call, no production write. |
| `scripts/equipment_identity/test_wger_ingestion.py` (NEW) | 35 tests covering T1 (license/provenance preservation), T2 (all 4 mapping dimensions), and generated-file integrity. |
| `core/equipment_identity/p1/wger_staging/staging_snapshot.json` (generated, committed) | T1 output. |
| `core/equipment_identity/p1/wger_staging/mapping_report.json` (generated, committed) | T2 output. |

No change to any P1.G1-G3 shared infrastructure (`functions-equipment-identity/`
is completely untouched by this gate). This gate is entirely new,
self-contained Python under `scripts/equipment_identity/`, matching the
established convention for read-only staging/reporting/registry work in this
namespace (`rights.py`, `provenance.py`, `canonical_json.py`).

## 2. Real data gathered

All 4 raw fixtures were captured by hand against the real, live wger public
API (`https://wger.de/api/v2/...`) via direct `curl`/`WebFetch` calls, not
generated or guessed:

- **Equipment** (`GET /api/v2/equipment/?format=json&limit=50`) -- the
  API reported `count=12`; all 12 returned in one page: Barbell, SZ-Bar,
  Dumbbell, Gym mat, Swiss Ball, Pull-up bar, "none (bodyweight exercise)",
  Bench, Incline bench, Kettlebell, Resistance band, Cable machine.
- **Muscle** (`GET /api/v2/muscle/?format=json&limit=30`) -- `count=15`, all
  15 returned: Anterior deltoid, Biceps brachii, Biceps femoris, Brachialis,
  Gastrocnemius, Gluteus maximus, Latissimus dorsi, Obliquus externus
  abdominis, Pectoralis major, Quadriceps femoris, Rectus abdominis,
  Serratus anterior, Soleus, Trapezius, Triceps brachii.
- **License** (`GET /api/v2/license/?format=json&limit=10`) -- `count=5`,
  all 5 returned: CC-BY-SA 3, CC-BY 4, CC-BY-SA 4, CC0, ODbL.
- **Exercise-translation sample** (`GET /api/v2/exercise-translation/
  ?format=json&language=2&limit=200`) -- 57 real English-language entries,
  client-side filtered from a 200-record raw page (see §3 for why the
  filtering had to be client-side).

## 3. Two real, verified API findings this gate honestly carries forward

**wger's own `language` query filter on `/exercise-translation/` is
unreliable at result-set sizes beyond a handful of records.** Confirmed
live and reproducibly, not a one-off glitch: `limit=3&language=2` returns
`[2, 2, 2]` (all English); `limit=10` returns `[2, 2, 2, 2, 2, 2, 1, 23, 2,
6]` (other languages leak in); `limit=200` returns 8 distinct language ids
mixed together. Worked around by fetching a larger raw page (`limit=200`,
200 raw results) and filtering to `language == 2` client-side in Python
before writing the fixture -- 57 of 200 raw results were genuinely English.
This is documented in the fixture's own `note` field, not silently
corrected without a trace.

**Individual exercise/exercise-translation records do not carry a resolved
per-object license in the live API response.** Every fetched record's
`license` key is `null` -- verified across 57 English-filtered records and
a separate 200-record unfiltered batch (257/257 null). wger's own GitHub
README states exercise/ingredient data is licensed "Creative Commons (see
individual entries)", and the real site-wide vocabulary of 5
Creative-Commons-family licenses is enumerated by `/api/v2/license/` -- but
the public API does not expose which of those 5 applies to a given record.
`licenseAuthor` (a contributor handle) is the only per-object attribution
value actually present. This is documented in the fixture's own
`licenseFieldGap` field, and is exactly what T3's tests hold the ingestion
to: `license: null` and `licenseAuthor` both preserved byte-identical,
never resolved or invented.

## 4. Mapping report (T2) -- 4 dimensions, real cross-referenced data

Two dimensions are **hand-curated** (genuine domain/anatomical knowledge,
each row independently checkable):

- **Equipment** (wger's 12 entries vs. `core/equipment_identity/p0/
  functional_type_snapshot_v1.json`'s 69 real ids): 6 MATCHED (Barbell,
  Dumbbell, Pull-up bar, Kettlebell, Resistance band, Cable machine), 2
  ALIAS_CANDIDATE (SZ-Bar->ez_curl_bar -- SZ-Bar is literally the German
  name for an EZ-curl bar; Swiss Ball->stability_ball -- established
  synonym), 3 UNMATCHED (Gym mat, Bench, Incline bench -- no confident SPTR
  counterpart), 1 NOT_APPLICABLE ("none (bodyweight exercise)" -- not real
  equipment, excluded from the ontology on purpose rather than force-mapped).
- **Muscle** (wger's 15 entries vs. SPTR's own 15-value muscle vocabulary,
  derived live from `mobile/assets/data/exercises_vendor.json`'s `muscles`/
  `primaryMuscles` fields across all 1887 exercises): 10 MATCHED, 3
  ALIAS_CANDIDATE (Obliquus externus abdominis->core and Rectus
  abdominis->core -- both commonly grouped under "core" in consumer fitness
  taxonomies; Soleus->calves -- a real anatomical fact, Soleus is a calf
  muscle alongside Gastrocnemius), 2 UNMATCHED (Brachialis, Serratus
  anterior -- no confident SPTR counterpart). Reverse-direction honesty:
  4 SPTR muscles (adductors, back, forearms, lower_back) are never
  referenced by any wger entry in this mapping -- surfaced explicitly in
  `sptrMusclesNeverReferenced`, not silently absent.

One dimension is **deterministic, not hand-curated** -- disclosed as
weaker evidence in its own `method` field:

- **Exercise** (the 57-entry English sample vs. SPTR's real 1887-exercise
  catalog, `mobile/assets/data/exercises_vendor.json`): normalized-title
  matching (lowercase, punctuation stripped) -- 6 MATCHED (exact normalized
  match), 11 ALIAS_CANDIDATE (substring containment, minimum 6-character
  normalized length), 40 UNMATCHED. With 1887 real SPTR exercises and 3323
  real wger translations, hand curation does not scale the way it does for
  the 12/15-entry equipment/muscle vocabularies -- this dimension is
  offered as staging candidates for human review, never a verified
  equivalence, and every `sptrMatchIds` entry is independently verified to
  reference a real id that actually exists in the catalog.

One dimension is **explicitly NOT_MODELED**, not fabricated:

- **Variation** -- wger's `variation_group` UUID groups mutually-
  substitutable exercise variants; SPTR's own exercise catalog has no
  corresponding grouping mechanism at all. Reported as `NOT_MODELED` with a
  real rationale per the gate's own "disagreements visible" AC, rather than
  silently omitted or given a fabricated one-off correspondence.

## 5. Tests

`python -m pytest scripts/equipment_identity/test_wger_ingestion.py -q` --
**35/35 passing** (30 initial + 5 added during review, see §6).

`python -m pytest scripts/equipment_identity/ -q` (full namespace regression)
-- **141/141 passing** (was 106 before this gate).

Covers: T1 license/provenance preservation (including the honest
`license: null` carry-through), no-mutation-of-raw-fixtures, every mapping
dimension's coverage completeness and cross-reference integrity against the
real P0 snapshot / real exercise catalog, determinism across repeated runs,
generated-file-matches-fresh-build for both committed JSON outputs, and a
structural no-network-call guard.

## 6. Review record

2 independent parallel specialist reviews (silent-failure-hunter,
python-reviewer), proportionate to this gate's scope (one new, fully
self-contained module with no shared-infrastructure blast radius).

**1 MAJOR found and fixed (silent-failure-hunter):** `build_equipment_
mapping_report()`/`build_muscle_mapping_report()` validated only the
forward direction of the classification/sptrId relationship (MATCHED/
ALIAS_CANDIDATE requires a real sptrId) with no reverse companion
(UNMATCHED/NOT_APPLICABLE requires sptrId to be None) -- a future
hand-edit could produce an internally self-contradictory row (e.g.
`classification: "UNMATCHED"` but a real, present `sptrId`) that would
sail through validation and be written into the committed report. Fixed
symmetrically in both functions; 2 new regression tests added.

**1 MAJOR found and fixed (python-reviewer):** `_write_json_atomic` used a
bespoke `json.dumps(..., sort_keys=False)` instead of this namespace's own
mandatory canonical writer (`canonical_json.dump_pretty`, `sort_keys=True`)
-- `canonical_json.py`'s own module docstring states every generator under
`scripts/equipment_identity/` must go through it, specifically because
sort-key determinism is "cheap to get right once and easy to get subtly
wrong six times." Verified the claim directly against `canonical_json.py`
before accepting it. Fixed: both generated files now go through
`canonical_json.dump_pretty`; both regenerated and byte-identical to a
fresh build. 1 new regression test added asserting on-disk bytes match
`dump_pretty`'s own output exactly, not just structural equality after a
second parse.

**1 MINOR found and fixed (python-reviewer):** the atomic-write temp
filename had no per-process uniqueness (`path.with_suffix(path.suffix +
".tmp")` always resolves to the same name), which could race under this
workspace's documented concurrent-session pattern (multiple Claude Code
sessions routinely operate on the same checkout). Fixed: temp filename now
embeds `os.getpid()`. 1 new regression test added asserting the pid appears
in the writer's own source and that no stray tmp file survives a
successful write.

**1 MINOR found and fixed (silent-failure-hunter):** `build_exercise_
mapping_report()` had no production-code floor against an empty/truncated
wger sample fixture -- only the test suite's hard-coded `==57` assertion
stood in the way, which does not run outside pytest. Fixed: the function
now raises `WgerIngestionError` on an empty `results` list (both the wger
sample and the SPTR catalog). 1 new regression test added.

**1 MINOR explicitly deferred, documented as known residual (python-
reviewer):** the exercise dimension's `_MIN_ALIAS_SUBSTRING_LENGTH = 6`
alias-candidate gate is one-directional (only the wger-side normalized
length is checked) and uses raw substring containment rather than
word-boundary tokenization -- two exercises sharing only a common 6+
character word fragment could theoretically produce a nonsensical
ALIAS_CANDIDATE pairing. No such false positive was found in the actual
57-entry sample. The reviewer's own assessment: "acceptable known
limitation as shipped, not a blocking defect," given the dimension's
`method` field already discloses it as weaker, non-auto-applied staging
evidence, and this is a read-only report with zero production blast
radius. Not fixed in this gate; a future enhancement could require the
SPTR-side normalized length to also clear the threshold, or tokenize on
word boundaries.

**Both reviewers independently confirmed clean:** no swallowed exceptions
anywhere in the module (zero `try`/`except` blocks; every failure mode
raises `WgerIngestionError` loudly or lets a natural exception propagate);
`_write_json_atomic`'s temp-file-then-`.replace()` pattern cannot leave a
corrupt/partial file on disk under a write failure; `Path.with_suffix`'s
double-suffix construction (`.json` + `.tmp` -> `.json.tmp`) is correct,
not a bug; no `frozenset`/`set` iteration order reaches generated JSON
without an intervening `sorted()` call, so output is deterministic across
runs and Python versions independent of the canonical-writer fix; every
`sptrMatchIds`/`sptrId` reference in every dimension points at a real id
that actually exists in its target vocabulary; the network-call structural
guard test is a legitimate (if trivially-evadable-by-deliberate-rename)
protection against an accidental live-fetch regression, not a fake check.

## 7. Why this closes for real rather than DEFERRED_NOT_REQUIRED

The gate's own DoD explicitly sanctions deferral if genuine ingestion
"cannot be closed honestly within reasonable effort." That was not the
case here: wger's public API was live and reachable, real data was
genuinely fetchable for all 4 dimensions the gate's own AC lists (equipment,
muscle, exercise, variation), and a genuine -- not fabricated -- mapping
was genuinely producible for 3 of those 4 dimensions, with the 4th
(variation) honestly reported as NOT_MODELED rather than forced. Deferring
would have been the wrong call given real ingestion was actually achievable.

## 8. Close conditions

- [x] No production write -- `stagingOnly: true`/`productionWrite: false`
      on every staging snapshot build; nothing in this gate touches
      Firestore, a Cloud Function, or any collection
      `functions-equipment-identity` exports (still zero production
      exports throughout P1).
- [x] Per-object provenance preserved -- every raw fixture and every
      staged record carries `sourceUrl`/`capturedAt`/`retrievalMethod`.
- [x] License preservation -- `license` (including the honest `null`) and
      `licenseAuthor` both carried through byte-identical, directly tested.
- [x] Mapping report covers matched/unmatched/alias/muscle/equipment/
      variation with disagreements visible (reverse-direction
      `sptrMusclesNeverReferenced`, explicit `NOT_MODELED` for variation).
- [x] No production reuse of wger content is unlocked by this gate --
      that stays a separate, future, explicitly license-gated decision.
- [x] `python -m pytest scripts/equipment_identity/ -q` -- 141/141.
- [x] 2 independent reviews, 2 MAJOR fixed, 2 MINOR fixed, 1 MINOR
      explicitly deferred with rationale.
- [x] Decision log entry recorded (`core/DECISION_LOG.md`).

## Rollback

Revert this gate's commit. No production data, no Firestore writes, no
deploy occurred, and no other gate's files were touched.
