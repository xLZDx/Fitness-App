# P0.G2 — ML provenance recovery / ratchet

Status: CLOSED (pending push/remote-sync verification — see §7 below).
Source commit at freeze time: see the commit this file was added in.

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G2): ratchet training/evaluation reproducibility **before** another
learned recognition component (a future equipment-identity model) is added
— without "fixing" `equipment_recognition@v1`/`@v2`'s already-documented
historical gaps. Nothing in this gate touches, reinterprets, or "recovers"
any UNKNOWN value `core/ml/SCANNER_PROVENANCE.md` already recorded; that
document did the hard, honest work already and this gate does not repeat it.

## 1. What this gate is, and is not

This gate does **not** invent a new ML governance system. It adds one
contract — a provenance manifest shape and a validator — for the model that
does not exist yet, and reuses everything that already governs
`equipment_recognition`:

| Reused, not duplicated | From |
|---|---|
| Lifecycle states + legal transitions (`TRANSITIONS`) | `scripts/ml/lifecycle.py` — imported directly (`provenance.TRANSITIONS is lifecycle.TRANSITIONS`, asserted by a test) |
| Git-backed commit existence check | `scripts/ml/training_run.py`'s `_commit_exists` — the exact function `training_run.validate` already uses to refuse ML-2a |
| Dataset addressability convention | `core/ml/DATASET_REGISTRY.json`'s `dataset_id`/`dataset_version`/`status` shape (referenced conceptually; a future equipment-identity dataset would register there the same way, not in a second registry) |
| `UNKNOWN` / `NOT_RECORDED` vocabulary | `MODEL_REGISTRY.json`'s own header rule: "Nothing here is fabricated. A value that is not known is stated as UNKNOWN, NOT_RECORDED or LEGACY" |

## 2. The contract

`core/equipment_identity/p0/equipment_identity_provenance_contract.schema.json`
documents the shape; `scripts/equipment_identity/provenance.py`'s
`validate_manifest()` is the actual enforcement (a static JSON Schema cannot
express "this commit must resolve in this repository" or "the evaluation
dataset must not equal the training dataset").

Every manifest declares a `provenanceClass`:

- **`FUTURE`** — a model that does not exist yet, or is being proposed for
  any lifecycle state. All 21 required fields must be present and non-
  placeholder (`UNKNOWN`/`NOT_RECORDED`/`LEGACY` refused outright). Six get
  real structural verification: `artifactSha256`/`datasetHash` (well-formed
  sha256), `artifactBytes` (positive int), `trainingCodeCommit` (must
  resolve to a real commit in this repository), `evaluationDatasets`
  (non-empty, must not contain `datasetId` itself), `trainingTimestamp`
  (must parse as an ISO-8601 date). Ten free-text fields (`task`,
  `architecture`, `artifactPath`, `trainingCodeLocation`, `datasetId`,
  `datasetManifest`, `dependencyPin`, `inputSchema`, `outputSchema`,
  `deploymentSurface`) get a non-triviality check (rejects a bare 1-2
  character value like `"x"`) but not deep semantic verification — this
  module does not confirm `artifactPath` exists on disk, for example.
- **`HISTORICAL_GRANDFATHERED`** — restricted to `(modelId, modelVersion)`
  pairs that ALREADY exist in `MODEL_REGISTRY.json`, checked against the
  real registry at validation time (`_grandfathered_registry_entries()`) —
  **not** self-declarable by whoever writes the manifest (see §6, a review
  round caught and closed exactly this gap). Placeholders are accepted for
  a genuinely-grandfathered entry. An already-`CHAMPION` legacy model (v1 —
  "champion by default rather than by evaluation", the same
  first-of-its-kind precedent `MODEL_REGISTRY.json` already records for
  `content_qa`) is accepted as historical fact, not demoted by this
  validator. What is refused: a HISTORICAL_GRANDFATHERED manifest claiming
  `CHALLENGER_CANDIDATE`, `SHADOW_READY`, `SHADOW`, or `PROMOTION_REVIEW` —
  moving a still-incomplete model FURTHER along the promotion track is a
  fresh decision, and a fresh decision needs real evidence, not inherited
  slack from a model that predates this governance.

`manifest_from_registry_entry()` is a read-only remap of a real
`MODEL_REGISTRY.json` entry (snake_case) into this schema's shape
(camelCase) — it does not invent data, and `provenance.py` never writes to
`MODEL_REGISTRY.json`, `DATASET_REGISTRY.json`, or anywhere else.

## 3. What this gate proves about the existing registry, today

Running `python scripts/equipment_identity/provenance.py`:

```
equipment_recognition@v1: HISTORICAL_GRANDFATHERED, promotable=False
equipment_recognition@v2: HISTORICAL_GRANDFATHERED, promotable=False
```

- v1's `training_code_commit: UNKNOWN` remains exactly that — this gate does
  not touch it, and the validator accepts it as historical fact rather than
  demanding it be resolved retroactively (it cannot be; the training
  pipeline was never under version control, per `SCANNER_PROVENANCE.md`).
- v1's `lifecycle_state: CHAMPION` is accepted, not rejected — it is already
  shipped, recorded fact, not a claim this validator is being asked to
  authorize.
- v2's `deployment_status: NOT_SHIPPED` and `lifecycle_state: EVALUATED`
  remain exactly that; `promotable: False` means v2's incomplete provenance
  (`architecture: NOT_RECORDED`, `input_schema_version: NOT_RECORDED`) can
  never by itself justify moving it to `CHALLENGER_CANDIDATE` — a real
  provenance record would be required first, same as any new model.

## 4. Tests run

```
python -m pytest scripts/equipment_identity/test_provenance.py -q
23 passed
```

Covers the gate contract's 8 fixture cases (complete future manifest passes;
missing dataset hash / artifact hash / training-code-commit-with-no-
permitted-historical-status each fail; a FUTURE manifest with a
`NOT_RECORDED` field pretending `CHAMPION`-ready fails; legacy v1's
`UNKNOWN` values are accepted as historical, not promotable; legacy v2
remains `NOT_SHIPPED`; the validator never rewrites the registry), 9
supporting cases from the initial build (bogus-but-well-formed commit
rejected; self-evaluation rejected; empty `evaluationDatasets` rejected;
unknown `provenanceClass` rejected; v1's `CHAMPION` state specifically not
rejected by grandfathering; a grandfathered manifest cannot claim a
promotion-track state; `manifest_from_registry_entry` does not mutate its
input; `TRANSITIONS` is the identical object from `scripts/ml/lifecycle.py`,
not a redeclared copy; `main()` runs clean against the real registry), plus
6 regression cases added during the review round in §6 (a trivial free-text
field like `"x"` fails; an unparseable `trainingTimestamp` fails; a
fabricated model cannot launder through `HISTORICAL_GRANDFATHERED` — the
BLOCKER's own reproduction, now a permanent test; v1's real `null`
`rollback_target` survives the remap as `None`, not `"NOT_RECORDED"`; a
genuinely-absent `rollback_target` key still defaults to `"NOT_RECORDED"`;
a wrongly-typed `rollbackTarget` is rejected as missing).

Existing ML governance suites, unmodified, run alongside to confirm no
regression:

```
python -m pytest scripts/ml/test_ml_contracts.py scripts/ml/test_scanner_provenance.py scripts/ml/test_evaluation_report.py -q
86 passed
```

Full `scripts/` Python suite (359 tests across `scripts/ml`, `scripts/ct1`,
`scripts/equipment_identity`) run together to catch cross-suite interference
— see §5, this is how the module-rename defect below was actually found:

```
python -m pytest scripts/ml/ scripts/ct1/ scripts/equipment_identity/ -q
359 passed
```

One pre-existing, unrelated failure was observed and deliberately left
untouched: `scripts/review/test_clinical_import.py::test_the_checked_in_worklist_is_the_one_the_catalogue_produces`
fails at the last-committed HEAD (`f23130b`) with none of this gate's
changes present — confirmed by `git stash` and re-running that one test in
isolation. Out of scope for P0.G2 (a different subsystem, review-worklist
generation, unrelated to ML provenance); not fixed here per this project's
own discipline of not touching unrelated behavior.

## 5. A real defect found and fixed during this gate: `scripts/ct1/baseline.py`

While writing `provenance.py`'s tests, running the full `scripts/` suite
together (rather than each new test file in isolation, which is what P0.G1
had been verified with) surfaced an import collision:
`scripts/ct1/review_batch.py` does `from baseline import DATA, REPO, load,
run_checks`. `scripts/equipment_identity/baseline.py` (P0.G1's generator)
shares the exact bare module name `baseline` — this repository's `scripts/`
tree has no package `__init__.py` files, so each test file's own
`sys.path.insert(0, <its own directory>)` makes module names global across
the whole tree. Whichever `baseline` module Python imports first gets cached
in `sys.modules["baseline"]`; when both directories' tests ran in one pytest
session, `scripts/ct1`'s tests could receive `equipment_identity`'s
`baseline.py` instead of their own, and failed with
`ImportError: cannot import name 'DATA' from 'baseline'`.

**Fixed by rename**, not by working around the collision:
`scripts/equipment_identity/baseline.py` → `recognition_baseline.py`.
Updated: the module's own docstring and `generatedBy` payload fields (both
committed JSON artifacts regenerated, hashes changed as a result — see
`P0_G1_BASELINE.md` §2), `test_baseline.py`'s import, and every reference in
`P0_G1_BASELINE.md`. Re-verified: `python -m pytest scripts/ml/ scripts/ct1/
scripts/equipment_identity/ -q` → 359 passed, and `find scripts -name
"*.py" | xargs -n1 basename | sort | uniq -d` → no remaining duplicate
module basenames anywhere in `scripts/`.

This is recorded here, in P0.G2's own note, rather than only in P0.G1's,
because P0.G2 is the gate that found it — P0.G1's own review rounds (three
independent specialists) ran each new test file against the existing
Flutter/Python suites it knew to check, but none of them ran the *new*
Python test file alongside *other* `scripts/` directories' suites in one
process, which is what this collision needed to surface.

## 6. Review record (P0.G2 §7.4)

Same substitution as P0.G1: the project-scoped `fitness-data-scientist` and
`silent-failure-hunter` agents GPT's prompt named were checked again and
remain unavailable to the Agent tool in this session (still present under
`.claude/agents/`, still not resolvable — the same gap P0.G1 flagged for a
future session to re-check). `silent-failure-hunter` **is** available as a
global agent (it is one of P0.G1's own three substitutes), so it was reused
directly rather than substituted a second time; `python-reviewer` stood in
for `fitness-data-scientist`'s ML/data-correctness angle, since the gate's
actual content (a Python provenance validator, not a domain-fitness
question) is squarely that reviewer's territory.

Questions asked, per the gate contract — answered here with the FIXED code's
actual behavior (see the findings below for what was true before the fix):
- Can a future model reach promotion with missing provenance? — No:
  `validate_manifest` refuses any placeholder value, any 1-2-character
  free-text field, and any unparseable `trainingTimestamp` for a `FUTURE`
  manifest; refuses a `HISTORICAL_GRANDFATHERED` manifest claiming a
  promotion-track state; and — after the fix below — refuses
  `HISTORICAL_GRANDFATHERED` entirely for any `(modelId, modelVersion)` not
  already in `MODEL_REGISTRY.json`.
- Is historical `UNKNOWN` being laundered into a recovered fact? — No:
  `manifest_from_registry_entry` reads `MODEL_REGISTRY.json` verbatim and
  never writes to it (confirmed structurally by both reviewers independently
  — no `open(..., "w")`/`.write_text`/`json.dump` anywhere in the file);
  `test_validator_never_rewrites_registry` asserts the file's bytes are
  unchanged after every validation call in the suite.
- Are dataset/artifact hashes actually binding? — For `FUTURE`: yes,
  `_looks_like_sha256` structurally enforced (both reviewers independently
  confirmed no bypass, including uppercase-hex handling), plus
  `trainingCodeCommit` checked against real git history via the same
  function `training_run.validate` uses. For `HISTORICAL_GRANDFATHERED`: not
  re-verified here — that verification already happened in
  `SCANNER_PROVENANCE.md`'s own investigation and is not repeated.
- Is this duplicating existing lifecycle machinery? — No: `TRANSITIONS` and
  `_commit_exists` are imported, not redeclared; `test_lifecycle_states_match_scripts_ml_lifecycle`
  asserts object identity (`is`, not `==`), and both reviewers independently
  confirmed this is a genuine shared reference.

### Round 1 findings — both reviewers run cold, independently, no shared context

**BLOCKER / MAJOR (both reviewers converged independently)** — `HISTORICAL_GRANDFATHERED`
was entirely self-declared: nothing checked a manifest's `(modelId,
modelVersion)` against the real registry before granting the exemption. A
hand-built manifest for a brand-new, completely fabricated model
(`modelId: "equipment_identity"`, every substantive field literally the
string `"UNKNOWN"`) claiming `provenanceClass: HISTORICAL_GRANDFATHERED` +
`lifecycleState: CHAMPION` passed `validate_manifest` cleanly — reproducing
exactly ML-2a (unverifiable provenance reaching a "validated" state), the
failure mode this whole gate exists to prevent, just laundered through a
self-asserted class label instead of a missing field. **Verified by direct
reproduction** before accepting: ran the exact fabricated manifest through
`validate_manifest` and confirmed it returned `{"ok": True, ...}`. **Fixed**:
added `_grandfathered_registry_entries()`, which reads `MODEL_REGISTRY.json`
fresh on every call (never cached/hardcoded) and restricts
`HISTORICAL_GRANDFATHERED` to `(modelId, modelVersion)` pairs actually
present there. Re-ran the same fabricated manifest after the fix — now
raises `ProvenanceError`. Permanent regression test:
`test_a_fabricated_model_cannot_launder_through_historical_grandfathered`.

**MAJOR (both reviewers independently)** — 12–15 of the 21 `FUTURE`-required
fields got only a presence check, not a content check; a non-empty, non-
placeholder but content-free value (`"x"`, `"?"`, `"TBD"`) passed silently,
contradicting the doc's and docstring's own "every field must be a
concrete, verifiable value" claim. **Fixed**: added a non-triviality check
(`_looks_trivial`, minimum 3 non-whitespace characters) for the 10 free-text
fields, and an ISO-8601 parse check for `trainingTimestamp`. The doc's claim
(§2 above) was also corrected to state precisely which fields get deep
structural verification vs. non-triviality-only, rather than repeating the
overclaim. Not claimed as fully closed: full semantic verification (does
`artifactPath` exist on disk, is `task` a real task name) remains out of
scope, stated explicitly rather than implied away.

**MAJOR (python-reviewer)** — `manifest_from_registry_entry`'s
`entry.get("rollback_target") or "NOT_RECORDED"` silently relabeled v1's
deliberately-recorded `rollback_target: null` ("No previous version exists.
This is v1." — `MODEL_REGISTRY.json`'s own note) as the placeholder string
reserved for genuinely unknown values, making the `_is_missing` exemption
written specifically to preserve that `None` dead code for the one entry it
was meant to describe. **Fixed**: `entry.get("rollback_target", "NOT_RECORDED")`
— `.get`'s own default only fires when the key is absent, preserving a real
`None`. Regression test: `test_manifest_from_registry_entry_preserves_a_real_null_rollback_target`
asserts `manifest_from_registry_entry(v1)["rollbackTarget"] is None`.

**MINOR (python-reviewer)** — `_is_missing`'s `rollbackTarget` exemption
returned `False` (not missing) for ANY present value, not just `None`/a
string, looser than its own inline comment claimed. **Fixed**: narrowed to
`not (value is None or isinstance(value, str))`. Regression test:
`test_rollback_target_of_the_wrong_type_is_treated_as_missing`.

All four findings verified against real source/behavior before being
accepted (not taken on either reviewer's word alone), fixed in the same
round, and locked in with new regression tests — 6 added, `test_provenance.py`
now 23 tests, all green, alongside the full 359-test `scripts/` suite (§4).
1 of the allowed 5 fix/review loops used. No unresolved BLOCKER/MAJOR/MINOR.

The one real defect this gate's own process surfaced before review even
ran (§5, the module-name collision) was fixed immediately, not deferred.

## 7. Close conditions (P0.G2 §7.5)

- [x] Final AC/DoD complete: manifests are rebuildable/deterministically
      validated (17/17 tests); every UNKNOWN provenance field stays UNKNOWN,
      never backfilled with a guess (§3, §6).
- [x] New contract mechanically enforced (`provenance.py`, not policy alone).
- [x] Complete/incomplete fixture behavior proven (§4).
- [x] Existing ML lifecycle tests pass (86/86, §4).
- [x] v1/v2 history remains truthful (§3 — `UNKNOWN`/`NOT_SHIPPED` unchanged).
- [x] Rollback/failure artifact documented: `provenance.py` raises
      `ProvenanceError` naming the exact reason on any refusal; never writes
      partial state; a failed `validate_manifest` call leaves every file on
      disk untouched (§4/§6, `test_validator_never_rewrites_registry`).
- [x] No unresolved BLOCKER/MAJOR — 1 BLOCKER + 3 MAJOR/MINOR found and
      fixed in round 1, see §6.
- [x] Exact commit pushed/synced — done at gate close time and
      re-confirmed at the P0 aggregate verification (`git fetch origin` +
      `git rev-list --left-right --count HEAD...origin/master` = `0 0`).
