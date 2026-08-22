# SPTR Equipment Recognition v4.4 — full AC/DoD reference (Epic / Story / Task)

**Status:** DRAFT, pending a GPT-PM review round before it may be treated as ready for
implementation (operator instruction, 2026-08-22: "а потом еще раунд ревью AC/DoD с гпт и только
потом мы можем закрыть это как готово к имплементации" — a GPT-PM review round comes after this
draft, and only after that verdict can this be closed as implementation-ready). Supersedes the
first draft of this file (two-tier: full AC/DoD for P0+P1.G1 only, lightweight contracts for the
rest). Operator instruction, 2026-08-22, verbatim: "ты должен слушать меня, я говорю что твой
воркфлоу должен включать AC/DoD для всего документа и гейтов/подгейтов как в жире — эпик, стори,
таск, и для всего есть AC/DoD" — every phase, gate, and sub-gate/deliverable gets its own AC/DoD,
structured like a Jira Epic → Story → Task hierarchy, in full, now. This directly overrides the
just-in-time deferral GPT-PM proposed and the operator had initially endorsed (see
`core/review/SPTR_EQUIPMENT_RECOGNITION_V4_4_ACDOD_TIMING_QUESTION_2026-08-22.md`) — that tradeoff
is restated honestly in Part 3 rather than silently dropped.

No binding design decision changes here. Every AC/DoD below consolidates already-binding text from
v4.1 (base gate definitions, `SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md`,
lines 600–1153) plus v4.2/v4.3/v4.4's amendments where a gate was rewritten, extended, corrected, or
added — cited inline. Scope: Phases P0–P6 (34 gates total; production stays gated behind this
range). P7–P8 (Contribution & Active Learning, Scale) are unchanged since v4.1 and out of scope for
this pass, unless the operator asks to extend it.

## Hierarchy legend

| Jira term | This project | Level in this document |
| --- | --- | --- |
| Epic | Phase (P0–P6) | `## Phase` |
| Story | Gate (P*.G*) | `### P*.G*` |
| Task | One discrete deliverable inside a gate | table row under each Story |

**AC vs DoD, used consistently at every level:**
- **Acceptance Criteria (AC)** — the specific, checkable condition that proves the item is correct.
  At Story level this is the gate's `Verification` text, restated as checkable bullets. At Task
  level it is what specifically proves that one deliverable is right.
- **Definition of Done (DoD)** — everything that must be true before the item is considered closed,
  including AC passing, review sign-off, and (at Story level) the rollback/failure-mode plan being
  documented. DoD is always AC plus process, never AC alone.

---

## Phase P0 — Foundation, provenance & platform readiness

**Epic AC:** all 7 gates below (P0.G0–P0.G6) individually closed with evidence; the region/isolation
decisions from P0.G5/P0.G6 are recorded, not merely discussed.
**Epic DoD:** every Story's DoD checklist is ticked; `core/DECISION_LOG.md` carries one entry per
closed gate; no P1+ gate has started implementation before P0.G1–G4 (their hard prerequisites) close.

### P0.G0 — App Check platform readiness

CLASSIFICATION: EXTERNAL PREREQUISITE / BLOCKING · Source: v4.2 new gate (closes B-01) + v4.3
extension (App-Check-transition evidence rule)

Purpose. Make explicit that production exact-identity promotion depends on a platform-wide App
Check migration this workstream does not own, so P2.G3/P6 cannot silently close against a security
condition that isn't actually met.

Inputs. `functions/src/scaling.ts`'s current `APP_CHECK_ENFORCED` flag and its documented unmet
preconditions (Play Integrity distribution-channel mismatch for the operator's own test builds).

Required review. Security + Firebase/backend review.

Rollback / failure mode. Remain shadow-only indefinitely; does not block P0-P5 foundation/shadow
work. A material enforcement-status transition invalidates pre-transition auth/availability shadow
evidence (v4.3) — a bounded post-transition canary/re-shadow period is required before that data
counts toward P6.G1.

**Story AC:**
- `APP_CHECK_PLATFORM_READINESS` status exists with exactly the three defined values
  (`BLOCKED_EXTERNAL_PLATFORM_MIGRATION` / `READY_FOR_SHADOW` / `READY_FOR_PRODUCTION`).
- P2.G3's exit condition references this status directly, never asserts `enforceAppCheck=true` as
  its own deliverable.
- Any transition that changes whether enforcement is active is detectable and excludes
  pre-transition auth/availability samples from P6.G1's evidence-freshness check.

**Story DoD:**
- [ ] `READY_FOR_PRODUCTION` recorded with evidence, OR production exact identity is explicitly and
      visibly blocked pending it — no undocumented third state.
- [ ] Security + Firebase/backend review signed off.
- [ ] Rollback plan (shadow-only indefinitely) documented and exercised if this gate stalls.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Define `APP_CHECK_PLATFORM_READINESS` status enum | Exactly 3 named states exist in code/config, no free-text status | Enum merged, referenced by P2.G3 and P6.G1, reviewed |
| T2 — Split shadow vs. production enforcement | Shadow/dev exact identity can run with enforcement off; production cannot | Mechanical check (test or server-side assertion) proves the split, not a comment |
| T3 — App-Check-transition evidence invalidation rule | Transition timestamp is recorded; auth/availability samples before it are excluded from P6.G1 counts | P6.G1's evidence-freshness check demonstrably excludes pre-transition samples |

### P0.G1 — Current recognition baseline freeze

CLASSIFICATION: FOUNDATION / PRE-IMPLEMENTATION · Source: v4.1 §9, unchanged

Purpose. Capture the exact shipped/current scanner behavior so future exact-identity work cannot
silently rewrite generic semantics.

Inputs. Current master, scanner contracts, model registry, current 30-photo evaluation evidence.

Required review. Flutter reviewer + ML/data reviewer.

Rollback / failure mode. If provenance cannot be reproduced, block learned-model promotion but
continue ontology/source work.

**Story AC:** baseline report is reproducible from source against existing scanner tests; current
30 photos are marked HOLDOUT/NO_TRAINING and excluded from any future training pipeline by
construction, not by convention.

**Story DoD:**
- [ ] Baseline report reproducible from a clean checkout.
- [ ] 30 holdout photos marked and mechanically excludable.
- [ ] Flutter + ML/data review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Versioned baseline note | Note states current OCR/TFLite/cloud path behavior as observed, not assumed | Committed, dated, references source commit |
| T2 — Hash/version current model paths | Hashes/versions recorded for every active recognition path | Recorded values match `git rev-parse`/model registry at capture time |
| T3 — Preserve holdout inventory | 30-photo set enumerated with a HOLDOUT/NO_TRAINING tag | Tag is machine-checkable (e.g. a manifest file), not just documentation |

### P0.G2 — ML provenance recovery

CLASSIFICATION: FOUNDATION · Source: v4.1 §9, unchanged

Purpose. Ratchet training/evaluation reproducibility before adding another learned recognition
component.

Inputs. `MODEL_REGISTRY.json` and any extant equipment-model tooling/manifests.

Required review. ML/data reviewer + governance reviewer.

Rollback / failure mode. Do not "repair" history by inventing missing provenance.

**Story AC:** manifests are either rebuildable or deterministically validated; every UNKNOWN
provenance field is explicitly recorded as unknown, never backfilled with a guess.

**Story DoD:**
- [ ] Training/eval manifests version-controlled with pinned dependencies.
- [ ] No fabricated commit/version values anywhere in the manifests.
- [ ] ML/data + governance review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Version-controlled manifests | Manifests checked in, dependency pins present | Rebuild or deterministic validation passes |
| T2 — Dataset source manifests | Every dataset traces to a recorded source | No dataset entry lacks a source reference |
| T3 — Record UNKNOWN fields explicitly | Historical v1/v2 gaps are labeled UNKNOWN, not silently filled | New identity ML work points only to recoverable code/manifests |

### P0.G3 — Source & rights registry

CLASSIFICATION: FOUNDATION / LEGAL · Source: v4.1 §9, unchanged

Purpose. Create fail-closed source/license governance before mass acquisition.

Inputs. Source Strategy, official source URLs, marketplace/API terms.

Required review. Security/privacy + provenance/legal review.

Rollback / failure mode. Any ambiguous right remains staging-only.

**Story AC:** unknown rights cannot become display/training/embedding eligible — enforced by a unit
or schema test, not by policy alone.

**Story DoD:**
- [ ] 100% of ingested sources carry a rights state; unknown routes to quarantine automatically.
- [ ] Security/privacy + provenance/legal review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `equipment_sources` schema + rights dimensions | Schema captures every rights dimension the design needs | Schema reviewed, no dimension added ad hoc later |
| T2 — Quarantine rules | A record with unknown rights cannot reach display/training/embedding paths | Enforced by test, not by reviewer discipline |
| T3 — Source-priority policy + terms-capture format | Conflicting sources resolve deterministically by priority | Format documented and used by at least one real source |

### P0.G4 — Catalog version & type snapshot

CLASSIFICATION: FOUNDATION · Source: v4.1 §9, unchanged

Purpose. Create authoritative catalog-version semantics without duplicating `equipment.json` as a
second source of truth.

Inputs. `equipment.json` and the exact-model schema.

Required review. Architecture + ontology review.

Rollback / failure mode. Regenerate snapshot from `equipment.json`; never hand-edit a duplicate type
catalog.

**Story AC:** a build test fails if `primaryTypeId` references a nonexistent `equipmentId`; the
snapshot hash/version is deterministic across identical inputs.

**Story DoD:**
- [ ] Server validates exact models against the current functional type snapshot.
- [ ] Architecture + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Generated immutable type snapshot | Snapshot is generated, not hand-authored, from `equipment.json` | Regeneration from the same input yields the same hash |
| T2 — Catalog version manifest | Manifest ties a version to a specific snapshot hash | Manifest consumed by server validation, not decorative |
| T3 — Build-time referential check | Nonexistent `equipmentId` reference fails the build | CI demonstrates the failure on a deliberately broken input |

### P0.G5 — Cloud feasibility, IAM, region & SDK spike

CLASSIFICATION: FOUNDATION / ARCHITECTURE · Source: v4.2 rewrite (closes the region MAJOR)

Purpose. Prove the preferred Firebase/Vertex/Firestore vector path fits the actual project — region
is a fixed input, not an open architecture choice.

Inputs. `functions/src/scaling.ts`'s existing `REGION = "europe-west1"` constant, pinned to the
current `eur3` Firestore location and baked into every already-deployed function URL including
`stripeWebhook`; current IAM/service accounts; Vertex regional availability.

Required review. Firebase/backend + security + architecture review.

Rollback / failure mode. Stay OCR/text-only and postpone visual retrieval (unaffected by P6-T).

**Story AC:** exactly one of three outcomes is recorded with evidence — colocated, deliberately
split-region with a measured latency budget, or stay OCR/text-only — and no outcome moves or
duplicates the existing region for already-deployed payment/account functions.

**Story DoD:**
- [ ] One of the three outcomes chosen and recorded, not left open-ended.
- [ ] `stripeWebhook`'s region/URL provably untouched by the decision.
- [ ] Firebase/backend + security + architecture review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Real staging-project KNN smoke test | Smoke test runs against a real staging project, not just emulator | Result recorded with latency/cost numbers |
| T2 — App Check callable smoke test | Callable path tested under both enforcement states relevant to shadow/production | Pass/fail recorded per state |
| T3 — Region outcome decision | One of (a) colocated / (b) split-region with latency budget / (c) OCR/text-only defer chosen | Decision documented with the evidence that drove it |

### P0.G6 — Functions deployment isolation decision

CLASSIFICATION: FOUNDATION / ARCHITECTURE · Source: v4.2 new gate (closes the "15 new files" MAJOR)

Purpose. Decide, with evidence, how a new ML/Vertex/vector-search workload is added to the existing
shared, multi-domain Functions codebase without risking already-shipped paths, especially
`stripeWebhook`.

Inputs. `firebase.json`'s single `"default"` codebase declaration; `functions/src/scaling.ts`'s
existing per-function scaling profiles and their stated rationale; the ~15 new TypeScript files the
design's file plan introduces.

Required review. Backend/architecture + release engineering review.

Rollback / failure mode. Disable identity Functions exports entirely; existing domains unaffected.

**Story AC:** a deliberately-broken identity-module TypeScript error does NOT block a
`stripeWebhook` hotfix deploy under the chosen design — this is the actual acceptance test, not an
architectural assertion.

**Story DoD:**
- [ ] Isolation strategy chosen ((a) separate codebase or (b) selective deploy + lazy init +
      dedicated `IDENTITY` scaling profile) and documented.
- [ ] Stripe emulator/e2e regression check exists and passes before every identity-backend deploy.
- [ ] Backend/architecture + release engineering review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Isolation strategy decision | (a) or (b) chosen with evidence, not by default | Decision documented with the regression test proving it |
| T2 — New `IDENTITY` scaling profile | Profile has its own `maxInstances`/memory override in `scaling.ts` | Profile merged and referenced by identity Functions |
| T3 — Stripe regression check wired to identity deploys | A deliberately-broken identity module does not block `stripeWebhook` | CI/deploy pipeline demonstrates this live, not by inspection only |

---

## Phase P1 — Canonical Machine Knowledge Base

**Epic AC:** ontology/schema (P1.G1) is in place and access-controlled before any adapter (P1.G2-4)
writes to it; reconciliation (P1.G5) resolves the pilot catalog; the publish pipeline (P1.G6) is the
only path any status reaches `VERIFIED`/`ACTIVE`.
**Epic DoD:** all 6 gates closed; P1.G1's mutation-test suites both green in CI; no adapter or
pipeline bypasses `firestore.rules`'s authority boundary.

### P1.G1 — Equipment identity ontology & Firestore schema

CLASSIFICATION: POST_MVP_HIGH · Source: v4.2 extension (closes B-02) + v4.4 extension
(RecognitionAuthorityTuple immutability)

Purpose. Implement additive Brand/ProductLine/EquipmentModel/Asset/Source/ExternalMapping/SetupSpec
boundaries and the access-control boundary that makes "server authority" real.

Inputs. P0 outputs, current equipment ontology, current `firestore.rules`'s wildcard-exclusion
pattern.

Required review. Flutter/architecture + ontology + Firebase/backend + security review.

Rollback / failure mode. Schema changes remain additive; no migration of exercise `equipmentId`; an
unpassed mutation-test suite blocks this gate's exit, full stop.

**Story AC:** the emulator mutation-test suite passes (client CREATE/UPDATE authority fields →
DENY, server/admin write → ALLOW, cross-account → DENY, using the existing `test:rules` npm script);
a session-mutation test proves no code path can update a pinned `RecognitionAuthorityTuple` field
once written — only replace the whole session via a new `recognitionSessionId`.

**Story DoD:**
- [ ] Can represent 50 pilot models without changing `equipmentId` semantics.
- [ ] Both mutation-test suites (rules + session-authority) pass in CI.
- [ ] Flutter/architecture + ontology + Firebase/backend + security review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Schemas, converters, validators, indexes | Schema validation + multi-function model tests pass | `modelId`/`canonicalSlug` uniqueness enforced |
| T2 — `firestore.rules` authority exclusions | `recognised_models`/`equipment_identity_sessions`/identity telemetry excluded from `users/{uid}/**` client-write wildcard | `test:rules` suite proves DENY/ALLOW/DENY as specified |
| T3 — `firestore.indexes.json` entries | Every new query pattern (including vector indexes) has an index | Queries run without missing-index errors |
| T4 — Pinned `RecognitionAuthorityTuple` immutability | No code path can mutate a pinned field post-write | Session-mutation test in CI, added per v4.4 |

### P1.G2 — Official P0 brand adapters

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Populate canonical metadata from first-party sources (Technogym, Life Fitness/Hammer
Strength, Matrix, Core/Nautilus).

Inputs. First-party brand sources listed above.

Required review. Data/provenance + ontology review.

Rollback / failure mode. Adapter breakage quarantines updates; existing published catalog remains
unchanged.

**Story AC:** fixture-based parser tests pass; source-change detection fires on drift; disagreements
surface as findings, never silent overwrites.

**Story DoD:**
- [ ] Pilot brand metadata has official sources and 100% provenance fields.
- [ ] Data/provenance + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Read-only metadata adapters (4 brands) | Each adapter has a fixture-based parser test | Adapter output normalized to the P1.G1 schema |
| T2 — Provenance fields on every record | Source ref present on 100% of ingested records | Verified by schema-level check, not spot-check |
| T3 — Conflict reports | Disagreeing sources produce a visible report, not a silent pick | Report reviewed by ontology curator before any promotion |

### P1.G3 — P1 brand adapters

CLASSIFICATION: POST_MVP · Source: v4.1 §9, unchanged

Purpose. Extend official metadata coverage to Precor/Panatta.

Inputs. P1 official sources; same contracts as P1.G2.

Required review. Data/provenance + ontology review.

Rollback / failure mode. Disable adapter on source drift.

**Story AC:** same parser/source-drift tests as P1.G2 pass for the two new brands.

**Story DoD:**
- [ ] Coverage report complete; no silent overwrite of P0-brand (P1.G2) records.
- [ ] Data/provenance + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Precor adapter | Fixture-based parser test passes | Coverage report includes Precor |
| T2 — Panatta adapter | Fixture-based parser test passes | Coverage report includes Panatta |

### P1.G4 — WGER_REFERENCE_INGESTION

CLASSIFICATION: POST_MVP_HIGH / ENRICHMENT · Source: v4.1 §9, unchanged

Purpose. Build read-only exercise enrichment staging and a mapping report.

Inputs. wger API/data model and per-entry licenses.

Required review. Ontology + content/safety + provenance review.

Rollback / failure mode. Delete staging/import output without product impact.

**Story AC:** no production writes occur; deletion/replacement sync fixture and license-preservation
test both pass.

**Story DoD:**
- [ ] Staging snapshot and mapping report reproducible with per-object provenance.
- [ ] Production reuse is separately license-gated (explicitly not unlocked by this gate).
- [ ] Gate confirmed OPTIONAL/PARALLEL — does not block P2 machine identity.
- [ ] Ontology + content/safety + provenance review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Staging snapshot | Snapshot reproducible from source with per-object license/provenance | No production collection touched |
| T2 — External mappings | Matched/unmatched/alias/muscle/equipment/variation report generated | Report reviewed, disagreements visible |
| T3 — License preservation test | Per-object license survives ingestion unmodified | Test proves no license field is dropped or altered |

### P1.G5 — Catalogue reconciliation

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Compare the SPTR functional catalog, exact models, and external exercise/source data.

Inputs. P1.G1-G4 outputs.

Required review. Ontology curator + product/data review.

Rollback / failure mode. No production write for an unresolved conflict.

**Story AC:** the reconciliation report is deterministic; no unresolved conflict is ever
auto-promoted.

**Story DoD:**
- [ ] All pilot models have a resolved `primaryTypeId`; unresolved conflicts are explicitly
      AMBIGUOUS/STAGING.
- [ ] Ontology curator + product/data review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Missing/duplicate/conflict detection | Report enumerates missing models, duplicate aliases, type conflicts | Deterministic re-run produces the same report on unchanged input |
| T2 — Source/exercise-mapping disagreement resolution | Disagreements resolved or explicitly left AMBIGUOUS | No conflict silently defaults to one source |

### P1.G6 — Catalog publication pipeline

CLASSIFICATION: POST_MVP_HIGH · Source: v4.2 new gate (closes the ownership gap behind
P2.G3's `textSupportStatus: VERIFIED` dependency)

Purpose. Own the SOURCE → STAGING → NORMALIZE → VALIDATE → DIFF → REVIEW → IMMUTABLE CATALOG
VERSION → PRODUCTION publish pipeline that v4.1's file plan named but no gate actually built.

Inputs. P1.G1 schema, P0.G3 rights registry.

Required review. Backend + ontology + governance review.

Rollback / failure mode. Freeze at the last known-good active version.

**Story AC:** a version can be published, reviewed, activated, and rolled back without hand-editing
a duplicate catalog; no adapter/scraper can auto-publish.

**Story DoD:**
- [ ] Reviewed-diff approval required before any version becomes active.
- [ ] Rollback to a prior version tested, not just designed.
- [ ] Interim `textSupportStatus: EXPERIMENTAL` promotion path exists, staging-only, never
      user-facing.
- [ ] Backend + ontology + governance review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Staged publish pipeline (7 stages) | Each stage is real, owned code, not a placeholder | End-to-end run demonstrated on a real diff |
| T2 — Atomic `activeCatalogVersion` pointer switch | Switch is atomic; no partial-version read is possible | Tested under a simulated mid-switch read |
| T3 — Interim `EXPERIMENTAL` promotion path | Path is staging-only, auditable, never reaches users | P2.G3/P2.G5 can produce OCR-only evidence through it |
| T4 — Rollback test | A prior version can be reactivated | Rollback exercised at least once, result recorded |

---

## Phase P2 — OCR-first Identity

**Epic AC:** structured OCR (P2.G1) → parsed evidence (P2.G2) → server-resolved exact IDs (P2.G3)
→ mobile-visible identity (P2.G4) chain works end to end in shadow; the GO/DEFER checkpoint (P2.G5)
is a real decision, not a formality.
**Epic DoD:** all 5 gates closed; existing generic scanner tests (`scanner_page_test.dart`,
`scan_controller_test.dart`) pass completely unmodified throughout.

### P2.G1 — Structured OCR capability

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9 + v4.2 clarification (closes the `implements` MINOR)

Purpose. Extend the ML Kit OCR contract to return lines/bounds/confidence while preserving the
existing String API.

Inputs. Current `mlkit_text_recogniser` + `machine_text_anchor`.

Required review. Flutter reviewer.

Rollback / failure mode. Feature flag/adapter can fall back to the legacy String path.

**Story AC:** device/plugin tests + pure unit tests pass; generic anchor behavior is unchanged;
`StructuredTextRecogniser` is implemented as a separate interface probed with an `is` check at call
sites (mirroring `FallbackReportingRecogniser`) — never added as a new abstract member of
`MachineTextRecogniser`, which would break existing `implements`-based fakes
(`FakeMachineTextRecogniser`).

**Story DoD:**
- [ ] Existing generic OCR tests pass unmodified.
- [ ] Structured lines/bounds available via the new interface.
- [ ] `FakeMachineTextRecogniser` and other `implements`-based fakes still compile.
- [ ] Flutter reviewer signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `MachineTextEvidence` model | Lines/bounds/confidence represented | Model reviewed, backward-compatible |
| T2 — `StructuredTextRecogniser` separate interface | Probed with `is` check, not merged into base interface | Existing fakes compile unchanged |
| T3 — Backward-compatible adapter | Legacy String API still returns correct output | Feature-flag fallback verified |

### P2.G2 — IdentityTextParser

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Parse brand/line/model/SKU/type hints without altering generic denoising.

Inputs. Structured OCR + catalog aliases.

Required review. Flutter + ontology + adversarial QA.

Rollback / failure mode. Parser failure yields no identity evidence; generic scan unaffected.

**Story AC:** hard cases pass — two machines in frame, neighbour placard, two model codes, OCR
noise, brand-only text.

**Story DoD:**
- [ ] No silent exact selection with conflicting codes.
- [ ] Deterministic evidence output.
- [ ] Flutter + ontology + adversarial QA review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Pure parser + normalized tokens | Parser is pure (no side effects), tokens normalized | Unit-tested against all 5 hard cases |
| T2 — Conflict detection | Two conflicting codes never silently resolve to one | Conflict surfaced as evidence, not hidden |
| T3 — Centrality/placard heuristics | Placard-vs-neighbour-machine text is distinguishable | Heuristic tested against the neighbour-placard hard case |

### P2.G3 — Server exact text lookup

CLASSIFICATION: POST_MVP_HIGH · Source: v4.2 rewrite (closes the rate-limiter duplication and the
App Check dependency)

Purpose. Resolve unique strong text evidence against the authoritative catalog without image
upload.

Inputs. P2.G2 + `equipment_models` + catalog version + the existing `abuse_guard.ts` transactional
quota mechanism + P0.G0's App Check platform-readiness status.

Required review. Backend/security + ontology review.

Rollback / failure mode. Disable text exact policy; return type-only.

**Story AC:** unique/nonunique code tests, type compatibility, and rights-independent catalog
lookup all pass; App Check enforcement is conditional on P0.G0 readiness (shadow: may be off;
production: inherits the platform's staged rollout, never independently asserted true); rate
limiting goes through the existing `abuse_guard.ts`/`users/{uid}/usage/{day}` mechanism — never a
new competing `rate_limit.ts`.

**Story DoD:**
- [ ] Verified text-supported (P6-T `VERIFIED`) pilot models return shadow exact IDs with full
      evidence/versioning, including `textPolicyVersion`.
- [ ] No second, incompatible quota store exists.
- [ ] Backend/security + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Cloud Function text path + indexes | Unique/nonunique code tests pass | Model-code/alias indexes deployed |
| T2 — Identity-scan quota class in `abuse_guard.ts` | No new competing rate-limit store created | Quota class added to the existing mechanism only |
| T3 — App Check conditional enforcement | Enforcement state follows P0.G0's status, not a hardcoded flag | Shadow/production behavior both tested |
| T4 — `textPolicyVersion` field | Every response carries the policy version used | Field present and versioned in evidence records |

### P2.G4 — Additive mobile identity contract & progressive UX plumbing

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9 (Purpose) + v4.2 rewrite (Deliverables, per §7.1)

Purpose. Add `EquipmentIdentity` to the result UI without changing `VisualMatch` or generic scanner
history.

Inputs. P2.G3 API contract.

Required review. Flutter/product UX + safety review.

Rollback / failure mode. Disable identity enrichment flag; generic scanner behavior remains
identical.

**Story AC:** `EquipmentIdentity` is served by a separate `family(scanId)` provider, never merged
into `ScanResult` (binding rule, §7.1); `NEED_MORE_VIEW` renders as a plain re-scan prompt until
P5.G1 ships guided multi-view, and is excluded from P2.G5's value-checkpoint arithmetic until then;
widget/state tests cover type-only/brand/exact/needMoreView/unknown/cancelled/unavailable states;
**`scanner_page_test.dart` and `scan_controller_test.dart` pass completely unmodified** — this is
the literal, testable definition of "additive" for this gate.

**Story DoD:**
- [ ] Exact identity shown in non-production/shadow UI without blocking exercises.
- [ ] Both pre-existing generic test files pass byte-for-byte unmodified.
- [ ] Flutter/product UX + safety review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `family(scanId)` provider | Not merged into `ScanResult` | Verified by code review against §7.1's binding rule |
| T2 — Progressive type-first rendering | No spinner dependency on exact identity | UI renders type result before identity resolves |
| T3 — `NEED_MORE_VIEW` interim prompt | Plain re-scan prompt, excluded from P2.G5 arithmetic | Excluded flag verified in the value-checkpoint report |
| T4 — Regression proof | `scanner_page_test.dart`/`scan_controller_test.dart` unmodified | Diff shows zero changes to those two files |

### P2.G5 — OCR-only shadow & value checkpoint

CLASSIFICATION: POST_MVP_HIGH / GO-NO-GO · Source: v4.1 §9, unchanged (now explicitly feeds the
P6-T lane per v4.2, rather than being a dead end)

Purpose. Prove that Brand → Line → Model catalog + structured OCR creates enough real user value to
justify the more expensive visual-retrieval phases now.

Inputs. Shadow text identity on real scans, latency, exact text-resolution rate, need-more-view
rate, catalog coverage, and product value evidence.

Required review. Product + ML/data + architecture.

Rollback / failure mode. No sunk-cost escalation — catalog/OCR value remains useful either way.

**Story AC:** no production exact claim is made unless `textSupportStatus` and policy gates already
pass; comparison against the current generic scanner never uses sealed blind-test labels.

**Story DoD:**
- [ ] GO_VISUAL / DEFER_VISUAL decision explicitly recorded, not implied.
- [ ] GO only if visual retrieval has a measured unmet need.
- [ ] Product + ML/data + architecture review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — OCR-only quality/value report | Report built from real shadow data, not projections | Report reviewed by product + ML/data |
| T2 — GO_VISUAL / DEFER_VISUAL decision | Decision explicit, evidence-backed | Recorded in decision log with the evidence cited |

---

## Phase P3 — Licensed Corpus & Golden Set

**Epic AC:** every asset used downstream (P4, P6) traces to an explicit rights grant (P3.G1); sealed
evaluation sets (P3.G2) are genuinely inaccessible to implementation/tuning; the training corpus
(P3.G3) never touches sealed data.
**Epic DoD:** all 3 gates closed; independent custody arrangement for P3.G2's sealed sets confirmed
in writing.

### P3.G1 — Rights-approved asset acquisition

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Acquire only assets whose intended use is explicitly allowed.

Inputs. P0.G3 registry + P1 pilot catalog.

Required review. Provenance/legal + data review.

Rollback / failure mode. Quarantine/delete derivative copies; catalog metadata remains.

**Story AC:** 100% of assets carry source URL/hash/retrieval date/rights dimensions; pHash dedup
runs before any downstream use.

**Story DoD:**
- [ ] No asset with unknown rights enters shippable display, embeddings, or training corpus.
- [ ] Provenance/legal + data review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Hashed asset manifests | Every asset has hash, source URL, retrieval date | 100% coverage verified |
| T2 — Rights/provenance labels | Rights dimension recorded per asset | Unknown-rights assets flagged, not defaulted to allowed |
| T3 — pHash dedup | Duplicate assets detected before use | Dedup run logged and reviewed |

### P3.G2 — Development regression/calibration sets + sealed blind test v1

CLASSIFICATION: RELEASE-BLOCKING EVALUATION FOUNDATION · Source: v4.1 §9, unchanged

Purpose. Separate engineer-visible development evidence from calibration and a genuinely sealed
independent production test.

Inputs. `LEGACY_REAL_GYM_REGRESSION_SET`, newly acquired independent physical instances/gyms,
explicit OOD/hard-negative collection.

Required review. ML/data + adversarial QA + ontology review.

Rollback / failure mode. If the sample is too small, production exact claim remains blocked.

**Story AC:** no physical-instance leakage between sets; pHash duplicate grouping run; sealed labels
genuinely inaccessible to implementation/tuning, under independent custody.

**Story DoD:**
- [ ] `DEV_REGRESSION_SET`, `CALIBRATION_SET`, `SEALED_BLIND_REAL_GYM_TEST_SET`,
      `SEALED_OOD_TEST_SET` all exist with instance/gym IDs and hidden labels/results.
- [ ] Independent custodian/runner arrangement confirmed.
- [ ] ML/data + adversarial QA + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `DEV_REGRESSION_SET` + `CALIBRATION_SET` | Engineer-visible, no sealed labels mixed in | Sets built and reviewed |
| T2 — `SEALED_BLIND_REAL_GYM_TEST_SET` | Labels held by an independent custodian | Access-control test proves implementation team cannot read labels |
| T3 — `SEALED_OOD_TEST_SET` | Explicit OOD/hard-negative collection, sealed | Same access-control test applied |
| T4 — Instance-leakage check | No physical instance appears across DEV and SEALED sets | pHash + instance-ID cross-check run and recorded |

### P3.G3 — Training/reference corpus v1

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Build a rights-clean, engineer-visible reference/training corpus for retrieval/fusion
development without consuming sealed evaluation evidence.

Inputs. P3.G1 approved assets, explicitly eligible training/reference acquisitions, source
manifests and dev-only hard negatives; excludes `SEALED_*` sets.

Required review. ML/data + provenance review.

Rollback / failure mode. Quarantine an ineligible source/domain and rebuild from remaining
manifests without contaminating sealed tests.

**Story AC:** class/brand/viewpoint balance checked; pHash duplicate grouping run before split;
physical-instance/gym leakage checks pass; `SEALED_*` identifiers are absent from the corpus.

**Story DoD:**
- [ ] Corpus rebuildable from manifests.
- [ ] Every included asset eligible for its intended use.
- [ ] Synthetic/manufacturer/real-gym provenance stays separable.
- [ ] ML/data + provenance review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `TRAIN_REFERENCE_CORPUS` manifest | Rebuildable, labeled by model/instance/viewpoint/source | Manifest committed, hashes verified |
| T2 — `SEALED_*` absence check | No sealed identifier appears in the corpus | Automated check run against the manifest |
| T3 — Hard-negative coverage | Dev-only hard negatives present and labeled | Coverage reviewed by ML/data |

---

## Phase P4 — Visual Retrieval & Decision Quality

**Epic AC:** retriever choice (P4.G1) is benchmark-justified; fusion (P4.G2) does not let one weak
signal dominate; calibration (P4.G3) is frozen before any sealed evaluation; the Gemini verifier
(P4.G4) never becomes a requirement for a type result.
**Epic DoD:** all 4 gates closed; P4.G3's frozen policy version is the one P6.G2 actually evaluates
— never a later, silently different version.

### P4.G1 — Embedding provider & retriever benchmark

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Add image embeddings and choose the simplest server-side retriever that meets measured
pilot latency/cost/quality.

Inputs. P3 corpus/exemplars, Vertex multimodal embedding, Firestore vector indexes.

Required review. Backend/security + ML review.

Rollback / failure mode. Turn off visual path; OCR/type path remains.

**Story AC:** version/dimension compatibility and `catalogVersion` filtering checked; top-K
correctness verified; latency/cost benchmarked; no protected exemplar leaks to the client.

**Story DoD:**
- [ ] Retriever choice justified by benchmark; Firestore stays preferred if it clears the bar.
- [ ] Backend/security + ML review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `EmbeddingProvider`/`VectorRetriever` interfaces | Interfaces implemented against Vertex + Firestore KNN | Interchangeable without touching callers |
| T2 — Top-K correctness + no-leakage test | Top-K matches expected; no exemplar data reaches the client | Both tests pass in CI |
| T3 — Latency/cost benchmark | Real numbers recorded at pilot scale | Benchmark reviewed against P0.G5's region decision |

### P4.G2 — Evidence fusion

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9 (Deliverables/Verification/Exit/Rollback) + v4.2
Purpose correction (fixes a copy-paste defect that had duplicated P4.G3's text)

Purpose. Fuse visual retrieval, structured OCR, generic type evidence, and optional logo/viewpoint
evidence into ranked model candidates without allowing one weak signal to silently dominate. This
gate does not perform calibration — see P4.G3.

Inputs. P4.G1 retriever outputs + P2 structured text evidence + `typeEvidenceStatus` + catalog
compatibility.

Required review. ML/data + ontology review.

Rollback / failure mode. Disable fusion and return ranked retrieval/text candidates with abstention;
generic type path stays intact.

**Story AC:** ablation tests, conflicting-brand/model/type tests, missing-signal tests,
neighbouring-placard cases, and exemplar-count/viewpoint bias checks all pass.

**Story DoD:**
- [ ] Fusion improves candidate ranking/recall at fixed safety constraints versus each single
      signal.
- [ ] No weak feature alone converts conflict into exact identity.
- [ ] ML/data + ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Versioned fusion policy | Per-signal feature contract + conflict rules documented | Policy versioned, referenced by evidence records |
| T2 — Candidate aggregation by `modelId` | Aggregation deterministic | Ablation tests pass |
| T3 — `rawCandidateScore` + diagnostics | Score and per-signal diagnostics attached to every candidate | Consumed by P4.G3 calibration, not re-derived |

### P4.G3 — Calibration & open-set gate

CLASSIFICATION: RELEASE-BLOCKING · Source: v4.1 §9 (Verification/Exit/Rollback) + v4.2 Purpose
correction + Deliverables extension (Clopper-Pearson naming, fusion/calibration split)

Purpose. Turn P4.G2's fused raw candidate scores into a calibrated, per-identity-level confidence,
and define the abstention/open-set policy.

Inputs. `CALIBRATION_SET` + dev OOD/hard negatives + frozen P4.G2 fusion outputs. `SEALED_*`
labels/results remain inaccessible.

Required review. ML/data + adversarial reviewer.

Rollback / failure mode. Raise thresholds, restrict support status, or disable exact claim;
TYPE_ONLY / BRAND+TYPE remain available.

**Story AC:** calibration-set reliability, dev-OOD false-exact analysis, per-brand/line confusion,
and sensitivity/threshold stability all checked; no sealed-test tuning occurs; the exact one-sided
Clopper-Pearson method is explicitly named.

**Story DoD:**
- [ ] Calibration artifact explicitly names the fusion→calibration split (which function produces
      the raw score, which calibrates it).
- [ ] Curve count checked against the calibration set's minimum ~20-images/model target — revisited
      if inadequate for the number of curves actually required (4 identity levels).
- [ ] A frozen calibrated policy version is ready for shadow and later sealed P6 evaluation;
      production exact-model claim remains blocked until P6.
- [ ] ML/data + adversarial reviewer signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Calibration artifact (fusion/calibration split named) | Reliability/ECE/Brier reported per evidence class | Artifact reviewed and versioned |
| T2 — Thresholds by identity level/evidence class | Curve count matches actual identity-level count | Sample-size adequacy explicitly checked, not assumed |
| T3 — One-sided Clopper-Pearson method named | Method explicitly stated, not implied | Referenced identically in P6.G2/P6.G3 |
| T4 — Frozen policy version | Policy version locked before any sealed evaluation | Version ID recorded, immutable from this point |

### P4.G4 — Candidate-bounded Gemini verifier

CLASSIFICATION: POST_MVP · Source: v4.1 §9 + v4.2 extension (`verifierInvoked` field)

Purpose. Use Gemini only to adjudicate real retrieved candidates.

Inputs. Top 3-5 candidates + image/evidence.

Required review. AI/backend + safety/security review.

Rollback / failure mode. Disable verifier without breaking retrieval/fusion.

**Story AC:** schema enforcement rejects a hallucinated candidate ID; verifier-off comparison run to
measure actual uplift.

**Story DoD:**
- [ ] Verifier improves measured decision quality, or is rejected based on the comparison.
- [ ] Never required for a type-only result.
- [ ] Every response carries the mandatory `verifierInvoked` field, and P4.G3's stated
      threshold policy applies when the verifier did not run.
- [ ] AI/backend + safety/security review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Structured MATCH/UNKNOWN/NEED_MORE_VIEW response | Schema-enforced, hallucinated ID rejected | Response includes `candidateId`/`nextView`/`evidence` |
| T2 — `verifierInvoked` field | Present on every response, true/false | P4.G3's non-invoked threshold policy applies when false |
| T3 — Verifier-off comparison | Measured uplift (or lack of it) recorded | Decision to keep/reject verifier based on this data |

---

## Phase P5 — Product UX & Machine Memory

**Epic AC:** guided multi-view (P5.G1) resolves ambiguity without losing the generic result; the
equipment page (P5.G2) never changes vetted safety eligibility; exact/instance history (P5.G3/G4)
never leaks across accounts; user correction (P5.G5) exists before any public exact-model claim.
**Epic DoD:** all 5 gates closed; P5.G4 confirmed genuinely optional (not a P6 prerequisite).

### P5.G1 — Guided multi-view

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Ask for the discriminating next view instead of guessing.

Inputs. `NEED_MORE_VIEW` response and the existing `CameraSession`.

Required review. Flutter/UX + QA review.

Rollback / failure mode. Cancel multi-view and keep generic type.

**Story AC:** widget/device flow tests pass; stale scans cancel correctly; conflicting views cause
abstention, not a forced pick.

**Story DoD:**
- [ ] Ambiguous sibling models can request a useful second view without losing the generic result.
- [ ] Flutter/UX + QA review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Guided PLACARD/LOGO/SIDE/FULL capture | Each view type has a distinct capture flow | Widget tests cover all four |
| T2 — Multi-view evidence aggregation | Conflicting views produce abstention | Tested with a deliberately conflicting pair |

### P5.G2 — Exact-model equipment page & verified setup

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Enrich the existing `EquipmentDetailPage` rather than create a second product.

Inputs. Verified `EquipmentIdentity` + `SetupSpec`.

Required review. Flutter/product + safety review.

Rollback / failure mode. Strip model context; generic page still works.

**Story AC:** exact vs. ambiguous vs. type-only UI states tested; setup facts never render if not
verified.

**Story DoD:**
- [ ] Exact identity enriches the page but cannot change vetted exercise/safety eligibility.
- [ ] Flutter/product + safety review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Route/optional model context | Page works with and without model context | No regression to the generic page |
| T2 — Source-qualified setup facts | Only shown when verified | Test proves no setup fact renders for unverified identity |

### P5.G3 — Exact history

CLASSIFICATION: POST_MVP_HIGH · Source: v4.1 §9, unchanged

Purpose. Remember exact models separately from generic equipment history.

Inputs. Verified exact identity events.

Required review. Privacy/security + Flutter review.

Rollback / failure mode. Disable exact history writes.

**Story AC:** account isolation, delete/logout behavior, and duplicate/update semantics all tested.

**Story DoD:**
- [ ] No cross-account leak.
- [ ] Ambiguous/alternative results are never remembered as exact.
- [ ] Privacy/security + Flutter review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — `users/{uid}/recognised_models` records | Versions + evidence summary present; no raw photo by default | Schema matches P1.G1's authority rules |
| T2 — Account isolation test | Cross-account read/write denied | Emulator test proves DENY |

### P5.G4 — Private PhysicalMachineInstance memory

CLASSIFICATION: POST_MVP / OPTIONAL — NOT A P6 PREREQUISITE · Source: v4.1 §9, unchanged

Purpose. Bind user setup memory to a particular gym machine without contaminating global identity.

Inputs. Existing gym/setup memory foundations + verified model identity.

Required review. Privacy + product/ontology review.

Rollback / failure mode. Fall back to model/type memory only.

**Story AC:** account isolation, identity-downgrade behavior, and ambiguity handling all tested.

**Story DoD:**
- [ ] Setup memory recallable only for the intended user/instance.
- [ ] Never used as sole model proof.
- [ ] Confirmed optional — recognition promotion may proceed without this gate.
- [ ] Privacy + product/ontology review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Private instance record (gymId, modelId, optional fingerprint) | Scoped to one user | Isolation test passes |
| T2 — Identity-downgrade handling | Ambiguity does not silently upgrade to exact | Tested against a deliberately ambiguous case |

### P5.G5 — User correction / misidentification feedback

CLASSIFICATION: RELEASE PREP · Source: v4.1 §9, unchanged

Purpose. Give the user an explicit, safe correction path before public exact-model promotion.

Inputs. Exact/brand/type result card and current unknown/alternative flows.

Required review. Product/UX + privacy + ML governance.

Rollback / failure mode. Disable feedback collection while retaining safe generic fallback.

**Story AC:** correction cannot silently mutate the global catalog or become ground-truth training
data; a11y/l10n and account/privacy behavior tested.

**Story DoD:**
- [ ] Public exact identity has a visible recovery path.
- [ ] Feedback is quarantined as evidence, not truth.
- [ ] Product/UX + privacy + ML governance review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — "Not this model" flow | Reachable from every exact-result state | a11y/l10n tested |
| T2 — Quarantined telemetry event | Not an automatic training label | Test proves no auto-promotion to training data |
| T3 — Optional guided rescan | Offered after a correction | Reuses P5.G1's guided multi-view |

---

## Phase P6 — Shadow, Evaluation & Promotion

**Epic AC:** the evidence-lane invariant (P6.G0) holds before shadow (P6.G1) even starts counting;
sealed evaluation (P6.G2) runs on frozen artifacts only; promotion (P6.G3) is per-model,
pre-registered, and has a rehearsed rollback.
**Epic DoD:** all 4 gates closed in strict order (G0 before G1 before G2 before G3); 0
BLOCKER/CRITICAL/MAJOR on the promoted surface; GPT-PM independent review completed for G3.

### P6.G0 — Evidence-lane separation invariant

CLASSIFICATION: RELEASE-BLOCKING PREREQUISITE, ahead of P6.G1 · Source: v4.4 new gate (closes
N-BLOCKER-1) — already the reference-format gate this whole document imitates

Purpose. Prove, mechanically, that the P6-T text-only promotion lane cannot produce an
`EXACT_MODEL` claim contaminated by visual exact-identity evidence.

Inputs. §6.4.1's `evidenceLane` derivation rule; P4.G2's fusion implementation.

Required review. Backend/ML + release review.

Rollback / failure mode. Until this gate passes, `textSupportStatus: VERIFIED` may not authorize
`identityLevel: EXACT_MODEL` in production for any model that also has visual retrieval/verifier
signals active — such models remain shadow/`NOT_SUPPORTED`-for-`EXACT_MODEL` in production.

**Story AC:** a CI mutation test forces a visual exact-identity discriminator into the fusion path
for a model whose `textSupportStatus == VERIFIED` and `visionSupportStatus != VERIFIED`, and asserts
the response is never `evidenceLane: TEXT_ONLY` with `identityLevel: EXACT_MODEL` — it must instead
report `evidenceLane: VISUAL` and abstain/downgrade.

**Story DoD:**
- [ ] Mutation test exists, is wired into CI, and passes — a manual code-review sign-off does not
      satisfy this gate.
- [ ] Backend/ML + release review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — CI mutation test | Forces contamination scenario, asserts correct abstention | Blocking in CI, not advisory |
| T2 — `evidenceLane` field wired through fusion | Field present on every response, derived server-side | Cannot be set/overridden by client input |

### P6.G1 — Shadow deployment

CLASSIFICATION: RELEASE-BLOCKING PREREQUISITE *(reclassified from POST_MVP/OPTIONAL — v4.2 fixed a
copy-paste of P5.G4's classification, itself one of the confirmed BLOCKERs)* · Source: v4.2
reclassification + v4.4 extension (App-Check-transition evidence-freshness sub-condition)

Purpose. Run the identity backend on real scans without changing the production generic result, to
surface production-traffic failure modes a sealed evaluation cannot.

Inputs. P2-P4 runtime, current scanner, P0.G0's readiness status.

Required review. Release/ML/privacy review.

Rollback / failure mode. Disable shadow flag immediately; this gate's incompletion blocks
P6.G2/G3 — it does not merely delay them informally.

**Story AC:** compare current generic vs. identity-layer outcomes; privacy/telemetry audit passes;
terminal-outcome completeness check confirms every attempt resolves to exactly one §6.5 value;
evidence counted toward the minimum-volume requirement excludes any auth/availability sample
invalidated by a P0.G0 App-Check-mode transition.

**Story DoD:**
- [ ] Defined minimum shadow volume/duration/SLO met (target set once P2-P4 land).
- [ ] Zero unresolved privacy/security MAJOR.
- [ ] This gate's exit formally recorded before P6.G2 may begin — an exception requires an
      explicit, documented release waiver, never a default skip.
- [ ] Release/ML/privacy review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Shadow telemetry at minimum volume | Volume/duration target explicitly set and met | Terminal-outcome completeness check passes |
| T2 — App Check/rate-limit error SLO | SLO defined and measured | Met before P6.G2 opens |
| T3 — Evidence-freshness exclusion (v4.4) | Pre-transition auth/availability samples excluded | Exclusion demonstrated against a real or simulated transition |

### P6.G2 — Independent real-gym evaluation

CLASSIFICATION: RELEASE-BLOCKING · Source: v4.1 §9 + v4.2 extension (split P6-T/P6-V lanes)

Purpose. Measure exact claims on blind real gyms/physical instances, run separately (and
independently sealed) for the P6-T text lane and the P6-V visual lane, using the pre-registered
per-model candidate set and multiplicity-corrected significance level.

Inputs. Frozen artifacts/policy (P4.G3) + sealed blind real-gym and sealed OOD sets (P3.G2).
Thresholds are already locked.

Required review. ML/data + adversarial + release reviewer.

Rollback / failure mode. Remain shadow/text-only/type-only.

**Story AC:** independent evaluator/custodian runs the sealed sets after artifact freeze; multiple
frames from one physical machine are never counted as independent evidence; dual-label/adjudication
used for ambiguous ground truth; §8.2's tightened "independent encounter" definition (minimum
time/context separation, per-instance sample-share cap) is a pass/fail precondition, not a post-hoc
lens.

**Story DoD:**
- [ ] Point metrics plus one-sided 95% confidence bounds, cluster-aware/physical-instance analysis,
      calibration, abstention, latency/cost, confusion matrices produced.
- [ ] P6-T and P6-V lanes evaluated separately, both sealed independently.
- [ ] Statistical confidence gates pass for the defined promoted model set — otherwise remain
      shadow/text-only/type-only.
- [ ] ML/data + adversarial + release reviewer signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — P6-T sealed evaluation run | Independent custodian, frozen text-lane artifacts | Confidence bounds computed |
| T2 — P6-V sealed evaluation run | Independent custodian, frozen visual-lane artifacts | Confidence bounds computed |
| T3 — Independent-encounter precondition | Minimum time/context separation + per-instance sample-share cap enforced | Enforced as pass/fail gate, not analysis-only |

### P6.G3 — Model-by-model promotion

CLASSIFICATION: PRODUCTION PROMOTION · Source: v4.1 §9 (Verification base) + v4.2 correction (fixes
a copy-paste of P6.G2's text; binds the pre-registration rule and rollback-runbook requirement)

Purpose. Promote only models whose pre-registered, individually-corrected confidence bound (per
§8.2) actually passes.

Inputs. P6.G2's evaluation output; the promotion decision's own rollback target.

Required review. Release + safety + ontology + GPT-PM independent review (per §10).

Rollback / failure mode. Demote model to SHADOW/SUPPORTED/CATALOG_ONLY within the runbook's stated
latency target — a measured SLA, not an unmeasured capability claim.

**Story AC:** promotion mutation test — an unsupported model must abstain (`NOT_SUPPORTED`, per
§6.5); the rollback drill is actually re-run on the stated cadence, not only once.

**Story DoD:**
- [ ] A promotion decision exists per pre-registered candidate model, each with its own
      individually-corrected (Bonferroni or hierarchical) confidence bound.
- [ ] An actual operational runbook exists: named trigger metric/alert with a specific threshold,
      named owner/on-call role, maximum detection-to-demotion latency target, rehearsed drill with a
      stated re-test cadence.
- [ ] 0 BLOCKER/CRITICAL/MAJOR for the promoted surface; evidence attached; the runbook drill has a
      recent, dated pass.
- [ ] Release + safety + ontology + GPT-PM independent review signed off.
- [ ] Decision log entry recorded.

**Tasks:**

| Task | Acceptance Criteria | Definition of Done |
| --- | --- | --- |
| T1 — Per-model promotion decision | Pre-registered candidate set only, no post-hoc addition | Individually-corrected confidence bound attached |
| T2 — Named rollback runbook | Trigger metric, owner, latency target all named | Not a placeholder "alert exists" statement |
| T3 — Rehearsed rollback drill | Drill actually run, not only designed | Re-run on the stated cadence, dated pass recorded |
| T4 — Promotion mutation test | Unsupported model abstains as `NOT_SUPPORTED` | Test passes in CI |

---

# Part 3 — What this document does not do, and the tradeoff it accepts

- It does not open any implementation gate. No gate above is OPEN as of this document.
- It does not change any binding text in the v4.1–v4.4 design documents; every AC/DoD here
  consolidates already-binding text, cross-checked against the source sections cited inline.
- **It deliberately abandons GPT-PM's two-tier proposal** (lightweight Gate Contracts now,
  full AC/DoD just-in-time per gate) in favor of full AC/DoD for all 34 gates immediately, per
  direct operator instruction overriding that earlier plan. GPT-PM's own stated risk for this
  choice, verbatim from the prior round: *"полный детальный AC/DoD для всех P0–P6 сейчас писать не
  стоит — это почти гарантированно создаст stale-spec/rework, потому что реальные ограничения
  уточняются по мере прохождения предыдущих gates. История с P0.G0 и P6.G1 как раз это уже
  доказала."* Concretely: several Story-level ACs above (P4.G3's curve count vs. sample-size
  adequacy, P0.G5/P0.G6's architecture decisions, P6.G1's minimum-volume target) are stated as open
  checks precisely because their real values are not known until earlier gates close — those items
  will need revisiting when their gate actually opens, which is exactly the rework risk GPT-PM
  flagged. Recorded here rather than hidden, per the operator's own standing evidence-over-inference
  rule — this is a known, accepted tradeoff, not an oversight.
- **Not yet done, and required before this document may be treated as ready for implementation**
  (operator instruction, 2026-08-22): a GPT-PM review round on this document itself. Only after
  that verdict — and any resulting revision — may this be closed as implementation-ready.
