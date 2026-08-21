# Equipment Recognition v4.1 — Independent Verdict (Claude + GPT-PM cross-review)

| Field | Value |
| --- | --- |
| Design reviewed | `core/design/sptr_equipment_recognition_v4_1/SPTR_EQUIPMENT_RECOGNITION_MASTER_TECHNICAL_PLAN_v4.1_CONSENSUS_2026-08-21.md` + companion `..._INDEPENDENT_REVIEW_R1-R3_CONSENSUS_2026-08-21.md` |
| Prior status (author's own R1-R3 consensus) | APPROVE FOR PHASED IMPLEMENTATION |
| **This verdict** | **SUPERSEDED — BLOCKER REMEDIATION REQUIRED** |
| Method | Two independent review passes, cross-reconciled: (1) GPT-PM via PM Bridge (Playwright transport, live round-trip against the same ChatGPT conversation that produced v4.1), (2) four cold Claude subagents (Architecture/Flutter, ML/Data Science, QA/Adversarial, silent-failure hunter) reading only the source documents and the real `Fitness_App` repository, blind to GPT's output |
| Repo baseline verified | `master` @ `532235d35d320b340929a736cae40c5e1661f5d5` (design's own claimed baseline `3dd2e3e...` confirmed as a real 8-commits-back ancestor; the four files the design cites as "current repository truth" are byte-identical between the two) |
| Foundation work (P0, read-only P1) | May proceed |
| User-facing / production exact identity, exact history, model-specific setup | **BLOCKED** pending remediation below |

## Why this supersedes the R1-R3 APPROVE

The v4.1 document's own R1-R3 rounds were produced by one continuous reviewer (GPT) role-playing different personas in the same chat, self-consolidating to APPROVE. This verdict is the first pass that (a) checked the design's claims against the actual `Fitness_App` working tree rather than the document's own prose, and (b) ran two genuinely independent review methods and reconciled their output rather than treating one pass as final.

Two of the four confirmed BLOCKERs are **repo-grounded facts that contradict the design's own binding invariants**, not design-level gaps:

- The design requires `enforceAppCheck=true` as a security exit condition (§8.5, §11, P2.G3). App Check enforcement is globally **disabled** in this repo today (`functions/src/scaling.ts:113-124`), gated on an unrelated infrastructure migration (the operator's own Firebase App Distribution test builds cannot currently attest).
- `firestore.rules:24-35`'s `users/{uid}/{coll}/{document=**}` wildcard grants full client write to any subcollection not explicitly excluded. The design's `recognised_models` (exact-model history, P5.G3) is **not** in the exclusion list — a modified client can forge `identityLevel: EXACT_MODEL` history with arbitrary `catalogVersion`/`modelId`, which breaks every "server authority" claim the design makes about exact identity.

## Confirmed BLOCKERs (4)

| ID | Claim | Source | Required change |
| --- | --- | --- | --- |
| B-01 | App Check enforcement is globally off, blocked on an unrelated platform migration; P2.G3/P6 security exit can't honestly close | Claude Architecture (repo-grounded) — accepted by GPT without rebuttal | New prerequisite gate (e.g. `P0.G0`/`PLATFORM-AC-01`) with states `BLOCKED_EXTERNAL_PLATFORM_MIGRATION` / `READY_FOR_SHADOW` / `READY_FOR_PRODUCTION`; explicit shadow-vs-production identity split; no production promotion while `APP_CHECK_ENFORCED != true` |
| B-02 | `recognised_models` is client-forgeable through the `users/{uid}/**` wildcard write rule | Claude Architecture (repo-grounded) — accepted by GPT, called "worse than a missing rules entry" | `firestore.rules` + `firestore.indexes.json` become mandatory P1/P5 deliverables; deny-by-default/server-authoritative rules for exact history; emulator mutation tests (client CREATE/UPDATE authority fields → DENY, server/admin write → ALLOW, other-account access → DENY) |
| B-03 | P6.G1 shadow deployment is misclassified `OPTIONAL / NOT A P6 PREREQUISITE` (a literal copy-paste of P5.G4's classification string) | GPT B-01, independently reproduced by Claude Architecture via a different method (copy-paste detection) | Reclassify P6.G1 as `RELEASE-BLOCKING PREREQUISITE`; define minimum shadow volume/time, terminal-outcome completeness, App Check/rate-limit error SLO before promotion |
| B-04 | Sealed-test reuse for model-by-model promotion (P6.G3) creates a post-selection / multiple-comparisons problem the single global confidence bound doesn't address | GPT B-02, independently reproduced by Claude ML/Data Science | Pre-register per-model promotion criteria and a fixed candidate set before the sealed run, with a multiplicity correction (e.g. Bonferroni across K candidate models) or an explicit hierarchical/partial-pooling statistical model — never select which models "pass" after inspecting sealed results |

## Cross-confirmed CRITICAL / MAJOR findings (independently found by both GPT and Claude, different methods)

| Topic | GPT finding | Claude finding |
| --- | --- | --- |
| DEFER_VISUAL has no production path | C-01 | ML/Data Science: "DEFER_VISUAL structurally forecloses any path to production OCR-only exact-model claims" |
| Catalog/policy versioning recorded, not enforced | C-02 | Architecture: `recognitionSessionId` doesn't pin `(catalogVersion, policyVersion)`; a session can span a version switch |
| Infra/security failure collapses into ordinary TYPE_ONLY | C-03 | silent-failure hunter: `decision` enum has no terminal state for infra/security failure |
| Demotion/correction doesn't revoke actionable historical state | C-04 | silent-failure hunter Finding 4: same scenario, independently described |
| False-exact-on-OOD unmeasurable online | M-04 | ML/Data Science Finding 7: same conclusion |
| Raw OCR text not covered by the "no raw image in logs" rule | M-05 | silent-failure hunter Finding 5: same gap, same wording almost verbatim |
| Stale-scan client discard doesn't stop server-side cost/work | M-02 | silent-failure hunter Finding 2: same scenario |
| First non-Stripe Cloud Function claim | M-03 (GPT's original framing) | Architecture **corrected** this: Functions already serves 12 functions across multiple domains (only `functions/package.json`'s stale `description` field says Stripe-only). GPT retracted its own framing and refined it to: new ML/Vertex workload added to an existing **mixed** Functions codebase without defined deployment isolation — still MAJOR, different reason |

## Claude-only findings GPT accepted on reconciliation (repo-grounded, no live GPT access to this code)

All ACCEPTed by GPT in the final round, no rebuttal:

- **Region pinning** (`europe-west1`/`eur3`) is tied to the existing Stripe webhook URL's stability (`scaling.ts:65-68`); P0.G5 must not treat region as an open architecture choice — a region move risks a payments-outage window.
- **Duplicate rate limiter**: `rate_limit.ts` (§12.3) duplicates the already-shipped, transactional `abuse_guard.ts` quota system. Extend the existing one; a second limiter needs a stated gap analysis first.
- **Non-`autoDispose` provider, no `scanId` lifecycle primitive**: `visualEquipmentControllerProvider` is a global `NotifierProvider`, not `autoDispose`/`family`; §7.1's async-staleness invariant is currently prose with no Riverpod mechanism behind it. Needs a `family` keyed by `scanId`/`recognitionSessionId` + `autoDispose` + a current-session guard.
- **Client-readable `equipment_models` vs. server authority** — accepted with refinement: reading display metadata is fine; the violation is a client deciding "this model is VERIFIED, therefore exact/setup is authorized" from cached fields instead of a live server policy check. Contract must separate display metadata from authoritative eligibility.
- **Unnamed statistical method**: the confidence-bound math (`~100`/`~299` at zero errors) matches an exact one-sided Clopper-Pearson bound, but the document never names it — an implementer defaulting to a Wald/normal approximation gets a degenerate interval at zero observed errors. Name Clopper-Pearson explicitly.
- **Round-cap exhaustion has no defined outcome**: an unresolved BLOCKER/CRITICAL at round 5 must force `GATE REMAINS OPEN / NO PROMOTION / ESCALATE TO OPERATOR`, never an implicit pass by exhaustion.
- **Existing ML governance/CI machinery not reused**: `scripts/ml/lifecycle.py` + `test_ml_contracts.py`, wired into `.github/workflows/flutter.yml`, already mechanically enforce `MODEL_REGISTRY.json` claims against the real asset tree. The design's new promotion machinery (`scripts/ml/equipment_identity/*`) should route through this existing contract instead of building a parallel, CI-unenforced one.
- 15 new Cloud Functions files land in the single existing Functions codebase with no scaling/deploy isolation from `stripeWebhook` — GPT accepted as MAJOR but did not accept "separate codebase" as the only valid fix; calls for an evidence-driven choice (separate codebase/runtime vs. proven selective-deploy + lazy-init + resource isolation).
- `MODEL_REGISTRY.json`'s existing schema doesn't cleanly fit `equipment_identity_embedding`/`gemini_equipment_verifier` as new `models[]` entries — the registry already has a `vendor_models` category (used today for the existing `gemini` entry) that fits hosted-vendor-model concepts better.
- Retrieval-specific leakage vector: an asset used to build the `equipment_model_exemplars` retrieval index could also appear in `CALIBRATION_SET`, producing a near-perfect self-match; the pHash-only split rule doesn't catch this.
- Named reviewer roles in §10 (R2 "Provenance/legal", R5 "Release reviewer") have no matching agent definition under `Fitness_App/.claude/agents/` — while R1/R3/R4's roles (`fitness-data-scientist`, `exercise-ontology-curator`, `clinical-safety-gate`, `fitness-flutter-reviewer`) genuinely do exist. Separately, R5's "GPT review mechanism" is currently a global no-op (`ENABLED_REPO_ROOTS = []` in `gpt_review_gate.py`).
- Optional verifier (P4.G4, `POST_MVP`) can silently drop out of the `EXACT_MODEL` decision path with no distinct signal that a claim was produced without Gemini adjudication.

## New invariant GPT proposed as the single unifying conclusion of the silent-failure half of both reviews

```
NO SILENT DEGRADATION
Every exact-identity attempt MUST produce exactly one machine-observable terminal outcome.

SAFE ABSTENTION is not SERVICE FAILURE.
SERVICE FAILURE is not UNSUPPORTED MODEL.
UNSUPPORTED MODEL is not UNKNOWN EQUIPMENT.
CLIENT CANCEL is not BACKEND TIMEOUT.
POLICY REVOCATION is not HISTORICAL EXACT IDENTITY.
```

## What survived both reviews unchanged (do not re-litigate)

- The additive `equipmentId`-first architecture: exact model never replaces the functional ontology or bypasses existing safety/exercise filtering (D2, §7.2, §13, P5.G2 exit) — repeated across independent artifacts, holds up.
- `machine_text_anchor.dart`'s noise-word denoising stays untouched; a separate `IdentityTextParser` is the right structural call.
- Reusing `core/ml/MODEL_REGISTRY.json` instead of a second ML lifecycle is the right call (though its `vendor_models` category, not `models[]`, is the correct fit for the new hosted-model entries — see above).
- Rights model (§4.4) is genuinely fail-closed and multi-dimensional.
- The 30-photo legacy-regression reclassification and the OCR-first "resolve via text before uploading an image" design are sound.
- P0.G5's refusal to trust emulator parity for vector search is correct for this repo, which does run real emulator-backed rules/e2e suites.

## Recommended next step

Per GPT-PM's own conclusion (agreed by Claude): not another full review round on v4.1, but mechanically assemble a **v4.2 Remediated Review Candidate** from this consolidated finding set, closing at minimum the items listed under "What v4.2 must close" in the full HTML report, then run one final verification pass confirming the agreed fixes actually landed in the document — not a fresh open-ended review.

## PM Bridge live-test note

This review doubled as the first live end-to-end test of PM Bridge's Playwright transport after the Gate 6 concurrency fix. Result: `gpt_send` succeeded (after one retry — a title-based sidebar-hydration race, since fixed by switching `Fitness_App`'s `config/conversations.md` entry to ID-based routing, mirroring pm-bridge's own earlier fix). `gpt_await_reply` failed to detect the landed reply on two separate exchanges (a real, still-open turn-count-detection bug, not a missing reply — both times the reply was actually present and complete on the page, confirmed by direct read-only diagnostic). The reply content itself was retrieved and logged via `gpt_ingest_reply` as a fallback both times. This is a genuine unresolved defect in `gpt_await_reply`'s playwright-transport reply-detection logic, not a design-review finding — tracked separately, not fixed as part of this task.
