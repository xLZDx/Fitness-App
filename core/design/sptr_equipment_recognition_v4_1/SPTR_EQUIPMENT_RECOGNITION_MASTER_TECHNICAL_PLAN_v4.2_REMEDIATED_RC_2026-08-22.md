SPTR / Fitness-App

# Equipment Recognition Master Technical Plan v4.2 — Remediated Review Candidate

Single design authority: v4.1 CONSENSUS + independent Claude/GPT-PM cross-review (2026-08-22) that superseded it

| Field | Value |
| --- | --- |
| Project | xLZDx/Fitness-App |
| Canonical branch | master |
| Repository baseline (v4.1, unchanged) | 3dd2e3e23e2a30c0e99a6995a1229acc5a0834a7 |
| Repository baseline re-verified for this revision | 532235d35d320b340929a736cae40c5e1661f5d5 (8 commits ahead of the v4.1 baseline; the files this document cites as repository truth are unchanged across that range, confirmed empty diff) |
| Document status | REMEDIATED REVIEW CANDIDATE — pending round-2 consensus with GPT-PM. Not yet APPROVE. |
| Predecessor status | v4.1 CONSENSUS (APPROVE FOR PHASED IMPLEMENTATION) was SUPERSEDED 2026-08-22 by independent Claude+GPT-PM cross-review: 4 BLOCKER confirmed, see `core/review/SPTR_EQUIPMENT_RECOGNITION_V4_1_INDEPENDENT_VERDICT_2026-08-22.md`. |
| Production exact-model claim | BLOCKED until P6 sealed blind evaluation + statistical confidence bounds + calibration/open-set gate + model-by-model promotion + all four v4.1 BLOCKERs closed |
| Workstream classification | POST_MVP_HIGH. Foundation work (P0, read-only P1) may proceed today. Runtime/promotion implementation is BLOCKED until B-01..B-04 below are closed. |
| Primary design rule | Preserve functional equipmentId; add exact model identity as an additive enrichment layer; **new for v4.2: every exact-identity attempt produces exactly one machine-observable terminal outcome — no silent degradation** |

```text
MASTER DECISION (unchanged from v4.1)
SPTR must own its own canonical Machine Knowledge Base. Official manufacturer data establishes brand/line/model/SKU truth; licensed assets and real gym photos support recognition; wger and other exercise APIs enrich the exercise graph after recognition. Runtime evolution is additive: current equipmentId, safety, exercise filtering, CameraSession, ScanOutcome and generic recognition remain authoritative foundations. Exact identity may improve the answer, but it may never bypass existing safety or turn uncertainty into a fabricated exact model.
```

```text
NEW MASTER INVARIANT FOR v4.2 (proposed by GPT-PM, accepted by Claude, the unifying conclusion of the silent-failure half of the 2026-08-22 cross-review)

NO SILENT DEGRADATION
Every exact-identity attempt MUST produce exactly one machine-observable terminal outcome.

SAFE ABSTENTION is not SERVICE FAILURE.
SERVICE FAILURE is not UNSUPPORTED MODEL.
UNSUPPORTED MODEL is not UNKNOWN EQUIPMENT.
CLIENT CANCEL is not BACKEND TIMEOUT.
POLICY REVOCATION is not HISTORICAL EXACT IDENTITY.
```

# 0. Document basis and authority

This document merges and reconciles four evidence layers:

1. SPTR Equipment Recognition Source Strategy (21 Aug 2026).
2. SPTR / Fitness-App — Equipment Recognition v3.
3. Current Fitness-App/master source, re-verified at HEAD `532235d3...` for this revision.
4. **New for v4.2:** the independent Claude+GPT-PM cross-review of v4.1 (2026-08-22), full record at `core/review/SPTR_EQUIPMENT_RECOGNITION_V4_1_INDEPENDENT_VERDICT_2026-08-22.md`, whose 4 confirmed BLOCKERs and accepted MAJORs this revision integrates into binding text.

## 0.1 Review consensus authority (v4.1, unchanged as history)

v4.1 incorporated three review rounds run by a single continuous reviewer role-playing separate personas (R1 specialist, R2 remediation, R3 Devil's Advocate) and self-consolidated to APPROVE FOR PHASED IMPLEMENTATION. That status is **superseded**, not deleted — see §0.2.

## 0.2 v4.2 remediation record — what changed and why

This section is the authoritative changelog from v4.1 to v4.2. Every row cites the finding ID from the 2026-08-22 cross-review and the section of this document that now closes it. `ACCEPT`/`ACCEPT WITH REFINEMENT` = GPT-PM's disposition on reconciliation; nothing here is a Claude-only unilateral rewrite.

| ID | Severity | Finding | Disposition | Closed in |
| --- | --- | --- | --- | --- |
| B-01 | BLOCKER | App Check enforcement globally off, security exit can't honestly close | ACCEPT, no rebuttal | New §3 D11, new gate P0.G0 |
| B-02 | BLOCKER | `recognised_models` client-forgeable via Firestore wildcard write | ACCEPT, "worse than a missing rules entry" | §4.5 (new), P1.G1 deliverables, P5.G3 exit |
| B-03 | BLOCKER | P6.G1 shadow misclassified OPTIONAL (copy-paste of P5.G4) | ACCEPT | P6.G1 reclassified RELEASE-BLOCKING PREREQUISITE |
| B-04 | BLOCKER | Sealed-test reuse for per-model promotion = post-selection/multiple-comparisons risk | ACCEPT | §8.2 pre-registration rule, P6.G3 rewritten |
| C-01 | CRITICAL | DEFER_VISUAL has no production promotion lane | ACCEPT, folded into this list | New P6-T text-only promotion lane, §9 |
| C-02 | CRITICAL | catalogVersion recorded, not enforced as runtime authorization | ACCEPT | §6.5 session-pinning, §4.2 `equipment_identity_policies` runtime read rule |
| C-03 | CRITICAL | Infra/security failure silently collapses into ordinary TYPE_ONLY/UNKNOWN | ACCEPT | §6.5 full terminal-outcome enum |
| C-04 | CRITICAL | Demotion/correction doesn't revoke actionable historical state | ACCEPT | §7.4 history status enum |
| M-01 | MAJOR | No client/server identity contract version negotiation | (Claude Architecture, folded into C-02 remediation) | §6.5 `identityContractVersion` |
| M-02 | MAJOR | Stale-scan discard doesn't stop server-side cost/work | ACCEPT | §6.6 (new) idempotency/single-flight |
| M-03 | MAJOR | New ML/Vertex workload in existing mixed Functions codebase without isolation (refined from GPT's retracted "first non-Stripe function" framing) | ACCEPT, refined | New P0.G6, §12.3 |
| M-04 | MAJOR | false-exact-on-OOD unmeasurable online without labels | ACCEPT | §8.4 ONLINE_OBSERVABLE vs LABELED_EVALUATION_ONLY split |
| M-05 | MAJOR | Raw OCR text not covered by "no raw image in logs" | ACCEPT | §8.5 extended |
| — | MAJOR | Region (`europe-west1`/`eur3`) pinned to Stripe webhook, treated as open P0.G5 decision | ACCEPT | P0.G5 rewritten |
| — | MAJOR | `rate_limit.ts` duplicates existing `abuse_guard.ts` | ACCEPT | §12.3, P2.G3 rewritten |
| — | MAJOR | Non-`autoDispose` provider, no `scanId` lifecycle primitive | ACCEPT | §7.1 rewritten with concrete Riverpod primitive |
| — | MAJOR | Client-readable `equipment_models` vs server authority | ACCEPT WITH REFINEMENT | §4.2 client-visibility column tightened |
| — | MAJOR | `textSupportStatus=VERIFIED` circular promotion dependency | ACCEPT, folded into C-01 | New P6-T lane |
| — | MAJOR | Statistical method never named | ACCEPT | §8.2, §11 name Clopper-Pearson explicitly |
| — | MAJOR | Round-cap exhaustion with unresolved BLOCKER has no defined outcome | ACCEPT (governance gap) | §10 `ESCALATED_UNRESOLVED` state |
| — | MAJOR | Existing ML CI machinery (`scripts/ml/lifecycle.py`, `test_ml_contracts.py`) not reused | ACCEPT | §8.3 rewritten |
| — | MAJOR | 15 new Functions files, no scaling/deploy isolation | ACCEPT, evidence-driven fix not mandated | P0.G6 (new) |
| — | MAJOR | `MODEL_REGISTRY.json` schema mismatch (`models[]` vs `vendor_models`) | ACCEPT | §8.3 |
| — | MAJOR | Retrieval-exemplar/calibration-probe leakage | ACCEPT | §8.2 split rule extended |
| — | MAJOR | §10 reviewer roles partially unbacked by real agents; R5 GPT mechanism currently a no-op | ACCEPT, documented honestly | §10 |
| — | MAJOR | Optional verifier can silently drop from EXACT_MODEL path | ACCEPT | §6.5 `verifierInvoked` mandatory field |
| — | MINOR | P4.G2/P4.G3 and P6.G2/P6.G3 copy-paste defects | ACCEPT (mechanical) | §9 gate text corrected |
| — | MINOR | NEED_MORE_VIEW has no resolution path before P5.G1 ships | ACCEPT | P2.G4 exit clarified |
| — | MINOR | `MachineTextRecogniser.implements` breaks fakes on new abstract member | ACCEPT | P2.G1 deliverables clarified |
| — | MINOR | No `textPolicyVersion`/`identityPolicyVersion` field | ACCEPT | §6.5 |

Everything not listed above (rights model, additive `equipmentId` architecture, OCR-noise separation, `MODEL_REGISTRY.json` reuse in principle, 30-photo reclassification, P0.G5's distrust of emulator parity for vector search) survived both review passes unchanged and is carried forward verbatim from v4.1.

# Contents

- 1. Comparison of the two designs and merged resolutions
- 2. Verified current repository baseline
- 3. Master product and architecture decisions
- 4. Canonical data model and Firestore boundaries
- 5. Source acquisition, Wger enrichment and rights governance
- 6. Recognition runtime: OCR, retrieval, fusion, calibration, verifier and terminal outcomes
- 7. UX, safety, privacy, history and gym-instance memory
- 8. Dataset, evaluation, ML governance and observability
- 8.5 Cloud/security threat model and runtime guardrails
- 9. Phased implementation plan and gate definitions
- 10. Multi-round review protocol
- 11. Release metrics, promotion rules and kill criteria
- 12. Repository/file plan and implementation dependencies
- 13. Explicit non-goals and forbidden shortcuts
- 14. Source/reference ledger
- 15. Final recommended execution sequence

# 1. Comparison of the two designs and merged resolutions

Unchanged from v4.1 — see §0.1 of that document (`core/design/sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md`). No finding in the 2026-08-22 cross-review touched this section.

# 2. Verified current repository baseline

The plan is additive because the repository already contains critical plumbing that must not be replaced. Unchanged from v4.1's table of `machine_text_anchor.dart` / `scan_outcome.dart` / `equipment_models.dart` / `MODEL_REGISTRY.json` contracts — re-verified byte-identical at current HEAD.

**New for v4.2 — corrected backend truth (M-03).** v4.1 and its own R1-R3 review both stated the Cloud Functions backend serves "only Stripe Checkout/webhooks." This was **wrong** — `functions/src/index.ts` exports 12 functions across multiple domains (`startFreeTrial`, `createCheckoutSession`, `createPortalSession`, `stripeWebhook`, `optInDonorWall`, `optOutDonorWall`, `generateAnnualReceipt`, `startCoachOnboarding`, `bookCoachSession`, `reportEquipment`, `deleteAccount`, plus a video-URL pair), and `abuse_guard.ts` / `scaling.ts` / `account_export.ts` already exist. Only `functions/package.json`'s stale `description` field says Stripe-only. Equipment Identity is not the first non-Stripe workload — it is the **first substantial ML inference/search workload** inside an existing mixed transactional/application Functions surface, which is a narrower but still real deployment-isolation concern (see P0.G6).

| Existing contract | Evidence in repository | Master-plan treatment |
| --- | --- | --- |
| `machine_text_anchor.dart` | Brand names stripped as generic noise; ranked type candidates, honest ambiguity preserved. | Keep intact. Separate `IdentityTextParser`, probed via `is` type-check, not a new abstract member on `MachineTextRecogniser` (its `implements`-based fakes would otherwise break — see P2.G1). |
| `scan_outcome.dart` | Offline 10-class model always `alternatives`; confidence threshold cannot repair closed-set errors. | Preserve. `EquipmentIdentity` is a **separate** provider, never added to `ScanResult` itself (see §7.1). |
| `equipment_models.dart` | `ExerciseItem.equipmentId` is the functional relation used throughout the product. | Never replaced. |
| `MODEL_REGISTRY.json` | v1 bundled by availability not quality; v2 unshipped, provenance incomplete; registry already has a `vendor_models` category (used today for `mlkit_pose_detection`, `mlkit_text_recognition`, `gemini`) distinct from the trained-classifier `models[]` schema. | New hosted-model entries (`equipment_identity_embedding`, `gemini_equipment_verifier`) route through `vendor_models`, not `models[]` — see §8.3. |
| `firestore.rules` | `users/{uid}/{coll}/{document=**}` (lines 24-35) grants full client write to any subcollection not explicitly excluded (`subscription`/`usage`/`receipts`/`profile` are). The file's own comment records this exact failure class recurring three times already. | `recognised_models` and any new identity telemetry collection **must** be added to the exclusion list — see §4.5. |
| `functions/src/scaling.ts` | `REGION = "europe-west1"` pinned to the `eur3` Firestore location; region is "baked into every function URL" and a move would recreate the Stripe webhook endpoint with a payments-outage window (scaling.ts:52-70). `APP_CHECK_ENFORCED` is off by default with three documented, unrelated preconditions (scaling.ts:81-124). | Region is a **fixed input**, not an open P0.G5 decision (see P0.G5). App Check enforcement is an external platform-readiness prerequisite (see P0.G0). |
| `functions/src/abuse_guard.ts` | Transactional daily quota at `users/{uid}/usage/{yyyy-mm-dd}`, already closed to clients by `firestore.rules`. | Equipment-identity rate limiting extends this, not a new `rate_limit.ts` (see §12.3, P2.G3). |
| `scripts/ml/lifecycle.py` + `scripts/ml/test_ml_contracts.py` | Already mechanically check `MODEL_REGISTRY.json`'s `deployment_status` against the real asset tree and registry-claimed metrics against cited reports, wired into `.github/workflows/flutter.yml`'s `ct1-content-qa` job. | Equipment-identity promotion evidence routes through this existing CI-enforced contract instead of a parallel bespoke system (see §8.3). |

# 3. Master product and architecture decisions

D1-D10 unchanged from v4.1 (functional type first; additive identity; OCR-first with evidence authority; image-on-demand; server authority; Firebase-first conditionally locked; precision > coverage; verified setup only; privacy separation; model-by-model promotion).

**D11 (new, closes B-01). App Check is an external platform prerequisite, not a deliverable of this workstream.** Production exact-identity promotion requires `APP_CHECK_ENFORCED = true` on the equipment-identity callable. That flag depends on a platform-wide migration (Play Integrity attestation for the operator's own Firebase App Distribution test channel) that this workstream does not own and cannot unilaterally complete. Shadow and development identity work may proceed with enforcement off; user-facing and production identity may not. See P0.G0.

**D12 (new, closes C-02/C-03). A recognition session pins its evidence-authority tuple once, and any exact claim carries a full, unambiguous terminal outcome.** Every `recognitionSessionId` resolves `(catalogVersion, fusionPolicyVersion, textPolicyVersion, embeddingVersion)` once at session start and reuses that exact tuple for every view aggregated into that session — a live catalog/policy switch never silently mixes evidence from two versions. Every enrichment attempt terminates in exactly one outcome from the full enum in §6.5 — infrastructure/security failure is never observationally indistinguishable from honest abstention. This is the binding form of the "NO SILENT DEGRADATION" invariant on the front page.

**D13 (new, closes C-04). Historical exact-identity records carry actionability state, separate from provenance.** `recognised_models` history is never erased (provenance is immutable, per D-existing rule), but every record's *current actionability* (whether it may still be rendered as an active recommendation) is a separate, mutable field that a demotion or user correction updates immediately. See §7.4.

# 4. Canonical data model and Firestore boundaries

## 4.1 Identity layers

Unchanged from v4.1 (Layer A EquipmentType / B Brand-Line-Model / C Recognition evidence / D PhysicalMachineInstance / E Exercise Knowledge Graph).

## 4.2 Recommended Firestore collections

Unchanged from v4.1's 13 collections, with two refinements:

- **`equipment_models` client visibility, tightened (closes the "client-readable vs server authority" MAJOR, ACCEPT WITH REFINEMENT).** The client may read **display-only fields** (`canonicalName`, `brandId`, `productLineId`, `modelCode` for display, `catalogVersion` id) for rendering an already-adjudicated result. The client must **not** be able to independently derive `textSupportStatus`/`visionSupportStatus`/eligibility from a cached read and treat that as authorization. Whether a given `identityLevel` may currently be claimed, and whether a setup fact may currently be shown as actionable, is a decision the client always re-asks the server for at render time (see §7.3/§7.4) — never inferred client-side from a locally cached catalog snapshot.
- **New collection: `equipment_identity_sessions`.** One document per `recognitionSessionId`, written once at session start by the server, holding the pinned `(catalogVersion, fusionPolicyVersion, textPolicyVersion, embeddingVersion)` tuple (D12). Every subsequent request in that session reads this pin rather than re-resolving "current active" versions mid-session. A support-status *demotion* or policy kill-flag published after a session is pinned invalidates that session (server checks a live revocation flag on every request, independent of the cached pin) and forces `CANCELLED_STALE`/`NEED_MORE_VIEW` rather than continuing to honor stale evidence — additive catalog changes (new models, non-demoting metadata) do not invalidate an in-flight session.

## 4.3 Core EquipmentModel contract

Unchanged from v4.1.

## 4.4 Asset and rights contract

Unchanged from v4.1 — the fail-closed rights rule was not challenged by either review pass.

## 4.5 Firestore rules boundary (new section, closes B-02)

```text
BLOCKER, now closed in binding text
firestore.rules:24-35's users/{uid}/{coll}/{document=**} wildcard grants full client
write to any subcollection not explicitly excluded. recognised_models (exact-model
history) was not excluded in v4.1's file plan, which never listed firestore.rules or
firestore.indexes.json as deliverables at all -- meaning a modified client could forge
identityLevel: EXACT_MODEL history with an arbitrary catalogVersion/modelId that no
recognizer ever produced.
```

Binding rule for v4.2: `firestore.rules` and `firestore.indexes.json` are **mandatory P1.G1 deliverables**, not implied side effects of adding new collections. `recognised_models`, any future identity telemetry collection, and `equipment_identity_sessions` join the existing exclusion list (`subscription`/`usage`/`receipts`/`profile`) as **server/admin-write-only** — deny-by-default for client writes, following the exact pattern the rules file's own comment already documents for the three prior incidents of this class. P1.G1's verification must include an emulator mutation-test suite proving:

- client `CREATE` on `recognised_models/*` → DENY
- client `UPDATE` of authority fields (`identityLevel`, `catalogVersion`, `evidence`) → DENY
- server/Admin SDK write → ALLOW
- cross-account read/write → DENY

P5.G3 (exact history) is not considered implemented without this suite passing, regardless of whether the mobile UI code is complete.

# 5. Source acquisition, Wger enrichment and rights governance

Unchanged from v4.1 — not challenged by either review pass.

# 6. Recognition runtime: OCR, retrieval, fusion, calibration, verifier and terminal outcomes

## 6.1 Structured OCR split

Unchanged in architecture from v4.1, with one implementation-contract correction (closes the `MachineTextRecogniser.implements` MINOR): `StructuredTextRecogniser` is a **separate, probed capability interface** (checked with an `is` type test, mirroring the existing `FallbackReportingRecogniser` pattern at `visual_equipment_providers.dart:85`), never a new abstract member added to `MachineTextRecogniser` itself — the latter would break every `implements`-based fake in the existing test suite, since Dart's `implements` does not inherit default method bodies.

## 6.2 Cheap exact-model path

Unchanged from v4.1.

## 6.3 Visual retrieval and candidate aggregation

Unchanged from v4.1, with one addition to the VectorRetriever interface contract: it must expose an `evict(exemplarId)` method so a quarantined/rights-revoked asset's vector can be removed from *whichever* backend is active without backend-specific code at call sites (relevant to the P4.G1 benchmark and any future P8.G3 migration).

## 6.4 Fusion, confidence and open-set policy

Unchanged from v4.1's signal-storage table. Two additions:

- **Statistical method named explicitly (closes the "unnamed method" MAJOR).** Every confidence bound in this document (§8.2, §11, P6.G2/G3) is an **exact one-sided Clopper-Pearson binomial confidence bound**, not a normal/Wald approximation — the latter produces a degenerate (zero-width, falsely certain) interval at zero observed errors, which is exactly the operating point these gates sit at. Implementations (`scripts/ml/equipment_identity/evaluate.py`) must use an exact binomial method (e.g. `scipy.stats.beta.ppf`-based Clopper-Pearson) and this must be checked in review, not merely produce numbers that happen to match.
- **Verifier invocation must be an observable fact, not an implicit assumption (closes the "optional verifier silent drop" MAJOR).** Every response with `identityLevel: EXACT_MODEL` carries a mandatory `verifierInvoked: bool` field. Calibration (P4.G3) must define whether/how thresholds differ when `verifierInvoked = false` (i.e. the verifier was disabled/degraded and fusion+calibration alone produced the claim) — this is never allowed to be an unmarked, invisible degradation of adjudication rigor.

## 6.5 Recognition response contract (rewritten, closes C-02, C-03, M-01)

```text
EquipmentIdentityResponse {
  scanId
  recognitionSessionId
  identityContractVersion          # NEW -- client/server contract negotiation (M-01)
  type: { id }
  typeEvidenceStatus
  identityLevel: TYPE_ONLY | BRAND_AND_TYPE | PRODUCT_LINE | EXACT_MODEL

  decision: MATCH
          | ABSTAIN                 # honest low-confidence / ambiguous -- NORMAL, expected
          | NEED_MORE_VIEW
          | NOT_SUPPORTED            # model/catalog entry exists but not eligible for claim
          | CANCELLED_STALE          # scanId/recognitionSessionId superseded before completion
          | UNAVAILABLE_TIMEOUT
          | UNAVAILABLE_NETWORK
          | UNAVAILABLE_APPCHECK
          | UNAVAILABLE_RATE_LIMIT
          | UNAVAILABLE_BACKEND
          | UNAVAILABLE_CATALOG_VERSION   # session's pinned tuple was revoked mid-session

  abstainReason?: LOW_CONFIDENCE | EMBEDDING_FAILURE | INDEX_UNAVAILABLE
                | VERIFIER_SCHEMA_VIOLATION | RATE_LIMITED | TIMEOUT
                # required whenever decision resolves to ABSTAIN or any UNAVAILABLE_*
                # value; feeds a metrics series SEPARATE from "abstention rate" (see 8.4)

  brand?
  productLine?
  model?
  calibratedConfidence?
  verifierInvoked: bool             # NEW, mandatory when identityLevel == EXACT_MODEL
  verifierModel?
  evidence[]
  nextView?: LOGO | PLACARD | SIDE | FULL
  catalogVersion
  fusionPolicyVersion
  textPolicyVersion                 # NEW -- was missing; closes provenance gap
  identityPolicyVersion             # NEW -- policyVersion field promised by section 4.2
                                     #   of v4.1 but never actually defined; now real
  ocrVersion
  embeddingVersion?
}
```

Binding rule: this enum change is the mechanical closure of C-03 ("infra/security outage can silently collapse into ordinary TYPE_ONLY"). `ABSTAIN` remains the ordinary, healthy, expected outcome for genuine low-confidence/ambiguous recognition — it is never used for a backend/security failure. Every `UNAVAILABLE_*`/`CANCELLED_STALE` value gets its own telemetry counter, distinct from the abstention-rate metric, so a real outage or an active prompt-injection probe cannot present as "the system is behaving with healthy precision-first caution" on an operator's dashboard.

## 6.6 Server-side session lifecycle, cancellation and idempotency (new section, closes M-02, C-02)

v4.1's §7.1 async-state invariant only described client-side behavior ("a stale response may never overwrite a newer capture"). It said nothing about the server-side work already in flight for a superseded scan, and nothing about a warm Cloud Function instance's catalog-pointer cache surviving an emergency demotion. Both are closed here:

- **Server-side supersession check.** Before starting the expensive step (Vertex embedding call, Firestore KNN, Gemini verifier invocation) and again immediately before writing the response, the callable re-reads the latest `recognitionSessionId` the client has acknowledged for that user/device. If a newer session has since started, the in-flight request short-circuits to `CANCELLED_STALE` rather than completing normal work whose result nobody will read. The client additionally sends a best-effort cancel signal when it discards a scan (fire-and-forget, does not block the UI).
- **Discarded-work observability.** A `work_discarded_as_stale` counter tracks server-side effort that ran to completion but was superseded, so rapid legitimate re-scanning that eats a user's own rate-limit budget is visible rather than silently degrading a later, wanted scan.
- **Bounded catalog/policy cache.** A Cloud Function instance may cache the active catalog/policy pointer, but only with an explicit, bounded TTL (target: 60s) plus a push-based invalidation path (Firestore listener or Pub/Sub) that every warm instance must honor on emergency demotion. §4.2's `equipment_identity_sessions` pin (D12) is checked for live revocation on every request within a session, independent of this cache — so "roll back without an app release" (§8.5) is an enforced latency bound, not merely an assertion that a flag exists somewhere that can eventually be flipped.

# 7. UX, safety, privacy, history and gym-instance memory

## 7.1 Progressive recognition UX (rewritten, closes the non-autoDispose/scanId MAJOR)

v4.1 stated the async-staleness invariant as prose with no concrete implementation mechanism. Verified against `mobile/lib/features/visual_equipment/state/visual_equipment_providers.dart:202-205`: the existing `visualEquipmentControllerProvider` is a global, non-`autoDispose` `NotifierProvider<VisualEquipmentController, AsyncValue<ScanResult>>`. Putting `EquipmentIdentity` onto `ScanResult` (as v4.1's P2.G4 literally proposed) would give the "additive" identity layer no disposal hook to hang staleness-cancellation on, and would force every existing test assertion site that touches `ScanResult` construction to reason about scan identity — not additive in practice.

**Binding mobile-architecture rule for v4.2:** `EquipmentIdentity` is never added to `ScanResult`. It is served by a **separate** `AutoDisposeFutureProvider.family<EquipmentIdentity, ScanId>` (or an equivalent `Notifier` keyed by `scanId`), generated by the scanner page at capture time. Riverpod's own `family` key plus `autoDispose` **is** the staleness mechanism — a stale family instance is garbage-collected on navigation away, structurally, not defensively re-checked. The existing generic `ScanResult`/`visualEquipmentControllerProvider` and its widget tests remain untouched, which is what "additive" is supposed to mean and what v4.1 only asserted.

```text
TYPE KNOWN
  -> show generic answer immediately (existing controller, terminal for the scan)
  -> exercises/safety available immediately
  -> exact identity enrichment runs on a SEPARATE family(scanId) provider, in parallel

EXACT MODEL FOUND
  -> enrich card with brand / line / model code (composed from the separate provider)

MODEL AMBIGUOUS
  -> keep generic type
  -> offer guided second scan (PLACARD / LOGO / SIDE / FULL) -- see P5.G1 for when this
     capture flow actually exists; before P5.G1 ships, NEED_MORE_VIEW renders as a plain
     re-scan prompt against the existing capture path and is excluded from P2.G5's
     value-checkpoint arithmetic (closes the "NEED_MORE_VIEW dead end" MINOR)

TYPE UNKNOWN
  -> existing MachineCard / honest unknown path
```

Two-channel write rule (closes the history-ordering gap): the generic history row at `users/{uid}/recognised_equipment/{equipmentId}` is written exactly as today, unaffected by enrichment timing. The exact-history write (§7.4) is a separate, idempotent upsert keyed by `scanId`, with no ordering dependency on the generic write and no compensation logic needed if enrichment never completes (`CANCELLED_STALE`/any `UNAVAILABLE_*` outcome simply never writes an exact-history row).

## 7.2 Safety invariant

Unchanged from v4.1 — held up under both review passes without a single contested finding.

## 7.3 Model-specific setup (extended, closes part of C-04)

Unchanged base contract (`EquipmentModelSetupSpec` with provenance/applicability/verification status). **New render-time rule:** displaying a *stored* exact-model setup fact requires re-checking the model's *current* `catalogStatus`/`textSupportStatus`/`visionSupportStatus`/SetupSpec verification state at render time, not only at the moment it was first captured. If any of those has changed unfavorably since capture, the UI shows an explicit "this recommendation has since been withdrawn — needs reconfirmation" state instead of silently continuing to display retracted guidance.

## 7.4 History and PhysicalMachineInstance (extended, closes C-04, binds D13)

New field on every `recognised_models/{modelId}` record: **`actionabilityStatus: ACTIVE | USER_REJECTED | POLICY_REVOKED | SUPERSEDED`**, mutable, separate from the immutable provenance fields (`catalogVersion`, `fusionPolicyVersion`, `evidence` class at time of capture, which — per v4.1 and unchanged here — are never erased by a later demotion or correction).

- A server-side demotion of the model's support status immediately sets `actionabilityStatus: POLICY_REVOKED` on every affected history record (a Cloud Function trigger or batch job on demotion, not a lazy client-side check only) and on the corresponding `PhysicalMachineInstance` reference.
- A user's P5.G5 "Not this model" correction immediately sets `actionabilityStatus: USER_REJECTED` on the specific record being corrected.
- Any UI surface rendering a saved exact-model setup fact or physical-machine-instance memory checks `actionabilityStatus == ACTIVE` (plus the §7.3 render-time re-validation) before treating it as actionable; `POLICY_REVOKED`/`USER_REJECTED`/`SUPERSEDED` records remain visible in history for provenance but are never rendered as current, trustworthy guidance.

## 7.5 Inference vs training contribution

Unchanged from v4.1.

# 8. Dataset, evaluation, ML governance and observability

## 8.1 Corpus hierarchy

Unchanged from v4.1.

## 8.2 Minimum evidence targets and evaluation rigor (extended, closes B-04 and three MAJORs)

Base evidence-target table unchanged from v4.1. Four additions, all closing findings from the 2026-08-22 cross-review:

**Statistical method named explicitly.** The one-sided 95% confidence bounds throughout this document (§11, P6.G2, P6.G3) are computed with the **exact Clopper-Pearson binomial method**. This is stated here as a binding requirement, not left for an implementer to infer from the fact that the worked "~100"/"~299" examples happen to match that method's output. A normal/Wald approximation is explicitly forbidden for this gate (it degenerates to a zero-width, falsely certain interval at zero observed errors, which is this gate's actual operating point at pass time).

**"Independent encounter" tightened.** v4.1's split rule forbade counting multiple *frames of one scan* as independent evidence, but said nothing about revisiting the *same physical unit on separate days*, and set no floor on the diversity of physical units/models within a sample. Binding rule for v4.2: an "encounter" requires a minimum time/context separation from any other encounter of the *same* physical instance (a same-day revisit does not count as new evidence), **and** no single physical instance may contribute more than a stated fraction (e.g. 10%) of the qualifying sealed-test sample. This is a pass/fail precondition on the sealed-test protocol itself, not only a post-hoc cluster-aware analysis of results.

**Per-model promotion requires pre-registration (closes B-04).** Before any sealed evaluation run whose results will feed P6.G3 model-by-model promotion, the specific candidate model set and their individual promotion criteria must be **pre-registered** — fixed and recorded before sealed labels are opened. If the number of simultaneously-evaluated candidate models is K, the significance level for each individual model's confidence bound is corrected for multiplicity (e.g. Bonferroni: use α/K), or an explicit hierarchical/partial-pooling statistical model is used instead of independent per-model bounds. Selecting which models "pass" only after inspecting sealed per-model results, with no correction, is explicitly forbidden — the same discipline v4.1 already applied to threshold tuning (§13 non-goals) now applies to model-selection itself.

**Retrieval-exemplar / calibration-probe separation (closes a MAJOR).** Any asset used to build the `equipment_model_exemplars` retrieval index for a model is excluded, at the **source-asset level** (not merely by pHash near-duplicate detection, which a resize/crop can evade), from that model's `CALIBRATION_SET` and `SEALED_*` probes. Verified as part of P3.G1/P3.G3.

**Two production promotion lanes, not one (closes C-01).** v4.1 celebrated `DEFER_VISUAL` (§9 P2.G5) as a legitimate, successful outcome, but its only defined path to `textSupportStatus: VERIFIED` ran through the visual-phase sealed-test machinery (P3→P4→P6), which `DEFER_VISUAL` explicitly skips — leaving a text-only success state with no reachable production status. v4.2 splits promotion into two independently reachable lanes:

```text
P6-T  TEXT PROMOTION LANE                  P6-V  VISUAL PROMOTION LANE
  TEXT SHADOW                                (unchanged from v4.1's P6 sequence:
    -> TEXT CALIBRATION                       P3 corpus -> P4 embedding/fusion/
    -> SEALED TEXT/OCR EVAL                   calibration -> P6 shadow -> sealed
    -> TEXT MODEL-BY-MODEL PROMOTION          real-gym/OOD eval -> promotion)
  (no P4 visual-retrieval dependency)
```

P6-T reuses the exact same statistical rigor as P6-V (Clopper-Pearson bounds, independent-encounter clustering, pre-registered per-model criteria) applied to a text-only sealed set instead of a real-gym visual set. A model may be `textSupportStatus: VERIFIED` and `visionSupportStatus: NONE` indefinitely — this is the intended, successful shape of a `DEFER_VISUAL` outcome, not a stalled state waiting on P4.

## 8.3 ML registry, versioning and governance reuse (rewritten, closes two MAJORs)

- Reuse `core/ml/MODEL_REGISTRY.json`; do not create a second ML lifecycle — unchanged principle from v4.1, but the mechanism is now specified correctly.
- **`equipment_identity_embedding` and `gemini_equipment_verifier` route through the registry's existing `vendor_models.entries` category**, not `models[]`. `models[]`'s schema requires classifier-shaped fields (`class_count`, `training_code_commit`, a real in-repo `artifact_sha256` the CI fence checks) that do not honestly describe a hosted Vertex/Gemini endpoint SPTR does not train — forcing them into `models[]` would violate the registry's own rule 1 ("nothing here is fabricated") via placeholder provenance fields. `vendor_models` already covers this shape (see the existing `gemini` entry, already used by `features/ai_coach`/`features/visual_equipment`) and needs only version fields for embedding-model/index version and verifier prompt/schema version. Add a `CLOUD_API`/`CLOUD_FUNCTION` value to `deployment_surface` if any entry needs its own registry row beyond the existing `ON_DEVICE`/`OFFLINE_ADVISORY` values.
- `equipment_identity_fusion` is either a trained combiner (fits `models[]`, needs real training/eval data per §8.2's calibration requirements) or a deterministic rule set (fits the existing `content_qa baseline-v1` precedent: null hashes, "deterministic rule set; no learned parameters"). This must be decided honestly and stated explicitly when P4.G2 is implemented — not left ambiguous.
- **Equipment-identity promotion evidence routes through the existing, already-CI-enforced ML governance contract.** `scripts/ml/lifecycle.py` + `scripts/ml/test_ml_contracts.py` + `.github/workflows/flutter.yml`'s `ct1-content-qa` job already mechanically check `MODEL_REGISTRY.json`'s `deployment_status` against the real asset tree and check registry-claimed metrics against a cited evaluation report (`test_evaluation_report.py`). P6.G2/P6.G3/P6-T's sealed-evaluation "confidence bound passes" claim must be checked by an equivalent CI-enforced test against the actual evaluation output before a gate can be marked closed — a human eyeballing a printed number once, with no re-verification, is explicitly insufficient. `equipment_identity_evaluations` (§4.2) is a second promotion lifecycle on catalog equipment models, distinct from `MODEL_REGISTRY.json`'s champion/challenger lifecycle on ML artifacts — this document states that distinction explicitly rather than implying one registry axis covers both.

## 8.4 Observability and cost (rewritten, closes M-04)

**Two disjoint metric classes**, not one undifferentiated observability table:

```text
ONLINE_OBSERVABLE (no ground truth needed, safe to dashboard continuously)
  generic latency p50/p95
  exact enrichment p50/p95
  OCR-only exact resolution rate
  visual retrieval invocation rate
  verifier invocation rate
  exact abstention rate (ABSTAIN outcomes specifically -- see 6.5)
  per-UNAVAILABLE_*-reason failure rate (distinct series, see 6.5 abstainReason)
  work_discarded_as_stale rate (see 6.6)
  cost per scan / per exact resolution
  App Check / rate-limit failure rate
  user-reported correction rate (P5.G5 telemetry -- a KNOWN UNDERCOUNT of the true
    false-exact rate, non-response bias: most misidentified users never report it;
    never presented as equivalent to a measured error rate)

LABELED_EVALUATION_ONLY (requires sealed/audited ground truth, NOT continuously
  observable from raw production traffic)
  false EXACT_MODEL on OOD / on unsupported models
  exact-model precision
  calibration reliability (ECE/Brier or equivalent)
```

Binding rule: "false exact on OOD" is never reported on a routine production dashboard as a live, continuously-updated number — that quantity has no ground-truth label in ordinary traffic. It is estimated only via (a) the P6 sealed evaluation itself, and (b) a recurring, smaller-scale periodic human-reviewed audit sample on a stated cadence. The production dashboard's nearest online proxy is the explicitly-labeled "user-reported correction rate (known undercount)" series above — never renamed to imply it is the true false-exact rate.

## 8.5 Cloud/security threat model and runtime guardrails (extended, closes M-05)

Unchanged base rules from v4.1 (App Check, image transport limits, no raw image in Firestore/logs, source-adapter allowlists, operational rollback). **Extension, closes M-05:** the "no raw image in Firestore or logs" rule extends explicitly to **raw and structured OCR text** (`MachineTextEvidence.fullText`, `ParsedIdentityText.lines[].text`). A camera frame can capture third-party PII never intended for capture (another gym member's name tag, membership-card barcode area, phone screen, whiteboard schedule). Any logging of OCR content — including for routine debugging — must use only the *parsed* identity tokens (brand/model-code candidates), never the full raw text, and full-frame OCR text gets the same ephemeral-processing default as the image itself.

# 9. Phased implementation plan and gate definitions

```text
Scheduling rule (unchanged)
This workstream is POST_MVP_HIGH by default. P0/P1 foundation and read-only data work
may proceed in parallel only when it does not displace current proven MVP blockers.
Runtime exact-model user-facing promotion is never allowed merely because the data
pipeline exists -- and, new for v4.2, is explicitly BLOCKED until B-01..B-04 close.
```

| Phase | Name | Scope | Phase exit |
| --- | --- | --- | --- |
| P0 | Foundation, provenance & platform readiness | Freeze scanner truth, recover ML provenance, define rights/versioning, prove cloud region/IAM/SDK feasibility, **confirm App Check platform readiness**, **decide Functions deployment isolation** | No new user-facing exact claim |
| P1 | Canonical Knowledge Base | Ontology/schema **+ mandatory Firestore rules/indexes**, official brand adapters, Wger staging, catalogue reconciliation, **catalog publication pipeline ownership** | A lawful, access-controlled exact-model catalog exists |
| P2 | OCR-first Identity | Structured OCR, identity parser, server text lookup **reusing `abuse_guard.ts`**, additive contracts/progressive UI plumbing **as a separate scanId-keyed provider** | Text identity shadow works; OCR-only value checkpoint decides visual-phase timing |
| P3 | Licensed Corpus & Golden Set | Acquire approved assets; dev regression/calibration sets **with source-level exemplar/calibration separation**; sealed blind real-gym/OOD tests | Evaluation data exists without leakage |
| P4 | Visual Retrieval & Decision Quality | Embeddings, Firestore vector search, fusion, calibration **(Clopper-Pearson named explicitly)**, verifier **(`verifierInvoked` mandatory)** | Trustworthy candidate/abstention engine in shadow |
| P5 | Product UX & Machine Memory | Guided multi-view, equipment page **with render-time re-validation**, verified setup, history **with `actionabilityStatus`**, private physical-instance memory | Useful exact identity without breaking generic flow |
| P6 | Shadow, Evaluation & Promotion | **Mandatory** real scans shadow, blind real-gym test, **pre-registered** per-model promotion, **split P6-T/P6-V lanes** | First model set may become VISION/TEXT VERIFIED |
| P7 | Contribution & Active Learning | Unchanged from v4.1 | Lawful learning loop |
| P8 | Scale | Unchanged from v4.1 | Operationally sustainable recognition catalog |

## Phase P0 — Foundation, provenance & platform readiness

### P0.G0 — App Check platform readiness (new gate, closes B-01)

CLASSIFICATION: EXTERNAL PREREQUISITE / BLOCKING

Purpose. Make explicit that production exact-identity promotion depends on a platform-wide App Check migration this workstream does not own, so P2.G3/P6 cannot silently close against a security condition that isn't actually met.

Inputs. `functions/src/scaling.ts`'s current `APP_CHECK_ENFORCED` flag and its three documented unmet preconditions (Play Integrity distribution-channel mismatch for the operator's own test builds being the concrete blocker).

Deliverables. A tracked `APP_CHECK_PLATFORM_READINESS` status with values `BLOCKED_EXTERNAL_PLATFORM_MIGRATION` / `READY_FOR_SHADOW` / `READY_FOR_PRODUCTION`, owned outside this workstream; an explicit, mechanically checkable split between shadow/development exact identity (may run with enforcement off) and production exact identity (may not).

Verification. P2.G3's exit condition references this status directly rather than asserting `enforceAppCheck=true` as if it were this workstream's own deliverable.

Required review. Security + Firebase/backend review.

Exit. `APP_CHECK_PLATFORM_READINESS = READY_FOR_PRODUCTION` recorded with evidence, OR production exact identity remains explicitly blocked pending it — no third option.

Rollback / failure mode. Remain shadow-only indefinitely; this does not block P0-P5 foundation/shadow work.

### P0.G1-G4 — unchanged from v4.1 (baseline freeze, ML provenance recovery, source & rights registry, catalog version & type snapshot).

### P0.G5 — Cloud feasibility, IAM, region & SDK spike (rewritten, closes the region MAJOR)

CLASSIFICATION: FOUNDATION / ARCHITECTURE

Purpose. Prove the preferred Firebase/Vertex/Firestore vector path fits the actual project — **region is a fixed input, not an open architecture choice.**

Inputs. `functions/src/scaling.ts`'s existing `REGION = "europe-west1"` constant, pinned to the current `eur3` Firestore location and baked into every already-deployed function URL including `stripeWebhook`; current IAM/service accounts; Vertex regional availability.

Deliverables. Exactly one of three explicit outcomes, not an open-ended "region decision": (a) the preferred Vertex/vector path is **colocated** with `europe-west1`/`eur3`; (b) a **deliberately split-region** design with a measured, stated latency budget for the cross-region hop, and a data-residency decision; or (c) **stay OCR/text-only** (defer P4). Under no circumstance does this gate move or duplicate the existing region for already-deployed payment/account functions — a region change for those would recreate `stripeWebhook`'s URL and risk the exact payments-outage window `scaling.ts`'s own comment warns about.

Verification. Real staging-project KNN smoke test; App Check callable smoke test; latency/cost estimate against the chosen outcome.

Required review. Firebase/backend + security + architecture review.

Exit. One of the three outcomes above is recorded with evidence.

Rollback / failure mode. Stay OCR/text-only and postpone visual retrieval (unaffected by P6-T, per §8.2).

### P0.G6 — Functions deployment isolation decision (new gate, closes the "15 new files" MAJOR)

CLASSIFICATION: FOUNDATION / ARCHITECTURE

Purpose. Decide, with evidence, how a new ML/Vertex/vector-search workload is added to the existing shared, multi-domain Functions codebase (Stripe, coaching, account, reporting — see §2's corrected repository truth) without risking those already-shipped paths, especially `stripeWebhook`.

Inputs. `firebase.json`'s single `"default"` codebase declaration; `functions/src/scaling.ts`'s existing per-function scaling profiles (256 MiB / 1 CPU / concurrency 80) and its own stated rationale for why they exist (protecting `stripeWebhook` from resource starvation); the ~15 new TypeScript files §12.3 introduces.

Deliverables. An evidence-driven choice between (a) a **separate Firebase Functions `codebase`** for `equipment_identity` (firebase-tools supports multiple codebases, so identity deploys cannot block payment deploys or fail the shared `predeploy` TypeScript build), or (b) **proven selective deploy + lazy initialization + a dedicated `IDENTITY` scaling profile** with its own `maxInstances`/memory override, keeping one codebase. Either way: a new scaling profile entry in `scaling.ts`, and a Stripe emulator/e2e regression check that must pass before every identity-backend deploy.

Verification. A deliberately-broken identity-module TypeScript error must NOT block a `stripeWebhook` hotfix deploy under the chosen design — this is the actual acceptance test.

Required review. Backend/architecture + release engineering review.

Exit. Chosen isolation strategy documented with the regression test proving it.

Rollback / failure mode. Disable identity Functions exports entirely; existing domains unaffected.

## Phase P1 — Canonical Machine Knowledge Base

### P1.G1 — Equipment identity ontology & Firestore schema (extended, closes B-02)

CLASSIFICATION: POST_MVP_HIGH

Purpose. Implement additive Brand/ProductLine/EquipmentModel/Asset/Source/ExternalMapping/SetupSpec boundaries **and the access-control boundary that makes "server authority" real.**

Inputs. P0 outputs, current equipment ontology, current `firestore.rules`'s wildcard-exclusion pattern.

Deliverables. Schemas, converters/validators, indexes, example seed records — **and, now mandatory, not implied: `firestore.rules` additions excluding `recognised_models`/`equipment_identity_sessions`/any new identity telemetry collection from the `users/{uid}/**` client-write wildcard, plus `firestore.indexes.json` entries for every new query pattern this design needs (including vector indexes).**

Verification. Schema validation, multi-function model tests, immutable `modelId`/`canonicalSlug` uniqueness tests, **and the §4.5 emulator mutation-test suite (client CREATE/UPDATE authority fields → DENY, server/admin write → ALLOW, cross-account → DENY) — this repo already has a `test:rules` npm script (`functions/package.json:12`) as the harness for this.**

Required review. Flutter/architecture + ontology + Firebase/backend + **security** review.

Exit. Can represent 50 pilot models without changing `equipmentId` semantics **and the mutation-test suite passes.**

Rollback / failure mode. Schema changes remain additive; no migration of exercise `equipmentId`; an unpassed mutation-test suite blocks this gate's exit, full stop.

### P1.G2-G5 — unchanged from v4.1 (official brand adapters, extended brand adapters, WGER_REFERENCE_INGESTION, catalogue reconciliation).

### P1.G6 — Catalog publication pipeline (new gate, closes the ownership gap behind C-01/P2.G3's `textSupportStatus=VERIFIED` dependency)

CLASSIFICATION: POST_MVP_HIGH

Purpose. v4.1 listed `catalog_publish.ts`, `publish_catalog.py`, `equipment_catalog_publish_jobs`, and `equipment_catalog_active` as file-plan artifacts (§12) but no gate in §9 actually owned building them — leaving P2.G3's dependency on `textSupportStatus: VERIFIED` with no defined promotion mechanism until P6, and creating exactly the ungoverned-mutation risk v4.1's own R1-04/DA-09 findings forbade.

Inputs. P1.G1 schema, P0.G3 rights registry.

Deliverables. The staged publish pipeline (SOURCE → STAGING → NORMALIZE → VALIDATE → DIFF → REVIEW → IMMUTABLE CATALOG VERSION → atomic `activeCatalogVersion` pointer switch → PRODUCTION) as real, owned code, plus an **interim, auditable `textSupportStatus: EXPERIMENTAL` promotion path** (staging-only, never user-facing) so P2.G3/P2.G5 can produce OCR-only evidence without inventing an ungoverned mechanism under deadline pressure.

Verification. Reviewed-diff approval required before any version becomes active; rollback to a prior version tested; no auto-publish from any adapter/scraper.

Required review. Backend + ontology + governance review.

Exit. A version can be published, reviewed, activated and rolled back without hand-editing a duplicate catalog.

Rollback / failure mode. Freeze at the last known-good active version.

## Phase P2 — OCR-first Identity

### P2.G1 — Structured OCR capability (clarified, closes the `implements` MINOR)

Unchanged purpose/deliverables from v4.1, with the implementation constraint made explicit in the deliverable itself: **`StructuredTextRecogniser` is a separate interface, probed with an `is` check at call sites (mirroring the existing `FallbackReportingRecogniser` pattern) — never a new abstract member added to `MachineTextRecogniser`,** whose `implements`-based fakes (`FakeMachineTextRecogniser`) would otherwise fail to compile.

### P2.G2 — unchanged from v4.1 (IdentityTextParser).

### P2.G3 — Server exact text lookup (rewritten, closes the rate-limiter duplication and the App Check dependency)

CLASSIFICATION: POST_MVP_HIGH

Purpose. Resolve unique strong text evidence against the authoritative catalog without image upload.

Inputs. P2.G2 + `equipment_models` + catalog version + **the existing `abuse_guard.ts` transactional quota mechanism** + P0.G0's App Check platform-readiness status.

Deliverables. Cloud Function text path, model-code/alias indexes, policy checks; rate limiting via an **identity-scan quota class added to the existing `abuse_guard.ts`/`users/{uid}/usage/{day}` mechanism — not a new, competing `rate_limit.ts`**, which would create two incompatible quota stores measuring two incompatible windows.

Verification. Unique/nonunique code tests, type compatibility, rights-independent catalog lookup, **App Check enforcement conditional on `P0.G0` readiness (shadow: enforcement may be off; production: `enforceAppCheck: APP_CHECK_ENFORCED` inherits the platform's staged rollout, never independently asserted true).**

Required review. Backend/security + ontology review.

Exit. Verified text-supported (P6-T `VERIFIED`) pilot models can return shadow exact IDs with full evidence/versioning, including the new `textPolicyVersion` field.

Rollback / failure mode. Disable text exact policy; return type-only.

### P2.G4 — Additive mobile identity contract & progressive UX plumbing (rewritten per §7.1)

Purpose unchanged. Deliverables corrected: **`EquipmentIdentity` is served by a separate `family(scanId)` provider, never merged into `ScanResult`** (see §7.1's binding rule). `NEED_MORE_VIEW` renders as a plain re-scan prompt against the existing capture path until P5.G1 ships its guided multi-view flow, and is explicitly excluded from P2.G5's value-checkpoint arithmetic in the interim.

Verification. Widget/state tests for the new family provider's type-only/brand/exact/needMoreView/unknown/cancelled/unavailable states; **existing `scanner_page_test.dart` and `scan_controller_test.dart` pass completely unmodified** — this is the actual, testable definition of "additive" for this gate.

### P2.G5 — unchanged from v4.1 (OCR-only shadow & value checkpoint), now explicitly understood to feed the P6-T lane rather than being an implicit dead end.

## Phase P3-P5 — unchanged from v4.1 except where §4.5, §6.5, §6.6, §7.1, §7.3, §7.4, §8.2 above already state gate-level consequences; those sections are binding on the corresponding P3/P4/P5 gates without needing separate restatement here.

### P4.G2 — Evidence fusion (corrected, mechanical fix for a copy-paste defect)

Purpose corrected from v4.1 (which had copied P4.G3's text verbatim): **Fuse visual retrieval, structured OCR, generic type evidence and optional logo/viewpoint evidence into ranked model candidates without allowing one weak signal to silently dominate**, producing a `rawCandidateScore` and documented conflict rules. This gate does not perform calibration — see P4.G3.

### P4.G3 — Calibration & open-set gate (corrected, closes the Clopper-Pearson naming and the copy-paste defect)

CLASSIFICATION: RELEASE-BLOCKING

Purpose corrected: **turn P4.G2's fused raw candidate scores into a calibrated, per-identity-level confidence, and define the abstention/open-set policy** — not a restatement of fusion's own purpose.

Deliverables. Calibration artifact naming the fusion→calibration split explicitly (which function produces the raw score, which calibrates it), stating whether curves are per-evidence-class/per-identity-level (§6.4 lists four identity levels; the calibration set's minimum ~20 images/model target from §8.2 must be checked against however many separate curves this actually requires — likely inadequate as originally scoped and must be revisited once the curve count is fixed), reliability/ECE/Brier reporting, and **explicit naming of the exact one-sided Clopper-Pearson method** per §8.2/§6.4.

Verification unchanged from v4.1 plus: no sealed-test tuning; calibration-set reliability stratified by evidence class.

### P4.G4 — Candidate-bounded Gemini verifier (extended)

Deliverables extended: the response's mandatory `verifierInvoked` field (§6.4/§6.5) and P4.G3's stated policy for thresholds when the verifier did not run.

## Phase P6 — Shadow, Evaluation & Promotion (substantially rewritten, closes B-03, B-04)

### P6.G1 — Shadow deployment (RECLASSIFIED, closes B-03)

CLASSIFICATION: **RELEASE-BLOCKING PREREQUISITE** *(was: POST_MVP / OPTIONAL — NOT A P6 PREREQUISITE, a copy-paste of P5.G4's classification string; this was itself one of the confirmed BLOCKERs)*

Purpose. Run the identity backend on real scans without changing the production generic result, to surface production-traffic failure modes a sealed evaluation cannot: App Check token distribution under real devices, cold-starts, quota/concurrency behavior, real device/network mix, Cloud Function error mapping, actual request shape and cost.

Inputs. P2-P4 runtime, current scanner, P0.G0's readiness status.

Deliverables. Shadow telemetry (versions, candidates, abstentions, the full §6.5 terminal-outcome distribution, latency/cost) at a **defined minimum volume and duration** (to be set once P2-P4 land; not "some shadow traffic," a stated target), with a required App Check/rate-limit error SLO and zero unresolved privacy/security MAJOR before P6.G2 may begin.

Verification. Compare current generic vs. identity-layer outcomes; privacy/telemetry audit; terminal-outcome completeness check (every attempt resolves to exactly one §6.5 value, per D12).

Required review. Release/ML/privacy review.

Exit. Minimum shadow volume/time/SLO met. **P6.G2 may not begin without this gate's exit being formally recorded** — an exception requires an explicit, documented release waiver, not a default skip.

Rollback / failure mode. Disable shadow flag immediately; this gate's incompletion blocks P6.G2/G3, it does not merely delay them informally.

### P6.G2 — Independent real-gym evaluation (extended, split P6-T/P6-V)

Purpose extended: measure exact claims on blind real gyms/physical instances, **run separately (and independently sealed) for the P6-T text lane and the P6-V visual lane per §8.2**, using the pre-registered per-model candidate set and multiplicity-corrected significance level.

Deliverables/Verification otherwise unchanged from v4.1 (confidence-bound point metrics, cluster-aware analysis, independent evaluator/custodian, dual-label adjudication for ambiguous ground truth) — but now with §8.2's tightened "independent encounter" definition (minimum time/context separation, per-instance sample-share cap) as a pass/fail precondition, not only a post-hoc analysis lens.

### P6.G3 — Model-by-model promotion (corrected, closes the copy-paste defect and binds B-04's pre-registration rule)

CLASSIFICATION: PRODUCTION PROMOTION

Purpose corrected from v4.1 (which had copied P6.G2's text verbatim): **promote only models whose pre-registered, individually-corrected confidence bound (per §8.2) actually passes** — this gate's deliverable is the promotion decision and its rollback target, not a repetition of P6.G2's evaluation metrics.

Deliverables. A promotion decision per pre-registered candidate model, each model's individually-corrected (Bonferroni or hierarchical) confidence bound, and — **new, closes the rollback-runbook MAJOR** — an actual operational runbook: a named trigger metric/alert (not "an alert exists" but the specific metric and threshold), a named owner/on-call role, a maximum detection-to-demotion latency target, and a rehearsed drill with a stated re-test cadence, not a one-time "rollback target tested" note at gate close.

Verification. Promotion mutation: an unsupported model must abstain (`NOT_SUPPORTED`, per §6.5); the rollback drill is actually re-run on the stated cadence, not only once.

Required review. Release + safety + ontology + GPT-PM independent review (per §10).

Exit. 0 BLOCKER/CRITICAL/MAJOR for the promoted surface; evidence attached; the runbook drill has a recent, dated pass.

Rollback / failure mode. Demote model to SHADOW/SUPPORTED/CATALOG_ONLY within the runbook's stated latency target — this is now a measured SLA, not an unmeasured capability claim.

## Phase P7-P8 — unchanged from v4.1.

# 10. Multi-round review protocol (extended, closes the round-cap governance gap and the reviewer-role honesty gap)

```text
Review rule (unchanged)
Each full Gate ends with an independent review. Subgates inside a Gate do not spawn
extra reviews unless evidence demands it. Review attempts that fail open due to
transport/tooling are recorded as ATTEMPTED_FAILED_TRANSPORT, never PASS or CONSENSUS.
```

**New, binding: round-cap exhaustion has a deterministic outcome.** v4.1 capped review at five rounds but never said what happens if round five still has an unresolved BLOCKER/CRITICAL. Binding rule for v4.2:

```text
unresolved BLOCKER after round cap        = GATE REMAINS OPEN, NO PROMOTION, ESCALATE
unresolved CRITICAL after round cap       = same
unresolved gate-affecting MAJOR           = gate remains open unless explicitly proven
                                             outside the gate's scope, with evidence
```

`ESCALATED_UNRESOLVED` is added as a mandatory terminal status alongside `OPEN`/`FIXED`/`REJECTED_WITH_EVIDENCE` in the findings table (§10.2/Appendix A). Spending five rounds is never itself grounds for treating a finding as resolved — silence is not consensus, matching the general evidence-over-inference principle this project already applies elsewhere.

**Reviewer roster honesty (new).** §10's round table names roles (`fitness-data-scientist`, `exercise-ontology-curator`, `clinical-safety-gate`, `fitness-flutter-reviewer` for R1/R3/R4) that genuinely exist as agent definitions under `Fitness_App/.claude/agents/` — those rounds have real mechanical backing. R2's "Provenance/legal"/"security/privacy" and R5's "Release reviewer" currently do not have a matching agent definition in this repository; either create them before relying on those rounds, or record the reviewer's actual identity per round rather than implying a role that resolves to nothing. **R5's "GPT review mechanism" is currently a machine-wide no-op** (`ENABLED_REPO_ROOTS = []` in `~/.claude/hooks/gpt_review_gate.py`, per `~/.claude/CLAUDE.md` §15) — this document's own review used PM Bridge's manual `gpt_send`/`gpt_await_reply` tools directly, not the mandatory commit/push gate, and that distinction should not be lost in future gate closures.

Finding format unchanged: `severity | claim | evidence | failure scenario | required change`. Verification lines throughout §9 should name a concrete CI check or a signed-off artifact with reviewer identity and timestamp wherever the finding is release-blocking (P6.G2/G3, P4.G3, P0.G5, P0.G0, P1.G1's mutation-test suite) — an unfalsifiable "verified" claim with no named artifact is not an acceptable gate closure for those specific gates.

## 10.2 v4.1's three-round review outcome — unchanged historical record; see that document. Superseded, per §0.2 of this document, by the 2026-08-22 cross-review.

# 11. Release metrics, promotion rules and kill criteria (extended)

Base table unchanged from v4.1, with the statistical method named explicitly (Clopper-Pearson, per §8.2/§6.4) and the metric split from §8.4 applied: any metric requiring ground-truth labels (exact-model precision, false-exact-on-OOD, calibration reliability) is `LABELED_EVALUATION_ONLY` and is never presented on a routine production dashboard as if it were continuously observable. Kill/pause criteria unchanged from v4.1.

# 12. Repository/file plan and implementation dependencies (extended)

## 12.1-12.2 — unchanged from v4.1 mobile file plan, with the P2.G4/§7.1 correction: the new provider file is a **separate** `equipment_identity_provider.dart` (`family(scanId)`, `autoDispose`), not a modification that adds fields to `scan_outcome.dart`'s `ScanResult`.

## 12.3 Backend (extended, closes the rate-limiter duplication and adds deployment files)

```text
functions/src/equipment_identity/
  contract.ts
  recognize.ts
  identity_catalog.ts
  catalog_publish.ts
  text_lookup.ts
  input_security.ts
  embedding_provider.ts
  vector_retriever.ts
  firestore_vector_retriever.ts
  evidence_fusion.ts
  calibration.ts
  verifier.ts
  policy.ts
  telemetry.ts
  # rate_limit.ts REMOVED -- extends functions/src/abuse_guard.ts instead (see P2.G3)

# Files to CHANGE, not just add (new for v4.2 -- were missing from v4.1's file plan):
functions/src/index.ts       # export the new identity callables
functions/src/scaling.ts     # new IDENTITY scaling profile (P0.G6); abuse_guard.ts
                              # extended with an identity-scan quota class (P2.G3)
functions/src/abuse_guard.ts # extended, not duplicated
firestore.rules              # mandatory -- see 4.5, P1.G1
firestore.indexes.json       # mandatory -- see 4.5, P1.G1
```

## 12.4-12.5 — unchanged from v4.1, with the §8.3 clarification that `equipment_identity` promotion evidence routes through the existing `scripts/ml/lifecycle.py`/`test_ml_contracts.py` CI contract rather than a fully parallel, CI-unenforced governance path.

No-binary rule unchanged from v4.1.

# 13. Explicit non-goals and forbidden shortcuts (extended)

All of v4.1's non-goals carry forward unchanged. New for v4.2, closing specific findings above:

- Do not treat region as an open P0.G5 architecture choice when it is pinned to a live, already-deployed payment webhook's URL.
- Do not add a second rate-limiter/quota subsystem alongside `abuse_guard.ts` without a stated gap analysis showing the existing one cannot be extended.
- Do not let a client determine current model support/eligibility from cached/readable catalog fields; eligibility is always a live server policy check.
- Do not add `EquipmentIdentity` fields to `ScanResult`; it is served by its own `scanId`-keyed, `autoDispose` provider.
- Do not treat five review rounds spent as itself a resolution of an unresolved BLOCKER/CRITICAL/gate-affecting MAJOR.
- Do not select which models "pass" promotion after inspecting sealed per-model results without a pre-registered, multiplicity-corrected protocol.
- Do not log full raw OCR text for debugging; log only parsed identity tokens.
- Do not let a warm Cloud Function instance serve `EXACT_MODEL` for a model whose support was demoted beyond the stated cache-TTL/invalidation bound.

# 14. Source/reference ledger

Unchanged from v4.1, with one addition: `core/review/SPTR_EQUIPMENT_RECOGNITION_V4_1_INDEPENDENT_VERDICT_2026-08-22.md` (this revision's own remediation source) and `functions/src/index.ts`, `functions/src/scaling.ts`, `functions/src/abuse_guard.ts`, `firestore.rules`, `firestore.indexes.json` as newly-cited repository evidence.

# 15. Final recommended execution sequence

Unchanged in shape from v4.1's ten-step sequence, with step 2 (P0 foundation) now explicitly including P0.G0 (App Check readiness) and P0.G6 (deployment isolation) alongside the original baseline/provenance/rights/versioning/region work, and step 8 (P6) now explicitly running P6-T and P6-V as two lanes rather than one.

```text
FINAL STATUS FOR v4.2

DESIGN STATUS: REMEDIATED REVIEW CANDIDATE -- pending round-2 consensus with GPT-PM.
FOUNDATION WORK (P0, read-only P1): MAY PROCEED.
USER-FACING / PRODUCTION EXACT IDENTITY: BLOCKED until B-01..B-04 close AND round-2
  review confirms no new BLOCKER/CRITICAL surfaced by this remediation.

This document does not self-certify. It goes back to GPT-PM for round 2 of the
2026-08-22 cross-review before any status change to CONSENSUS/APPROVE.
```

# Appendix A — Gate close checklist

Unchanged from v4.1, with one addition: "Every release-blocking gate's Verification line names a concrete CI check or a signed-off artifact with reviewer identity and timestamp" (§10).

# Appendix B — Revision history

| Version | Date | State | Summary |
| --- | --- | --- | --- |
| v4.0 RC1 | 2026-08-21 | REVIEW CANDIDATE | Merged Source Strategy + Equipment Recognition v3. |
| v4.1 CONSENSUS | 2026-08-21 | APPROVE FOR PHASED IMPLEMENTATION → **SUPERSEDED 2026-08-22** | 3 self-run rounds; approved, then superseded by independent Claude+GPT-PM cross-review the next day. |
| **v4.2 REMEDIATED RC** | **2026-08-22** | **REMEDIATED REVIEW CANDIDATE — pending round 2** | Closes all 4 confirmed BLOCKERs (App Check readiness, Firestore wildcard write, P6 shadow reclassification, sealed-test pre-registration) and ~20 accepted MAJOR/MINOR findings from the independent cross-review; adds the NO SILENT DEGRADATION invariant, split P6-T/P6-V promotion lanes, full terminal-outcome enum, and session-pinned catalog/policy authorization. Not yet re-approved — awaiting GPT-PM's round-2 read. |
