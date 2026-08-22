# P0.G3 — Source & rights registry

Status: CLOSED (pending push/remote-sync verification — see §7 below).

Purpose (per `SPTR_EQUIPMENT_RECOGNITION_V4_4_GATE_CONTRACTS_AND_AC_DOD_2026-08-22.md`
P0.G3): create fail-closed source/license governance before mass asset
acquisition. **This gate builds governance machinery, not legal
approvals.** Nothing here declares a real license legally sufficient; it
only makes "unknown/unreviewed" fail closed instead of quietly defaulting
to allowed. Story AC, verbatim: "unknown rights cannot become
display/training/embedding eligible — enforced by a unit or schema test,
not by policy alone."

## 1. What was built

| File | Role |
|---|---|
| `core/equipment_identity/p0/source_registry.schema.json` | Structural shape of one source record. |
| `core/equipment_identity/p0/rights_decision.schema.json` | Structural shape of the nested `rights` object. |
| `core/equipment_identity/p0/source_registry.json` | The seeded registry: 12 sources, all `UNREVIEWED`. |
| `core/equipment_identity/p0/SOURCE_PRIORITY.md` | The `sourceClass` → allowed-`priority` policy table. |
| `scripts/equipment_identity/rights.py` | The actual enforcement — schema validation plus five fail-closed eligibility functions. |
| `scripts/equipment_identity/test_rights.py` | 22 tests. |

## 2. The fail-closed policy, as implemented

Every eligibility function (`eligible_for_display`, `_recognition_processing`,
`_training`, `_derivative`, `_redistribution`) takes the **whole source
record**, not just its `rights` object, so a `SEARCH_DISCOVERY`-priority
record is refused structurally — independent of what its rights booleans
say — in addition to `legalReviewState` gating everything:

```
DISPLAY                 priority != DISCOVERY_ONLY AND legalReviewState == REVIEWED AND commercialAllowed AND displayAllowed
RECOGNITION_PROCESSING  priority != DISCOVERY_ONLY AND legalReviewState == REVIEWED AND commercialAllowed AND recognitionProcessingAllowed AND NOT noAiRestriction
TRAINING                priority != DISCOVERY_ONLY AND legalReviewState == REVIEWED AND commercialAllowed AND trainingAllowed AND NOT noAiRestriction
DERIVATIVE              priority != DISCOVERY_ONLY AND legalReviewState == REVIEWED AND commercialAllowed AND derivativeAllowed AND NOT noAiRestriction
REDISTRIBUTION          priority != DISCOVERY_ONLY AND legalReviewState == REVIEWED AND commercialAllowed AND redistributionAllowed
```

`commercialAllowed` gates every use, not just a "commercial use" flag off
to the side — SPTR is itself a commercial product, so any privileged use
of a source happens in that context regardless of which specific use is
being asked about (added during the review round, §6 below — it was
originally a required field that no eligibility function actually read).

`noAiRestriction=false` on an `UNREVIEWED` source is never read as
permission — `legalReviewState` is checked before any other field, for
every use. `validate_rights` additionally refuses, at the schema-validation
layer, an `UNREVIEWED` record that carries ANY true value in the six
`*Allowed` permission fields (`PERMISSION_FIELDS` in `rights.py`) — so the
"zero fake permissions" close condition is enforced twice, once
structurally (a bad record can't even be loaded) and once at the
eligibility layer (even if it somehow were loaded, the priority/review-state
gates would still refuse it).

`attributionRequired`/`shareAlike`/`termsCaptured` are deliberately
excluded from the "granted permission" set: the first two are obligations
that make a use MORE restrictive, not grants, and `termsCaptured` is
factual metadata (terms text exists somewhere) independent of whether
anyone has reviewed it yet — a source can honestly have its terms captured
and still be entirely unreviewed.

## 3. Priority is determined, not chosen

`rights.CANONICAL_PRIORITIES_BY_SOURCE_CLASS` restricts which `priority`
values each `sourceClass` may declare (full table and rationale in
`SOURCE_PRIORITY.md`). `SEARCH_DISCOVERY`'s only legal priority is
`DISCOVERY_ONLY` — structurally impossible to declare anything else, which
is the mechanical half of "search discovery can never be a training/display
source" (the eligibility-layer priority check above is the other half —
belt and suspenders, not redundancy: the priority-enum restriction stops a
bad record from being written at all; the eligibility check stops a bad
record from being *used* even if one somehow existed).

## 4. What was seeded, and what deliberately was not

All 12 seeded sources are transcribed from citations already recorded in
`core/design/sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md`
(§5's source-class table, lines 274-289, and its citation ledger [1]-[11],
lines 1531-1555) — not fetched live by this gate, not invented. That
document's own "Legal note" (line 1555) already states the exact same
principle this registry enforces: presence in the citation ledger is
discovery/reference evidence only, never a legal determination.

Every seeded `rights` object is `legalReviewState: UNREVIEWED` with all six
`*Allowed` booleans `false` and `termsCaptured: false` — per §8.3 of the
implementation prompt: "DO NOT make a live legal conclusion from memory."
`noAiRestriction` defaults to `true` for every seeded entry — a deliberate
fail-closed choice, not a claim that a No-AI clause was actually found: the
true value is unknown, and this flag only ever ADDS restriction, never
grants anything, so assuming the more conservative reading costs nothing
while a source stays unreviewed.

**Deliberately not seeded**: `DISTRIBUTOR`, `REFURBISHED_USED`, and
`OFFICIAL_BIM` are real, validated `sourceClass` values (all present in the
schema and in `CANONICAL_PRIORITIES_BY_SOURCE_CLASS`), but the
source-strategy document names only the CLASS ("official distributors,"
"refurbished/used inventories," "official 2D/3D/BIM/architect portals")
without a specific canonical URL — this registry does not invent one. A
real entry should be added once a specific provider is actually identified;
the class-level policy (including `OFFICIAL_BIM`'s `P0`/`P1` priority
ceiling) is already in place to receive it, and `validate_source_record`
enforces that ceiling identically whether or not an example exists yet.

**No asset was downloaded or fetched by this gate** — per §8.3's explicit
instruction. Every `canonicalUrl` is a citation copied from the design
document, not a URL this gate visited.

## 5. Tests run

```
python -m pytest scripts/equipment_identity/test_rights.py -q
22 passed
```

19 tests from initial authoring, covering the gate contract's 10 required
cases (every registry record validates schema; every record has an
explicit rights state; UNREVIEWED + any requested privileged use → deny;
missing rights object → validation fail; `noAiRestriction=true` blocks
recognition/training/derivative; a `"royalty free"` string in
`decisionBasis` alone cannot grant training; source-class priority is
deterministic; `SEARCH_DISCOVERY` can never be a training/display source;
no adapter can auto-promote a source; malformed timestamps/hashes fail
validation) plus 9 supporting cases (an UNREVIEWED record cannot even be
loaded if it carries a true permission boolean; `REVIEWED`+allowed grants
exactly the requested use and no other; `noAiRestriction=false` on an
unreviewed source is still not permission; `REVIEWED` requires
`reviewedAt`; a captured-terms hash requires `termsCaptured=true`; the
validator never rewrites the registry file; `load_registry` does not
mutate what it returns; a malformed `termsSnapshotSha256` fails; a
non-DISCOVERY priority on a `SEARCH_DISCOVERY` record fails registry
validation outright) — plus 3 regression tests added from the review round
(§6): `test_reviewed_without_terms_captured_fails_validation`,
`test_blocked_state_cannot_carry_a_granted_permission`,
`test_commercial_clearance_is_required_for_every_privileged_use`.

Full `scripts/` Python suite (`scripts/ml`, `scripts/ct1`,
`scripts/equipment_identity`), run together to catch any cross-suite
interference the way P0.G2 found one:

```
python -m pytest scripts/ml/ scripts/ct1/ scripts/equipment_identity/ -q
381 passed
```

## 6. Review record (P0.G3 §8.5)

Three independent, cold reviewers (no shared context, run in parallel):
`security-reviewer`, `silent-failure-hunter`, and `code-reviewer`
(substituting for the still-unavailable project-scoped
`regulatory-compliance-reviewer` — same substitution pattern as P0.G1/G2).
Reviewer boundary, honored by all three: they may detect missing/unsafe
rights LOGIC; none declared a real license legally sufficient, since none
exist to evaluate.

**MAJOR (found independently by both `security-reviewer` and
`silent-failure-hunter` — corroboration treated as strong evidence per this
project's review discipline) — `REVIEWED` did not require
`termsCaptured=true`.** `rights_decision.schema.json`'s own description of
`legalReviewState` documents the invariant ("REVIEWED means a human
reviewed actual captured terms — termsCaptured=true"), but
`validate_rights` never checked it — only `reviewedAt` was required. A hand
edit could set `legalReviewState=REVIEWED` with `termsCaptured=false` and
grant real eligibility with zero evidence terms were ever captured. Both
reviewers reproduced this exactly: the project's own
`test_reviewed_and_allowed_grants_the_specific_use_only` test built such a
record via `_reviewed_permissive_record` (whose base `termsCaptured` was
`False` and never overridden) and asserted it eligible. **Verified** by
reading `rights.py` directly — confirmed the gap existed exactly as
described. **Fixed**: `validate_rights` now raises unless
`termsCaptured is True` whenever `legalReviewState == "REVIEWED"`
(`rights.py`). `_reviewed_permissive_record` updated to set
`termsCaptured: True` by default so "permissive" means what it says.
Regression test added: `test_reviewed_without_terms_captured_fails_validation`.

**MAJOR (`security-reviewer`) — `commercialAllowed` was required by the
schema but read by no eligibility function.** A `REVIEWED`+`displayAllowed`
source with `commercialAllowed=false` (e.g. "personal/editorial use only")
was still reported eligible for display, even though SPTR is a commercial
product using the source in a commercial context. **Verified** by reading
all five `eligible_for_*` functions in `rights.py` — confirmed none
referenced the field. **Fixed**: every `eligible_for_*` function now also
requires `_commercially_allowed(record)`. Regression test added:
`test_commercial_clearance_is_required_for_every_privileged_use`.

**MINOR (`silent-failure-hunter`) — `BLOCKED` could carry a true permission
boolean without being rejected at validation.** The "zero fake permissions"
check originally applied only to `UNREVIEWED`; not currently exploitable
(`eligible_for_*` gates strictly on `legalReviewState == "REVIEWED"`) but a
self-contradictory `BLOCKED`+`displayAllowed=true` record was accepted as
structurally valid data. **Fixed**: the check now covers both
`UNREVIEWED` and `BLOCKED`. Regression test added:
`test_blocked_state_cannot_carry_a_granted_permission`.

**MINOR (`code-reviewer`, regulatory angle) — two documentation gaps.**
(a) `SOURCE_PRIORITY.md`'s `MARKETPLACE_3D` row didn't state that a
marketplace's `rights` record covers the platform, not any individual
asset, even though the design doc itself warns license terms vary
per-asset. **Fixed**: added an explicit scope note to that row (§3 above).
(b) `OFFICIAL_BIM` was a real, unseeded `sourceClass` missing from this
doc's "deliberately not seeded" list (only `DISTRIBUTOR`/`REFURBISHED_USED`
were named). **Fixed**: §4 above now names all three.

**MINOR (`security-reviewer`) — `eligible_for_*` trust caller-provided
field types without re-validating.** Currently safe because every record
reaching these functions passes through `load_registry`'s validation
first, and no production caller of `rights.py` exists yet anywhere in the
repo (confirmed by grep). Accepted as a known limitation rather than fixed
now: adding a defense-in-depth type re-check inside every eligibility
function would duplicate `validate_rights`'s own checks for no current
benefit, and this project's own conventions favor the smallest verifiable
change over speculative hardening. Flagged here for whoever builds the
first real consumer of `eligible_for` to keep in mind if that consumer
assembles records outside `load_registry`.

**MINOR (`code-reviewer`, regulatory angle) — no test enforces that
`rights.py`'s constants stay in sync with the two `.schema.json` files.**
Neither schema is loaded by a JSON Schema validator anywhere in the repo
(`rights.py`'s checks are hand-written and stricter/equal, not schema-
driven) — the `termsCaptured` MAJOR above is a concrete instance of this
drift risk (the schema's own description already stated the invariant the
code was missing). Accepted as a known limitation, not fixed in this gate:
closing it needs either wiring a real `jsonschema` validator into
`rights.py` or a standalone sync test asserting the schema `required`/enum
lists match the Python constants — a real scope addition beyond this
gate's close conditions, worth a future gate or a dedicated follow-up.

Everything else each reviewer checked (schema-loophole surface, injection/
eval sinks, `decisionBasis` never read by eligibility logic, fail-closed
behavior on malformed/empty registry files, no TOCTOU/caching gap, the
12-source citation cross-check against the v4.1 design doc's citation
ledger, `SEARCH_DISCOVERY`'s structural double-enforcement) came back
clean — no BLOCKER found by any of the three reviewers.

All fixes verified: `python -m pytest scripts/equipment_identity/test_rights.py -q`
→ 22 passed (19 original + 3 regression); full suite
`python -m pytest scripts/ml/ scripts/ct1/ scripts/equipment_identity/ -q`
→ 381 passed.

## 7. Close conditions (P0.G3 §8.6)

- [x] Schemas and registry exist.
- [x] 100% of registry entries carry an explicit rights state (§5,
      `test_every_record_has_rights_state`).
- [x] Unknown/unreviewed is mechanically quarantined (§2 — enforced twice,
      at validation and at the eligibility layer).
- [x] Zero fake permissions (§2, §4 — every seeded entry's six `*Allowed`
      fields are `false`; a validation-layer check refuses any record that
      violates this for `UNREVIEWED`).
- [x] Tests pass (§5).
- [x] Rollback/failure evidence documented (§8 below).
- [x] Reviewers: no unresolved BLOCKER/MAJOR — three independent reviewers
      ran; both MAJORs found were fixed and verified, all MINORs addressed
      or explicitly accepted as documented limitations (§6).
- [ ] Commit pushed/synced — pending, see the close-out step below.

## 8. Rollback / failure handling

- `validate_source_record`/`validate_rights` raise `RightsValidationError`
  naming the exact reason on any malformed or under-evidenced record —
  there is no silent partial acceptance. `load_registry` raises on the
  FIRST invalid record rather than returning a partially-trustworthy list.
- `rights.py` never writes to `source_registry.json` or anywhere else —
  confirmed by `test_validator_never_rewrites_the_registry_file` (byte
  comparison before/after `load_registry()`/`main()`).
- If a future source needs its `legalReviewState` promoted to `REVIEWED`,
  that is a human hand-editing `source_registry.json` with real evidence
  (`reviewedAt`, ideally `termsSnapshotSha256`) — `rights.py` exposes no
  promotion/approval/grant function of any kind
  (`test_no_adapter_can_auto_promote_a_source` asserts this structurally,
  by introspecting the module for any function whose name suggests one).
- A red `test_source_class_priority_is_deterministic` or
  `test_malformed_timestamp_fails_validation`-style failure is this gate's
  designed behavior when a record is wrong — the fix is correcting the
  record, not loosening the check.
