# P0.G4 — Catalog version & type snapshot

Status: CLOSED (pending push/remote-sync verification — see §7 below).

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G4): create authoritative catalog-version semantics **without duplicating
`equipment.json` as a second source of truth**. Story AC, verbatim: "a
build test fails if `primaryTypeId` references a nonexistent
`equipmentId`; the snapshot hash/version is deterministic across identical
inputs."

## 1. What was built

| File | Role |
|---|---|
| `scripts/equipment_identity/type_snapshot.py` | Generator + pure `validate_type_reference` function. |
| `scripts/equipment_identity/test_type_snapshot.py` | 17 tests. |
| `core/equipment_identity/p0/functional_type_snapshot_v1.json` | Generated immutable snapshot (69 types, sorted by id). |
| `core/equipment_identity/p0/functional_type_snapshot_manifest.json` | Version manifest tying a `snapshotId` to a full `snapshotSha256`. |
| `.github/workflows/flutter.yml` | New CI step running the whole `scripts/equipment_identity/` suite (see §5). |

`mobile/assets/data/equipment.json` (69 entries: `id`, `name`,
`manufacturer`, `category`, `description`) remains the single functional-
ontology source of truth — Layer A per the v4.1 design doc: "Functional
class used by exercises/safety/programmes. Immutable semantics." No second
hand-maintained catalog was created.

## 2. Snapshot shape and hashing

```
functional_type_snapshot_v1.json:
  schemaVersion: 1
  sourcePath: "mobile/assets/data/equipment.json"
  sourceSha256: <sha256 of the real equipment.json file bytes>
  typeCount: 69
  types: [ ...canonical equipment.json entries, sorted by id... ]

functional_type_snapshot_manifest.json:
  schemaVersion: 1
  snapshotId: "equipment-types-v1-<first16(snapshotSha256)>"
  snapshotSha256: <FULL sha256, never a truncated prefix>
  snapshotPath / sourcePath / sourceSha256 / typeCount: same as above
  generatedBy: "scripts/equipment_identity/type_snapshot.py"
```

`snapshotSha256 = SHA256(canonical compact JSON of the \`types\` array
alone)` — deliberately not a hash of the whole payload, which would make
the hash depend on `sourceSha256`/`typeCount` (fields derived FROM `types`,
not part of what the hash identifies). Object keys are canonicalized by
`json.dumps(..., sort_keys=True)` at serialization time (both for hashing
and for the pretty-printed committed file) — no manual key reordering is
needed. `types` is sorted by `id` before either form is produced, so
reordering `equipment.json`'s entries can never change the hash (§4 proves
this). No wall-clock timestamp is ever written to either generated file —
required for byte-identical reruns (§4).

## 3. `validate_type_reference` — the reusable seam

```python
validate_type_reference(primary_type_id, supported_type_ids, snapshot)
```

Rules, each independently tested (§4):
- `primaryTypeId` must exist in the snapshot's `types`.
- Every `supportedTypeId` must exist in the snapshot's `types`.
- `primaryTypeId` must be present in `supportedTypeIds` — the default path
  is one of the model's own supported functions, not a separate claim.
- Duplicate ids within `supportedTypeIds` are invalid.
- **No silent normalization of an unknown id** — every violation raises
  `TypeSnapshotError` naming the exact bad id(s); nothing is dropped,
  defaulted, or coerced into a "closest match."

No production `EquipmentModel` schema exists yet (that is a later P1
concern per the v4.1 design doc's Layer B) — `test_type_snapshot.py` uses
fixture snapshots/ids rather than a real exact-model record, exactly as the
gate's own scope specifies.

`equipment.json` entries carry a `manufacturer` field (currently always
`"Any"` for all 69 types), copied into the snapshot unmodified since the
snapshot preserves "canonical full objects from equipment.json" verbatim —
this is not the exact-model layer's manufacturer concept (Layer B in the
design doc: `EquipmentBrand`/`ProductLine`/`EquipmentModel`); it is just
whatever `equipment.json` itself already records for that functional type,
carried through unchanged, same as `name`/`category`/`description`.

## 4. Tests run

```
python -m pytest scripts/equipment_identity/test_type_snapshot.py -q
17 passed
```

Covers every case the gate's implementation plan named: current
`equipment.json` → deterministic snapshot; reordering the source input →
same semantic snapshot hash (proven by shuffling the real 69 entries with a
fixed seed and rebuilding from the shuffled file); duplicate equipment id →
FAIL; a non-list source → FAIL; a fixture exact-model with a nonexistent
`primaryTypeId` → FAIL; a nonexistent `supportedTypeId` → FAIL; a valid
multi-function fixture → PASS; rerunning the generator twice and diffing
the output files byte-for-byte → identical. Two additional cases beyond
the minimum list: the checked-in `functional_type_snapshot_v1.json`/
`functional_type_snapshot_manifest.json` are asserted to equal a fresh
`build_snapshot()` call exactly (proves the committed files are not
hand-edited or stale), and the generator is asserted to never modify
`equipment.json` itself.

Full `scripts/` Python suite (`scripts/ml`, `scripts/ct1`,
`scripts/equipment_identity`):

```
python -m pytest scripts/ml/ scripts/ct1/ scripts/equipment_identity/ -q
398 passed
```

## 5. CI wiring (T3's own requirement)

T3's AC/DoD requires "CI demonstrates the failure on a deliberately broken
input." Auditing `.github/workflows/flutter.yml` while building this gate
found that **no P0 equipment-identity test suite (P0.G1's, P0.G2's,
P0.G3's, or this gate's) had ever been wired into CI** — the existing
`ct1-content-qa` job lists specific `scripts/ml`/`scripts/ct1`/
`scripts/review` paths individually and none of them touch
`scripts/equipment_identity`. This gap predates P0.G4 (it applies equally
to P0.G1–G3) but P0.G4 is the first gate whose own AC/DoD explicitly
requires CI proof, so it is fixed here: a new step, "Equipment identity —
P0 baseline, provenance, rights, type snapshot", runs
`python -m pytest scripts/equipment_identity/ -q` in `ct1-content-qa`,
which now exercises all four P0 gates' tests — including this gate's own
`test_exact_model_fixture_with_nonexistent_primary_type_id_fails` and
`test_nonexistent_supported_type_id_fails`, which is the literal build-time
referential check T3 asks CI to demonstrate.

## 6. Review record (P0.G4)

Two independent, cold reviewers: `flutter-reviewer` (substituting for the
project-scoped, still-unavailable `fitness-flutter-reviewer`) and
`type-design-analyzer` (substituting for the project-scoped, still-
unavailable `exercise-ontology-curator` — its invariant/type-correctness
lens was judged the closest match to "can a bad model reference an unknown
type" and "can the snapshot drift without a test failure"). Questions per
the gate's own implementation plan: does this preserve `equipmentId` as
functional ontology? Is any exact-model concept leaking into functional
type truth? Can the snapshot drift without a test failure? Can a bad model
reference an unknown type?

**MAJOR x2 (`type-design-analyzer`) — `validate_type_reference` broke its
own documented contract, crashing with a bare `KeyError`/`TypeError`
instead of `TypeSnapshotError` for malformed input.** (1) A `snapshot`
dict missing the `"types"` key, or a `types` entry with no `"id"`, raised
`KeyError` — a future caller written to `except TypeSnapshotError` (the
pattern this module's own docstring trains callers to use) would not catch
it. (2) A non-string entry in `supported_type_ids` (e.g. a raw dict passed
instead of an extracted id string) crashed with `TypeError: unhashable
type` inside the duplicate-detection set comprehension, before any of the
intended validation even ran. **Verified** by reading `validate_type_
reference` directly — confirmed both code paths lacked any guard before
the offending dict/set operations. **Fixed**: explicit type/shape checks
added at the top of the function for `primary_type_id`, every element of
`supported_type_ids`, and the `snapshot["types"]` shape — each raises a
clear `TypeSnapshotError` before any dict/set operation that could crash
with an unrelated exception. Four regression tests added:
`test_malformed_snapshot_missing_types_key_raises_type_snapshot_error`,
`test_snapshot_entry_without_an_id_raises_type_snapshot_error`,
`test_non_string_supported_type_id_raises_type_snapshot_error_not_type_error`,
`test_non_string_primary_type_id_raises_type_snapshot_error`.

**MAJOR-in-practice, not flagged as such by either reviewer but found while
verifying their line-ending observation (`flutter-reviewer`'s MINOR #5) —
`sourceSha256` was computed from the local Windows working-copy's CRLF
bytes, which would not match what a Linux CI checkout produces.** This
repo has `core.autocrlf=true`; `equipment.json`'s committed git object is
LF-only (verified: `git show HEAD:mobile/assets/data/equipment.json` — 0
CRLF, 485 LF), but the local Windows checkout that generated this gate's
first commit attempt was CRLF (verified: local file read — 485 CRLF, 0
lone LF). Since this gate's own new CI step (§5) runs
`test_generated_files_on_disk_match_a_fresh_build`, which recomputes
`sourceSha256` fresh and compares it to the committed manifest, a CI run on
a default Linux runner (LF checkout) would have failed against a
Windows-CRLF-computed `sourceSha256` — not because the snapshot was
actually stale, but purely from a platform line-ending mismatch introduced
by wiring this suite into CI for the first time. **Fixed**: `.gitattributes`
now pins `mobile/assets/data/equipment.json text eol=lf` (and
`core/equipment_identity/p0/*.json text eol=lf` for cleanliness), the local
working copy was renormalized to match the already-LF git object
byte-for-byte (confirmed via `git diff --cached` showing no change), and
the snapshot/manifest were regenerated from the normalized file —
`sourceSha256` changed from the CRLF-based value to the LF-based one that
now matches what every platform's checkout will produce.

**MINOR (`flutter-reviewer`) — `manufacturer` field documentation.** Added
an explicit note (§1 above) that the snapshot's `manufacturer` field is
`equipment.json`'s own existing field carried through unmodified, not the
exact-model layer's manufacturer/brand concept.

**MINOR (`type-design-analyzer`) — no load-time integrity check between the
snapshot file and its manifest's hash.** Accepted as a known limitation,
not fixed in this gate: no production consumer of `load_snapshot()` exists
yet (same reasoning as P0.G3's accepted `eligible_for` type-recheck MINOR)
— a `load_and_verify_snapshot()` helper that recomputes and compares the
hash is worth adding once a real server-side consumer exists to actually
benefit from the extra check.

Everything else each reviewer checked came back clean: `equipmentId` is
preserved verbatim as the functional-ontology key (no renaming/
reinterpretation); no exact-model concept otherwise leaks into functional
type truth; the checked-in snapshot/manifest are asserted equal to a fresh
build (§4's `test_generated_files_on_disk_match_a_fresh_build`); the
16-hex `snapshotId` prefix is correctly treated as a label everywhere, with
the full hash as the only actual integrity check; no input mutation; the
omission of full-record validation for `name`/`category`/`description` is
correctly in-scope-excluded (this gate is about type identity, not
full-record validation). No BLOCKER found by either reviewer.

All fixes verified: `python -m pytest scripts/equipment_identity/test_type_snapshot.py -q`
→ 17 passed (13 original + 4 regression); full suite
`python -m pytest scripts/ml/ scripts/ct1/ scripts/equipment_identity/ -q`
→ 398 passed.

## 7. Close conditions (P0.G4 §9.5 / T1–T3)

- [x] T1 — Generated immutable type snapshot: regeneration from the same
      input yields the same hash (§4).
- [x] T2 — Catalog version manifest ties a version to a specific snapshot
      hash (§2); intended for server consumption once a real exact-model
      server path exists (§8, known limitation — none exists yet in any
      phase built so far).
- [x] T3 — Build-time referential check: a nonexistent `equipmentId`
      reference fails the build; CI demonstrates this (§5).
- [x] No second hand-maintained ontology (§1).
- [x] Tests pass (§4).
- [x] Rollback/failure evidence documented (§8).
- [x] Reviewers: no unresolved BLOCKER/MAJOR — two independent reviewers
      ran; both MAJORs found (fragile validator, CRLF/LF sourceSha256
      mismatch) were fixed and verified; both MINORs addressed (§6).
- [ ] Commit pushed/synced — pending, see the close-out step below.

## 8. Rollback / failure handling, and known limitations

- Per the gate contract's own rollback mode: "Regenerate snapshot from
  `equipment.json`; never hand-edit a duplicate type catalog." Nothing in
  `type_snapshot.py` provides a hand-edit path — `write_snapshot()` always
  recomputes both files from the live source file.
- `load_source_entries`/`build_snapshot` raise `TypeSnapshotError` (naming
  the exact bad id(s)) on a non-list source, a missing/empty id, or a
  duplicate id — there is no silent partial snapshot.
- **Known limitation, not fixed in this gate**: the formal Story DoD item
  "Server validates exact models against the current functional type
  snapshot" and T2's "Manifest consumed by server validation, not
  decorative" cannot be literally satisfied yet — no server-side
  exact-model ingestion/validation path exists in any phase built so far
  (Functions codebase isolation is P0.G6's scope, and even that gate does
  not build an exact-model submission endpoint). `validate_type_reference`
  is built as the reusable seam a future server path is expected to call
  directly rather than reimplement, per the gate's own implementation
  plan ("No production EquipmentModel schema yet. Use test fixtures
  only."). This is a real, honestly-documented gap, not a silent
  overclaim — the corresponding DoD checkboxes stay unchecked above until
  a real server consumer exists.
