# P0.G1 — Current recognition baseline freeze

Status: CLOSED (pending push/remote-sync verification — see §6 below).
Source commit at freeze time: `c6059c5efa648773cb80c09a8f8bbed5e36ee8f8`.

This note is the human-readable companion to the two generated artifacts in
this directory. It does not restate their content; it records how they were
produced, what they mean, and what they do not cover.

## 1. What this gate freezes

Before exact-identity work (P1+) touches anything, this gate captures what the
**current, already-shipping** recognition pipeline actually does — derived
from source, not from a description of intended behavior. The generator is
`scripts/equipment_identity/recognition_baseline.py`; it is re-run, never hand-edited.

Pipeline order, as read from the actual orchestration controller
(`mobile/lib/features/visual_equipment/state/visual_equipment_providers.dart`,
`VisualEquipmentController.classifyFilePath`):

1. **Text anchor** (`machine_text_anchor.dart`) — OCR-based string matching
   against the catalogue. Silent unless the OCR text names exactly one
   machine; three-or-more distinct name hits collapse to a generic result
   rather than guessing.
2. **Hybrid visual classifier** (`gemini_equipment_service.dart`,
   `HybridVisualEquipmentService`) — cloud (Gemini) tried first, on-device
   TFLite (`equipment_v1.tflite` via `MlkitVisualEquipmentService`) as the
   offline fallback.
3. **Machine describer** (`machine_describer.dart`) — last resort for an
   out-of-catalogue item; distinguishes `ScanOutcome.unknown` (nameable but
   not in the catalogue) from `.noEquipment`.

## 2. Generated artifacts

| File | Payload SHA256 (compact form) |
|---|---|
| `recognition_baseline_v1.json` | `961880b7b4602c40739aacdbf24238349dd8408c7cd7dc97d2724931324266ed` |
| `legacy_real_gym_regression_inventory.json` | `00c7d1c4c7c3a93c252e6080dc0ede7962be590ee3df6e87dd45c59e2a9b8c27` |

Both hashes moved twice from their first-committed values: once during the §7 review round (new `liveMode` fact,
`offlineFallbackNeverReportsConfident` → `photoPathOfflineFallbackNeverReportsConfident`, plus the legacy-inventory
transcription-verification hardening), and once more for the module rename below (`generatedBy`'s value changed in
both files, which is the only content difference that rename produced).

**Module renamed 2026-08-22, during P0.G2 work**: `baseline.py` → `recognition_baseline.py`. This repository's
`scripts/` tree has no package `__init__.py` files, so a bare module name is global once two directories both do
`sys.path.insert(0, <their own dir>)` — `scripts/ct1/baseline.py` already owned the name `baseline`, and running
both test suites in one pytest session silently shadowed it in `sys.modules`, breaking `scripts/ct1/review_batch.py`'s
own `from baseline import ...`. Caught by running the full test suite together rather than each new suite in
isolation; fixed by rename, not by working around the collision.

Both hashes are computed by `canonical_json.payload_sha256` (compact,
sorted-key JSON — insensitive to pretty-printing/line-ending drift; see that
module's own docstring). Regenerate with:

```
python scripts/equipment_identity/recognition_baseline.py --write
python scripts/equipment_identity/recognition_baseline.py --check   # must report both hashes above
```

`recognition_baseline_v1.json` records: the functional catalogue's hash and
type count (69 types, `mobile/assets/data/equipment.json`); the
`MODEL_REGISTRY.json` hash; 10 scanner-contract file hashes with a
human-readable role each; the shipped `equipment_v1.tflite` artifact's actual
SHA256/byte size (cross-checked against `MODEL_REGISTRY.json`'s own recorded
`artifact_sha256`/`artifact_bytes` — the generator fails loudly if they
disagree); an explicit `NOT_SHIPPED` record for `equipment_recognition@v2`
(present in the registry, absent from this checkout — never inferred as
deployed); and a set of "generic invariants" extracted from the real source
text of each contract file (scan outcome states, match source values, offline
fallback never reports `confident`, text anchor runs before the classifier,
text-anchor ambiguity semantics, and a sweep confirming no exact-identity
concept — `identityLevel`, `EXACT_MODEL`, `RecognitionAuthorityTuple`,
`evidenceLane`, `recognitionSessionId`, `EquipmentIdentityResponse` — exists
anywhere under `visual_equipment/` or `equipment/` yet).

Two related but distinct "offline never confident" facts are recorded
separately, not folded into one (see §7 — this split is itself a review
fix): `photoPathOfflineFallbackNeverReportsConfident` covers only the
single-photo path (`ScanResult.fromMatches`'s `answeredOffline` guard);
`liveMode` covers the continuous viewfinder path separately, and records
that it has **no** equivalent guard — it is always on-device (no cloud
call exists in `mlkit_live_equipment_service.dart`) and its `settled`
reading is written straight into recognition history by
`scanner_page.dart`'s `ref.listen`, the same way a confident photo result
is remembered.

## 3. Legacy 30-photo set

`legacy_real_gym_regression_inventory.json` classifies the operator's 30
real-gym photos (`core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md`,
captured 2026-07-30 and 2026-08-06) as:

```
datasetRole:          LEGACY_REAL_GYM_REGRESSION
trainingAllowed:       false
sealedBlindEvaluation: false
promotionHoldout:      false
```

This is deliberately **not** the P6 sealed blind test set — it is a frozen
regression/reference sample, per B1's own closing line: "эти 30 фото — тест,
не обучающая выборка" (these 30 photos are a test, not a training set).
Tests 6/7 in `test_baseline.py` assert these three booleans can never flip to
`true` from this generator.

**Raw files**: the directory B1 records (`D:\Downloads\Photos-1-001 (1)`) is
confirmed absent from this checkout (`Path(...).exists()` returns `False` at
generation time). Per the plan's own instruction, this does **not** fail
P0.G1 — the inventory binds instead to B1's own recorded evaluation text
(`sourceDocSha256` in the artifact), and `rawContentHashes` is honestly
`UNAVAILABLE_IN_THIS_CHECKOUT`, never fabricated. No absolute operator-local
path is required by CI; the generator only reads it to record a presence
boolean.

The 4 individually-labeled frames in the artifact (3 confident-wrong
predictions plus the operator's own screenshot) are hand-transcribed from
B1's table and cross-verified against B1's own text by
`recognition_baseline._verify_legacy_frames` (also exercised as
`test_legacy_frames_are_grounded_in_the_b1_note_text`) — a transcription slip
fails the generator loudly instead of silently drifting from source.

Headline measurement, carried into `measurementSummary` for the record: none
of the 4 labeled machines are among the model's 10 trained classes; minimum
observed top-1 confidence across all 30 photos was 0.215 — still above both
deployed thresholds (0.05 live, 0.10 photo) — so a confidence threshold alone
cannot produce an honest "I don't know."

## 4. Tests run

Python (`scripts/equipment_identity/test_baseline.py`, the 9 minimum cases
from the gate contract plus 6 supporting cases, one of which
— `test_5b_missing_registry_key_fails_loudly_not_silently` — was added
during the review round in §7):

```
python -m pytest scripts/equipment_identity/test_baseline.py -q
15 passed, 1 warning in 1.37s
```

The one warning is an upstream `pytest-asyncio` deprecation notice, unrelated
to this module.

Flutter, focused scanner/visual-equipment suite (discovered by listing
`mobile/test/features/visual_equipment/` rather than assuming a stale file
list — 16 test files plus `scanner_page_test.dart`):

```
cd mobile
flutter test test/features/scanner_page_test.dart test/features/visual_equipment/
All tests passed!  (274 tests, 00:07)
```

This is the full existing regression suite for the pipeline this baseline
freezes — text anchor, ML Kit OCR bridge, scan outcome/result semantics,
scan controller orchestration, Gemini/hybrid cloud path, recognition history,
machine card flow (including the F016 unscreened-movement-description guard),
visual match ranking. None of these tests were modified by this gate; they
are cited as evidence the baseline's claims about current behavior are the
same claims the existing suite already enforces.

## 5. Known limitations

- The baseline covers **structural/contract-level** facts (file hashes,
  branch order, enum states) — it does not re-run or reproduce B1's own
  30-photo confidence measurement; that measurement is cited, not repeated.
- `equipment_recognition@v2` is recorded as `NOT_SHIPPED, presentInThisRepoCheckout: false`
  purely from `MODEL_REGISTRY.json` plus a local path existence check — this
  baseline does not attempt to independently verify v2's training/eval
  history, only its shipped/unshipped status.
- The exact-identity token sweep (`_exact_identity_absent`) is a text search
  over two source trees (`visual_equipment/`, `equipment/`) for a fixed token
  list. It proves these concepts are absent from *those trees today*; it is
  not a repo-wide guarantee and is expected to start returning hits once
  P1+ introduces `RecognitionAuthorityTuple`/`evidenceLane` — at which point
  this baseline stops being regenerated and instead serves as the frozen
  "before" reference the v4.4 plan calls for.
- `_extract_block`'s balanced-bracket parser handles Dart's named-parameter
  `}) {` closing syntax correctly (verified during development — an earlier
  naive regex silently truncated a function body at the parameter list's own
  closing brace); it has not been exercised against every Dart syntax shape
  in the repository, only the specific contract files this baseline reads.
  **Its failure mode on an unhandled shape is not guaranteed to be loud**:
  the counter treats every `{`/`}`/`(`/`)` character uniformly regardless of
  whether it sits inside a string or comment, so a future stray brace-like
  character added inside a string/comment in one of the swept methods could
  in principle produce a silently truncated-or-extended body rather than a
  raised `BaselineError` (flagged by `python-reviewer` in §7 below; not fixed
  this round — string/comment-aware brace counting is a real change to a
  function every extractor in this module depends on, scoped out as
  disproportionate to what caused the finding: no swept file currently
  contains an unbalanced brace/paren inside a string or comment).

## 6. Rollback / failure handling

- Both generators (`build()`, `build_legacy_inventory()`) raise
  `BaselineError` and exit non-zero on any missing file, hash mismatch, or
  malformed source — there is no silent partial baseline. `main()` returns 1
  in that case and writes nothing.
- `--check` never writes; it only compares a freshly-built payload against
  the committed file (ignoring `sourceCommit`, which is expected to change
  commit-to-commit) and fails loudly on drift. CI should run `--check`, never
  `--write`, so a source change that silently invalidates the baseline is
  caught rather than auto-updated.
- Both generators are pure reads over the repository tree — `build()` and
  `build_legacy_inventory()` never write to disk themselves; only `--write`
  does, and only to the explicit `--out` target. `test_9_baseline_does_not_alter_source`
  asserts the four source files this gate depends on are byte-identical
  before and after calling both generators.
- If a future change to the scanner pipeline breaks `--check`, the correct
  response is to regenerate (`--write`) only after confirming the change is
  intentional — a red `--check` is this gate's designed failure mode, not a
  bug to route around.

## 7. Review record (P0.G1 §6.5)

The project-scoped `fitness-flutter-reviewer`/`fitness-data-scientist` agents
were not available to the Agent tool in this session despite existing under
`.claude/agents/`; three global specialists were run independently in
parallel instead, covering the same ground from complementary angles:
`flutter-reviewer` (Dart-source correctness of every structural claim),
`python-reviewer` (generator/test-suite correctness), `silent-failure-hunter`
(the master plan's "no silent degradation" principle specifically).

**Round 1 — findings, all independently verified against real source before
being accepted:**

- **MAJOR** (flutter-reviewer) — `offlineFallbackNeverReportsConfident` was
  scoped only to the single-photo path but named/described as if pipeline-
  wide; the live-viewfinder path (`mlkit_live_equipment_service.dart` /
  `RecognitionSmoother`) has no equivalent guard and its `settled` reading is
  written to recognition history exactly like a confident result. **Verified**
  by direct read of `live_recognition.dart` (no `offline`-branch exists) and
  `scanner_page.dart:422-429` (`ref.listen` → `_remember(...)` on any
  `settled` reading, no confidence/source distinction). **Fixed**: split into
  `photoPathOfflineFallbackNeverReportsConfident` (renamed, same derivation)
  and a new `liveMode` fact block, derived by
  `_live_mode_has_no_offline_downgrade_guard()` (`recognition_baseline.py`), which itself
  fails loudly if the live service ever gains a cloud reference or an
  `offline`-branch appears in `RecognitionSmoother.add`.
- **MAJOR** (silent-failure-hunter + independently, python-reviewer) —
  `MODEL_REGISTRY.json`'s `bundled`/`champion`/`class_count`/
  `supports_unknown_or_abstain` fields were read with `dict.get()` (no
  default), so a missing key silently resolved to `False`/`None` instead of
  raising — and `test_5` re-derived its "expected" value through the same
  `.get()` call, so it could never disagree with a wrong result. **Verified**
  by reading `recognition_baseline.py`'s original lines directly. **Fixed**: added
  `_require()` (raises `BaselineError` naming the missing field), routed all
  four fields through it, and rewrote `test_5` to assert the raw registry
  dict actually contains each key before comparing.
- **MAJOR** (silent-failure-hunter + independently, python-reviewer) —
  `_verify_legacy_frames` only checked `frameId`/`modelPrediction` occurred
  *somewhere* in B1's text; `modelConfidence`/`groundTruth` were never
  checked, and even the checked fields used "occurs anywhere in the
  document" rather than "occurs in THIS frame's own row" — a value swapped
  between the two `treadmill`-predicted frames would pass undetected.
  **Verified** by reading B1's table directly. **Fixed**: replaced with
  `_parse_b1_table_rows()`, a real per-row markdown-table parser (two regexes
  for the two row shapes B1 uses), and rewrote `_verify_legacy_frames` to
  check each frame's prediction/confidence/ground-truth-anchor against ITS
  OWN parsed row, not the document as a whole.
- **MINOR** (python-reviewer) — `test_1`/`test_1b` determinism checks hashed
  `sourceCommit` along with everything else, so a concurrent commit landing
  between the two `build()` calls (this workspace runs concurrent sessions)
  could fail the test on a real-but-irrelevant change. **Fixed**: both tests
  now strip `sourceCommit` before hashing, mirroring what `--check` already
  did.
- **MINOR** (python-reviewer) — `_scan_outcome_states`/`_match_source_values`
  used a `\n\}`-terminated regex, the exact unsafe construct
  `_extract_block`'s own docstring warns about. **Fixed**: routed both
  through `_extract_block`'s balanced-brace counter instead.
- **MINOR** (python-reviewer) — `_extract_block`'s brace counter is not
  string/comment-aware, so its failure mode on pathological input is a
  silent wrong result, not necessarily a loud error; the prior "not exercised
  against every Dart syntax shape" limitation note didn't disclose that
  specific risk. **Fixed**: §5's limitation note now says so explicitly.
  **Not fixed** (scoped out, disproportionate to the actual current risk —
  no swept file trips it today): making the counter string/comment-aware.
- **NIT** (python-reviewer) — `item["id"]` on a malformed catalogue entry
  raises a bare `KeyError` rather than `BaselineError`; still fails loudly
  (non-zero exit), just an inconsistent message. Not fixed — reviewer's own
  assessment was this needs no required change.

**Round 1 also explicitly checked and found no material issue** on: current-
vs-desired-behavior framing; whether the legacy 30-photo set could ever be
mistaken for/upgraded into a P6 sealed blind test set; whether the three
legacy-classification booleans are structurally impossible to flip (they
are — Python literals, not derived); whether `rawContentHashes` could ever
become a fabricated hash (it cannot — exactly two possible values); whether
`genericInvariants` are genuinely proven by source inspection rather than
rubber-stamped (they are, traced by hand against the real `.dart` sources by
two independent reviewers); `canonical_json.py`'s hashing/serialization
soundness; the `--out`/`--target all` argument handling.

**Round 2**: not needed — round 1's findings were fixed in one pass (all
three reviewers converged on largely the same two MAJOR issues
independently, which is itself corroborating evidence the findings were
real rather than reviewer noise), verified by re-running the full test suite
(15/15 green) and regenerating both artifacts (`--check` clean). No BLOCKER
or unresolved MAJOR/MINOR remains. 1 of the allowed 5 fix/review loops used.

## 8. Close conditions (P0.G1 §6.6)

- [x] Baseline generation is deterministic (test 1, 1b).
- [ ] Artifacts committed (pending — this doc is written pre-commit;
      flip once the commit in §8's close-condition line below lands).
- [x] Current scanner focused tests green (274/274, §4 above).
- [x] Legacy holdout is explicitly `trainingAllowed: false`,
      `sealedBlindEvaluation: false` — `NO_TRAINING`, not sealed.
- [x] Independent specialist review (3 global specialists substituting for
      the unavailable `fitness-flutter-reviewer`/`fitness-data-scientist`
      project agents — see §7 above). 2 MAJOR + 3 MINOR found and fixed in
      round 1; no unresolved BLOCKER/MAJOR/MINOR.
- [x] Rollback/failure handling documented (§6 above).
- [ ] Commit pushed and remote exact SHA verified (`git fetch origin` +
      `git rev-list --left-right --count HEAD...origin/master` = `0 0`) —
      done at gate close time, recorded in `core/DECISION_LOG.md`, not
      duplicated here to avoid a second source of truth that can drift.
