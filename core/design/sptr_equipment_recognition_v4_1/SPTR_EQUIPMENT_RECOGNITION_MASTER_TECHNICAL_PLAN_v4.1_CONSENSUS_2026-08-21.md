SPTR / Fitness-App

# Equipment Recognition Master Technical Plan v4.1 — Consensus

Единый design authority: Source & License Strategy + Equipment Recognition v3 + current repository truth

| Поле | Значение |
| --- | --- |
| Project | xLZDx/Fitness-App |
| Canonical branch | master |
| Repository baseline | 3dd2e3e23e2a30c0e99a6995a1229acc5a0834a7 (verified 2026-08-21) |
| Document status | CONSENSUS AFTER 3 INDEPENDENT REVIEW ROUNDS — APPROVE FOR PHASED IMPLEMENTATION |
| Production exact-model claim | BLOCKED until sealed blind real-gym evaluation + statistical confidence bounds + calibration/open-set gate + model-by-model promotion |
| Workstream classification | POST_MVP_HIGH. P0/P1/P2 foundation may proceed only when it does not displace current proven MVP blockers; expensive visual work requires the P2 value checkpoint. |
| Primary design rule | Preserve functional equipmentId; add exact model identity as an additive enrichment layer |

```text
MASTER DECISION
SPTR must own its own canonical Machine Knowledge Base. Official manufacturer data establishes brand/line/model/SKU truth; licensed assets and real gym photos support recognition; wger and other exercise APIs enrich the exercise graph after recognition. Runtime evolution is additive: current equipmentId, safety, exercise filtering, CameraSession, ScanOutcome and generic recognition remain authoritative foundations. Exact identity may improve the answer, but it may never bypass existing safety or turn uncertainty into a fabricated exact model.
```

# 0. Document basis and authority

This document merges and reconciles three evidence layers:

1. SPTR Equipment Recognition Source Strategy (21 Aug 2026): manufacturer/BIM/3D/exercise-source research, provenance/licensing, WGER_REFERENCE_INGESTION and corpus design.

2. SPTR / Fitness-App — Equipment Recognition v3: repository-aware additive exact-model architecture, OCR-first identity, Firebase/Vertex/Firestore retrieval, fusion, confidence, UX and release gates.

3. Current Fitness-App/master source at the verified baseline: machine_text_anchor.dart, scan_outcome.dart, equipment_models.dart, MODEL_REGISTRY.json and related scanner/backend contracts.

## 0.1 Review consensus authority

This v4.1 version incorporates three review rounds: R1 independent specialist review, R2 cross-review/rebuttal and remediation, and R3 Devil's Advocate. Findings marked FIXED are integrated into the binding architecture below. Production exact-model claims remain blocked even though phased implementation is approved.

Highest-impact changes: the existing 30 gym photos are a legacy regression set, not a blind test; release metrics use confidence bounds and independent encounter units; catalog publication is versioned/two-phase; generic type is not an unsafe hard prefilter; OCR/source text is untrusted input to the verifier; a cloud feasibility gate precedes vector implementation; and an OCR-only value checkpoint precedes expensive visual phases.

```text
Authority boundary
This is a technical implementation and review plan, not a claim that exact-model recognition is production-ready. No model, brand or setup instruction is promoted by documentation alone. Promotion requires the evaluation gates in this document.
```

# Contents

- 1. Comparison of the two designs and merged resolutions

- 2. Verified current repository baseline

- 3. Master product and architecture decisions

- 4. Canonical data model and Firestore boundaries

- 5. Source acquisition, Wger enrichment and rights governance

- 6. Recognition runtime: OCR, retrieval, fusion, calibration and verifier

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

| Dimension | Source Strategy | Recognition v3 | Master resolution |
| --- | --- | --- | --- |
| Primary purpose | Build a lawful, structured source/data pipeline for the machine recognition KB. | Add exact brand/line/model identity to the existing scanner runtime. | Both are required. Source strategy becomes the supply chain; v3 becomes the runtime consumer. |
| Existing equipmentId | Canonical machine type should stay separate from exact model. | Explicitly keeps equipmentId as functional type and adds EquipmentModel. | LOCKED: equipmentId remains functional ontology and downstream safety/exercise key. |
| Exact model key | Stable internal SPTR identity; external IDs are mappings. | Examples use readable slug as modelId. | Use immutable internal modelId (UUID/ULID) + canonicalSlug as readable unique secondary key. External SKU/IDs never become primary key. |
| Source priority | Official manufacturer > official support/architect > distributor > marketplace/user. | Catalog fields include sources/rights but ingestion source order is not the focus. | Adopt source-priority and conflict policy from Source Strategy. |
| Wger | High-value read-only exercise enrichment source. | Not covered in runtime v3. | Add WGER_REFERENCE_INGESTION as a separate enrichment gate; never use it as exact-machine truth. |
| 3D/BIM | Useful if rights permit; synthetic data kept separate from real validation. | Visual exemplars and vector retrieval assume curated imagery. | Add explicit 3D/BIM acquisition and derivative/training gates before exemplars are eligible. |
| OCR | Brand/model tokens useful in recognition corpus. | Strongest cheap exact-model path; split generic text anchor from identity parser. | LOCKED: structured OCR and unique model-code lookup are the first runtime milestone. |
| Brand words | Useful exact-identity evidence. | Current generic anchor strips them as noise. | Do not change generic denoising semantics; create IdentityTextParser that preserves brand/line/model evidence. |
| Visual retrieval | Multi-modal recognition recommended. | Vertex multimodal embedding + Firestore vector search + candidate fusion. | Firebase-first accepted. Re-evaluate another vector store only after measured cost/latency/scale trigger. |
| Confidence | Fail closed into ambiguous/unknown; precision over coverage. | Separates raw visual/OCR/verifier/calibrated confidence. | LOCKED: only calibrated policy may emit exact model; LLM confidence is never probability. |
| Recognition support status | Catalog presence != recognition support. | Single lifecycle mixes TEXT_IDENTIFIABLE and vision states. | Improve by splitting text-support and vision-support status so OCR-only promotion can happen safely before vision. |
| Physical machine instance | Explicit layer: gym + exact model + setup memory. | Adds recognised_models history; model-specific setup. | Keep global model identity separate from user-private physical instance. Shared gym inventory requires its own governance gate. |
| User photos | Consent/provenance required. | Inference and training contribution explicitly separated. | LOCKED: no silent training upload; explicit opt-in, redaction, EXIF removal, retention and delete path. |
| ML lifecycle | Versioned manifests and corpus provenance. | Reuse core/ml/MODEL_REGISTRY.json. | LOCKED: no second ML registry. Add equipment identity models/configs to existing registry. |
| Evaluation | Independent real photos, OOD, hard negatives, instance/gym split. | Exact precision/OOD gates, per-model promotion, shadow. | Merge both: real-gym blind set + calibration + model-by-model support promotion. |

```text
Key conflict resolved: gate numbering
Both input documents used ER-0…ER-9 for different meanings. This master plan replaces both number sets with Phase/Gate IDs (P0.G1, P1.G1, etc.) so future reviews cannot close the wrong gate by name.
```

# 2. Verified current repository baseline

The plan is additive because the repository already contains critical plumbing that must not be replaced:

- Scanner flow with current CameraSession and crop/capture path.

- ML Kit OCR wrapper and machine_text_anchor.dart, which intentionally treats brand terms as generic-type noise and preserves honest ambiguity.

- ScanOutcome/ScanResult with explicit confident, alternatives, unknown, noEquipment, timeout and failed states; offline fallback is deliberately never presented as settled.

- Functional equipment/exercise ontology: ExerciseItem.equipmentId feeds exercise filtering, programmes, history and safety-related behavior.

- Firebase platform: Auth, Firestore, Cloud Functions, App Check and Firebase AI Logic already exist in the product stack.

- MODEL_REGISTRY.json already defines lifecycle semantics and records the shipped 10-class v1, experimental 37-class v2 and provenance gaps.

| Existing contract | Evidence in repository | Master-plan treatment |
| --- | --- | --- |
| machine_text_anchor.dart | Brand names such as Nautilus/Technogym/Life Fitness/Matrix are stripped as generic noise; phrase matching returns ranked type candidates and preserves ambiguity. | Keep intact for generic type recognition. Add a separate structured identity parser. |
| scan_outcome.dart | Offline 10-class model is always alternatives; confidence threshold cannot repair out-of-catalog closed-set errors. | Preserve honest uncertainty and add EquipmentIdentity as orthogonal enrichment. |
| equipment_models.dart | ExerciseItem.equipmentId is the functional machine relation used throughout the product. | Never replace it with manufacturer model/SKU. |
| MODEL_REGISTRY.json | v1 is bundled champion by availability, not quality; v2 is not shipped; training provenance is incomplete. | Phase P0 must recover/ratchet provenance before any new learned identity model is promoted. |

# 3. Master product and architecture decisions

D1. Functional type first. The user can proceed with exercises as soon as current equipmentId is trustworthy; exact model is enrichment, not a workout blocker.

D2. Additive identity. New EquipmentIdentity/EquipmentModel must not change VisualMatch or existing equipmentId semantics.

D3. OCR-first with evidence authority. A unique brand+model-code (or globally unique model-code) read from the intended machine can establish exact identity without visual retrieval when ownership/conflict/text-support gates pass. Generic type is not an unconditional hard veto: low-confidence/offline generic type is soft evidence; a strong conflicting type signal causes NEED_MORE_VIEW rather than silent override.

D4. Image-on-demand. Exact visual recognition runs after shutter/guided scan, not every live frame.

D5. Server authority. Catalog lookup, embeddings, candidate aggregation, calibration policy and protected exemplars remain server-side.

D6. Firebase-first, conditionally locked. Cloud Functions + Vertex multimodal embeddings + Firestore vector search are the preferred first implementation because they fit the current stack, but P0.G5 must verify region/IAM/SDK/index feasibility and P4.G1 must benchmark the retriever. PostgreSQL/pgvector or another store is introduced only on measured need.

D7. Precision > coverage. Exact-model claims abstain aggressively; type-only/brand+type are valid product outcomes.

D8. Verified setup only. Model-specific setup facts require provenance; LLM may summarize approved facts but may not invent them.

D9. Privacy separation. Inference is not training contribution; persistent user photo storage requires explicit opt-in and privacy processing.

D10. Model-by-model promotion. Catalog can contain thousands of models while only a subset is text/vision verified.

```text
CURRENT FOUNDATION                         NEW ADDITIVE IDENTITY LAYER

CameraSession -> centre crop
      |                         +--> Structured OCR -> IdentityTextParser
      +--> Generic OCR anchor --|                         |
      |                         |                         +--> exact code lookup
      +--> Gemini generic ------+--> equipmentId          |
      |                                                   v
      +--> TFLite fallback -> alternatives           Exact Identity API
                                                        |
                           immediate type UI <------------+
                              |                           |
                        exercises/safety            OCR + catalog
                                                        + image embedding
                                                        + vector retrieval
                                                        + fusion/calibration
                                                        + optional verifier
                                                            |
                                      TYPE_ONLY / BRAND+TYPE / PRODUCT_LINE /
                                      EXACT_MODEL / NEED_MORE_VIEW / UNKNOWN
```

# 4. Canonical data model and Firestore boundaries

## 4.1 Identity layers

| Layer | Entity | Key invariant |
| --- | --- | --- |
| A | EquipmentType (existing equipmentId) | Functional class used by exercises/safety/programmes. Immutable semantics. |
| B | EquipmentBrand / ProductLine / EquipmentModel | Manufacturer identity. Every model maps to primaryTypeId and optional supportedTypeIds[]. |
| C | Recognition evidence / exemplars / policies | Never changes type ontology; only improves identity confidence. |
| D | PhysicalMachineInstance | A specific unit at a gym. Depends on model identity; never becomes the model class. |
| E | Exercise Knowledge Graph | Existing SPTR catalog plus read-only external mappings such as wger. |

## 4.2 Recommended Firestore collections

| Collection | Purpose | Client visibility |
| --- | --- | --- |
| equipment_brands | Canonical brand registry. | Read-only public/app-safe fields only. |
| equipment_product_lines | Normalized line/series identities. | Read-only app-safe fields. |
| equipment_models | Exact model identity, type mapping, aliases, lifecycle, support status. | Read-only subset; no protected rights notes. |
| equipment_sources | Source metadata, terms/legal review state. | Server/admin only. |
| equipment_assets | Asset provenance, hashes, rights dimensions, storage refs. | Server/admin; user-display only for assets explicitly allowed. |
| equipment_model_exemplars | Embedding vectors + viewpoint + quality + source-domain. | Server-side retrieval only. |
| equipment_external_mappings | wger/distributor/manufacturer external IDs and mapping status. | Server/admin. |
| equipment_model_setup_specs | Verified model-specific setup facts + citations/provenance. | Read-only when VERIFIED. |
| equipment_catalog_versions | Immutable catalog/version manifests and source hashes. | App can read current version ID. |
| equipment_identity_policies | Thresholds, fusion/calibration versions, capability flags. | Server; response emits policyVersion. |
| equipment_identity_evaluations | Golden/OOD metrics, per-model status, promotion evidence. | Admin/reporting. |
| equipment_catalog_active | Single active catalogVersion/policy pointer; atomic switch and rollback. | App may read version ID; writes server/admin only. |
| equipment_catalog_publish_jobs | Staging validation, diff/review approval and publish audit trail. | Server/admin only. |

```text
Primary-key refinement
Use an immutable internal modelId (UUID/ULID) as the actual key. Keep canonicalSlug (for example nautilus-inspiration-ipvp5) as a unique human-readable secondary field. This avoids future identity migration when marketing names or product-line spelling changes.
```

## 4.3 Core EquipmentModel contract

```text
EquipmentModel {
  modelId: internal immutable ID
  canonicalSlug: "nautilus-inspiration-ipvp5"
  brandId: "nautilus"
  productLineId?: "nautilus-inspiration"
  canonicalName: "Inspiration Chest Press"
  modelCode: "IPVP5"
  skuAliases: [...]
  primaryTypeId: "chest_press_machine"
  supportedTypeIds: ["chest_press_machine"]
  generation?: "5"
  aliases: [...]
  catalogStatus: ACTIVE | DISCONTINUED | LEGACY | RETIRED
  textSupportStatus: NONE | EXPERIMENTAL | VERIFIED
  visionSupportStatus: NONE | EXPERIMENTAL | SHADOW | SUPPORTED | VERIFIED
  sourceConfidence: OFFICIAL | SECONDARY | USER_VERIFIED | INFERRED
  catalogVersion: "..."
}
```

Multi-function invariant. A model may support multiple functional types. primaryTypeId is required for the default path; supportedTypeIds[] carries secondary functions. No 1:1 assumption is allowed.

Variant/revision invariant. Add an optional EquipmentVariant only when an official configuration/SKU materially changes recognisable appearance, controls or setup. EquipmentModelSetupSpec must carry applicability (model/variant, generation, region and serial/revision range when available).

## 4.4 Asset and rights contract

```text
EquipmentAsset {
  assetId
  modelId
  sourceId
  assetType: PHOTO | VIDEO | PDF | MANUAL | 3D | RENDER | OCR_CROP
  viewpoint
  originalUrl
  storagePath?
  sha256
  perceptualHash?
  retrievedAt
  sourceLastModifiedAt?
  labelProvenance
  rights: {
    legalReviewState: UNREVIEWED | REVIEWED | BLOCKED
    commercialAllowed: bool
    displayAllowed: bool
    recognitionProcessingAllowed: bool
    trainingAllowed: bool
    derivativeAllowed: bool
    redistributionAllowed: bool
    attributionRequired: bool
    shareAlike: bool
    noAiRestriction: bool
    termsCaptured: bool
    termsSnapshotSha256?
    licenseIdOrTermsVersion?
    reviewedAt?
    recheckAt?
    decisionBasis?
  }
}
```

```text
Fail-closed rights rule
Unknown rights are not "probably allowed." If the relevant dimension is unknown, the asset stays in quarantine/staging for that use. Display, embedding/retrieval, model training and derivative generation are separate rights decisions.
```

# 5. Source acquisition, Wger enrichment and rights governance

| Source class | Priority | Use in SPTR | Hard restriction |
| --- | --- | --- | --- |
| Official manufacturer pages/PDFs | P0 | Canonical brand/line/model/SKU/spec truth; aliases; official visual anchors. | Media rights still require review. |
| Official 2D/3D/BIM/architect portals | P0/P1 | Geometry, silhouette, dimensions; licensed synthetic-view generation. | Derivative/training permission must be explicit. |
| wger | ENRICHMENT P0 | Exercise UUID, aliases, muscles, equipment relations, variations, translations, media metadata, deletion/replacement semantics. | Not exact-machine DB; do not copy AGPL backend code; preserve per-entry license. |
| ExerciseDB | STAGING | Second-opinion exercise/equipment/muscle coverage. | Commercial/media terms before production. |
| API Ninjas Exercises | STAGING | Coverage and safety/instruction comparison. | Commercial use terms/cost gate. |
| Official distributors | P1/P2 | Regional aliases, legacy models, RU text, secondary specs. | Secondary truth; ToS/copyright/dedup. |
| Refurbished/used inventories | P2 long-tail | Discontinued models, real-world condition variants. | Never primary spec source. |
| 3dsky/3ddd | LICENSE-GATED | Geometry and rare/legacy 3D references. | Royalty-free != ML right. |
| Sketchfab | LICENSE-GATED | 3D discovery and licensed views. | Respect NoAI and per-asset license. |
| Search-engine image scraping | DISCOVERY ONLY | Find candidate sources. | No default ingestion/training corpus. |

Initial brand pack. P0: Technogym, Life Fitness/Hammer Strength, Matrix, Nautilus/Core Health & Fitness. P1: Precor, Panatta. P2: DHZ, HOIST, PRIME, Arsenal, Cybex legacy and others after source/licensing reconnaissance.

## 5.1 WGER_REFERENCE_INGESTION

Wger is an optional exercise-knowledge enrichment source, not a machine-identity dependency. The adapter is read-only and writes to staging/mapping artifacts first. Wger must not block exact-machine P1/P2 progress. Any production reuse of translations/media or database-derived content remains blocked until per-object license/attribution/share-alike compatibility is explicitly reviewed; staging/comparison may continue with provenance preserved.

| wger field | SPTR use | Promotion rule |
| --- | --- | --- |
| Exercise.uuid | external_sources.wger.uuid | Stable external mapping only; never SPTR primary key. |
| Alias | Search/OCR/result normalization | May become alias after dedup/content review. |
| muscles / muscles_secondary | Graph comparison/enrichment | Disagreement creates review finding; never silently overwrites safety-critical SPTR data. |
| equipment | Equipment type -> exercise candidates | Mapping requires ontology curator review. |
| variation_group | Substitution/variation relationships | Staging until reconciled with SPTR movement taxonomy. |
| Translation | RU/EN candidate copy | License/content review before UI publication. |
| ExerciseImage / ExerciseVideo | Media candidate | Per-object rights gate; staging by default. |
| last_update_global + deletion log | Incremental sync/replacement | Sync may update staging/mapping; production changes still gate-reviewed. |

# 6. Recognition runtime: OCR, retrieval, fusion, calibration and verifier

## 6.1 Structured OCR split

```text
ML Kit OCR
   |
   +--> GenericTypeTextAnchor
   |       brand/series words may be noise
   |       output: equipmentId candidates
   |
   +--> IdentityTextParser
           brand words = evidence
           product line = evidence
           model code/SKU = strongest text evidence
           bounding boxes = ownership / centrality evidence
```

The current machine_text_anchor behavior must not be "fixed" by removing brands from its noise list. That would couple generic recognition to exact identity and reintroduce confident wrong matches. The new parser consumes the same OCR output through a structured capability interface.

```text
MachineTextEvidence {
  fullText
  lines[]: {
    text
    bounds
    cornerPoints?
    angle?
    confidence?
  }
}

ParsedIdentityText {
  brandCandidates[]
  productLineCandidates[]
  modelCodeCandidates[]   # preserve digits/hyphens/slashes
  typeHints[]
  conflicts[]
}
```

## 6.2 Cheap exact-model path

Before any image embedding, attempt authoritative catalog resolution using structured text evidence. A unique model-code match may emit exact identity only when all policy conditions pass:

- model code is unique in the current catalog version;

- OCR region is compatible with the central machine / placard ownership policy;

- no conflicting model code is present;

- model-code parsing preserves digits, hyphens and common OCR confusions; O↔0 / I↔1 substitutions may create candidates but may not create exact certainty without corroboration;

- type evidence is reconciled by authority: VERIFIED/high-assurance generic type conflict -> NEED_MORE_VIEW; low-confidence, ambiguous or offline-fallback type is soft evidence and cannot veto a unique verified model-code match;

- textSupportStatus for the model is VERIFIED;

- calibrated text-policy threshold and quality requirements pass.

```text
Privacy/cost optimization
If strong text evidence resolves the model, the exact-identity request can send text/type evidence only and avoid uploading the image for visual retrieval. Image processing is the fallback, not the default.
```

## 6.3 Visual retrieval and candidate aggregation

```text
shutter image
   -> Vertex multimodal embedding
   -> Firestore vector nearest-neighbour search
   -> top K exemplars
   -> group by modelId
   -> top N model candidates
   -> fusion with type/OCR/logo/viewpoint evidence
```

- typeId is a hard prefilter only when typeEvidenceStatus is VERIFIED/HIGH_ASSURANCE. Ambiguous, low-confidence or offline-fallback type evidence remains a fusion/ranking feature;

- brand is normally a ranking feature, not a hard filter;

- hard brand filtering is allowed only with strong evidence such as unique model code/logo/text;

- several exemplars per model are required; a single studio image cannot define a model;

- candidate margin and multi-view consistency are explicit features.

Retriever abstraction. Firestore KNN is the preferred backend, but VectorRetriever is an interface. P4.G1 benchmarks Firestore KNN against a simple cached/brute-force baseline at pilot scale so complexity is earned by measured latency/cost/quality rather than assumed.

## 6.4 Fusion, confidence and open-set policy

| Signal | Stored separately | Use |
| --- | --- | --- |
| visualDistance / visualScore | Yes | Candidate similarity only; not user probability. |
| OCR brand/line/model score | Yes | Strong textual evidence and conflicts. |
| generic type compatibility | Yes | Ontology constraint. |
| logo evidence | Yes | Ranking/strong brand evidence. |
| exemplar diversity / count | Yes | Reliability of visual evidence. |
| verifier decision | Yes | MATCH / UNKNOWN / NEED_MORE_VIEW only. |
| calibratedConfidence | Yes | Only value allowed to drive exact-model production claim. |

Gemini role. Gemini is not asked an open-ended "what model is this?" question for production identity. It receives 3-5 catalog candidates and returns structured MATCH / UNKNOWN / NEED_MORE_VIEW with candidateId, nextView and evidence. Its self-confidence is never treated as calibrated probability. OCR text, manufacturer text and source metadata are untrusted data, never instructions: serialize/quote fields, enforce candidate IDs, disable tool/action authority, validate strict schema output, cap lengths and reject prompt-like control text. The verifier cannot invent or add candidates.

## 6.5 Recognition response contract

```text
EquipmentIdentityResponse {
  scanId
  recognitionSessionId
  type: { id }
  typeEvidenceStatus
  identityLevel: TYPE_ONLY | BRAND_AND_TYPE | PRODUCT_LINE | EXACT_MODEL
  decision: MATCH | UNKNOWN | NEED_MORE_VIEW
  brand?
  productLine?
  model?
  calibratedConfidence?
  evidence[]
  nextView?: LOGO | PLACARD | SIDE | FULL
  catalogVersion
  ocrVersion
  embeddingVersion?
  verifierModel?
  fusionPolicyVersion
}
```

# 7. UX, safety, privacy, history and gym-instance memory

## 7.1 Progressive recognition UX

```text
TYPE KNOWN
  -> show generic answer immediately
  -> exercises/safety available immediately
  -> exact identity enrichment runs in parallel/on shutter

EXACT MODEL FOUND
  -> enrich card with brand / line / model code

MODEL AMBIGUOUS
  -> keep generic type
  -> offer guided second scan (PLACARD / LOGO / SIDE / FULL)

TYPE UNKNOWN
  -> existing MachineCard / honest unknown path
```

Exact identity never blocks a safe generic workout path. "Need more view" is preferable to silently choosing a sibling model.

Async-state invariant. Every exact request is keyed by scanId + recognitionSessionId. A response for an older/cancelled scan may never overwrite a newer capture, route or user selection. Leaving the scanner cancels or ignores late enrichment results.

## 7.2 Safety invariant

```text
exact model
   -> primaryTypeId / supportedTypeIds
   -> existing equipmentId
   -> existing vetted exercise catalog
   -> existing safety / injury / eligibility filters
   -> user
```

```text
Forbidden safety shortcut
Exact model -> LLM-generated exercises -> user is prohibited. Model identity may select verified setup facts, but it may not create or bypass the existing exercise/safety ontology.
```

## 7.3 Model-specific setup

- seat position / adjustment ranges;

- starting arm / pad / handle adjustments;

- weight-stack units / pulley ratio / model-specific controls;

- verified placard/manual wording and warnings.

All such facts live in EquipmentModelSetupSpec with source provenance, applicability (model/variant/generation/region/serial range where available), source document/version and verification status. LLM output may rephrase verified facts for UX only; it may not create missing facts. Safety-sensitive setup requires a stricter assurance policy than merely displaying the model name and may require explicit user confirmation when identity or applicability is not high-assurance.

## 7.4 History and PhysicalMachineInstance

| Layer | Storage/contract | Rule |
| --- | --- | --- |
| Existing generic history | users/{uid}/recognised_equipment/{equipmentId} | Preserve. |
| Exact model history | users/{uid}/recognised_models/{modelId} | Additive; only policy-passed exact identity. Store catalogVersion, fusionPolicyVersion and evidence class; later demotion/correction never erases historical provenance. |
| Physical machine memory | user-private machine-instance record: gymId + modelId + local instance fingerprint/setup notes | Never sole identity evidence. Optional and not a prerequisite for recognition promotion. |
| Shared gym inventory | Future governed collection | Separate gate: consent, moderation, cross-account/privacy rules and source attribution. |

## 7.5 Inference vs training contribution

- Inference does not automatically persist the image as training data.

- Training contribution is an explicit opt-in action with consentVersion.

- Before persistent training upload: remove EXIF/GPS on device; perform on-device face redaction where technically feasible, then server-side verification/redaction again. If raw faces ever transit before redaction, privacy copy and policy must state that truthfully.

- Retention policy and deletion path are mandatory.

- Contribution review/label status is separate from the recognition result that prompted the contribution.

Training-eligibility invariant. User-contributed examples remain quarantined until source/consent checks and human or explicitly authorized reviewed labels exist. Recognition output must never label its own training data as ground truth.

- The current 30 real gym photos remain evaluation/holdout evidence and are not consumed for training.

# 8. Dataset, evaluation, ML governance and observability

## 8.1 Corpus hierarchy

| Level | Label | Examples |
| --- | --- | --- |
| 0 | unknown / not_a_machine | Furniture, unrelated objects, unsupported machines. |
| 1 | equipment family | cardio, selectorized, plate-loaded, cable, rack, free weight. |
| 2 | functional type | chest_press_machine, lat_pulldown, treadmill. |
| 3 | brand | Nautilus, Matrix, Technogym. |
| 4 | product line | Inspiration, Insignia, Selection. |
| 5 | exact model/SKU | IPVP5, model code, SKU. |
| 6 | physical instance | A specific unit in a gym; never used as model class. |

## 8.2 Minimum evidence targets per vision-supported model

| Evidence | Pilot target | Notes |
| --- | --- | --- |
| Official clean imagery | 4-8 views where available | Reference/source truth, not real-gym validation. |
| Real gym training images | Target 20+ per model when training learned visual identity | Different machines/gyms/phones; target can adapt after baseline. |
| Independent validation | Dev validation: multiple instances/gyms; final blind test separately sealed | Do not use the same physical unit or engineer-visible sealed labels for threshold tuning. |
| Detail crops | 3-8 | Logo, placard, model code, console, selector, adjustments. |
| Licensed 3D renders | 8-24 when rights allow | Synthetic domain labeled separately. |
| Official manual/product sheet | 1+ | SKU/spec/geometry anchors. |
| Sibling hard negatives | >=3 where available | Same brand/line visually similar models. |
| OOD set | mandatory | Separate dev OOD and sealed OOD. Independent unit is an encounter/instance cluster, not a frame. |

Split rule. Do not randomly split images of the same physical machine across train/calibration/test. Split by physical instance or gym, group perceptual duplicates before split, and evaluate statistics at independent encounter/instance clusters rather than treating multiple frames of one machine as independent. Synthetic data never substitutes for real-world validation.

Dataset authority. The operator's existing 30 real-gym photos have already been repeatedly inspected and used in v1/v2/OCR development. They are therefore LEGACY_REAL_GYM_REGRESSION_SET, not a sealed blind holdout. They remain NO_TRAINING and NO_CALIBRATION, but cannot support the final independent production claim. P3 must create a new SEALED_BLIND_REAL_GYM_TEST_SET and SEALED_OOD_TEST_SET whose labels/results are hidden from implementation/tuning until policy thresholds are frozen.

Statistical release rule. Provisional point targets (97% exact precision, <=1% false EXACT_MODEL on OOD) are not sufficient by themselves. Promotion uses one-sided 95% confidence bounds on independent encounters/clusters. Initial system gate: lower confidence bound for exact-claim precision >=97%; upper confidence bound for false-exact OOD <=1%. With zero observed errors this implies roughly >=100 independent exact claims and >=299 independent OOD encounters respectively; any failures require larger samples. Thresholds are locked before sealed-test execution.

## 8.3 ML registry and versioning

- Reuse core/ml/MODEL_REGISTRY.json; do not create a second ML lifecycle.

- Add model IDs such as equipment_identity_embedding, equipment_identity_fusion, gemini_equipment_verifier where they become real deployed/evaluated components.

- Every recognition result records catalogVersion, OCR version, embedding model/index version, verifier model, fusion policy and app version.

- Training code, dataset manifests, source manifests, evaluation scripts, model configs and dependency pins must be versioned/recoverable.

- Large binaries may live outside Git, but content-addressed manifests/digests and source records are versioned.

## 8.4 Observability and cost

| Metric | Why it matters |
| --- | --- |
| generic latency p50/p95 | Must not regress current scanner usability. |
| exact enrichment p50/p95 | Guides UX and timeout policy. |
| OCR-only exact resolution rate | Measures cheapest/highest-explainability path. |
| visual retrieval rate | Cost/privacy surface after OCR fails. |
| verifier invocation rate | Should stay bounded to ambiguous top-N cases. |
| exact abstention rate | Coverage vs precision tradeoff. |
| false exact on OOD | Primary safety/trust guardrail. |
| cost per scan / per exact resolution | Scale and architecture trigger. |
| App Check/rate-limit failures | Security/availability. |

## 8.5 Cloud/security threat model and runtime guardrails

- Endpoint protection: authenticated callable function, enforceAppCheck=true, per-user/device rate limits, bounded concurrency, quotas/budget alarms and least-privilege service account.

- Image transport: client resize/compress/metadata strip; explicit maximum dimensions/bytes; no raw image in Firestore or logs; ephemeral processing only unless separate contribution consent exists.

- Untrusted input: OCR, URLs, manufacturer/distributor text and user metadata cannot control prompts, tools, file paths or network destinations.

- Source adapters: source-specific allowlists, redirect/domain checks, rate limits and terms/robots review; no arbitrary URL fetcher.

- Operational rollback: active catalog pointer, per-model support demotion and policy feature flag must roll back without an app release.

# 9. Phased implementation plan and gate definitions

```text
Scheduling rule
This workstream is POST_MVP_HIGH by default. P0/P1 foundation and read-only data work may proceed in parallel only when it does not displace current proven MVP blockers. Runtime exact-model user-facing promotion is never allowed merely because the data pipeline exists.
```

| Phase | Name | Scope | Phase exit |
| --- | --- | --- | --- |
| P0 | Foundation & provenance | Freeze scanner truth, recover ML provenance, define rights/versioning, and prove cloud region/IAM/SDK feasibility. | No new user-facing exact claim. |
| P1 | Canonical Knowledge Base | Ontology/schema, official brand adapters, Wger staging, catalogue reconciliation. | A lawful exact-model catalog exists. |
| P2 | OCR-first Identity | Structured OCR, identity parser, server text lookup, additive contracts/progressive UI plumbing. | Text identity shadow works; OCR-only value checkpoint decides whether expensive visual phases proceed now. |
| P3 | Licensed Corpus & Golden Set | Acquire approved assets; create dev regression/calibration sets plus new sealed blind real-gym/OOD tests. | Evaluation data exists without leakage. |
| P4 | Visual Retrieval & Decision Quality | Embeddings, Firestore vector search, fusion, calibration, verifier. | Trustworthy candidate/abstention engine in shadow. |
| P5 | Product UX & Machine Memory | Guided multi-view, equipment page, verified setup, history, private physical-instance memory. | Useful exact identity without breaking generic flow. |
| P6 | Shadow, Evaluation & Promotion | Real scans, blind real-gym test, per-model support promotion. | First model set may become VISION/TEXT VERIFIED. |
| P7 | Contribution & Active Learning | Opt-in training contribution, redaction, moderation, retraining queue. | Lawful learning loop. |
| P8 | Scale | 50 -> 300 -> 1000 models based on measured demand/coverage. | Operationally sustainable recognition catalog. |

## Phase P0 — Foundation & provenance

### P0.G1 — Current recognition baseline freeze

CLASSIFICATION: FOUNDATION / PRE-IMPLEMENTATION

Purpose. Capture the exact shipped/current scanner behavior so future exact-identity work cannot silently rewrite generic semantics.

Inputs. Current master, scanner contracts, model registry, current 30-photo evaluation evidence.

Deliverables. Versioned baseline note; hashes/versions of current OCR/TFLite/cloud paths; preserved holdout inventory.

Verification. Existing scanner tests + baseline report reproducible from source.

Required review. Flutter reviewer + ML/data reviewer.

Exit. Baseline is reproducible and current 30 photos are marked HOLDOUT/NO_TRAINING.

Rollback / failure mode. If provenance cannot be reproduced, block learned-model promotion but continue ontology/source work.

### P0.G2 — ML provenance recovery

CLASSIFICATION: FOUNDATION

Purpose. Ratchet training/evaluation reproducibility before adding another learned recognition component.

Inputs. MODEL_REGISTRY.json and any extant equipment-model tooling/manifests.

Deliverables. Version-controlled training/eval manifests, dependency pins, dataset source manifests, known UNKNOWN fields explicitly recorded.

Verification. Rebuild or at minimum deterministic manifest validation; no fabricated commit/version values.

Required review. ML/data reviewer + governance reviewer.

Exit. New identity ML work can point to recoverable code/manifests; unresolved historical v1/v2 provenance stays explicitly historical.

Rollback / failure mode. Do not "repair" history by inventing missing provenance.

### P0.G3 — Source & rights registry

CLASSIFICATION: FOUNDATION / LEGAL

Purpose. Create fail-closed source/license governance before mass acquisition.

Inputs. Source Strategy, official source URLs, marketplace/API terms.

Deliverables. equipment_sources schema, rights dimensions, quarantine rules, source-priority policy, terms-capture format.

Verification. Unit/schema tests: unknown rights cannot become display/training/embedding eligible.

Required review. Security/privacy + provenance/legal review.

Exit. 100% of ingested sources carry rights state; unknown -> quarantine.

Rollback / failure mode. Any ambiguous right remains staging-only.

### P0.G4 — Catalog version & type snapshot

CLASSIFICATION: FOUNDATION

Purpose. Create authoritative catalog-version semantics without duplicating equipment.json as a second source of truth.

Inputs. equipment.json and new exact-model schema.

Deliverables. Generated immutable type snapshot/hash for backend validation; catalog version manifest.

Verification. Build test fails if primaryTypeId references a nonexistent equipmentId; hash/version deterministic.

Required review. Architecture + ontology review.

Exit. Server validates exact models against current functional type snapshot.

Rollback / failure mode. Regenerate snapshot from equipment.json; never hand-edit duplicate type catalog.

### P0.G5 — Cloud feasibility, IAM, region & SDK spike

CLASSIFICATION: FOUNDATION / ARCHITECTURE

Purpose. Prove the preferred Firebase/Vertex/Firestore vector path fits the actual project before P4 implementation.

Inputs. Current Node 20 / firebase-functions 6 stack, Firebase project regions, Firestore location, Vertex availability, current IAM/service accounts.

Deliverables. Pinned client dependencies, region/data-residency decision, least-privilege IAM, vector-index smoke test, App Check callable smoke test, latency/cost estimate and rollback decision.

Verification. Real staging-project KNN smoke test plus mocked/unit layer; do not assume emulator parity for vector search.

Required review. Firebase/backend + security + architecture review.

Exit. Preferred retriever is technically feasible with known regions, permissions, dependencies and cost envelope; otherwise choose another server-side retriever without changing product contracts.

Rollback / failure mode. Stay OCR/text-only and postpone visual retrieval.

## Phase P1 — Canonical Machine Knowledge Base

### P1.G1 — Equipment identity ontology & Firestore schema

CLASSIFICATION: POST_MVP_HIGH

Purpose. Implement additive Brand/ProductLine/EquipmentModel/Asset/Source/ExternalMapping/SetupSpec boundaries.

Inputs. P0 outputs, current equipment ontology.

Deliverables. Schemas, converters/validators, indexes, Firestore rules/admin boundaries, example seed records.

Verification. Schema validation, multi-function model tests, immutable modelId/canonicalSlug uniqueness tests.

Required review. Flutter/architecture + ontology + Firebase/backend review.

Exit. Can represent 50 pilot models without changing equipmentId semantics.

Rollback / failure mode. Schema changes remain additive; no migration of exercise equipmentId.

### P1.G2 — Official P0 brand adapters

CLASSIFICATION: POST_MVP_HIGH

Purpose. Populate canonical metadata from first-party sources.

Inputs. Technogym, Life Fitness/Hammer Strength, Matrix, Core/Nautilus sources.

Deliverables. Read-only metadata adapters, normalized records, source refs, conflict reports; binaries not downloaded by default.

Verification. Fixture-based parsers; source change detection; disagreements become findings.

Required review. Data/provenance + ontology review.

Exit. Pilot brand metadata has official sources and 100% provenance fields.

Rollback / failure mode. Adapter breakage quarantines updates; existing published catalog remains unchanged.

### P1.G3 — P1 brand adapters

CLASSIFICATION: POST_MVP

Purpose. Extend official metadata coverage to Precor/Panatta.

Inputs. P1 official sources.

Deliverables. Same contracts as P1.G2.

Verification. Same parser/source drift tests.

Required review. Data/provenance + ontology review.

Exit. Coverage report complete; no silent overwrite of P0 records.

Rollback / failure mode. Disable adapter on source drift.

### P1.G4 — WGER_REFERENCE_INGESTION

CLASSIFICATION: POST_MVP_HIGH / ENRICHMENT

Purpose. Build read-only exercise enrichment staging and mapping report.

Inputs. wger API/data model and per-entry licenses.

Deliverables. Staging snapshot, per-object license/provenance, external mappings, matched/unmatched/alias/muscle/equipment/variation report.

Verification. No production writes; deletion/replacement sync fixture; license preservation test.

Required review. Ontology + content/safety + provenance review.

Exit. Staging snapshot and mapping report are reproducible with per-object provenance. Production reuse is separately license-gated. This gate is OPTIONAL/PARALLEL and does not block P2 machine identity.

Rollback / failure mode. Delete staging/import output without product impact.

### P1.G5 — Catalogue reconciliation

CLASSIFICATION: POST_MVP_HIGH

Purpose. Compare SPTR functional catalog, exact models and external exercise/source data.

Inputs. P1.G1-4 outputs.

Deliverables. Missing models, duplicate aliases, type conflicts, source disagreements, exercise mapping disagreements, legacy model candidates.

Verification. Deterministic reconciliation report; no unresolved conflict auto-promoted.

Required review. Ontology curator + product/data review.

Exit. All pilot models have resolved primaryTypeId; unresolved conflicts explicitly AMBIGUOUS/STAGING.

Rollback / failure mode. No production write for unresolved conflict.

## Phase P2 — OCR-first Identity

### P2.G1 — Structured OCR capability

CLASSIFICATION: POST_MVP_HIGH

Purpose. Extend ML Kit OCR contract to return lines/bounds/confidence while preserving existing String API.

Inputs. Current mlkit_text_recogniser + machine_text_anchor.

Deliverables. MachineTextEvidence, structured recogniser interface, backward-compatible adapter.

Verification. Device/plugin tests + pure unit tests; generic anchor behavior unchanged.

Required review. Flutter reviewer.

Exit. Existing generic OCR tests pass; structured lines/bounds available.

Rollback / failure mode. Feature flag/adapter can fall back to legacy String path.

### P2.G2 — IdentityTextParser

CLASSIFICATION: POST_MVP_HIGH

Purpose. Parse brand/line/model/SKU/type hints without altering generic denoising.

Inputs. Structured OCR + catalog aliases.

Deliverables. Pure parser, normalized tokens, conflict detection, centrality/placard heuristics.

Verification. Hard cases: two machines, neighbour placard, two model codes, OCR noise, brand-only.

Required review. Flutter + ontology + adversarial QA.

Exit. No silent exact selection with conflicting codes; deterministic evidence output.

Rollback / failure mode. Parser failure yields no identity evidence, generic scan unaffected.

### P2.G3 — Server exact text lookup

CLASSIFICATION: POST_MVP_HIGH

Purpose. Resolve unique strong text evidence against authoritative catalog without image upload.

Inputs. P2.G2 + equipment_models + catalog version.

Deliverables. Cloud Function text path, model-code/alias indexes, policy checks, App Check/rate limits.

Verification. Unique/nonunique code tests, type compatibility, rights-independent catalog lookup, auth/App Check.

Required review. Backend/security + ontology review.

Exit. Verified text-supported pilot models can return shadow exact IDs with full evidence/versioning.

Rollback / failure mode. Disable text exact policy; return type-only.

### P2.G4 — Additive mobile identity contract & progressive UX plumbing

CLASSIFICATION: POST_MVP_HIGH

Purpose. Add EquipmentIdentity to ScanResult/result UI without changing VisualMatch or generic history.

Inputs. P2.G3 API contract.

Deliverables. EquipmentIdentity model/service/provider; progressive type-first rendering; shadow flags; no spinner dependency on exact identity.

Verification. Widget/state tests for type-only/brand/exact/needMoreView/unknown; generic tests unchanged.

Required review. Flutter/product UX + safety review.

Exit. Exact identity can be shown in non-production/shadow UI without blocking exercises.

Rollback / failure mode. Disable identity enrichment flag; generic scanner behavior remains identical.

### P2.G5 — OCR-only shadow & value checkpoint

CLASSIFICATION: POST_MVP_HIGH / GO-NO-GO

Purpose. Prove that Brand → Line → Model catalog + structured OCR creates enough real user value to justify the more expensive visual-retrieval phases now.

Inputs. Shadow text identity on real scans, latency, exact text-resolution rate, need-more-view rate, catalog coverage and product value evidence.

Deliverables. OCR-only quality/value report and explicit GO_VISUAL / DEFER_VISUAL decision.

Verification. No production exact claim unless textSupportStatus and policy gates already pass; compare against current generic scanner without using sealed blind-test labels.

Required review. Product + ML/data + architecture.

Exit. GO only if visual retrieval has a measured unmet need; otherwise retain text identity and defer P3/P4 visual work.

Rollback / failure mode. No sunk-cost escalation: catalog/OCR value remains useful.

## Phase P3 — Licensed Corpus & Golden Set

### P3.G1 — Rights-approved asset acquisition

CLASSIFICATION: POST_MVP_HIGH

Purpose. Acquire only assets whose intended use is explicitly allowed.

Inputs. P0.G3 registry + P1 pilot catalog.

Deliverables. Hashed asset manifests, metadata, viewpoint labels, source-domain labels, quarantined blocked assets.

Verification. 100% source URL/hash/retrieval date/rights dimensions; pHash dedup.

Required review. Provenance/legal + data review.

Exit. No asset with unknown rights enters shippable display, embeddings or training corpus.

Rollback / failure mode. Quarantine/delete derivative copies; catalog metadata remains.

### P3.G2 — Development regression/calibration sets + sealed blind test v1

CLASSIFICATION: RELEASE-BLOCKING EVALUATION FOUNDATION

Purpose. Separate engineer-visible development evidence from calibration and a genuinely sealed independent production test.

Inputs. LEGACY_REAL_GYM_REGRESSION_SET, newly acquired independent physical instances/gyms, explicit OOD/hard-negative collection.

Deliverables. DEV_REGRESSION_SET, CALIBRATION_SET, SEALED_BLIND_REAL_GYM_TEST_SET, SEALED_OOD_TEST_SET with instance/gym IDs and hidden labels/results.

Verification. No physical-instance leakage, pHash duplicate grouping, sealed labels inaccessible to implementation/tuning, independent custody/runner.

Required review. ML/data + adversarial QA + ontology review.

Exit. Thresholds can be tuned on development/calibration data while final real-gym/OOD claims remain genuinely unseen.

Rollback / failure mode. If sample too small, production exact claim remains blocked.

### P3.G3 — Training/reference corpus v1

CLASSIFICATION: POST_MVP_HIGH

Purpose. Build a rights-clean engineer-visible reference/training corpus for retrieval/fusion development without consuming sealed evaluation evidence.

Inputs. P3.G1 approved assets, explicitly eligible training/reference acquisitions, source manifests and dev-only hard negatives; exclude SEALED_* sets.

Deliverables. Rebuildable TRAIN_REFERENCE_CORPUS manifest with model/instance/viewpoint/source labels, asset hashes, rights dimensions, split groups and provenance.

Verification. Class/brand/viewpoint balance, pHash duplicate grouping before split, physical-instance/gym leakage checks, hard-negative coverage; SEALED_* identifiers absent.

Required review. ML/data + provenance review.

Exit. Corpus can be rebuilt from manifests; every included asset is eligible for its intended use; synthetic/manufacturer/real-gym provenance stays separable.

Rollback / failure mode. Quarantine an ineligible source/domain and rebuild from remaining manifests without contaminating sealed tests.

## Phase P4 — Visual Retrieval & Decision Quality

### P4.G1 — Embedding provider & retriever benchmark

CLASSIFICATION: POST_MVP_HIGH

Purpose. Add image embeddings and choose the simplest server-side retriever that meets measured pilot latency/cost/quality.

Inputs. P3 corpus/exemplars, Vertex multimodal embedding, Firestore vector indexes.

Deliverables. EmbeddingProvider + VectorRetriever interfaces, Vertex embedding integration, Firestore KNN implementation and simple cached/brute-force pilot baseline where feasible.

Verification. Version/dimension compatibility, catalogVersion filtering, top-K correctness, latency/cost benchmark, no protected exemplar leakage to client.

Required review. Backend/security + ML review.

Exit. Retriever choice is justified by benchmark; Firestore remains preferred if it meets the bar.

Rollback / failure mode. Turn off visual path; OCR/type path remains.

### P4.G2 — Evidence fusion

CLASSIFICATION: POST_MVP_HIGH

Purpose. Fuse visual retrieval, structured OCR, generic type evidence and optional logo/viewpoint evidence into ranked model candidates without allowing one weak signal to silently dominate.

Inputs. P4.G1 retriever outputs + P2 structured text evidence + typeEvidenceStatus + catalog compatibility.

Deliverables. Versioned fusion policy with per-signal feature contract, conflict rules, candidate aggregation by modelId, per-signal diagnostics and rawCandidateScore.

Verification. Ablation tests, conflicting-brand/model/type tests, missing-signal tests, neighboring-placard cases, exemplar-count/viewpoint bias checks.

Required review. ML/data + ontology review.

Exit. Fusion improves candidate ranking/recall at fixed safety constraints versus each single signal; no weak feature alone converts conflict into exact identity.

Rollback / failure mode. Disable fusion and return ranked retrieval/text candidates with abstention; generic type path stays intact.

### P4.G3 — Calibration & open-set gate

CLASSIFICATION: RELEASE-BLOCKING

Purpose. Fuse visual retrieval, structured OCR, generic type evidence and optional logo/viewpoint evidence into ranked model candidates without allowing one weak signal to silently dominate.

Inputs. CALIBRATION_SET + dev OOD/hard negatives + frozen P4.G2 fusion outputs. SEALED_* labels/results remain inaccessible.

Deliverables. Calibration artifact, thresholds by identity level/evidence class, reliability/ECE/Brier or equivalent, abstention/open-set policy and frozen policy version.

Verification. Calibration-set reliability, dev-OOD false-exact analysis, per-brand/line confusion, sensitivity/threshold stability; no sealed-test tuning.

Required review. ML/data + adversarial reviewer.

Exit. A frozen calibrated policy is ready for shadow and later sealed P6 evaluation; production exact-model claim remains blocked until P6.

Rollback / failure mode. Raise thresholds, restrict support status or disable exact claim; TYPE_ONLY / BRAND+TYPE remain available.

### P4.G4 — Candidate-bounded Gemini verifier

CLASSIFICATION: POST_MVP

Purpose. Use Gemini only to adjudicate real retrieved candidates.

Inputs. Top 3-5 candidates + image/evidence.

Deliverables. Structured MATCH/UNKNOWN/NEED_MORE_VIEW response with candidateId/nextView/evidence.

Verification. Schema enforcement; hallucinated ID rejected; verifier-off comparison.

Required review. AI/backend + safety/security review.

Exit. Verifier improves measured decision quality or is rejected; never required for type result.

Rollback / failure mode. Disable verifier without breaking retrieval/fusion.

## Phase P5 — Product UX & Machine Memory

### P5.G1 — Guided multi-view

CLASSIFICATION: POST_MVP_HIGH

Purpose. Ask for the discriminating next view instead of guessing.

Inputs. NEED_MORE_VIEW response and existing CameraSession.

Deliverables. Guided PLACARD/LOGO/SIDE/FULL capture; multi-view evidence aggregation.

Verification. Widget/device flows; stale scan cancellation; conflicting views -> abstain.

Required review. Flutter/UX + QA review.

Exit. Ambiguous sibling models can request a useful second view without losing generic result.

Rollback / failure mode. Cancel multi-view and keep generic type.

### P5.G2 — Exact-model equipment page & verified setup

CLASSIFICATION: POST_MVP_HIGH

Purpose. Enrich existing EquipmentDetailPage rather than create a second product.

Inputs. Verified EquipmentIdentity + SetupSpec.

Deliverables. Route/optional model context, brand/line/model UI, source-qualified setup facts, same exercises/safety/AI Coach.

Verification. Exact vs ambiguous vs type-only UI tests; no setup if not verified.

Required review. Flutter/product + safety review.

Exit. Exact identity enriches page but cannot change vetted exercise/safety eligibility.

Rollback / failure mode. Strip model context; generic page still works.

### P5.G3 — Exact history

CLASSIFICATION: POST_MVP_HIGH

Purpose. Remember exact models separately from generic equipment history.

Inputs. Verified exact identity events.

Deliverables. users/{uid}/recognised_models records with versions/evidence summary, no raw photo by default.

Verification. Account isolation, delete/logout behavior, duplicate/update semantics.

Required review. Privacy/security + Flutter review.

Exit. No cross-account leak; ambiguous/alternative results not remembered as exact.

Rollback / failure mode. Disable exact history writes.

### P5.G4 — Private PhysicalMachineInstance memory

CLASSIFICATION: POST_MVP / OPTIONAL — NOT A P6 PREREQUISITE

Purpose. Bind user setup memory to a particular gym machine without contaminating global identity.

Inputs. Existing gym/setup memory foundations + verified model identity.

Deliverables. User-private instance record, gymId, modelId, optional local fingerprint and setup notes.

Verification. Account isolation, identity downgrade behavior, ambiguity handling.

Required review. Privacy + product/ontology review.

Exit. Setup memory can be recalled only for the intended user/instance; never sole model proof. Recognition promotion may proceed without this optional gate.

Rollback / failure mode. Fall back to model/type memory only.

### P5.G5 — User correction / misidentification feedback

CLASSIFICATION: RELEASE PREP

Purpose. Give the user an explicit safe correction path before public exact-model promotion.

Inputs. Exact/brand/type result card and current unknown/alternative flows.

Deliverables. "Not this model" / correction flow, telemetry event without automatic training label, optional guided rescan.

Verification. Correction cannot silently mutate global catalog or become ground-truth training data; a11y/l10n; account/privacy behavior.

Required review. Product/UX + privacy + ML governance.

Exit. Public exact identity has a visible recovery path and feedback is quarantined as evidence, not truth.

Rollback / failure mode. Disable feedback collection while retaining safe generic fallback.

## Phase P6 — Shadow, Evaluation & Promotion

### P6.G1 — Shadow deployment

CLASSIFICATION: POST_MVP / OPTIONAL — NOT A P6 PREREQUISITE

Purpose. Run identity backend on real scans without changing production generic result.

Inputs. P2-P4 runtime, current scanner.

Deliverables. Shadow telemetry with versions, candidates, abstentions, latency/cost. No raw-photo persistence unless separately authorized.

Verification. Compare current generic vs v3 type/brand/exact outcomes; privacy/telemetry audit.

Required review. Release/ML/privacy review.

Exit. Enough real shadow volume to evaluate calibration and failure modes.

Rollback / failure mode. Disable shadow flag immediately.

### P6.G2 — Independent real-gym evaluation

CLASSIFICATION: RELEASE-BLOCKING

Purpose. Measure exact claims on blind real gyms/physical instances.

Inputs. Frozen artifacts/policy + sealed blind real-gym and sealed OOD sets. Thresholds are already locked.

Deliverables. Point metrics plus one-sided 95% confidence bounds, cluster-aware/physical-instance analysis, calibration, abstention, latency/cost, confusion matrices and stratification by brand/model/gym/device where sample size permits.

Verification. Independent evaluator/custodian runs the sealed sets after artifact freeze; multiple frames from one physical machine are not counted as independent evidence; dual-label/adjudication for ambiguous ground truth.

Required review. ML/data + adversarial + release reviewer.

Exit. Statistical confidence gates pass for the defined promoted model set; otherwise remain shadow/text-only/type-only.

Rollback / failure mode. Remain shadow/text-only/type-only.

### P6.G3 — Model-by-model promotion

CLASSIFICATION: PRODUCTION PROMOTION

Purpose. Promote only models that meet their evidence/support gates.

Inputs. Frozen artifacts/policy + sealed blind real-gym and sealed OOD sets. Thresholds are already locked.

Deliverables. Point metrics plus one-sided 95% confidence bounds, cluster-aware/physical-instance analysis, calibration, abstention, latency/cost, confusion matrices and stratification by brand/model/gym/device where sample size permits.

Verification. Promotion mutation: unsupported model must abstain; rollback target tested.

Required review. Release + safety + ontology + GPT independent review.

Exit. 0 BLOCKER/CRITICAL/MAJOR for promoted surface; evidence attached.

Rollback / failure mode. Demote model to SHADOW/SUPPORTED/CATALOG_ONLY without app release if policy is server-side.

## Phase P7 — Contribution & Active Learning

### P7.G1 — Explicit contribution consent UX

CLASSIFICATION: POST_MVP

Purpose. Separate "scan" from "help improve recognition."

Inputs. Privacy requirements + current scanner unknown/ambiguous flows.

Deliverables. Opt-in consent UI, consent version, delete/revoke path.

Verification. Consent denied -> no persistent training upload; accessibility/l10n.

Required review. Privacy/security + UX review.

Exit. No contribution without explicit action.

Rollback / failure mode. Disable feature remotely.

### P7.G2 — Redaction, moderation & retention

CLASSIFICATION: POST_MVP

Purpose. Make contributions suitable for review without leaking obvious personal metadata.

Inputs. Opt-in images.

Deliverables. Face redaction, EXIF/GPS removal, TTL/retention, moderation/review states, source attribution.

Verification. Redaction fixtures, metadata stripping tests, deletion SLA tests.

Required review. Privacy/security + QA review.

Exit. 100% contributions pass processing before training eligibility.

Rollback / failure mode. Quarantine/delete contribution; no training use.

### P7.G3 — Retraining queue and challenger lifecycle

CLASSIFICATION: FULL PRODUCT

Purpose. Turn reviewed contributions into reproducible challenger datasets, not silent online training.

Inputs. Human/server-reviewed labels and source rights.

Deliverables. Versioned dataset manifests, train/eval pipeline, MODEL_REGISTRY challenger entries.

Verification. Leakage checks, golden untouched, challenger vs champion evaluation.

Required review. ML/data + governance review.

Exit. No automatic champion promotion; challenger must pass P6-equivalent evaluation.

Rollback / failure mode. Reject challenger; champion unchanged.

## Phase P8 — Scale

### P8.G1 — 50-model pilot completion

CLASSIFICATION: POST_MVP_HIGH

Purpose. Deeply support a demand-driven initial exact-model set.

Inputs. Scan frequency, unknown frequency, target gym penetration, content value.

Deliverables. ~50 cataloged models with defined text/vision status and source/rights completeness.

Verification. Coverage/latency/cost/quality dashboard.

Required review. Product + data + release review.

Exit. Pilot supports useful real-gym coverage with precision-first behavior.

Rollback / failure mode. Freeze catalog expansion; improve quality.

### P8.G2 — Scale to ~300 models

CLASSIFICATION: FULL PRODUCT

Purpose. Expand only after adapters/rights/index economics are stable.

Inputs. P8.G1 operational metrics.

Deliverables. Automated adapters, incremental embeddings, catalog diff/review workflow.

Verification. Cost/index/query performance and source drift tests.

Required review. Architecture/data/release review.

Exit. Quality and rights SLOs remain stable.

Rollback / failure mode. Pause new ingestion; existing models unaffected.

### P8.G3 — Scale to ~1000+ models / re-evaluate storage

CLASSIFICATION: FULL PRODUCT

Purpose. Decide whether Firestore vector architecture still fits measured scale.

Inputs. Real vector count, query latency, cost, write/update patterns.

Deliverables. Architecture decision record: stay on Firestore or migrate vector retrieval only if evidence warrants.

Verification. Benchmark alternative only when trigger reached; migration shadow/rollback plan.

Required review. Architecture + security + finance/ops review.

Exit. No platform migration without measured advantage and zero product semantics change.

Rollback / failure mode. Stay Firebase-first.

# 10. Multi-round review protocol

```text
Review rule
Each full Gate ends with an independent review. Subgates inside a Gate do not spawn extra reviews unless evidence demands it. Review attempts that fail open due transport/tooling are recorded as ATTEMPTED_FAILED_TRANSPORT, never PASS or CONSENSUS.
```

| Round | Primary focus | Required perspectives | Typical blockers |
| --- | --- | --- | --- |
| R0 | Source-of-truth / scope | Architecture + product owner | Wrong baseline, duplicate ontology, scope expansion, stale repo assumptions. |
| R1 | Ontology / data contracts | fitness-flutter-reviewer + exercise-ontology-curator + backend | equipmentId breakage, 1:1 assumptions, unstable IDs, migration risk. |
| R2 | Sources / rights / privacy | Provenance/legal role + security/privacy | Unknown rights treated as allowed, NoAI ignored, silent user-photo retention. |
| R3 | ML / evaluation | fitness-data-scientist + adversarial QA | Leakage, bad split, uncalibrated confidence, no OOD, manufacturer-only validation. |
| R4 | Clinical/safety/product | clinical-safety-gate + product/UX | Exact model bypasses safety, hallucinated setup, ambiguous model silently chosen. |
| R5 | Release / independent consensus | Release reviewer + GPT review mechanism + operator only if unresolved authority needed | Metrics not met, fail-open receipt called PASS, no rollback, missing provenance. |

Finding format. severity | claim | evidence | failure scenario | required change. The gate closes only when 0 BLOCKER and 0 CRITICAL remain. Any MAJOR that affects the gate exit must be fixed; a deferred MAJOR must be explicitly outside the current gate and have evidence that it does not invalidate the exit claim.

Maximum rounds. Up to five evidence-based reviewer/fix rounds before operator escalation, matching the project governance rule. Escalate only a genuinely unresolved authority/trust-model decision, not ordinary implementation decomposition.

## 10.2 Three-round independent review outcome

R1 produced 2 BLOCKER, 3 CRITICAL, 11 MAJOR and 2 MINOR findings. R2 cross-review accepted the high-impact findings and changed the architecture. R3 Devil's Advocate challenged product value, statistical validity, cloud lock-in, rights, neighboring placards, setup safety and recovery. After remediation, no design-level BLOCKER or CRITICAL remains. Production exact-model claims remain intentionally blocked by P6.

- FIXED: 30-photo set reclassified to legacy regression; new sealed blind real-gym/OOD sets required.

- FIXED: release thresholds now require confidence bounds and independent encounter/instance units.

- FIXED: hard type prefilter narrowed; low-confidence/offline type cannot veto stronger exact evidence.

- FIXED: catalog uses staged/versioned publication with atomic active-pointer rollback.

- FIXED: untrusted OCR/source text is isolated from verifier control instructions.

- FIXED: P0.G5 validates regions/IAM/SDK/vector feasibility before infrastructure lock-in.

- FIXED: scanId + recognitionSessionId prevent stale async enrichment overwrites.

- FIXED: Wger is optional enrichment and production reuse is license-compatibility gated.

- FIXED: setup specs carry variant/revision applicability and a stricter setup-assurance gate.

- FIXED: P2.G5 may defer visual retrieval if OCR/catalog already captures sufficient value.

- FIXED: user correction exists before public exact identity; feedback is not self-labeling training truth.

- ACCEPTED LIMITATION: exact-model production remains blocked until P6 independent evaluation/promotion.

| Review round | Gate | Severity | Finding | Resolution / rebuttal | Status | Evidence |
| --- | --- | --- | --- | --- | --- | --- |
| R__ | P_.G_ | BLOCKER/CRITICAL/MAJOR/MINOR | ... | ... | OPEN/FIXED/REJECTED_WITH_EVIDENCE | commit/test/report |
| R__ | P_.G_ | ... | ... | ... | ... | ... |
| R__ | P_.G_ | ... | ... | ... | ... | ... |

## 10.1 Pre-publication merge review applied to this document

| Finding | Severity | Resolution in v4 |
| --- | --- | --- |
| Both source documents used ER-0..ER-9 for different scopes. | MAJOR | Replaced with Phase/Gate identifiers P0.G1...P8.G3. |
| Readable slug as modelId risks identity drift. | MAJOR | Immutable internal modelId + canonicalSlug secondary key. |
| Single recognitionStatus mixes OCR support and vision support. | MAJOR | Split textSupportStatus and visionSupportStatus. |
| Visual pipeline may upload an image even when OCR model code already uniquely resolves identity. | MAJOR | Text-only authoritative server lookup precedes image embedding. |
| Physical-machine memory could become a hidden identity prior or privacy leak. | MAJOR | User-private instance layer; no sole-evidence identity; shared gym inventory is separate governed gate. |
| Rights model needs to distinguish display/training/embedding/derivative use. | BLOCKER for ingestion | Added recognitionProcessingAllowed and fail-closed multi-dimensional rights state. |
| Existing 30 gym photos risk being consumed by new training work. | BLOCKER for evaluation integrity | Explicitly frozen as holdout/no-training evidence. |
| Mature SPTR safety/exercise pipeline could be bypassed by exact-model enrichment. | BLOCKER | Explicit exact->typeId->existing safety/exercises invariant in architecture and gate exits. |

# 11. Release metrics, promotion rules and kill criteria

| Metric | Pilot / promotion rule |
| --- | --- |
| P0 brand canonical records with official source | >=95% for models intended for promotion; 100% of promoted models have official or explicitly reviewed source truth. |
| Assets with explicit rights state | 100%; relevant use dimension must be explicitly allowed in current terms snapshot. |
| Assets with source URL + hash + retrieval date | 100%. |
| Unresolved duplicate rate after pHash | <2% in eligible corpus; zero known cross-split leakage. |
| Exact-model precision when claiming exact | One-sided 95% lower confidence bound >=97% on sealed independent encounters/clusters; not point estimate only. |
| False EXACT_MODEL on unsupported/OOD | One-sided 95% upper confidence bound <=1% on sealed OOD encounters/clusters; clustered/safety-relevant pattern is blocker regardless aggregate. |
| Brand + type precision | >=95% provisional. |
| High-confidence type precision | >=95% and must not regress current honest generic path. |
| Calibration | Calibrate on separate CALIBRATION_SET; lock method/thresholds before sealed test; report reliability/ECE/Brier or equivalent plus stratified stability. |
| Abstention | Measured; precision > coverage. |
| p95 generic response | Target <=3s online; must not regress existing UX. |
| p95 exact enrichment | Target <=6s; generic result remains usable while enrichment runs. |
| Cloud fallback/error rate | Monitored with explicit outcome; no infinite spinner. |
| Cost per scan / exact resolution | Monitored; architecture migration only after measured trigger. |
| License/provenance violations | 0. |
| Sealed test independence | Required. No tuning/selection using sealed labels/results; independent custody/runner. |
| Minimum independent evidence | Sample size chosen to satisfy statistical bounds; with zero errors roughly >=100 exact claims and >=299 OOD encounters for provisional 97%/1% one-sided 95% gates. |
| User correction path | Required before public exact-model promotion; correction feedback is evidence, not automatic ground truth. |

Promotion semantics. Catalog presence does not imply support. A model may be CATALOG_ONLY, text experimental/verified, and vision experimental/shadow/supported/verified independently. The production policy determines whether exact identity can be claimed from the available evidence.

Kill / pause criteria. Pause user-facing exact promotion if false-exact OOD exceeds the gate, calibration is unstable across gyms/devices, rights coverage cannot be proven, App Check/security cannot be enforced, or generic scanner latency/reliability regresses. The fallback is always the current generic type/ambiguous/unknown behavior.

# 12. Repository/file plan and implementation dependencies

## 12.1 New mobile files

```text
mobile/lib/features/visual_equipment/data/
  equipment_identity.dart
  machine_text_evidence.dart
  machine_identity_text.dart
  equipment_identity_service.dart
  cloud_equipment_identity_service.dart
```

## 12.2 Existing mobile files to change additively

```text
mobile/lib/features/visual_equipment/data/
  mlkit_text_recogniser.dart
  scan_outcome.dart
  machine_text_anchor.dart       # generic behavior preserved

mobile/lib/features/visual_equipment/state/
  visual_equipment_providers.dart

mobile/lib/features/scanner/
  scanner_page.dart

mobile/lib/features/equipment/
  equipment_detail_page.dart

mobile/lib/core/router/
  app_router.dart

mobile/lib/main.dart
```

## 12.3 Backend

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
  rate_limit.ts
  telemetry.ts
```

## 12.4 Offline/catalog pipeline

```text
scripts/equipment_catalog/
  discover.py
  ingest.py
  normalize.py
  dedupe.py
  validate_sources.py
  build_aliases.py
  reconcile.py
  build_embeddings.py
  publish_catalog.py

scripts/ml/equipment_identity/
  build_dataset.py
  split_instances.py
  evaluate.py
  calibrate.py
  report.py
```

## 12.5 Versioned repository artifacts

```text
core/equipment_catalog/
  SCHEMA.md
  SOURCE_POLICY.md
  sources/
  manifests/
  LICENSE_LEDGER.csv
  CATALOG_VERSION.json
  WGER_MAPPING_REPORT.md

core/ml/
  MODEL_REGISTRY.json             # existing authority
  equipment_identity/
    DATASET_MANIFESTS/
    EVALUATION_REPORTS/
    CALIBRATION_REPORTS/
```

No-binary rule. Large images, videos, 3D assets and training corpora need not live in Git. Their content hashes, source manifests, rights state, split membership and retrieval/build provenance must.

# 13. Explicit non-goals and forbidden shortcuts

- Do not rewrite Scanner or replace CameraSession.

- Do not replace equipmentId with manufacturer model/SKU.

- Do not ship equipment_v2.tflite as a shortcut to exact-model identity.

- Do not train on the current 30 holdout gym photos.

- Do not remove current brand words from generic _kNoise; identity parsing is a separate path.

- Do not trust Gemini self-confidence as probability.

- Do not run exact-model cloud recognition on every live frame.

- Do not auto-save every scan to a training dataset.

- Do not allow exact identity to bypass current exercise/safety filtering.

- Do not use LLM-generated model-specific setup facts.

- Do not use the same physical machine across train/test split.

- Do not silently choose an exact model under ambiguity.

- Do not treat "public URL", "royalty free" or "downloadable" as ML-training permission.

- Do not copy wger Django/backend code into Fitness-App; use data/API concepts through licensed read-only ingestion.

- Do not add PostgreSQL/pgvector solely because vector search is fashionable; re-evaluate only on measured Firestore limits/cost.

- Do not treat the existing 30 gym photos as an independent blind production test.

- Do not tune thresholds or model selection on sealed blind-test labels/results.

- Do not let low-confidence/offline generic type act as a hard filter against stronger exact evidence.

- Do not auto-publish adapter/Wger/source changes into the active catalog; publish through a reviewed immutable version.

- Do not pass OCR/source text to an LLM as executable instructions or allow it to add candidates.

- Do not count multiple frames of one physical machine as independent statistical evidence.

- Do not use recognition output or user correction as automatic training ground truth.

# 14. Source/reference ledger

Repository references used for the merged architecture:

- mobile/lib/features/visual_equipment/data/machine_text_anchor.dart

- mobile/lib/features/visual_equipment/data/scan_outcome.dart

- mobile/lib/features/equipment/data/equipment_models.dart

- mobile/lib/features/scanner/scanner_page.dart

- mobile/lib/features/visual_equipment/state/visual_equipment_providers.dart

- core/ml/MODEL_REGISTRY.json

- mobile/assets/data/equipment.json

- mobile/assets/data/equipment_aliases.json

- core/product/GATE_D_EQUIPMENT_TYPE_HISTORY_D0_NOTE_2026-08-19.md

- core/product/GATE_G_SETUP_MEMORY_D0_NOTE_2026-08-19.md

Previously verified external source families retained from the Source Strategy:

[1] Technogym Interior Design: https://www.technogym.ru/ru-RU/technogym-interior-design/

[2] Matrix Design Planning / Architect Portal: https://www.matrixfitnesszh.com/DesignPlanning.html

[3] Life Fitness Facility Design: https://www.lifefitness.com.au/design/

[4] Core Health & Fitness Nautilus collection: https://shop.corehandf.com/collections/nautilus

[5] Precor product specification tables: https://static.precor.com/spec-tables/en-us/Precor-2022-NA-Spec-Tables.pdf

[6] Panatta official product pages: https://www.panattasport.com/

[7] 3dsky sports models: https://3dsky.org/3dmodels?cat=miscellaneous-models&subcat=sports

[8] Sketchfab: https://sketchfab.com/

[9] wger GitHub: https://github.com/wger-project/wger

[10] ExerciseDB API: https://v2.exercisedb.io/docs

[11] API Ninjas Exercises: https://api-ninjas.com/api/exercises

Legal note. The presence of a source in this ledger is discovery/reference evidence only. It is not a blanket legal determination for display, embedding, training, redistribution or derivative use. Those permissions are stored and reviewed per source/asset under P0.G3/P3.G1.

# 15. Final recommended execution sequence

```text
Recommended order
Do not start with a new large neural network. The highest-value sequence is: provenance/rights -> exact catalog -> structured OCR/model-code lookup -> shadow text identity -> lawful corpus/golden set -> visual retrieval/fusion/calibration -> guided UX -> independent promotion -> contribution/retraining.
```

1. Finish/avoid disrupting current proven MVP blockers; classify this workstream POST_MVP_HIGH unless the operator explicitly changes priority.

2. P0 foundation: freeze current scanner truth, recover ML provenance, source/rights registry, catalog/version invariant.

3. P1: canonical exact-model KB + P0 brand adapters + WGER_REFERENCE_INGESTION + reconciliation.

4. P2: structured OCR + IdentityTextParser + exact model-code lookup + additive mobile contracts in shadow, then P2.G5 OCR-only value GO_VISUAL / DEFER_VISUAL checkpoint.

5. P3 (only after GO_VISUAL): acquire rights-approved corpus, build dev/calibration sets, and create newly sealed blind real-gym + OOD tests under independent custody.

6. P4: Vertex embeddings + retriever benchmark (Firestore KNN preferred if measured fit) + fusion + calibration + candidate-bounded verifier.

7. P5: guided second scan, exact model page enrichment, verified setup, exact history and private machine-instance memory.

8. P6: shadow on real scans -> lock artifacts/thresholds -> independent sealed real-gym/OOD evaluation with confidence bounds -> model-by-model promotion.

9. P7: explicit opt-in contribution -> redaction/moderation -> challenger/retraining lifecycle.

10. P8: scale from ~50 to ~300 to ~1000 models only when quality, rights, cost and source adapters are stable.

FINAL CONSENSUS VERDICT / APPROVE this architecture for phased implementation after three review rounds. BLOCK every public/production exact-model quality claim until P6 sealed independent real-gym + OOD evaluation, statistical confidence bounds, calibration/open-set gates and model-by-model promotion pass. P2.G5 may deliberately defer visual retrieval if OCR/catalog already delivers sufficient product value. The design remains fail-closed: TYPE_ONLY / BRAND+TYPE / NEED_MORE_VIEW is better than a confident wrong exact model.

# Appendix A — Gate close checklist

- Current repository/branch/source SHA recorded.

- Inputs and source licenses/provenance captured.

- No existing equipmentId/safety/ScanOutcome invariant broken.

- Tests include success, ambiguity, unknown/OOD and mutation/failure path.

- Privacy/App Check/rate limits appropriate for any new cloud surface.

- Independent review executed; fail-open attempt not counted as PASS.

- 0 BLOCKER and 0 CRITICAL; gate-affecting MAJOR findings fixed.

- Commit and push verified against Fitness-App/master with 0 ahead / 0 behind.

- Any successful APK build is handled under the project's standing Firebase App Distribution rule.

- Evidence and rollback path recorded before moving to next full Gate.

# Appendix B — Revision history

| Version | Date | State | Summary |
| --- | --- | --- | --- |
| v4.0 RC1 | 2026-08-21 | REVIEW CANDIDATE | Merged Source Strategy + Equipment Recognition v3; resolved gate-number collision, ID semantics, text-vs-vision support, rights dimensions, text-only exact path and physical-instance privacy boundary. |
| v4.0 RC2 | TBD | after review round 1 | Architecture/ontology findings. |
| v4.0 RC3 | TBD | after review round 2 | Data/rights/ML findings. |
| v4.0 FINAL | TBD | after final release-plan review | Canonical repo Markdown may be committed only after review closure. |
| v4.1 CONSENSUS | 2026-08-21 | APPROVE FOR PHASED IMPLEMENTATION | 3 rounds integrated: sealed-test correction, statistical gates, staged catalog publication, evidence-authority type policy, threat model, cloud feasibility gate, OCR-only value checkpoint, user correction and Devil's Advocate consensus. |
