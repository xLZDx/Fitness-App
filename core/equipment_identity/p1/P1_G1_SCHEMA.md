# P1.G1 — Equipment identity ontology & Firestore schema

Status: CLOSED (pending push/remote-sync verification and `pm_set_gate` — see §9 below).

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P1.G1): implement additive Brand/ProductLine/EquipmentModel/Asset/Source/
ExternalMapping/SetupSpec boundaries and the access-control boundary that
makes "server authority" real. Story AC (AC-M04-corrected, 2026-08-22):
"the emulator mutation-test suite passes (client CREATE/UPDATE authority
fields → DENY, server/admin write → ALLOW, cross-account → DENY, using the
existing `test:rules` npm script)." This is P1's first gate — a pure
schema/rules/validator foundation, no exact-model UI surface, no real
catalog data yet (P1.G2+ own sourcing real models).

## 1. What was built

| File | Role |
|---|---|
| `functions-equipment-identity/src/p1/contracts.ts` | zod schemas: `ProvenanceRef`, `EquipmentBrand`, `ProductLine`, `StagedEquipmentModelCandidate`, `EquipmentModel`, `EquipmentAsset`, `EquipmentSource`, `ExternalMapping`, `EquipmentModelSetupSpec`, `RecognitionAuthorityTuple`, `CatalogVersionRecord`, `CatalogActivePointer`, `CatalogPublishJob`, `PublishApproval`, plus shared id-safety primitives (`SlugSchema`, `CatalogVersionSchema`, `EntityIdSchema`). |
| `functions-equipment-identity/src/p1/ids.ts` | `generateModelId`/`isValidModelId` (UUID v4), `deriveCandidateId` (staging-only, deterministic SHA-256), `buildProductLineId`/`buildCanonicalSlug` (never auto-dedupes — a collision is a visible conflict). |
| `functions-equipment-identity/src/p1/type_snapshot.ts` | TS port of `scripts/equipment_identity/type_snapshot.py`'s `validate_type_reference` — the T5 server-side consumer of P0.G4's functional-type snapshot. |
| `functions-equipment-identity/src/p1/catalog_repository.ts` | `validateEquipmentModelWrite`, `writeEquipmentModel` (the actual write path — validates before it ever calls `store.write`), `validateP1PilotStatusRestrictions`, `validateCatalogUniqueness`. |
| `functions-equipment-identity/src/p1/authority_tuple.ts` | `freezeAuthorityTuple`, `assertAuthorityTupleUnchanged` — schema/rules-layer immutability for `RecognitionAuthorityTuple` (T4, AC-M04-corrected: the *runtime* session-mutation test is P2.G3's). |
| `functions-equipment-identity/src/p1/firestore_paths.ts` | Collection/doc path builders for the whole P1 physical layout; `versionedDocId` enforces the `{catalogVersion}--{entityId}` scheme's own safety invariants at runtime. |
| `functions-equipment-identity/src/generated/functional_type_snapshot_v1.json` | Generated deployment copy of P0.G4's snapshot (§5.14). |
| `functions-equipment-identity/scripts/sync_p0_type_snapshot.js` | `sync`/`check` — `npm run build` runs `check` first; never silently rewrites. |
| `functions-equipment-identity/src/__tests__/p1_*.test.ts` | 6 new test files (contracts, ids, type_snapshot, authority_tuple, catalog_repository, firestore_paths) — 152 tests total in the whole `functions-equipment-identity` suite (up from 15 pre-existing P0 tests). |
| `firestore.rules` | New carve-outs (`recognised_models`, `equipment_identity_sessions`, `equipment_identity_telemetry`) from the per-user wildcard, plus 10 new top-level `equipment_*` catalog-authority collections, all server/admin-only. |
| `functions/src/__rules__/firestore_rules.test.ts` | +213 lines, 46 new mutation tests under "P1.G1:" describe blocks. Whole suite now 107 tests (was 61). |
| `scripts/equipment_identity/rights.py` | §6.8 hardening: `eligible_for()` now calls `validate_source_record()` before dispatch. |
| `scripts/equipment_identity/test_rights.py` | +2 tests proving the hardening; +5 schema/code drift tests (§6.8 task B). Suite now 30 tests (was 22). |
| `scripts/equipment_identity/test_type_snapshot.py` | +7 cross-language parity fixture tests. Suite now 24 tests (was 17). |
| `core/equipment_identity/p1/type_reference_validation_fixtures.json` | Shared cross-language fixture (§6.5) driving both the Python and TS `validate_type_reference`/`validateTypeReference` test suites. |
| `scripts/equipment_identity/verify_deployment_isolation.py` | P0.G6 isolation-probe fix (§7): the temp-copy build proof now also copies the P0 type snapshot alongside the identity codebase copy, matching a real checkout's layout — see §7 for why this was needed. |

`mobile/assets/data/equipment.json` (Layer A, functional ontology) is
untouched. No `ExerciseItem.equipmentId` semantic changed. No Flutter
runtime code changed.

## 2. Contracts (T1)

All schemas are `.strict()` zod objects (unknown fields rejected, not
silently dropped) except where noted. Key invariants enforced at the
schema layer:

- `EquipmentModel.modelId` — UUID v4, assigned once, never re-derived from
  modelCode/SKU/URL/slug (§5.5).
- `EquipmentModel.primaryTypeId` must be present in `supportedTypeIds`
  (`superRefine`, attached to `path: ["primaryTypeId"]`); `supportedTypeIds`
  must be non-empty and contain no duplicates (`path: ["supportedTypeIds"]`).
- `StagedEquipmentModelCandidate` structurally CANNOT carry a
  `primaryTypeId` field at all (`.strict()` rejects it) — adapters can
  never assign authoritative type identity (§5.8).
- `RecognitionAuthorityTuple` — validated then `Object.freeze`d
  (`freezeAuthorityTuple`); `assertAuthorityTupleUnchanged(before, after)`
  is a field-set-agnostic equality check for future runtime use (P2.G3).
- `EquipmentModel.productLineId`/`.generation` are `.optional()` only, NOT
  also `.nullable()` — a fix applied during review (see §7): admitting both
  `null` and `undefined` for "no value" let two otherwise-identical models
  serialize differently, which would break deterministic catalog-version
  content hashing once P1.G6 needs it.
- `SlugSchema`/`CatalogVersionSchema`/`EntityIdSchema` all reject `--` (the
  `{catalogVersion}--{entityId}` docId separator) and `/`; `EntityIdSchema`
  additionally rejects `.`/`..` and the reserved `__..__` pattern — also a
  fix applied during review (see §7).

## 3. P0.G4 type-reference validation — T5

`functions-equipment-identity/src/p1/type_snapshot.ts`'s
`validateTypeReference` is a behavior-identical TS port of
`scripts/equipment_identity/type_snapshot.py`'s `validate_type_reference`
(same error ordering, same messages). `catalog_repository.ts`'s
`validateEquipmentModelWrite` calls it against the generated snapshot
(`functions-equipment-identity/src/generated/functional_type_snapshot_v1.json`,
synced from `core/equipment_identity/p0/functional_type_snapshot_v1.json`,
`sourceSha256=c9e1706c...`, 69 types) before any write can proceed.

**Mutation proof** (`writeEquipmentModel` fake-store tests,
`p1_catalog_repository.test.ts`): a model with an invalid `primaryTypeId`
throws `CatalogValidationError` and `store.write` is asserted to have been
called zero times — spied, not just "did not throw."

**Cross-language parity** (§6.5's explicit requirement): both languages'
validators are driven by the same shared fixture file
(`core/equipment_identity/p1/type_reference_validation_fixtures.json`, 7
cases: valid single/multi-function, unknown primary, unknown supported,
primary-not-in-supported, duplicate supported id, empty primary) —
`scripts/equipment_identity/test_type_snapshot.py`'s
`test_shared_type_reference_validation_fixture_case` and
`p1_type_snapshot.test.ts`'s equivalent `test.each` both consume it.

## 4. Firestore rules (T2) and immutability declaration (T4)

Carve-outs added to the `users/{uid}/{coll}/{document=**}` wildcard for
`recognised_models`, `equipment_identity_sessions`,
`equipment_identity_telemetry` (mirroring the existing `usage`/`receipts`/
`profile` pattern), each backed by its own dedicated `match` block:

| Collection | Client read | Client write | Server/admin write |
|---|---|---|---|
| `users/{uid}/recognised_models/{modelId}` | ALLOW (owner only) | DENY | ALLOW |
| `users/{uid}/equipment_identity_sessions/{sessionId}` | DENY | DENY | ALLOW |
| `users/{uid}/equipment_identity_telemetry/{docId}` | DENY | DENY | ALLOW |
| 10 top-level `equipment_*` catalog collections | DENY | DENY | ALLOW |

**T4 (immutability, AC-M04-corrected):** since `equipment_identity_sessions`
is entirely server-only (no client read OR write), there is no client
mutation surface for an embedded `RecognitionAuthorityTuple` at all — the
schema/rules-layer declaration this task requires is satisfied structurally,
not just by convention. The *runtime* session-mutation test is explicitly
P2.G3's, once a real session runtime exists to test against.

**Mutation-test suite** (`functions/src/__rules__/firestore_rules.test.ts`,
run via the existing `npm --prefix functions run test:rules`, real
Firestore emulator via `@firebase/rules-unit-testing`): 46 new tests prove
client create/update/delete → DENY, owner read → ALLOW (where applicable),
cross-account read → DENY, `env.withSecurityRulesDisabled()` admin write →
ALLOW, and — critically — that "the per-user wildcard cannot override this
denial" (a dedicated test per collection group proving the wildcard's own
`coll != '...'` exclusion is what's actually doing the work, not the
specific block's `if false`, since Firestore ORs across all matching
rules).

```
npm --prefix functions run test:rules
107 passed (61 pre-existing + 46 new)
```

## 5. Catalog-level uniqueness (T1/§6.6)

`validateCatalogUniqueness` checks: unique `modelId`; unique
`canonicalSlug` within a `catalogVersion`; unique `brandId`/`productLineId`
within a `catalogVersion`; every model's `brandId`/`productLineId`
reference an existing brand/line; duplicate `modelCode` within the same
brand+line is surfaced (not silently accepted) as
`DUPLICATE_MODEL_CODE_SAME_BRAND_LINE`. Grouping keys are built via
`JSON.stringify` on the raw key-parts array (see §7 — this replaced an
earlier space-joined-string implementation that had a real false-positive
collision risk).

## 6. 50-model capacity (T1/§6.7)

`p1_catalog_repository.test.ts`'s "50-model capacity" describe block
builds a synthetic 50-record catalog (multi-function models included, one
in five) entirely through `validateEquipmentModelWrite` (real schema +
real P0 type-snapshot validation, not hand-constructed objects) and asserts
zero uniqueness violations. These are explicitly labeled test fixtures
only — never mixed into an actual pilot catalog, which P1.G5 alone
produces.

## 7. Review record (P1.G1)

Four independent, cold reviewers ran in parallel against the real diff:
`database-reviewer`, `security-reviewer`, `type-design-analyzer`,
`silent-failure-hunter`.

**Verdict summary:**
- `security-reviewer`: no BLOCKER/MAJOR. One MINOR (informational): the
  Firestore wildcard's negative-list (`coll != 'X'`) pattern is a latent
  risk if a future edit drops one exclusion line — matches the codebase's
  existing convention (`usage`/`receipts`/`profile`), no change required
  for this gate.
- `silent-failure-hunter`: no BLOCKER/MAJOR/MINOR defects. Confirmed via a
  repo-wide grep that `rights.py`'s new `validate_source_record()` call
  inside `eligible_for()` has zero existing callers that could be broken by
  the new raise (only `rights.py`'s own `main()` and the test suite call
  it). Confirmed `writeEquipmentModel`'s `enforceP1PilotRestrictions`
  default-off is correctly scoped (no real write caller exists yet in this
  gate) and not misrepresented as unconditional anywhere.
- `type-design-analyzer`: 1 MAJOR (fixed — `ids.ts` had zero test
  coverage), 4 MINOR (fixed — missing `.strict()` on
  `EquipmentBrandSchema`/`ProductLineSchema`; `productLineId`/`generation`
  dual null/undefined encoding; `deriveCandidateId`'s unenforced `\n`-safety
  invariant; untested `DUPLICATE_BRAND_ID`/`DUPLICATE_PRODUCT_LINE_ID`
  branches).
- `database-reviewer`: 3 MAJOR (all fixed — see below), 2 MINOR (1 fixed:
  `productLineId` null/undefined, same finding as type-design-analyzer's;
  1 deferred as explicitly non-blocking per the reviewer's own
  recommendation: unbounded array sizes, no current workload evidence
  requiring a cap yet), 1 NIT (resolved by this document's own existence).

**The 3 real MAJOR/MAJOR-adjacent defects found and fixed:**

1. **Ambiguous composite string keys** in `validateCatalogUniqueness`
   (`DUPLICATE_MODEL_CODE_SAME_BRAND_LINE` and the `.split(" ")`-based
   detail-string reconstruction for `DUPLICATE_BRAND_ID`/
   `DUPLICATE_PRODUCT_LINE_ID`) — `catalogVersion`/`modelCode` are free
   text and can contain spaces, so two structurally different 4-tuples
   could join to the identical space-delimited string and be misreported
   as one false "duplicate," which would incorrectly block a legitimate
   write. **Fixed**: grouping now keys on `JSON.stringify` of the raw parts
   array (collision-free regardless of content), and detail strings are
   built from the original field values, never re-derived by splitting the
   key. **Regression-proven**: `p1_catalog_repository.test.ts` constructs
   the exact word-boundary-shift collision the reviewer described (`(cv="cat
   one two", brand="three", pl="four", mc="five six")` vs `(cv="cat one",
   brand="two", pl="three", mc="four five six")`, both of which joined to
   the same string under the old scheme) and proves it no longer
   false-positives, plus a companion test proving a genuine duplicate with
   the same space-containing catalogVersion still correctly fires.
2. **Unconstrained free-text ids feeding raw Firestore docId
   construction** (`mappingId`, `setupSpecId`, `assetId`, `jobId` were bare
   `z.string().min(1)`, flowing straight into `versionedDocId`'s
   unescaped template-string concatenation). **Fixed**: new `EntityIdSchema`
   (rejects `/`, `--`, `.`/`..`, the reserved `__..__` pattern, capped at
   300 chars) applied to all four fields, plus a runtime
   `assertFirestoreSafeIdPart` guard inside every `firestore_paths.ts`
   path-builder (`versionedDocId`, `sourceDocPath`, `publishJobDocPath`,
   `catalogVersionDocPath`) as a backstop independent of whether the schema
   was actually used to validate the input.
3. **`--` inside `catalogVersion`/slug fields could make a future
   `documentId()` prefix-range read ambiguous** — `SlugSchema`'s regex
   legally admitted `"ab--cd"`, and `catalogVersion` was unconstrained free
   text. Real data doesn't exist yet, so this was cheap to close now and
   would have been expensive once P1.G5/G6 mint real ids. **Fixed**: new
   `CatalogVersionSchema` (bans `/` and `--`, capped at 200 chars) applied
   everywhere `catalogVersion`/`activeCatalogVersion`/
   `previousCatalogVersion` appears; `SlugSchema` itself now also bans `--`.

**New test coverage added specifically for the fix-round** (beyond the
regression tests above): `p1_ids.test.ts` (18 tests — `ids.ts` had none
before), `p1_firestore_paths.test.ts` (24 tests — this module, which the
entire versioned-docId scheme depends on, had none before), plus targeted
`.strict()`/null-rejection/`--`-rejection tests in `p1_contracts.test.ts`
and `DUPLICATE_BRAND_ID`/`DUPLICATE_PRODUCT_LINE_ID` tests in
`p1_catalog_repository.test.ts`.

All fixes independently re-verified by re-running the full affected test
suite (152/152 `functions-equipment-identity` tests, `npm run build`)
after each change, not just trusting the reviewers' analysis.

**A fifth defect, self-caught (not from the 4-reviewer panel, which reviews
code but does not execute the P0.G6 isolation test harness):** running the
full `scripts/equipment_identity/` Python suite after the fix round
(mandatory before commit, per the per-gate discipline) surfaced 2 failing
tests in `test_deployment_isolation.py`
(`test_broken_identity_copy_fails_while_default_codebase_still_builds`,
`test_main_runs_end_to_end_and_exits_zero`). Root cause: §5.14's
`npm run build` now runs `check:p0-snapshot` first, which reads
`core/equipment_identity/p0/functional_type_snapshot_v1.json` via a path
relative to `functions-equipment-identity`'s own location — a real,
intentional build-time dependency in every actual checkout (the identity
codebase never deploys without the rest of the repo present alongside it).
`verify_deployment_isolation.py`'s isolation probe, however, copies ONLY
`functions-equipment-identity` into a disposable temp directory to prove it
builds/fails independently of the default (Stripe) codebase — that temp
copy had no `core/` alongside it, so `check:p0-snapshot` failed on a
missing file unrelated to the actual isolation property being tested.
**Fixed**: `run_broken_identity_probe()` now also copies
`core/equipment_identity/p0/functional_type_snapshot_v1.json` (read-only,
the tracked file is never modified) into the temp root at the matching
relative path, mirroring what a real checkout always has. This does not
weaken P0.G6's actual isolation guarantee — the default codebase build
independence proof is unchanged — it only fixes the test harness's own
temp-copy fidelity, which P1.G1 was the first gate to actually exercise
since P0.G6 closed. Re-verified: full `python -m pytest
scripts/equipment_identity/ -q` — 104 passed (0 failed), including all 10
`test_deployment_isolation.py` tests.

## 8. P0 rights carry-forward hardening (§6.8)

Two accepted P0.G3 forward notes closed:

**A.** `eligible_for()` (`scripts/equipment_identity/rights.py`) now calls
`validate_source_record(record)` before dispatching to any
`eligible_for_*` function, so a malformed/inconsistent record raises the
same typed `RightsValidationError` every other rights failure raises,
instead of risking an untyped `KeyError` or a silently-wrong boolean read.
Fixing this surfaced one pre-existing test fixture bug: a test built a
`legalReviewState=REVIEWED` record without `termsCaptured=true` (itself
invalid per `validate_rights`), which the new validation now correctly
rejects — the fixture was corrected, not the validation weakened.

**B.** Five new schema/code drift tests in `test_rights.py` compare
`rights_decision.schema.json`/`source_registry.schema.json`'s `required`
fields and enums against `rights.py`'s `REQUIRED_RIGHTS_FIELDS`/
`LEGAL_REVIEW_STATES`/`REQUIRED_SOURCE_FIELDS`/`SOURCE_CLASSES`/
`PRIORITIES`/`CANONICAL_PRIORITIES_BY_SOURCE_CLASS` — a future
`termsCaptured`-class schema/code drift is now CI-visible instead of
silently possible.

```
python -m pytest scripts/equipment_identity/test_rights.py -q
30 passed (22 pre-existing + 8 new)
python -m pytest scripts/equipment_identity/test_type_snapshot.py -q
24 passed (17 pre-existing + 7 new)
```

P0.G3's own status is not reopened — this is recorded as P1 hardening on
top of an already-closed gate.

## 9. Close conditions

- [x] Can represent 50 pilot models without changing `equipmentId` semantics — §6.
- [x] The rules mutation-test suite (client/server/cross-account DENY/ALLOW/DENY) passes — §4.
- [x] `RecognitionAuthorityTuple` declared immutable at the schema/rules layer — §4.
- [x] Server-side `EquipmentModel` write validation consumes P0.G4's snapshot, rejects invalid type references — §3.
- [x] Flutter/architecture + ontology + Firebase/backend + security review signed off — §7 (4 independent reviewers; substituted `database-reviewer`/`security-reviewer`/`type-design-analyzer`/`silent-failure-hunter` for the gate contract's suggested `fitness-flutter-reviewer`/`exercise-ontology-curator`, neither of which exists as an available agent in this environment — no Flutter/mobile runtime surface exists in this gate to review, and `type-design-analyzer` is the closest available substitute for ontology/schema-invariant review).
- [x] Decision log entry recorded — see `core/DECISION_LOG.md`.
- [ ] Commit pushed and remote SHA verified (`git rev-list --left-right --count HEAD...origin/master` == `0 0`) — pending, next step after this document.
- [ ] `pm_set_gate` recorded — pending.

## 10. Rollback / failure handling

Schemas are additive only — no `equipmentId` migration occurred, no
existing collection's rules were narrowed (only new collections were
carved out of the wildcard and new top-level collections added). Rollback
is: revert the P1.G1 commit(s); no downstream gate has started yet, so no
partial-state cleanup is required. `firestore.rules`/`firestore.indexes.json`
changes are additive and safe to revert independently of any code change.

## 11. Known residual items (not blockers for this gate)

- Unbounded array sizes (`skuAliases`, `aliases`, `supportedTypeIds`,
  `provenance`) — no `.max()` cap yet. Database reviewer's own
  recommendation: revisit once real P1.G2+ ingestion volume/shape is known,
  not blocking for P1.G1's 50-pilot-model scope.
- `EquipmentModelStore`/a real Firestore-backed implementation of it does
  not exist yet — `writeEquipmentModel` is proven against a fake store
  only. P1.G5/G6 add the real write caller and must pass
  `enforceP1PilotRestrictions: true`.
- `firestore.indexes.json` remains empty — justified: P1.G1's code issues
  zero Firestore queries (confirmed via a repo-wide grep for `.where(`/
  `.orderBy(`/`query(`/`collectionGroup`/`startAt`/`startAfter` inside
  `functions-equipment-identity/src`, zero matches), only direct-path
  document reads/writes. `NO_COMPOSITE_INDEX_REQUIRED_FOR_P1`.
