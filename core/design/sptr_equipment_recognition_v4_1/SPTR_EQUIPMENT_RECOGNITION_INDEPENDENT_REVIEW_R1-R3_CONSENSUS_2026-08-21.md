*SPTR / Fitness-App*

# Equipment Recognition v4.1 — Independent Review & Consensus

*R1 Specialist Review — R2 Cross-Review & Remediation — R3 Devil's Advocate*

| Project | xLZDx/Fitness-App |
| --- | --- |
| Git baseline reviewed | master @ 3dd2e3e23e2a30c0e99a6995a1229acc5a0834a7 |
| Design reviewed | Equipment Recognition Master Technical Plan v4.0 RC1 |
| Rounds | 3 |
| Consensus | APPROVE FOR PHASED IMPLEMENTATION |
| Production exact-model claim | BLOCKED until P6 sealed blind evaluation + statistical confidence + calibration + promotion |

# 1. Review method and independence

Independent role passes attacked the design from separate failure models before any consolidation. The review did not inherit prior APPROVE verdicts. Only after findings were recorded were they reconciled. The final Devil's Advocate round attempted to invalidate the remediated design again.

- Architecture / Flutter / state lifecycle

- Firebase / backend / SRE

- ML / data science / evaluation

- Equipment ontology / catalog

- Data provenance / licensing

- Security / privacy / abuse

- Clinical-safety / product trust

- QA / adversarial / release

- Devil's Advocate final challenge

External feasibility was checked against current official Google/Firebase documentation: Firestore vector KNN supports Node.js and vectors up to 2048 dimensions; Vertex multimodal embeddings support 1408-dimensional image/text embeddings; ML Kit text lines/elements expose geometry and confidence where available; callable Cloud Functions support App Check enforcement. Project-specific IAM/region readiness still requires P0.G5.

# 2. Round 1 — Independent specialist findings

| ID / Sev | Claim | Evidence / concern | Failure scenario | Required change |
| --- | --- | --- | --- | --- |
| R1-01<br>BLOCKER | Existing 30 gym photos are not a blind holdout. | Already repeatedly inspected and used in v1/v2/OCR design/evaluation. | A final claim would be contaminated by development exposure. | Reclassify as LEGACY_REAL_GYM_REGRESSION_SET; create sealed blind real-gym/OOD tests. |
| R1-02<br>BLOCKER | 97% / 1% point thresholds lack statistical evidence requirements. | No confidence bounds or independent sample-unit rule. | Tiny samples can falsely pass strong-looking point targets. | One-sided 95% confidence bounds; encounter/instance clusters; threshold lock before sealed test. |
| R1-03<br>CRITICAL | Generic type as hard prefilter can remove the true exact model. | Current generic path includes ambiguous/offline/model errors. | True model never reaches fusion if wrong type deleted it first. | Hard-filter only verified/high-assurance type; otherwise soft fusion/conflict -> NEED_MORE_VIEW. |
| R1-04<br>CRITICAL | Catalog publication boundary is underspecified. | Adapters and source data drift continuously. | Partial updates can expose mixed catalog versions. | Immutable staging/versioned publish + reviewed diff + atomic active pointer + rollback. |
| R1-05<br>CRITICAL | Verifier receives untrusted OCR/source text. | OCR and scraped text can contain prompt-like instructions. | Prompt injection manipulates decision or candidate selection. | Serialize as data, strict schema/candidate IDs, no tool authority, length/control filtering. |
| R1-06<br>MAJOR | Cloud vector path assumes project-specific SDK/region/IAM readiness. | Repo uses Node 20 / firebase-functions 6; vector/Vertex dependencies and regions not yet proven. | Late infrastructure blocker or data-residency surprise. | P0.G5 smoke test, pinned dependencies, region/IAM/cost decision. |
| R1-07<br>MAJOR | No stale async enrichment invariant. | Exact result can arrive after newer scan/navigation. | Old model identity overwrites current user state. | scanId + recognitionSessionId; cancel/ignore stale result. |
| R1-08<br>MAJOR | Rights model lacks durable terms snapshot and redistribution/share-alike state. | External terms and license obligations can change. | Asset used under stale or incompatible permission. | terms hash/version, redistribution/shareAlike, recheck/review basis; fail closed. |
| R1-09<br>MAJOR | Wger production reuse has explicit license risk. | Per-object licenses/AGPL code boundary. | Content reuse creates attribution/share-alike obligations. | Optional staging only until compatibility review; never copy backend code. |
| R1-10<br>MAJOR | Setup facts lack variant/revision applicability. | Same family can differ by generation/region/console/serial revision. | Correct model name yields incorrect safety/setup detail. | Optional EquipmentVariant + SetupSpec applicability + stronger assurance. |
| R1-11<br>MAJOR | Inference image transport limits/logging policy are vague. | Visual cloud path processes user imagery. | Cost/latency/PII leaks via oversized payloads/logs. | Resize/compress/strip metadata; max bytes; ephemeral processing; no raw logs/Firestore. |
| R1-12<br>MAJOR | Contribution flow can self-poison labels. | Recognition output exists at contribution time. | Errors become self-confirming ground truth. | Quarantine; reviewed labels required before training eligibility. |
| R1-13<br>MAJOR | Model-code normalization/collision rules are weak. | Codes contain digits/hyphens and O/0/I/1 ambiguity; codes can repeat. | Normalization creates false exact match. | Preserve code syntax; ambiguity creates candidates only; brand/global uniqueness + corroboration. |
| R1-14<br>MAJOR | Per-model evidence can be pseudo-replicated by many frames of one unit. | Views are correlated. | App appears well tested on one physical machine. | Independent encounters/instances/gyms and cluster-aware metrics. |
| R1-15<br>MAJOR | Source adapters lack explicit network/supply-chain controls. | Scrapers follow mutable URLs/redirects. | SSRF, domain drift or poisoned source enters staging. | Source allowlists, redirect checks, rate limits, terms/robots review; no arbitrary fetcher. |
| R1-16<br>MAJOR | No mandatory user correction path before public exact promotion. | Even high-precision identity will fail sometimes. | Wrong exact model persists into history/setup memory. | Add Not-this-model / guided rescan; feedback is evidence, not label. |
| R1-17<br>MINOR | Exact history needs version provenance. | Catalog/policy changes over time. | Old identity becomes uninterpretable. | Store catalog/policy/evidence versions. |
| R1-18<br>MINOR | Vector backend is named too early. | At ~50 models a simple cached baseline may suffice. | Unnecessary infra cost/complexity. | VectorRetriever abstraction and benchmark before lock-in. |

# 3. Round 2 — Cross-review and remediation

| ID | Decision | Topic | Consensus resolution |
| --- | --- | --- | --- |
| R2-01 | ACCEPT | 30-photo set | Legacy regression only; new sealed blind real-gym/OOD sets under independent custody. |
| R2-02 | ACCEPT | Statistical gate | One-sided 95% bounds on independent encounters/clusters; thresholds lock before sealed test. |
| R2-03 | ACCEPT WITH REFINEMENT | Type evidence | Low-confidence/offline type is soft; verified conflict -> NEED_MORE_VIEW; strong unique model code may outweigh weak generic type. |
| R2-04 | ACCEPT | Catalog publication | Staging/version diff review + atomic active pointer + rollback. |
| R2-05 | ACCEPT | Verifier security | Untrusted text serialized; strict candidate/schema boundary; no tools/additional candidates. |
| R2-06 | ACCEPT | Cloud feasibility | P0.G5 added; Firestore-first remains conditional on real project spike. |
| R2-07 | ACCEPT | Async lifecycle | scanId + recognitionSessionId and stale-result rejection. |
| R2-08 | ACCEPT | Rights | Terms snapshot/version + redistribution/share-alike + recheck fields. |
| R2-09 | ACCEPT | Wger | Optional/nonblocking enrichment; production reuse separately license-gated. |
| R2-10 | ACCEPT | Setup facts | Variant/revision/region/serial applicability + stricter setup assurance. |
| R2-11 | ACCEPT | Image handling | Bounded client preprocessing; ephemeral raw inference; no raw logs/Firestore. |
| R2-12 | ACCEPT | Contribution labels | Quarantine + reviewed labels; no self-labeling. |
| R2-13 | ACCEPT | Model code | Preserve syntax; OCR confusions create candidates only. |
| R2-14 | ACCEPT | Evaluation independence | Encounter/instance clusters, sealed custodian, dual-label adjudication. |
| R2-15 | ACCEPT | Recovery | P5.G5 correction/rescan before public exact identity. |
| R2-16 | ACCEPT | Retriever abstraction | Benchmark Firestore KNN against simple pilot baseline. |

# 4. Round 3 — Devil's Advocate

| Challenge | Argument | Disposition | Consensus |
| --- | --- | --- | --- |
| DA-01 | Why build visual exact recognition at all if OCR + catalog may capture most value? | VALID | P2.G5 OCR-only GO_VISUAL / DEFER_VISUAL checkpoint; no sunk-cost escalation. |
| DA-02 | Firestore KNN may be unnecessary for 50 models. | VALID | Keep Firebase-first but benchmark through VectorRetriever. |
| DA-03 | 97% identity may still be too weak for safety-sensitive setup. | VALID | Separate display vs setup assurance; setup may require stronger confidence/user confirmation + VERIFIED applicability. |
| DA-04 | Neighbor placard can be perfectly OCR-read but belong to another machine. | VALID | Ownership ambiguity -> NEED_MORE_VIEW/PLACARD close-up; never pick first code. |
| DA-05 | The 30-photo set is already known to engineers. | CONFIRMED | Not blind; reclassified. |
| DA-06 | Wger adds legal complexity without helping exact machine identity. | VALID | Optional; cannot block P2/P4. |
| DA-07 | This work can distract from current MVP blockers. | CONFIRMED | Remain POST_MVP_HIGH; do not displace proven MVP blockers. |
| DA-08 | PhysicalMachineInstance memory is feature creep/privacy risk before recognition is proven. | VALID | P5.G4 optional; not P6 prerequisite; shared gym inventory out of scope. |
| DA-09 | Source adapters can auto-publish poisoned changes. | VALID | No direct publish; immutable version + approval + active pointer. |
| DA-10 | Model name does not imply exact console/region/serial variant. | VALID | Optional EquipmentVariant + SetupSpec applicability. |
| DA-11 | Even a 99% system needs a recovery path. | VALID | P5.G5 correction/guided rescan release-prep requirement. |
| DA-12 | A sticker can prompt-inject Gemini. | VALID | OCR is untrusted data; verifier has no instruction/tool authority. |
| DA-13 | Many views of one machine can fake a large sample. | VALID | Cluster by encounter/physical instance. |
| DA-14 | Embedding model upgrades invalidate vectors. | VALID | Versioned embedding/index, re-embedding challenger, old rollback target. |
| DA-15 | OCR-only may be the correct final scope for a long time. | ACCEPTED | DEFER_VISUAL is explicitly a successful evidence-based outcome. |

# 5. Statistical gate correction

The provisional targets Exact precision >=97% and false EXACT_MODEL on OOD <=1% remain product targets, but promotion now requires one-sided 95% confidence bounds on independent encounters/physical-machine clusters. Point estimates alone cannot close the gate.

| Metric | Consensus gate | Zero-error planning example | Notes |
| --- | --- | --- | --- |
| Exact-model precision when claiming exact | Lower 95% one-sided bound >=97% | ~100 independent exact claims with 0 false exact | Failures require larger n; correlated frames do not increase independent n. |
| False EXACT_MODEL on unsupported/OOD | Upper 95% one-sided bound <=1% | ~299 independent OOD encounters with 0 false exact | Any clustered/safety-relevant pattern can block regardless aggregate. |
| Calibration | Separate calibration set; lock method/thresholds before sealed test | N/A | Report reliability/ECE/Brier or equivalent and stability by gym/device where possible. |

# 6. External feasibility checks

- Firestore vector search: official docs support Node.js KNN/vector indexes and max dimension 2048. Vertex multimodal default 1408 fits this limit.

- Vertex multimodal embeddings: image/text embeddings share the same space; documented dimensions 128/256/512/1408.

- ML Kit text recognition: line/element geometry and confidence are available; implementation must tolerate confidence being unavailable/zero on some unbundled/older runtime combinations.

- Callable Cloud Functions: Auth/App Check tokens are supported and enforceAppCheck=true is documented. Current firebase-functions 6.0 is above the documented minimum.

- Project-specific region, IAM, SDK/vector-client dependency and index behavior remain unproven until P0.G5.

# 7. Final consensus

```text
CONSENSUS VERDICT

APPROVE FOR PHASED IMPLEMENTATION.

0 design-level BLOCKER and 0 design-level CRITICAL remain after R2/R3 remediation.

PRODUCTION EXACT-MODEL CLAIM REMAINS BLOCKED until P6: sealed blind real-gym + OOD evaluation, statistical confidence bounds, calibration/open-set policy, user correction path, security/App Check/rate limits, rights-complete active catalog version and model-by-model promotion.

The plan explicitly permits DEFER_VISUAL after P2.G5 if OCR/catalog already delivers enough value. That is a successful evidence-based scope decision, not an implementation failure.
```

# 8. Binding consensus changes

- 30 photos = legacy regression, never final blind test.

- New sealed real-gym and OOD tests with independent custody.

- Confidence-bound release metrics; independent encounter/instance units.

- Staged immutable catalog versions + atomic active pointer.

- Type evidence authority; no unsafe hard prefilter.

- P0.G5 cloud feasibility/IAM/region/SDK gate.

- P2.G5 OCR-only value GO_VISUAL / DEFER_VISUAL gate.

- VectorRetriever abstraction; Firestore-first after benchmark.

- Untrusted OCR/source text security boundary for verifier.

- scanId + recognitionSessionId stale-response protection.

- Wger optional/nonblocking; production reuse license-gated.

- SetupSpec applicability + optional variant layer + stronger setup assurance.

- User correction/guided rescan before public exact promotion.

- Contribution quarantine/review; no self-labeling.

- PhysicalMachineInstance optional and not required for recognition promotion.

# 9. Remaining intentionally blocked / external items

- Production exact-model quality claim: blocked until P6.

- Wger/media/content production reuse: blocked per object until rights compatibility is reviewed.

- Safety-sensitive model-specific setup: blocked unless identity assurance + VERIFIED applicable SetupSpec pass.

- Shared gym inventory/cross-user PhysicalMachineInstance: out of scope until separate privacy/governance authorization.

- Mass training contribution: blocked until P7 privacy/redaction/retention/review pipeline exists.

- Vector-store migration away from Firebase: blocked until measured scale/cost/latency trigger.

# 10. Recommended execution after consensus

1. Finish current SPTR MVP blockers first; keep this workstream POST_MVP_HIGH.

2. P0.G1-G5: baseline/provenance/rights/versioning + cloud feasibility.

3. P1: canonical exact-model KB and official P0 brand adapters. Wger may run in parallel but cannot block.

4. P2: structured OCR, model-code identity, additive mobile contracts, shadow text identity.

5. P2.G5: measure OCR-only value. Decide GO_VISUAL or DEFER_VISUAL.

6. If GO_VISUAL: P3 new dev/calibration/sealed test sets and rights-approved corpus.

7. P4: embedding/retriever benchmark, fusion, calibration/open-set, candidate-bounded verifier.

8. P5: guided multi-view, exact page/setup, exact history, correction path; machine-instance memory optional.

9. P6: shadow -> artifact/threshold freeze -> sealed independent evaluation -> model-by-model promotion.

10. P7/P8 only after promoted quality and product demand justify contribution/scaling.

# 11. Evidence base

- User-provided Equipment Recognition v3 design (2026-08-21).

- SPTR Equipment Recognition Source Strategy (manufacturer/BIM/3D/Wger/licensing research).

- SPTR Equipment Recognition Master Technical Plan v4.0 RC1.

- Fitness-App/master: machine_text_anchor.dart, scan_outcome.dart, equipment_models.dart, MODEL_REGISTRY.json, TECHSTACK.md, functions/package.json, firebase.json.

- Firebase official: Firestore vector search, callable Functions/App Check.

- Google Cloud official: Vertex multimodal embeddings.

- Google ML Kit official: Text Recognition line/element geometry/confidence APIs.
