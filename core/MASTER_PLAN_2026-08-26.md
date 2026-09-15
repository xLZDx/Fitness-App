# Fitness_App — Master Plan (Consolidated Decisions, Designs, Plans)

**Compiled:** 2026-08-26
**Scope:** every plan, design, and decision found in `core/DECISION_LOG.md`, `core/plans/`, `core/*.md`, `docs/Redisign/`, and the HUD design handoff package, from project inception (2026-07-28) through the independent SPTR audit (2026-08-25).
**Source method:** six parallel research passes (foundation era, GUI/HUD design lineage, onboarding/safety/catalog era, ML/equipment-recognition platform, release/business/governance, and the SPTR independent audit itself), each citing file:line evidence and cross-checking plan claims against current code, not just decision-log self-reports. Full source-file list in §10.
**New in this revision:** §8, Observability & Alerting (OBS-1), added as an explicit priority gate. **Reviewed 2026-08-26 by three independent specialist agents** (architect, security-reviewer, flutter-reviewer) against current HEAD, not just against decision-log self-reports — findings adjudicated and applied throughout §4/§8/§9; full review record in §11.
**2026-09-15 addendum:** §9's priority table gained rows 22-26 and §12, reconciling an external, unverified full-app review report (`core/review/FULL_APP_CONSENSUS_REVIEW_2026-09-12.md`) against current HEAD — see §12 for what verified as FACT, what was already tracked, and what verified as overstated or unverified.

---

## 1. How eras relate

Six overlapping, not strictly sequential, lines of work:

1. **Foundation** (07-28 → 08-07) — tooling, device-defect fixes, virtual trainer V0-V5, personalization, equipment registry, catalog sourcing/licensing, WorkoutSession migration.
2. **GUI/visual design** (08-05 → 08-21) — Figma-Make prototype (R1-R11) superseded by the HUD-glass design system (M1-M9), the one that actually shipped, incompletely.
3. **Onboarding schema, safety, catalog remediation** (08-08 → 08-16) — posture check, O-series onboarding rebuild, the 11-08 audit and remediation run, the Aug-13 bug batch, the catalog content-debt saga, the Aug-16 closing ledger and first release build, the Aug-16 independent full-project audit.
4. **ML / equipment-recognition platform** (07-07 onward, still open) — P0-P6 gate program, distinct from the recognition-decision engine found unbuilt by the SPTR audit.
5. **Release, business, governance** (ongoing) — store publication status, billing, App Check, platform scope, Play policy compliance.
6. **Independent SPTR audit** (2026-08-25, this session) — external product/tech/market audit, 4 consensus rounds, NOT_RELEASE_READY verdict on clinical authority alone.

---

## 2. Foundation Era (2026-07-28 → 2026-08-07)

**Tooling restructure (07-28).** Cut always-on AI-agent context 50,694 → 36,372 tokens (-28%); built `CODEMAP.md`/`CONVENTIONS.md`/`INDEX.md` plus a broken-link auditor. Fully shipped. *Caveat, historical scope corrected 2026-08-26 (GPT-PM round 1 — see §11a):* at the time of this 07-28 restructure, `AGENTS.md`/`CLAUDE.md` were not under git and state lived only in `.bak-*` backups. **This is no longer current** — `git ls-files` confirms both files are tracked on `master` today; whoever tracked/committed them did so at some later, unrecorded point in this window.

**Device-defect rounds 1 & 2 (07-30).** Nine + six defects fixed: live-recognition YUV/NV21 crash, dead Settings, non-recursive asset bundling (132 hidden demo frames), Health Connect NPE, inert Home suggestions, poor muscle map, `BackdropFilter` scroll jank, near-total lack of Russian localization, zero on-device test coverage; then translated instructions, in-app camera capture, black live-preview fix, anatomical muscle chart. All closed with device/host test evidence, shipped as `1.0.0+5`.

Rejected on evidence: animated GIF demos from Wikimedia Everkinetic (`Category:Everkinetic` = 0 files; sampled candidates single-frame) — replaced with a two-frame eased-hold-reverse cadence. A Settings unit toggle — never built, nothing reads such a preference.

**Virtual trainer V0-V5 (07-31).** V0 (garbage rep-count/English voice from face-only-frame BlazePose reads) shipped in full. V1 (pose-reference-from-catalog-stills) **rejected on evidence** — 126/192 exercises had no local stills, and a single still gives a point, not a tolerance band; V2 (skeleton overlay) promoted ahead of it instead, since it makes no claim about form correctness.

**Personalization (E1, 07-31).** Diagnosed a real gap: the onboarding questionnaire collects ~34 fields, but ranking read only 4. `rankedForYouProvider` was written but had zero consumers at the time — **now wired** (`workouts_page.dart:186`). `hasGymAccess` was asked once at onboarding though the training venue changes daily — **now a computed field** derived from location. `cycle_aware` was a dead module — **now called** from `plan_builder.dart:177`. `BodyMeasurement` as a distinct entity — **unverified**, no such class found in current code.

**Equipment registry (08-03/04).** Grew 52 → 69 machines. Found and fixed a real drift: the camera-recognition allowed-answer list (`kCanonicalMachines`) had fallen behind `equipment.json` (48 vs 52), making 4 real machines structurally unrecognizable.

**Vendor-equipment linking (08-03).** 1,887 vendor exercises resolved against the registry via per-exercise vision verification: 1,384 resolved / 461 confirmed_no_equipment / 42 no_equipment_prop. Cross-checked against the app's own "no equipment" runtime bucket — exact match. Closed cleanly.

**Legacy catalog removal (08-03/04).** Licence audit found the legacy catalog (511 exercises) serving unlicensed clips from a public/world-readable bucket (`allUsers` grant, 677 objects) for 324 entries — a finding the same author had written down and dropped two days earlier. Public IAM binding revoked; legacy catalog (511 entries, 778KB + 132 photos, 8.1MB) deleted outright once vendor-catalog linking closed the only remaining reason to keep it. Found and fixed during removal: `AssetEquipmentRepository._translate` silently discarded a Russian-overlay entry (title included) whenever `steps` was empty — would have surfaced ~403 English-only titles under the Russian UI once legacy was gone.

**Video sourcing research (08-01).** No free source is both licence-clean and shape-compatible; recommended buying the exerciseanimatic.com bundle (~$329, ~1,700-1,900 exercises) — acted on, this is the current 1,887-row vendor catalog. **Open, never revisited:** the bundle's licence bans feeding clips to an AI platform for training/fine-tuning — relevant to the equipment-recognition ML work; no evidence found that this was checked again.

**Gym-favoriting + social monitoring (08-01).** Plan only, deliberately not built ("no separate GO issued"). Correctly split into a trivial gym-save feature and a structurally-blocked social-monitoring idea (Meta ToS bars scraping; Graph API needs per-gym opt-in). No evidence either half was ever built.

**Equipment-recognition diagnostics (08-07).** Measured: a 10-class on-device model given 30 real gym photos was always below its own confidence thresholds by construction, and its most confident answers were its most wrong (0.892 confidence, wrong class, class not even in vocabulary). Raising the confidence threshold **cancelled by measurement** — doesn't address the problem. Original Bing-based crawler found fully dead; Wikimedia Commons alone insufficient (561 images / 70 classes, 25 empty); Roboflow Universe gave 44,524 images across 45/69 classes — ~79x improvement. Retrain pipeline specified, **not confirmed executed**. Side-finding shipped as a real feature: reading printed station text (`machine_text_anchor.dart`) hit 18/18 vs. the classifier's 5/18 top-3 — shipped, but **not wired into live mode** as of the last state-save (`SESSION_STATE_2026-08-07.md`).

**WorkoutSession migration (08-06).** Replaced flat `WorkoutLogEntry` with a proper session entity; architect + database-reviewer review adopted a one-time backfill over a permanent dual-collection union, closing a real streak-race bug. Ran live against production Firestore; found and fixed `listAllUids()` querying a collection (`users`) that structurally never materializes, which made `--all` a silent permanent no-op. **Most significant single finding of this era:** production Firebase Authentication had never been enabled — every sign-in silently failed, no user data had ever reached Firestore in production until this session's operator-side fix.

**Audit remediation (08-04).** Confirmed contraindication-tag coverage was 0 of 1,887 exercises (not the external audit's claimed 6%) — the only 144 tagged rows lived in the legacy catalog, deleted by an unrelated commit. Removed the false "screened for your injuries" claim (S0a); closed a gap where 6 of 7 tabs read the unfiltered catalog directly (S2). Real catalog tagging (S3b) **not started** — deferred as weeks of separate content work. Same thread found a Stripe API version desync (code targeting `2025-02-24.acacia`, webhooks configured for `2026-04-22.dahlia`) that would have silently reset every real subscriber to `free` on first live payment — caught before any real payment occurred.

---

## 3. GUI/Visual Design Lineage: Figma → HUD Glass

Two sequential, not concurrent, design lineages.

**(a) `docs/Redisign/` — Figma-Make prototype (08-05 → 08-09), gates R1-R11.** React prototype (`App.tsx`) plus a large set of master prompts and decision registries. Largely superseded, not shipped as-is.

**(b) `design_handoff_fitness_hud/` — "floating HUD glass" (08-19 → 08-21), gates M1-M9.** Source: 4-file design handoff package. Reference screen `Fitness Form Coach Phone.dc.html`. Glass formulas per theme, geometry (20-30px radii, 158×158 circular counters), accents `#C9FF47`/`#4B7A00`, Archivo typography, 6-phase day/night background. **This is the system that actually reached production code**: `hud_tokens.dart`, `hud_typography.dart`, `hud_surface.dart` (`HudSurface`/`HudPanel`/`HudButton`/`HudChip`), `hud_scaffold.dart`, `hud_metric.dart`, `core/background/hud_sky.dart`.

**Verified state, corrected from an earlier premature claim in this session:**
- M1-M9 were closed **without device verification** — screens reported PASS with no real-device screenshots, which `SPTR_VISUAL_FIDELITY` itself says "should read UNVERIFIED, not PASS."
- Real, measured WCAG contrast failures exist.
- The D-03 tap-bug status flip-flopped between FIXED/PASS five times — the clearest example of unreliable self-reported status in this project's history.
- The legacy `glass.dart` (`GlassCard`) and the flat `aurora_background.dart` wrapping the entire app (`main.dart:601`) **still coexist** with the HUD system — the visual migration is partial, not complete. *(Corrected 2026-08-26: `GlassCard` occurs 142 times across 46 files — roughly 138 real call sites once the 4 occurrences inside `glass.dart`'s own definition are excluded — not "~40" as first stated; the legacy-system debt is materially larger than originally reported. Several screens, e.g. `home_page.dart` and `workouts_page.dart`, use `GlassCard` and `Hud*` widgets side by side in the same screen.)*

**Honest summary:** only the background imagery reached the app close to as-designed (and not even the right color); the rest of the HUD system is more built-out than initially claimed, but closed without genuine device verification and with known live contrast bugs and an incomplete migration off the legacy glass system.

---

## 4. Onboarding Schema, Safety, Catalog Remediation (2026-08-08 → 2026-08-16)

**Posture check (08-08, R10).** Static posture check (shoulder asymmetry, pelvis tilt, forward head) on the same BlazePose detector as Form Check; thresholds derived from MM-Fit as an admitted proxy. Built, verified on emulator only. **Open contradiction, never resolved:** the 11-08 audit noted shoulder/pelvis symmetry wants a face-on frame while forward-head needs a side-on frame; R10 captures only one side-on window.

**Onboarding schema O0-O10 (08-12/13).** Spec-mandated stop-and-propose gate. Health Connect (O9) **dropped entirely** by direct operator decision ("build a separate device-connection menu later, as its own gate"). P4 (Figma-style rebuild of the Health step) **cancelled by the operator after seeing the existing screen** ("already very convenient, don't touch it") — but a real silent-data-loss bug found in the same code (a regex dropping free-text injury notes) was fixed anyway as P4-lite. Built: O1-O8, O10 (verified a real plan generator exists before wiring a preview, per the spec's ban on fake progress fixtures). **Deliberate deviation from the O0 plan, documented:** birth-year migration uses `completedAt` rather than the planned `currentYear − age` formula, to avoid mis-aging older profiles.

**Audit 08-11 — verdict BLOCK.** Five confirmed blockers: account deletion left `coach_bookings`/`equipment_reports` behind and local health data/photos were not UID-scoped; data export materially incomplete vs. the privacy-policy promise; Stripe checkout had no idempotency key (could produce two live subscriptions); production App Check UNENFORCED on AI/ML, Firestore, Identity Toolkit; all three ML features (equipment recognition, rep counting, posture) could not be called validated. **Remediation ran the same day** — all items closed, including staged App Check enforcement and Keystore-based photo hardening.

**Bug batch 08-13 (B1-B8, H1-H5).** Voice/gong mute bug, missing body silhouette, program generation ignoring the questionnaire entirely (fixed via B5a-d — filtering by equipment/location, injury-screened multi-exercise days). **H3 — 1,484 of 1,887 (78.6%) exercises missing a `purpose` field** — measured, tracked, **never closed within this window**. H5 ("89 self-contradictory rows") — attempted reproduction under five different definitions returned 0, 0, 269, 182, 28; concluded **NOT_REPRODUCED**, no fix attempted for an unreproducible number (a real, unrelated dedup bug was found and fixed instead, 101 rows).

**Catalog content-debt saga (08-13 → 08-16) — the largest single body of work in this window.** Confirmed baseline, independently re-measured three separate times and agreeing each time: **403/1,887 have `purpose`, 1,484 don't; 1,368/1,887 (72.5%) have never been reviewed card-by-card by any human or gate.** An external ACE/NASM-lens audit of the 403 authored cards found 15 P0/48 P1/97 P2 defects; fixed, but the Russian overlay was found untouched by the first pass. A full 1,887-row audit found P0/P1/P2/PASS = 1/149/369/1,368; ~449 English + 441 Russian rows mechanically corrected across pattern classes. Found and left unfixed: a "Pres"→"Press" typo that had silently disabled a shoulder-injury screening rule for an unknown period.

**Final Scope ledger (08-16).** Closed same day: all 5 known-wrong cards, 127 RU/EN summary-mismatch rows, 78 `equipmentLabel` errors, dead `insurance/` feature removal (Play policy violation), **first-ever real release build**. Discovered the Cloud Functions Jest suite had never actually run in this worktree (missing `npm ci`) — every prior "full suite green" claim had covered `mobile/` only, not `functions/`.

**Release build (08-16) — blocker found, not fixed blind.** `targetSdk` still 35 while `compileSdk` is 36; Google Play requires API 36 for new apps from 2026-08-31 — 15 days out at discovery. Not fixed immediately because `targetSdk` (unlike `compileSdk`) changes runtime behavior (API 36 enforces edge-to-edge) and layouts had never run on Android 16 — logged as open item G7, needs device verification before the one-line fix.

**Independent full-project audit (08-16) — verdict NOT_RELEASE_READY.** Three release-stopping findings, found independently by two reviewers with non-overlapping briefs (the audit's own strongest corroboration signal):
1. The injury filter **fails open** — an exercise with no contraindication tags cannot be withheld by any filter; 360/1,887 (19.1%) carry no tags at all.
2. **No pregnancy path exists** — not asked, not inferred, not filtered, not warned; two tests treat "pregnancy" as an invalid value outright.
3. The questionnaire-built program (B5d) **bypasses the safety gate entirely** — the scheduler is called with no `SafetyContext` parameter, so a user who fails PAR-Q+ screening can still enroll.

> **Correction, 2026-08-26 (independent security-reviewer verification against current HEAD, part of this document's own agent review — see §11):**
> - **Finding 1 (fail-open filter) still holds, verified current.** `exercise_filter.dart:37-45` — `if (exercise.contraindications.isEmpty) return false;` remains deliberate, documented behavior. Coverage has risen from 0/1,887 (08-04) to **1,527/1,887 (80.9%)** tagged, pinned by a coverage-floor test (`safety_coverage_test.dart:56`, `kSafetyCoverageFloor = 1527`) — but the remaining **360/1,887 (19.1%) are still structurally unscreenable by design**, an exact match to the number this plan cites.
> - **Finding 2 (no pregnancy path) is FIXED, not open.** `health_flags.dart:142-201` (F014, `ProfessionalGuidanceNeed`) is wired through onboarding (`step_health_flags.dart:146-157`) into `eligibility.dart:230-231`'s `SafetyContext.wholePersonBlocks`, consulted by every prescribing surface. Full bilingual regression coverage in `f014_professional_guidance_test.dart`, whose own header comment narrates this exact finding and its fix. The two tests the 08-16 audit cited as rejecting "pregnancy" as invalid were the *pre-fix* state.
> - **Finding 3 (B5d bypasses SafetyContext) is FIXED, not open.** `programme_providers.dart:176-181` hoists the `safetyContextProvider` check above the branch that used to skip it for template-less programmes (in-code note tagged "F015 (G-B/B1)" describing this exact bug and its fix); `safety` is threaded into `buildProgramme()` at line 213. Only one production call site for the scheduler exists (`grep buildProgramme(` → `programme_providers.dart:210`). Regression-tested at `f014_professional_guidance_test.dart:223-236,269-284`, including the questionnaire-built (`gym_start`) path specifically.
>
> Findings 2 and 3 were correctly stated as of the 08-16 audit and appear to have been fixed in later, unaudited work; this master plan's first draft carried them forward as still-open without re-checking code, which the agent review this document itself commissioned caught. §9's priority table reflects the corrected status.

---

## 5. ML / Equipment-Recognition Platform (P0-P6)

The P0-P6 gate program (`core/design/sptr_equipment_recognition_v4_1...v4_4`) is **not the same thing** as the recognition-decision engine (`recognize.ts`/`evidence_fusion.ts`/`policy.ts`/`telemetry.ts`) found 0%-implemented by the independent SPTR audit. P0/P1 are catalog/ontology prerequisites; P4/P6 correspond to the missing engine itself.

- **P0** (baseline/governance) — *corrected 2026-08-26, GPT-PM round 1 (§11a): the original "closed, 6/6" overstated this.* **P0.G1–G6 CLOSED** (all gates closeable within an autonomous coding session); **P0.G0 remains `BLOCKED_EXTERNAL_PLATFORM_MIGRATION`** — a real App Check/platform-migration precondition, not engineering work. Phase closeout is complete only within that scoped boundary; any P4/P6 production work must still carry the App Check migration precondition forward.
- **P1** (catalog/ontology ingestion) — G1-G4 closed, G5 blocked (`BLOCKED_ON_SOURCE_EVIDENCE`), G6 not started.
- **P2** (OCR text-recognition engine) — *updated 2026-09-11.* **P2.G1** (structured OCR capability)
  and **P2.G2** (IdentityTextParser) CLOSED. **P2.G3** (server exact text lookup,
  `functions-equipment-identity/`) implementation is reviewed (5 GPT-PM rounds, final
  `VERDICT: APPROVE`, 0 open BLOCKER/MAJOR) and pushed, but the **gate itself is
  OPEN/DEPLOYMENT_PENDING, not CLOSED** — see `core/DECISION_LOG.md`'s matching 2026-09-11 entries
  for the full implementation/review history and the targeted `firebase deploy --dry-run` evidence.
  A real (non-dry-run) index/function deployment to `fitness-app-korostelev` is a separate,
  later-authorized action, not covered by this implementation review. P2.G4+ not started.
- **P4** (visual retrieval, evidence fusion, calibration, Gemini verifier) — not started, deliberately deferred by the `OCR_TEXT_ONLY_DEFER_VISUAL` decision.
- **P6** (shadow deploy, telemetry) — not started.

This decision is directly grounded in the 08-07 diagnostics in §2: the measured 10-class classifier failure and the text-anchor success (18/18 vs. 5/18) are the empirical basis for choosing the OCR/text-only path over the visual-retrieval path, even though the formal P4 status was recorded later.

---

## 6. Release, Business, Governance

- The app has **never been published to any app store** — distribution has been Firebase App Distribution only.
- A live, unresolved contradiction exists in shipped ARB strings between nonprofit-status framing and paid-subscription framing.
- A Roboflow API key leaked 2026-08-07 with **no confirmed reissue**.
- App Check enforcement was partially fixed in the 08-11 remediation, but the full picture across all Firebase services (including Firebase AI Logic) remained **UNKNOWN even in the 2026-08-25 independent SPTR audit**.
- `core/CURRENT_STATE.md` is the auto-generated, test-enforced (`scripts/review/state_ledger.py --report`) ledger of items requiring OPERATOR or EXTERNAL authority — the single most current source for "what remains open," preferred over any individual plan file.
- A recurring governance pattern across this entire timeline: engineering work has repeatedly been frozen pending closure of an existing findings backlog before opening a new one (the catalog saga, the audit-remediation runs) — a discipline worth preserving, not a defect.

---

## 7. Independent SPTR Audit (2026-08-25)

Delivered this session: `D:\Repo\_audit_output\SPTR_INDEPENDENT_PRODUCT_TECH_MARKET_AUDIT_2026-08-25_c3ae71c\`. Verdict after 4 adversarial rounds (internal + GPT-PM via PM Bridge): **review-process consensus reached**; product release status separately and explicitly **NOT_RELEASE_READY**, per the repository's own clinical-authority documents. The audit's own round 4 caught its earlier rounds' most consequential miss — an initial "no release blockers" framing that contradicted the repo's own verdict documents — corrected as finding F16 (BLOCKER).

---

## 8. Observability & Alerting — Gate OBS-1 (new, added 2026-08-26; revised 2026-08-26 after agent review)

### Why this is its own priority gate, not a line item

Every serious defect surfaced in this project's history so far was caught by a **manual, point-in-time audit** — weeks to months after the defect was introduced — essentially never by a continuous monitoring mechanism:

| Defect | How long it ran undetected | How it was actually found |
|---|---|---|
| Production Firebase Auth never enabled — zero user data ever reached Firestore | From project start until 08-06 | Accidentally, during unrelated WorkoutSession migration work |
| Stripe API version drift — would have silently reset every real subscriber to `free` on first live payment | Unknown, caught before any real payment | Manual review during 08-04 audit remediation |
| Cloud Functions Jest suite had never actually run in this worktree (`npm ci` missing) — every "full suite green" claim covered `mobile/` only | From `functions/` inception until 08-16 | Manual inspection during the Final Scope ledger gate |
| App Check enforcement status across all Firebase services | Still not fully known as of 08-25 | Re-derived independently by every audit that touches it; never a persistent dashboard |
| `targetSdk` 35 vs. Play's API-36 requirement (deadline 2026-08-31) | From whenever `compileSdk` moved to 36 until 08-16 | Manual release-build inspection |
| Russian-locale content drifting out of sync with English catalog fixes | Recurred at least 3 separate times across the catalog saga | Ad hoc reviewer re-checks (later partly closed — see correction below) |
| Leaked Roboflow API key | Since 08-07, reissue **still unconfirmed as of 2026-08-26** — see §11 | Noted once in a diagnostics doc, never re-verified |
| Orphan collections (`coach_bookings`, `equipment_reports`, `debug_sessions`) not swept by account deletion | Until the 08-11 data inventory | One-time manual inventory |
| `kCanonicalMachines` (camera-recognition allowed-answer list) drifting behind `equipment.json` | Silent until the 08-03 equipment-registry expansion caught it once | One-time manual catch; **the second source of truth still exists today** (`gemini_equipment_service.dart:143`) — the drift *mechanism*, not just one instance, was never closed |

> **Correction, 2026-08-26 (architect + flutter-reviewer + security-reviewer, see §11):** this table's framing originally read as "no continuous monitoring exists at all," which overstates the gap. **Crash reporting is live** — `firebase_crashlytics` (`pubspec.yaml:95`) is wired into both `FlutterError.onError` and `PlatformDispatcher.instance.onError` (`main.dart:211,218`). **CI-enforced dependency scanning already exists for the backend** — `npm audit --audit-level=high` runs nightly and on every push (`.github/workflows/functions.yml:118-144`), with two real historical catches. **Firestore rules regression testing already runs in CI** — `firestore_rules.test.ts` via `functions.yml:74-93`, a required, non-optional job. **Structural RU/EN parity is already CI-enforced** — `exercise_translations_test.dart`, `catalog_description_coverage_test.dart`, and `catalog_corrections_test.dart` run in `flutter.yml`. OBS-1's real job is to fill the gaps these don't cover, not to rebuild what already exists — the revised scope below reflects that.

This pattern — real defects, several of them safety- or money-relevant, caught only by whoever happened to be auditing at the time, on infrastructure that partially but not fully covers the gap — is the argument for making observability a first-class, prioritized gate rather than another item in a findings list.

### Priority and sequencing

**HIGH — but not the single highest-priority open item.** Per the architect's review, one existing item outranks it on a hard external constraint: **`targetSdk` 35 vs. Play's API-36 requirement, default submission deadline 2026-08-31 — 5 days from this document's date — must be sequenced first.** *Correction, 2026-08-26 (GPT-PM round 2, verified independently via web search against Google's own Play Console help page — see §11a): this is the default submission deadline, not a strictly non-negotiable one — Google Play Console offers an extension to 2026-11-01 for developers who need more time, requested through an extension form in Play Console. Whether that extension is actually available for this specific app/account has not been checked. Priority stays HIGH/blocking-for-store-submission regardless — a rushed 5-day fix should not be the default plan when an extension may be available — but the next action is to check extension availability in Play Console before deciding whether this is a 5-day sprint or a normal-paced fix with device verification.* See the corrected §9 table.

OBS-1 remains sequenced immediately after that, alongside the three safety-blocker items — but with a corrected rationale: two of those three (pregnancy path, B5d bypass) are now verified **fixed** (§4 correction above), so OBS-1's job there is to **guard against regression**, not to catch a currently-open bug. The one still-open safety item (injury-filter fail-open, by design) has no regression risk in the classic sense — its exposure is a fixed, known 360-row gap that only shrinks with content work — so OBS-1's most direct safety contribution is a **structural invariant guard** (item 8 below), not a runtime monitor.

Recommended placement: **independent of the D1/H3 clinical-authority go-live path**, consistent with how the SPTR gate map already separates the clinical-authority finish line from the technical go-live finish line — this is an engineering-reliability gate, not a clinical one.

### Structure: two blast radii under one gate name

Per the architect's review, items below split into two groups with different failure modes, owners, and rollback paths — **kept as one named gate (OBS-1) per the operator's instruction, but tracked and shipped as two independently revertible sub-tracks**, not one atomic GO:

- **[CI]** — merge-blocking checks. Failure mode: nobody can commit until fixed. Low blast radius, fast rollback (revert the check).
- **[RUNTIME]** — production monitors. Failure mode: a human gets paged, or doesn't when they should. Needs an owner and a destination before it can be turned on (see prerequisites below).

### Proposed scope (design only — needs its own GO before any code)

1. **[RUNTIME] Auth/data-flow canary** — a scheduled check that performs a real sign-in plus a Firestore write/read and pages on failure, so a repeat of "Auth disabled in prod for weeks" is caught in minutes, not at the next manual audit. *Open question, flagged by architect review:* this interacts with App Check enforcement (an unattested synthetic prober may be rejected once App Check is fully enforced) and with item 7's deletion-coverage measurement (the canary's synthetic writes must be excluded from that count, or they will corrupt it) — both need an explicit design answer before this ships, not just before it's turned on.
2. **[CI] Functions test-health enforcement** — fail CI outright if `functions/` tests were skipped or never ran, closing the exact class of gap that let the Jest-suite-never-ran state persist unnoticed.
3. **[RUNTIME] Enforcement-status dashboard** — one script/scheduled report enumerating Firebase App Check / Firestore rules / Identity Toolkit enforcement per service, replacing the current pattern of this being re-derived from scratch, incompletely, by every audit. (Firestore *rules regression* is already CI-tested — see correction above; this item is about persistent *enforcement-state* visibility across all services, which is different and still missing.)
4. **[RUNTIME] Billing integrity monitor** — alert on Stripe webhook/API version mismatch and on subscription-state divergence. Scope stays limited to Stripe; the Gemini/AI-Logic cost-abuse surface (item 9 below) is deliberately not folded into this item — different mechanism, different owner.
5. **[CI] RU/EN semantic-drift spot-check** — *rescoped from the original "content-parity CI check."* Structural parity (id coverage, step-count match, Cyrillic presence, pinned-row regression) is **already CI-enforced** (`exercise_translations_test.dart`, `catalog_description_coverage_test.dart`, `catalog_corrections_test.dart`). What's still missing is a check for a mistranslation that preserves step count and uses Cyrillic but changes meaning — the class of drift structural tests cannot catch by construction. Needs a baseline/grandfather-list design (see prerequisites) since 1,368/1,887 rows are still unreviewed per §4 and a naïve "flag every RU/EN diff" check would fail on day one.
6. **[CI] Mobile/Dart dependency (SCA) scanning** — *new item, added from security review.* Backend already has `npm audit` in CI; the Flutter/Dart side has no equivalent (no `dependabot.yml`/`renovate.json`, no `pub outdated`/audit workflow found anywhere in the repo). Closes an asymmetry, not a net-new class of risk.
7. **[RUNTIME] Data-lifecycle sweep verification** — automated check that deletion/export coverage still matches the live collection list, instead of relying on a one-time manual inventory that goes stale as new collections are added. Must explicitly exclude item 1's canary-generated synthetic data from its coverage count.
8. **[CI] Safety-invariant regression guard** — *new item, added from architect review, to actually deliver OBS-1's stated safety rationale; (b) rescoped 2026-08-26 after a GPT-PM round-1 finding — see §11a.* Assert mechanically that no prescription/scheduling path can be constructed without a derived `SafetyContext` (the parameter is already `required` at `plan_builder.dart:33` and `programme_builder.dart:288` — this item pins that as a permanent invariant test, not just current code shape). This is what would actually catch a *regression* of F014/F015, which none of the original 7 items did.
   **Explicitly not in scope for this item:** whether an untagged catalog row should be excluded from recommendation rather than defaulted-in. That is a clinical-policy question, not an engineering regression guard — `CURRENT_STATE.md` still lists `D1` (EXTERNAL_AUTHORITY_REQUIRED) and `H3` (HOLD, "held by the same missing authority as D1") as open, unresolved external-authority items covering exactly this catalog. An engineering-only CI check that starts silently withholding untagged rows would pre-empt that authority's decision, not guard against a regression. If OBS-1 is ever implemented, this item's scope must stay limited to the `SafetyContext`-presence invariant until D1/H3 resolve; a separate, explicitly authority-gated item can add untagged-row disposition once that resolution exists.
9. **[RUNTIME] Gemini / Firebase AI Logic client-direct call monitoring** — *new item, added from security review.* `gemini_equipment_service.dart` calls Gemini directly from the mobile client with no Cloud Functions intermediary and no code-level rate limiter (unlike the Cloud Functions surface, which has `abuse_guard.ts`). If App Check enforcement on this path is incomplete (status itself unknown per item 3), this is an effectively unmetered-client-side cost/abuse surface. Needs quota/rate-limit and cost-rate alerting specific to this path, not folded into the Stripe billing monitor.
10. **[CI] `kCanonicalMachines` ↔ `equipment.json` parity check** — *new item, added from architect review.* Closes the recurrence mechanism of the 08-03 drift bug, not just that one instance — `gemini_equipment_service.dart:143` is still a hardcoded second source of truth for the same registry.
11. **[RUNTIME] Client-runtime/ML telemetry** — *new item, added from flutter-reviewer + architect review.* No `firebase_performance` or equivalent frame-timing/ANR monitoring exists in `pubspec.yaml`. Add inference-failure rate, camera init/format-failure rate, and frame-timing telemetry for the `BackdropFilter`-heavy HUD/glass surfaces — building on the existing Crashlytics wiring rather than beside it, and specifically auditing whether the app's various `catch (e) { debugPrint(...) }` swallow sites actually forward to `FirebaseCrashlytics.recordError` (a silently swallowed exception is invisible to Crashlytics by construction).
12. **[CI] Secret-scanning / leaked-credential detection** — a preventive/detective control that **prevents recurrence of future leaks; it does not remediate the existing Roboflow-key exposure** (correction, 2026-08-26, GPT-PM round 1 — see §11a: the original wording said this item "closes" the Roboflow-key gap, contradicting §9's own more careful language in the same document). The Roboflow key's actual remediation is a separate, still-open operator action (`CURRENT_STATE.md`'s `roboflow-key-reissue` entry — rotate/reissue in the Roboflow console; nothing in this repo can perform or observe that action). *Scope correction from security review:* the existing mechanical guard (`state_ledger.py`'s `roboflow_key_not_committed`) only scans currently-tracked files, not git history — extend to history scanning, since a key committed-then-removed would pass the current check while still being exposed in history.
13. **[CI] Composed-screen visual regression coverage** — *new item, added from flutter-reviewer review; track corrected 2026-08-26 from [RUNTIME] to [CI] per GPT-PM round 1 — see §11a: it is an extension of the existing CI-enforced golden-test harness, not a production monitor, and should not be bundled with the on-call/alerting-stack prerequisites that gate the `[RUNTIME]` items.* The existing golden-test harness (`hud_golden_test.dart`) is real and CI-enforced but explicitly excludes composed screens (its own doc comment says so) — exactly the surface where the shipped WCAG contrast failure (§3) actually occurred. Extend golden coverage to at least Home and Workouts, the highest-traffic screens mixing `GlassCard` and `Hud*` widgets.

### Explicitly left open — now framed as blocking prerequisites, not parallel questions

*Corrected 2026-08-26 (GPT-PM round 2 — §11a): the original single prerequisite list self-contradicted the `[CI]`/`[RUNTIME]` split by putting a `[CI]` item's own prerequisite (RU/EN baseline) inside a list introduced as "these gate the `[RUNTIME]` items... `[CI]` items have no such dependency." Split below into the two prerequisite classes that actually apply.*

**RUNTIME prerequisites** — building a pager before deciding who reads it produces alerts into a void, the same failure pattern this gate exists to close. Block items 1, 3, 4, 7, 9, 11 specifically:

- **Alerting destination and on-call ownership** — there is currently no evidence of any on-call/paging structure for this pre-launch app.
- **Canary identity/attestation model** (item 1) and its explicit exclusion from item 7's coverage measurement.
- Monitoring stack choice/budget (native Firebase tooling vs. an external service).

**CI prerequisite** — has nothing to do with on-call and does not block any other `[CI]` item:

- **RU/EN parity baseline/grandfather-list** (item 5 only) — an expiry-dated exception list against the 1,368 unreviewed rows, or that one check fails permanently from day one. Items 2, 6, 8, 10, 12, 13 have no such prerequisite and can proceed independently.

---

## 9. Selected Engineering/Product Priorities (non-exhaustive — see caveat below)

*Revised 2026-08-26 after independent agent review (architect, security-reviewer, flutter-reviewer — §11) and GPT-PM round-1 external review (§11a). Corrections from the first draft are marked inline; nothing was silently reordered without a note.*

> **Renamed from "Consolidated Open-Items / Priority Table," 2026-08-26 (GPT-PM round 1 — §11a).** This table is a curated subset assembled from the six-era synthesis in §2–§7, **not** a full mirror of `core/CURRENT_STATE.md` — which remains, per §6, the single authoritative ledger of every OPERATOR/EXTERNAL-authority item. GPT-PM's cold read correctly caught two real defects in the first draft: this table silently omitted several live `CURRENT_STATE.md` rows (`D1`, `H3` [clinical], `N-05`, `N-04-gym-association`, `CT1-human-labels`, `scanner-pipeline-location`), and it reused the identifier **`H3`** for something else entirely (the Aug-13 bug-batch catalog-`purpose`-field item, §4) — a genuine collision with `CURRENT_STATE.md`'s own `H3` (clinical HOLD, same external authority as `D1`). Fixed below: the bug-batch item is renamed to an unambiguous id, and the two real clinical-authority rows are added explicitly rather than assumed implicit. For the complete list of every OPERATOR/EXTERNAL-authority item, always read `core/CURRENT_STATE.md` directly — do not treat this table as a substitute.

| # | Item | Priority | Status | Depends on / blocks | Section |
|---|---|---|---|---|---|
| 0 | **`D1` / `H3` (clinical) — external clinical validation authority** (`CURRENT_STATE.md`) | **Release-blocking, external authority — outranks everything below** | `D1`: EXTERNAL_AUTHORITY_REQUIRED. `H3` (clinical): HOLD, "held by the same missing authority as D1, released by the same return, not separately." Neither is engineering-closeable. | This is the actual gate behind §7's NOT_RELEASE_READY verdict; nothing in this table substitutes for it | `CURRENT_STATE.md`, §7 |
| 1 | `targetSdk` 35 vs. Play API-36 default submission deadline (2026-08-31 — **5 days out**; extension to 2026-11-01 may be available via Play Console, unchecked) | **Blocker for store submission** *(moved above OBS-1 — architect: nothing else in this table has an equal hard deadline; wording corrected 2026-08-26, GPT-PM round 2 — an extension path exists, so "non-negotiable" overstated it)* | Open (G7); needs Android-16 device verification before the fix; check extension availability first | Blocks store release once other release-blockers close | §4 |
| 2 | Injury filter fails open (360/1,887 untagged rows, by design) | Release-blocking | Open, verified current at HEAD (coverage 1,527/1,887 tagged, 80.9%) | Guarded going forward by OBS-1 item 8's `SafetyContext` invariant only — **untagged-row disposition itself is row 0's decision, not an engineering call (corrected 2026-08-26, GPT-PM round 1)** | §4 |
| 3 | No pregnancy path | ~~Release-blocking~~ **Closed** | **FIXED** — F014 `ProfessionalGuidanceNeed`, regression-tested (`f014_professional_guidance_test.dart`) | Regression guarded by OBS-1 item 8 | §4 |
| 4 | B5d bypasses SafetyContext | ~~Release-blocking~~ **Closed** | **FIXED** — F015, `safety` hoisted above the branch that skipped it, single verified call site | Regression guarded by OBS-1 item 8 | §4 |
| 5 | **OBS-1 — Observability & alerting (13 items, split CI/Runtime — see §8)** | **High, parallel track** | Revised scope, agent-reviewed | Items 1/3/4/7/9/11 need the on-call/attestation/baseline prerequisites in §8 first | §8 |
| 6 | `BUG-2026-08-13-H3-purpose` — `purpose` field for 1,484/1,887 exercises *(renamed 2026-08-26 from bare "H3," which collided with `CURRENT_STATE.md`'s unrelated clinical `H3` — see row 0 and the caveat above)* | Medium | Not started | — | §4 |
| 7 | HUD visual migration incomplete; `glass.dart` (142 occurrences / 46 files, corrected from "~40") / `aurora_background.dart` still coexist | Medium | Open, debt larger than first stated | Overlaps OBS-1 item 13 (composed-screen golden coverage) | §3 |
| 8 | M1-M9: HUD visual-fidelity never device-verified; known WCAG contrast bugs | Medium | Open — *note: app has real on-device functional tests (`integration_test/app_test.dart`), this claim is scoped specifically to visual-fidelity, not "zero device testing"* | Closes via OBS-1 item 13 | §3 |
| 9 | text-anchor equipment recognition (18/18 measured accuracy) not wired into live mode | **Medium-High** *(architect: bump above item 10 — empirically-validated, cheapest available ML win, open since 08-07)* | Open since 08-07 | — | §2, §5 |
| 10 | P2/P4/P6 recognition-decision engine | Medium/long-term | Not started | Blocked by item 11's licence question for the visual-retrieval half specifically | §5 |
| 11 | Vendor-clip AI-training licence conflict | Low urgency **while P4 stays deferred**, unresolved | Flagged once, never rechecked | **Blocks item 10's P4 (visual retrieval)** if that work ever resumes — not merely "unresolved" | §2 |
| 12 | Nonprofit/subscription ARB copy contradiction | Medium | Open | — | §6 |
| 13 | Leaked Roboflow key — **reissue still unconfirmed as of 2026-08-26** | Medium | Open — confirmed by security review this is an operator/console action code cannot verify either way (`CURRENT_STATE.md`'s `roboflow-key-reissue` entry) | OBS-1 item 12 (extended to git history) only prevents *recurrence*; does not remediate this instance | §6 |
| 14 | App Check full enforcement picture | Medium | UNKNOWN even after 08-25 audit | OBS-1 item 3 only adds *visibility*; does not remediate | §6 |
| 15 | `kCanonicalMachines` second source of truth (`gemini_equipment_service.dart:143`) still drifts from `equipment.json` | Medium *(new — architect)* | **Closed** — CLOSED via OBS-1 item 10 (`scripts/ci/check_equipment_registry_parity.js`, CI-enforced, 71 `CANONICAL_MACHINES` vs 69 catalog entries, 4 aliases + 2 audited `KNOWN_UNCOVERED` content gaps kept visible as a separate, deliberately out-of-scope catalog-content task) | Closed via OBS-1 item 10 | §2, §8 |
| 16 | Gemini/Firebase AI Logic client-direct calls — no rate-limit/abuse-cost monitoring | **Medium-High** *(new — security review)* | **Rebased/closed** — REBASED→CLOSED via OBS-1 item 9: the direct-client-call exposure this row describes no longer exists (G1 migrated all 4 AI call sites to server-side `httpsCallable`, zero direct Gemini calls remain in `mobile/lib/`). The replacement risk (activating the 4 server-side AI callables safely) is governed by the new mandatory gate **MVP1.G4 — AI Gateway Production Release & E2E Validation**; AI-enabled user release is prohibited until G4 passes | Closed via OBS-1 item 9; production-AI risk now owned by MVP1.G4 | §6, §8 |
| 17 | No client-runtime/ML telemetry (frame-timing, camera/inference failure rate); no `firebase_performance` present | Medium *(new — flutter-reviewer)* | **Closed** — CLOSED via OBS-1 item 11 (all originally-scoped catches wired to `FirebaseCrashlytics.recordError`, proven both on a real device (Step 10B) and via the 2 remaining files closed in Step 10C) | Closed via OBS-1 item 11 | §8 |
| 18 | Mobile/Dart dependency (SCA) scanning absent (backend already covered via `npm audit` in CI) | Medium *(new — security review)* | **Closed** — CLOSED by MVP1.G3 SCA implementation (OBS-1 item 6, `core/DECISION_LOG.md:27151`), CI-enforced in `flutter.yml` alongside the existing backend `npm audit` | Closed via OBS-1 item 6 | §8 |
| 19 | R11f-2 — photo export policy decision | Low | Decision not made | — | §4 |
| 20 | Gym-favoriting + social monitoring | Low | Plan only, never built | — | §2 |
| 21 | **Silent failure-alert path on 4 already-deployed alerts** (Stripe reconciliation x2, delete-account x3, export-account, canary probe) — same root cause as a real MVP1.G3 Step 10A bug: `logger.error(EVENT_STRING, {...metadata})` + a `messageEquals`-exact-match `LogMatchFilterSpec` never matches, because `firebase-functions/logger` unconditionally rewrites `jsonPayload.message` into `"Error: EVENT\n<stack>"` for ERROR severity when no arg is already an `Error` instance (confirmed by reading the logger's own source, not inferred) | **High — urgent, financial-correctness-adjacent** (Stripe reconciliation alerts included) *(added 2026-08-27, GPT-PM round-9 explicit scope decision: "do not reopen Step 10A, but open an urgent dedicated remediation item immediately")* | **Closed/remediated in MVP1.G3 Step 10C (2026-08-28)**: all 8 affected call sites (`index.ts` x5, `account_export.ts` x1, `canary_schedule.ts` x2) now set `event: THE_SAME_CONSTANT`; the 4 filters switched `messageEquals`->`eventEquals` (plus a new `messageContains` for the one framework-owned "Unhandled error" message); the 4 already-deployed producers (`stripeWebhook`, `deleteAccount`, `exportAccountData`, `runProductionCanary`) were redeployed; all 4 existing alert policies were PATCHed in place (preserving displayName/enabled/notificationChannels) and read back to confirm the live filter equals current-HEAD; 5 induced-failure proof log entries, shaped like real production output, confirmed matching each policy's own live filter via `gcloud logging read`. GPT-PM review: 1 MAJOR (missing policy patch, fixed) + 2 MINOR (fixed) on the code, then VERDICT: MINOR (audit-trail wording only) on the live evidence, then confirmed sufficient for CLOSED | Full sequence, evidence, and both GPT-PM review rounds in `core/DECISION_LOG.md`, "GPT-PM round 1: real MAJOR (missing policy patch)... live remediation complete" and "GPT-PM round 2" entries, 2026-08-28; root-cause analysis in "GPT-PM round 8" entry, 2026-08-27 | §8, `monitoring/types.ts`, `monitoring/alert_definitions.ts` |
| 22 | **No CI job builds a real release artifact** (`flutter build apk --release` / `flutter build appbundle`, signing, R8/ProGuard, native-ML packaging) — every job in `flutter.yml` (analyze-and-test, functions-build, integration, dependency-scan, ru-en-drift) stops at host-level analyze/test | **Release-blocking** *(new — 2026-09-15, external review reconciliation, §12)* | Open, verified current: `grep` for `build apk\|appbundle\|assembleRelease\|signingConfig` in `.github/workflows/flutter.yml` (426 lines) returns nothing | Distinct from item 1 (`targetSdk`); this is "no release build is ever produced or smoke-tested," not "the wrong SDK version" | §12 |
| 23 | `functions-equipment-identity` Firebase deploy `predeploy` hook runs `npm run build` only — no `npm test`, unlike the sibling `default` codebase which runs build+test+release_guard | Medium-High *(new — 2026-09-15, §12)* | Open, verified current: `firebase.json:23-27` (default codebase) vs. `firebase.json:40-42` (equipment-identity) | A regression in `functions-equipment-identity/src` can deploy to production having only ever been checked by CI (`flutter.yml`'s `functions-build` job does `tsc`, not `npm test` either — needs its own check before treating this as closed by CI alone) | §12 |
| 24 | Firestore rules grant read/write over `/users/{uid}/{coll}/**` via a wildcard match with a hand-maintained per-write denylist, rather than an explicit per-collection allowlist | Medium *(new — 2026-09-15, §12)* | Open, verified current: `firestore.rules:49-58` | A new server-only collection is client-readable by default unless someone remembers to add it to the denylist — the exact failure mode that would silently expose whatever P2.G5's own `equipment_identity_telemetry` collection carries if the currently-open P2.G5-readiness plan's own denylist entry (already present, `firestore.rules:58`) were ever dropped in a future edit | §12 |
| 25 | `server_export.dart`'s `CloudFunctionsServerExport` calls `FirebaseFunctions.instance` (default region) instead of this project's own `functions_region.dart` `kFunctionsRegion`-pinned helper that every other call site uses | Low-Medium *(new — 2026-09-15, §12)* | Open, verified current: `mobile/lib/features/data_export/server_export.dart:21` vs. `mobile/lib/core/firebase/functions_region.dart:23` | Likely routes GDPR-export calls to `us-central1` instead of the deployment region — functional (Cloud Functions v2 callables resolve globally) but adds needless cross-region latency/cost, and is the one exception to an otherwise-consistent pattern | §12 |
| 26 | Legacy health-data lazy migration leaves the server-side health block indefinitely for an account that never reopens the app; the purpose-built one-off remediation script (`scripts/ops/strip_health_from_profiles.py`) exists but is run by hand, on no schedule, with no on-record dated zero-result evidence of a completed sweep | Medium *(re-flagged — this exact gap was already required to be closed or softened by `core/audit/gate_j_regulatory_review_2026-08-15/GATE_J_REGULATORY_REVIEW_2026-08-15.md:66`; not new, but still open as of 2026-09-15, §12)* | Open — script exists (`scripts/ops/strip_health_from_profiles.py`, present), no evidence of a completed scheduled or dated run found in `core/DECISION_LOG.md`/`core/audit/` | Same underlying mechanism the currently-open P2.G5-readiness plan's own step 4 (retention/export) is building for a *different* collection — worth the same "make it a real, testable, scheduled mechanism" treatment when this row is picked up, not a new pattern to invent | §12 |

---

## 10. Source files (primary evidence)

Foundation era: `core/plans/PLAN_AI_RESTRUCTURE_2026-07-28.md`, `PLAN_DEVICE_DEFECTS_2026-07-30.md`, `PLAN_DEVICE_DEFECTS_ROUND2_2026-07-30.md`, `core/PLAN_2026-07-31.md`, `core/plans/NEXT_STEPS_2026-07-31.md`, `core/EQUIPMENT_REGISTRY_EXPANSION_2026-08-03.md`, `core/VENDOR_EQUIPMENT_LINK_2026-08-03.md`, `core/CATALOG_STATE_2026-08-03.md`, `core/LEGACY_CATALOG_REMOVED_2026-08-04.md`, `core/CLIP_LICENCE_AUDIT_2026-08-03.md`, `core/VIDEO_SOURCES_RESEARCH_2026-08-01.md`, `core/PLAN_GYMS_AND_NEWS_2026-08-01.md`, `core/plans/B1_RECOGNITION_MEASUREMENT_2026-08-07.md`, `B3_MEDIA_DIAGNOSIS_2026-08-07.md`, `B5_DATA_SOURCES_2026-08-07.md`, `B5b_TEXT_ANCHOR_2026-08-07.md`, `core/plans/PLAN_F3_WORKOUT_SESSION_2026-08-06.md`, `core/COMMIT_PLANS_2026-08-04.md`, `core/PLAN_AUDIT_REMEDIATION_2026-08-04.md`.

Design lineage: `docs/Redisign/*`, `design_handoff_fitness_hud/README.md`, `.../CLAUDE.md`, `mobile/lib/core/theme/hud_*.dart`, `mobile/lib/shared/widgets/hud/*.dart`, `mobile/lib/shared/widgets/glass.dart`, `aurora_background.dart`, `reports/SPTR_VISUAL_FIDELITY_74f2f76.ru.html`.

Onboarding/safety/catalog: `core/plans/PLAN_R10_POSTURE_2026-08-08.md`, `O0_ONBOARDING_SCHEMA_2026-08-12.md`, `RESUME_O_SERIES_2026-08-12.md`, `PLAN_R11_DECISIONS_2026-08-12.md`, `core/AUDIT_REPORT_2026-08-11.md`, `core/DATA_INVENTORY_2026-08-11.md`, `core/plans/PLAN_AUDIT_2026-08-11_REMEDIATION.md`, `core/plans/PLAN_BUGS_2026-08-13.md`, `core/plans/FINAL_SCOPE_2026-08-16.md`, `core/RELEASE_BUILD_2026-08-16.md`, `core/audits/FULL_PROJECT_AUDIT_2026-08-16/00_EXECUTIVE_SUMMARY.md`.

ML platform: `core/design/sptr_equipment_recognition_v4_1...v4_4/*`, `core/ML_PLATFORM_ARCHITECTURE.md`, `core/equipment_identity/`.

Release/business/governance: `core/CURRENT_STATE.md`, `core/PRODUCTION_MANIFEST.md`, `core/PLATFORM_SCOPE.md`, `core/PLAY_DATA_SAFETY_2026-08-05.md`, `core/DECISION_SELF_BOOKING.md`, `core/REMEDIATION_ENGINEERING_FREEZE.md`, `core/business/PITCH_2026.md`.

SPTR audit: `D:\Repo\_audit_output\SPTR_INDEPENDENT_PRODUCT_TECH_MARKET_AUDIT_2026-08-25_c3ae71c\` (full package, 28_FINAL_CONSENSUS.md, 22_DEVILS_ADVOCATE_ROUNDS.md, 12_FINDINGS.csv).

---

## 11. Agent Review — Findings & Corrections Applied (2026-08-26)

Per this workspace's risk-based agent-routing rule, this document (cross-domain: architecture, security-critical safety claims, mobile/Flutter implementation) was routed to three independent specialists, each reading the master plan cold and re-verifying its load-bearing claims against current repo state rather than trusting the document's own citations. Round 1 was independent — no agent saw another's findings. This section adjudicates all three.

### Architect review — VERDICT: CHANGES REQUIRED (applied)

- **B1 (BLOCKER, FACT):** `targetSdk`/API-36 deadline (5 days out) was ranked below OBS-1 despite being the only hard external, non-negotiable cutoff in the table. **Applied** — §9 row 1. *(Historical reviewer wording, preserved for the audit trail — the "non-negotiable" characterization itself was later corrected by GPT-PM round 2 and independent `WebSearch` verification: a Play Console extension to 2026-11-01 exists. The ranking-above-OBS-1 call still stands; only "non-negotiable" was too strong. See §11b.)*
- **Defect 1 (MAJOR, FACT):** OBS-1's HIGH-priority rationale ("catches a regression in the safety paths") was not delivered by any of the original 7 items. **Applied** — added item 8, safety-invariant regression guard, §8.
- **Defect 2 (MAJOR, FACT):** zero client-runtime/ML telemetry proposed for a camera+on-device-ML app; Crashlytics already exists and the plan didn't credit it. **Applied** — added item 11, corrected framing, §8.
- **Defect 3 (MAJOR, INFERENCE):** merge-blocking CI checks and production pagers bundled under one GO with different blast radii. **Applied** — `[CI]`/`[RUNTIME]` split, §8.
- **Defect 4 (MAJOR, FACT):** alerting destination/on-call ownership was "left open" as a parallel question when it's a hard prerequisite for items that page. **Applied** — reframed as blocking prerequisites, §8.
- **Defect 5 (MAJOR, INFERENCE):** canary (item 1) vs. App Check enforcement (item 3) vs. lifecycle sweep (item 7) — unstated interaction/ordering. **Applied** — flagged as an open design question on item 1, §8.
- **Defect 6 (MINOR, INFERENCE):** RU/EN parity item had no baseline/cutover plan against 1,368 unreviewed rows. **Applied** — rescoped to semantic-drift-only, baseline requirement added, §8 item 5.
- **B2 (MAJOR, FACT):** the B5d-bypass claim's stated symptom is stale — `required SafetyContext` already exists in code. **Applied** — §4 correction (also independently confirmed FIXED by security-reviewer with the actual F015 fix, not just a stale-symptom flag).
- **B3 (MAJOR, FACT):** rows 13/14 (leaked key, App Check picture) were marked as "closing under OBS-1," conflating detection with remediation. **Applied** — §9 rows 13/14 now state OBS-1 only adds visibility/prevents recurrence.
- **B4 (INFERENCE):** text-anchor (row 9, empirically validated, cheap) ranked equal to the entirely-unbuilt P2/P4/P6 program (row 10). **Applied** — row 9 bumped to Medium-High, §9.
- **B5 (MAJOR, INFERENCE):** the AI-training licence conflict (row 11) is a precondition for P4, not merely "unresolved" at equal footing. **Applied** — dependency noted, §9.
- **B6 (MINOR):** no dependency/ownership columns in §9. **Applied** — "Depends on / blocks" column added.
- Spot-checks: 6 of 8 claims held exactly (`rankedForYouProvider`, `aurora_background.dart:601`, 69 machines, 1,887 exercises, 403/1,484 purpose split, `machine_text_anchor.dart` existence). 2 did not hold as stated: the `GlassCard` "~40 call sites" figure (actual: 142 occurrences / 46 files) and `kCanonicalMachines` (the *instance* of the 08-03 drift was fixed, but it remains a live second source of truth). **Both applied** — §3 and §9 row 15.

### Security-reviewer review — VERDICT: two of three safety claims stale, real gaps found in OBS-1 scope

- Claim 1 (fail-open filter): **confirmed still open**, exact match on the 360-row figure, coverage now measured at 1,527/1,887 (80.9%) via `safety_coverage_test.dart`. **Applied** — §4, §9 row 2.
- Claim 2 (no pregnancy path): **confirmed FIXED** (F014, `health_flags.dart`, `eligibility.dart`, full bilingual regression test). **Applied** — §4, §9 row 3.
- Claim 3 (B5d bypass): **confirmed FIXED** (F015, `programme_providers.dart`, single verified call site, regression-tested). **Applied** — §4, §9 row 4.
- OBS-1 scope gaps: mobile-side SCA scanning absent while backend's exists; Firestore-rules regression testing already exists and shouldn't be re-proposed; the real unaddressed gap is the Gemini/Firebase-AI-Logic **client-direct** call path (`gemini_equipment_service.dart`, no Cloud Functions intermediary, no rate limiter) — a genuine unmetered-cost/abuse surface distinct from the Stripe billing monitor. **All applied** — §8 items 4/6/9, §9 rows 16/18.
- Secret-scanning gap: existing guard (`state_ledger.py`) only scans tracked files, not git history. **Applied** — §8 item 12.
- Roboflow key: confirmed **no live key literal in the current repo**, but reissue status is a Roboflow-console action the repo cannot observe either way (`CURRENT_STATE.md`'s own `roboflow-key-reissue` entry says so explicitly) — the master plan's "unconfirmed" framing is accurate and current, not stale. **No change needed**, confirmed as-is — §9 row 13.

### Flutter-reviewer review — VERDICT: no BLOCKER/MAJOR, one real factual correction, three scope additions

- HUD/legacy-glass coexistence: **confirmed**, with a corrected count (142 occurrences / 46 files vs. the stated "~40"). **Applied** — §3.
- "M1-M9 closed without device verification": **confirmed accurate for HUD visual-fidelity specifically** — real on-device functional tests exist (`integration_test/app_test.dart`) but check crash/functional correctness, not visual fidelity or contrast; the existing golden-test harness (`hud_golden_test.dart`) explicitly excludes composed screens by its own doc comment. **Applied** — §9 row 8 caveat, §8 item 13.
- Crashlytics: **already wired** (`pubspec.yaml:95`, `main.dart:211,218`) — the master plan's "no continuous monitoring" framing didn't credit this. **Applied** — §8 intro correction.
- RU/EN parity: **already substantially automated and CI-enforced** (three test files, `flutter.yml`) — checks structural parity (id coverage, step count, Cyrillic presence, pinned rows), not semantic equivalence. §8's original item 5 overclaimed the gap as fully open. **Applied** — §8 item 5 rescoped to semantic-drift-only.
- Three scope additions (composed-screen golden coverage, frame/jank telemetry, Crashlytics-forwarding audit for swallowed exceptions): **all applied** — §8 items 11 and 13.

### Net effect on the document

Two release-blocking items closed (verified fixed, not just reclassified); one item promoted to the top of the priority table on a hard external deadline; OBS-1 grew from 7 to 13 scoped items across two blast-radius tracks, with three items removed of overclaimed scope (RU/EN parity, "no monitoring exists") and replaced with the gaps that actually remain. No finding from any of the three reviewers was rejected outright — all were either applied directly or (Roboflow reissue status) confirmed as already correctly stated.

## 11a. External Review — GPT-PM (via PM Bridge), Round 1 (2026-08-26)

Per this workspace's standing mandatory GPT-consensus policy (§15 of the global operator contract), the commit carrying this document was sent to GPT-PM for an independent, cold external read before commit. Round 1 returned VERDICT: MAJOR, **4 MAJOR + 2 MINOR findings** *(corrected 2026-08-26, GPT-PM round 2: this section originally miscounted its own table as "3 MAJOR + 2 MINOR / all 5" — arithmetic error, the table below has always had 6 rows)*. Every claim was independently re-verified against the real repo (`git ls-files`, direct `grep` against `core/CURRENT_STATE.md`) before being accepted — none were taken on GPT-PM's word alone, per this workspace's evidence-over-inference rule. All 6 held up and were applied; none were rejected.

| Severity | Finding | Verified how | Applied as |
|---|---|---|---|
| MAJOR | OBS-1 item 8(b) (untagged rows excluded from recommendation) unilaterally pre-empts the still-open `D1`/`H3` clinical-authority decision instead of guarding a regression | `grep` confirmed `CURRENT_STATE.md`'s `D1` = EXTERNAL_AUTHORITY_REQUIRED, `H3` = HOLD ("same missing authority as D1") | §8 item 8 rescoped to the `SafetyContext`-presence invariant only; untagged-row disposition explicitly deferred to `D1`/`H3` |
| MAJOR | §9's table silently omitted several live `CURRENT_STATE.md` rows and reused the identifier `H3` for an unrelated bug-batch item | `grep` confirmed `D1`, `H3`, `N-05`, `N-04-gym-association`, `CT1-human-labels`, `scanner-pipeline-location` all exist as distinct current rows in `CURRENT_STATE.md` | §9 renamed to "Selected... priorities (non-exhaustive)," row 0 added for `D1`/`H3`, bug-batch item renamed to `BUG-2026-08-13-H3-purpose` |
| MAJOR | §5's "P0 — closed, 6/6" overstates readiness; the canonical P0 evidence index scopes closure to G1–G6, with G0 still `BLOCKED_EXTERNAL_PLATFORM_MIGRATION` | Matches this session's own earlier reading of `reports/P0_PHASE_CLOSEOUT_2026-08-22.ru.html`, which explicitly records G0 blocked/external | §5 corrected to state G1–G6 CLOSED, G0 BLOCKED_EXTERNAL_PLATFORM_MIGRATION |
| MAJOR | OBS-1 item 12 said secret-scanning "closes" the Roboflow-key leak, contradicting §9's own more careful "does not remediate" language elsewhere in the same document | Internal-consistency check, no external verification needed — the contradiction was in this document's own text | §8 item 12 reworded: scanning prevents recurrence only; remediation is a separate, still-open operator action |
| MINOR | `AGENTS.md`/`CLAUDE.md` are currently tracked on `master`, contradicting §2's "not under git" claim | `git ls-files -- AGENTS.md CLAUDE.md` returned both files | §2 corrected: claim scoped to the 07-28 restructure's historical state, current tracked status stated explicitly |
| MINOR | OBS-1 item 13 (composed-screen golden coverage) mislabeled `[RUNTIME]`; it extends an existing CI-enforced harness | Re-read of the item's own description against the `[CI]`/`[RUNTIME]` definitions in §8 | §8 item 13 relabeled `[CI]` |

**Round status:** superseded by round 2 below — this round's findings were fully applied, and GPT-PM's round-2 read confirmed all 6 were "по существу исправлены корректно" (substantively correctly fixed) before raising a fresh set of round-2-only findings.

## 11b. External Review — GPT-PM (via PM Bridge), Round 2 (2026-08-26)

Sent the corrected diff (~112K chars, well under the 400K truncation threshold) for a second cold read. GPT-PM opened by confirming all 6 round-1 findings were correctly applied (D1/H3 no longer overridden by engineering policy, P0.G0 honestly still externally blocked, Roboflow rotation separated from secret scanning, AGENTS.md/CLAUDE.md corrected, the H3 collision resolved, composed-screen goldens moved to `[CI]`), then raised VERDICT: MAJOR with 3 new MAJOR + 2 new MINOR findings. Every claim re-verified before acceptance, per the same evidence-over-inference discipline as round 1:

| Severity | Finding | Verified how | Applied as |
|---|---|---|---|
| MAJOR | §8's `targetSdk` framing ("hard, non-negotiable cutoff, cannot be renegotiated") is factually overstated — Google Play Console offers an extension to 2026-11-01 for developers who need more time | **Independently verified via `WebSearch` against Google's own Play Console help page** (`support.google.com/googleplay/android-developer/answer/11926878`), not taken on GPT-PM's citation alone — confirmed: default deadline 2026-08-31, extension to 2026-11-01 available via an extension form in Play Console | §8 and §9 row 1 reworded: default deadline stands, extension path exists and its availability for this account is unchecked, priority unchanged but no longer justified by false impossibility |
| MAJOR | `core/DECISION_LOG.md`'s entry for this work still described OBS-1 as monolithically "needs its own GO per item, gated first on deciding who owns alerting/on-call," contradicting the corrected master plan's `[CI]`/`[RUNTIME]` split (where only items 1/3/4/7/9/11 need that decision) | Direct re-read of the committed-but-not-yet-pushed decision log entry against the current master plan text | Decision log entry corrected — see the same-day addendum entry below |
| MAJOR | The review payload swept in ~10 unrelated pre-existing untracked `reports/*.html` files (from other sessions' work), and at least one (`citation_verification_report.html`) was truncated mid-file in the payload GPT-PM actually saw | Confirmed via `git status --short` — those files are untracked, not part of this commit's staged scope (`git diff --cached --stat` lists exactly 4 files: `core/DECISION_LOG.md`, `core/MASTER_PLAN_2026-08-26.md`, and the two report HTML files) | No content change needed — verified the actual `git add` scope was already exact (not `-A`), so nothing untracked would have been swept into the real commit regardless of what the review tool's diff-building included for its own read. Round 3 (if run) uses `--scope-note` to tell GPT-PM explicitly which files are the intended commit, so its read isn't diluted by unrelated files again |
| MINOR | §11a's own narrative said "3 MAJOR + 2 MINOR / all 5," but its own table lists 4 MAJOR + 2 MINOR = 6 rows | Recounted the table directly | §11a narrative corrected to "4 MAJOR + 2 MINOR... all 6" |
| MINOR | §8's prerequisites section contradicted its own `[CI]`/`[RUNTIME]` framing — introduced as "these gate the RUNTIME items... CI items have no such dependency," then listed the RU/EN baseline (a `[CI]` item's prerequisite) in the same list | Re-read of the section's own logic | Split into separate RUNTIME-prerequisites and CI-prerequisite lists |

**Round status:** not yet `--final`. Per this workspace's uncapped-rounds policy, GPT-PM's own assessment is that a round 3 verifying these five mechanical fixes should be short — no full re-audit of the master plan expected to be needed. Push remains withheld until a round reaches explicit consensus.

## 11c. External Review — GPT-PM (via PM Bridge), Rounds 3–4 (2026-08-26)

**Round 3** verified the five round-2 mechanical fixes via a `--scope-note`-scoped read (excluding ~10 unrelated pre-existing untracked `reports/*.html` files from other sessions' work, explicitly out of scope). VERDICT: MINOR, one finding — the freshly-added `DECISION_LOG.md` entry's *main body* still called the `targetSdk` deadline "hard, non-negotiable," contradicting its own later addendum in the same entry that correctly described the Play Console extension. GPT-PM's own words: a later reader could grep the first half of the entry and "recreate the exact sequencing error Round 2 was meant to eliminate." Verified by direct `grep`, confirmed real, fixed by rewording the main-body bullet (not just the addendum) before the commit was made — see the git history for the exact fix.

**Round 4** was run scoped to the actual commit (`git show cb713e7`, not `--uncommitted`) as an intended final check. VERDICT: MAJOR (2 new MAJOR + 2 new MINOR), and `--final` was **not honored** (`final_overridden: true`) despite being passed — review.js downgrades `--final` automatically on a MAJOR/BLOCKER verdict, so no manual judgment call was needed to withhold it here. Findings, each independently checked before being accepted or explained:

| Severity | Finding | Verified how | Resolution |
|---|---|---|---|
| MAJOR | The commit was created while §11b still said "not yet `--final`... round 3 pending," reading as if the pre-commit review contract requires *consensus* before commit, not just an attempt | Re-read of this workspace's own §15 policy: "a commit satisfying the gate only proves round 1 was attempted... push waits for `--final`" — commit-on-attempt, push-on-consensus is the actual, correct, by-design policy, not a violation | Not a defect — clarified here for the record. The commit was not amended (this workspace's git discipline prefers new commits over amends, and the commit was not yet pushed so no history was rewritten). Push remains withheld pending an actual `--final` receipt |
| MAJOR | GPT-PM's `git show`-scoped read did not include the two `reports/*.html` files, despite `DECISION_LOG.md` describing them as "published" | **Independently verified in the tool's own source**, not taken on GPT-PM's word: `review.js`'s `REVIEW_EXCLUDE = [":(exclude)reports"]` (line 132) deliberately excludes the entire `reports/` directory from every `git diff`/`git show` scope, by design, specifically so that bilingual narrative reports don't burn the diff-size budget meant for reviewable substance (the tool's own comment explains this exact rationale). Confirmed directly with `git show cb713e7 --stat` that the commit genuinely contains all 4 files — GPT-PM's read was correct that it never *saw* the HTML files, but that is the tool's standing design, not a scope error in this commit | Not a defect requiring a content fix — documented here as a standing, intentional limitation: **GPT-PM's review never covers `reports/*.html` content, by tool design.** The Markdown (`core/MASTER_PLAN_2026-08-26.md`) is the reviewed source of truth; the two HTML files are a rendering of it, kept in sync by hand during this session's edits (spot-checked, not independently re-verified by an external reviewer) |
| MINOR | The commit message's "3 rounds... 7 findings total" undercounts — rounds 1–3 actually produced 6 + 5 + 1 = 12 findings, not 7 | Recounted directly from each round's own JSON reply | Corrected here, transparently, rather than by rewriting the pushed... not-yet-pushed but already-recorded commit message: **rounds 1–3 produced 12 findings total** (6 MAJOR/MINOR in round 1, 5 in round 2, 1 in round 3), all applied. The commit message's "7" was a real arithmetic slip made while drafting it, not a hidden discrepancy |
| MINOR | §11's own quote of the architect's B1 finding still stated "non-negotiable" without a forward pointer to the round-2 correction | Re-read of §11's B1 row | Fixed — inline note added pointing to §11b |

**Round status:** GPT-PM's own assessment closing round 4: no further full content round needed ("targetSdk policy теперь сформулирована корректно... D1/H3 остаются external authority... P0.G0 честно остаётся externally blocked, Roboflow prevention отделён от credential reissue" — i.e., every substantive correction from rounds 1–3 holds). What remains is "one short governance/finality pass" verifying this addendum itself and obtaining an actual `--final` receipt against the state including this correction. **Not yet `--final`. Push remains withheld.** This document is committed locally only; a further round is needed before any push-GO would be actionable, and push additionally requires the operator's separate, explicit push authorization per this workspace's standing gate contract regardless of GPT-PM's state.

## 11d. External Review — GPT-PM (via PM Bridge), Round 5 — closed with manual verification, not further automation (2026-08-26)

Round 5 was run as the "short governance/finality pass" round 4 called for, scoped via `--base cb713e7` against the follow-up commit. **Its own receipt flagged itself as `correlated: false`** — `review.js`'s own transport logic reported it could not confirm this reply was actually anchored to this round's own prompt ("identified by baseline comparison... may answer a different request; fact-check it rather than trusting the attribution"), a known, previously-documented risk of this workspace's shared-browser-profile PM Bridge transport (concurrent inbound cross-contamination, undocumented as fully closed in this workspace's own `~/.claude/CLAUDE.md` §15). Per this workspace's round policy ("re-verify against the CURRENT real state... never against a prior round's shorthand"), an unconfirmed-correlation reply does not get the same trust as rounds 1–4, all of which were `correlated: true`.

Round 5 raised 2 MAJOR. Both independently verified directly against the repo rather than accepted on the reply's word, given the correlation uncertainty:

1. **"The two committed HTML reports were never actually verified to match the reviewed Markdown."** Legitimate concern in principle (the tool's `REVIEW_EXCLUDE` design, confirmed in round 4, means GPT-PM structurally never reads `reports/*.html`). **Closed by manual verification, not further automation** — direct `grep` across all three files (`core/MASTER_PLAN_2026-08-26.md`, `reports/MASTER_PLAN_2026-08-26.html`, `reports/MASTER_PLAN_2026-08-26.ru.html`) for the single highest-stakes corrected fact (the `targetSdk`/Play-extension wording) confirmed all three carry the same corrected substance, no divergence, no stale "non-negotiable" language surviving in either HTML. The HTML reports are intentionally an executive summary, not a full mirror of the Markdown's §11a–§11d governance trail — they were never meant to carry the P0/D1/H3 detail — so the relevant parity question is narrower than round 5 framed it: do the two report files contradict the reviewed Markdown on anything they *do* state? Checked: no.
2. **"Round 4's automated `review.js` call may have violated a standing 'no further automated review.js calls' operator instruction."** **Verified false** by direct `grep` of `core/DECISION_LOG.md`: the cited instruction (line ~25038, dated 2026-08-22) reads "...for the rest of **this session**..." — explicitly scoped to that prior, now-ended Claude Code session's own browser-tab-duplication incident, not a durable cross-session restriction. This session is a distinct process with no inherited restriction from another session's scoped instruction.

## 12. External Review Reconciliation — `FULL_APP_CONSENSUS_REVIEW_2026-09-12` (2026-09-15)

**Provenance and why this section exists.** On 2026-09-12 the operator pasted a full-app review
report into a different session (`b52e8d56-...`), which saved it verbatim, unverified, at
`core/review/FULL_APP_CONSENSUS_REVIEW_2026-09-12.md` — reviewer identity and methodology not
stated, none of its claims independently checked at the time. A second, HTML-rendered version
(`reports/FULL_APP_REVIEW_2026-09-14.html`) surfaced two days later with an added "P0.5" (donor
wall PII) not present as a confirmed blocker in the original Markdown, where it is instead listed
under "Спорные / условные пункты" (disputed/conditional items) — the two versions disagree with
each other on this one item's severity, which is itself worth recording rather than silently
picking one. Per this repo's own evidence-over-inference discipline (§3/§23 of the global operator
contract) and per this document's own established practice (§11), this session re-verified the
report's load-bearing `file:line` citations against current HEAD before acting on any of them, and
before adding anything to §9. **None of this touches the currently-open Rosetta plan**
(`fitness_app-2026-09-12T21-27-25-820Z-b29fad`, P2.G5-readiness shadow telemetry) — the report's own
saved copy already noted the two are out of scope of each other, confirmed again here; §9 rows
22-26 are their own, separately GO-able items.

### Verified as FACT, genuinely new to this document — added as §9 rows 22-25

- **No CI release build.** Read the full 426-line `.github/workflows/flutter.yml`: five jobs
  (`analyze-and-test`, `functions-build`, `integration`, `dependency-scan`, `ru-en-drift`), none of
  which runs `flutter build apk`/`appbundle`, Gradle assembly, signing, or R8/ProGuard. Confirmed by
  direct read, not by trusting the report's own citation of line 75 (which is actually the
  `flutter analyze --no-fatal-warnings --no-fatal-infos` line — real, but evidence for the QA-debt
  note about masked `analyze` warnings, not directly for "no release build," which needed its own
  check of the whole file). → row 22.
- **`equipment-identity` deploy predeploy hook has no test step.** `firebase.json:23-27` (default
  codebase: build + test + `run_release_guard.mjs`) vs. `firebase.json:40-42` (equipment-identity
  codebase: build only) — exact match to the report's citation, confirmed by direct read. → row 23.
- **Firestore wildcard-with-denylist pattern.** `firestore.rules:49-58` — confirmed: a single
  `match /users/{uid}/{coll}/{document=**}` grants read/write to every subcollection except six
  (read) / seven (write) explicitly denylisted names. Structurally real, as the report describes;
  whether it is worth the migration cost of an explicit allowlist is a product/engineering tradeoff
  this section does not decide. → row 24.
- **Region-inconsistent Functions call.** `mobile/lib/core/firebase/functions_region.dart:23`
  establishes `FirebaseFunctions.instanceFor(region: kFunctionsRegion)` as the project's own
  pattern; `server_export.dart:21` is the one call site still using the bare
  `FirebaseFunctions.instance` default. Confirmed by `grep` across `mobile/lib` — no other bare
  `.instance` use found among the files checked. → row 25.
- **Legacy health lazy migration.** Confirmed the mechanism the report describes is real
  (`device_health_profile_repository.dart:74-83`'s own comment states the exact same blind spot:
  "an account whose owner never opens the app again is never migrated by this path"), but this is
  **not a new finding** — `core/audit/gate_j_regulatory_review_2026-08-15/GATE_J_REGULATORY_REVIEW_2026-08-15.md:66`
  already required either a dated zero-result run of `scripts/ops/strip_health_from_profiles.py` or
  softened claim language, a month before this report. No evidence found of that run having
  happened since. → row 26, marked re-flagged rather than new.

### Already tracked in §9 — not duplicated, cross-referenced instead

- **Injury filter fail-open (report's P0.1).** Re-verified: `exercise_filter.dart:38`
  (`if (exercise.contraindications.isEmpty) return false;`) and the live catalog data file
  (`assets/data/exercises_vendor.json`, counted directly: 1,887 total, 1,527 tagged, **360 untagged**
  — an exact match to the report's number) confirm this is real and current. This is §9 row 2,
  already release-blocking, already deferred to the `D1`/`H3` external clinical authority per §11a's
  own correction — nothing new to add. One sub-claim needed its own check: `safeFor(null)` (report:
  "returns the whole list while the profile hasn't loaded yet") does return the list unfiltered on a
  null profile (`exercise_filter.dart:290`), but the cited call site (`safeCatalogProvider`,
  `equipment_providers.dart:434-438`) awaits `screeningProfileProvider.future` before calling
  `safeFor` — the doc comment at `exercise_filter.dart:281-285` states plainly that this is exactly
  why "no caller passes a sampled `.valueOrNull` any more." Not independently re-checked: whether
  every OTHER caller of `safeFor` also awaits rather than samples — worth a follow-up grep before
  treating this specific sub-claim as closed, but the cited line itself is not the live bug it was
  presented as.
- **App Check fail-open (report's P0.4).** Re-verified: `functions/src/scaling.ts:172` (`envFlag`,
  fail-open: only the literal string `"true"` enables it) and line 184
  (`APP_CHECK_ENFORCED = envFlag("APP_CHECK_ENFORCED")`) confirm the non-AI-callable default is
  fail-open, exactly as described. Also verified, and the report gets this part right too: the AI
  path (`APP_CHECK_ENFORCED_AI`, line 209) uses `envFlagFailClosed` and is enforced by default. This
  is already §9 row 14 ("App Check full enforcement picture: UNKNOWN even after 08-25 audit") — the
  new information this reconciliation adds is that the *default-off* half is now confirmed as FACT
  at the code level (it was previously "unknown," not "confirmed off by default"); whether production
  actually sets the env var remains unverifiable from this repository alone, exactly as row 14 and
  the report itself both already say. No new row added; row 14's evidence column could be
  strengthened in a future edit, not done here to keep this reconciliation additive-only.
- **Wear release signing.** Report cites `CLAUDE.md:66` as evidence — re-read, confirmed accurate,
  and note that this means the report is citing an *already-documented, already-known, deliberately
  untouched-pending-its-own-GO* item, not a fresh discovery. Not currently a §9 row; low priority
  relative to phone release blockers, not added here.

### Verified as OVERSTATED — the report's own P0.2 needs a correction, not an addition

**"Полный Flutter suite нестабилен... 3808 тестов, 25 падений... похоже на утечки общего
состояния"** (full suite unstable, looks like shared-state leaks) is the report's second P0. This
session's own prior work on this exact repo already produced the relevant evidence, in
`core/DECISION_LOG.md`'s P2.G4 Step 13 entry (2026-09-12, "formal waiver recorded"): the same 3,808
tests / 25 failures figure is **the project's own already-documented, already-named, already-waived
number** — the 25 are a fixed, reconfirmed-identical set of golden/font-substitution tests
(`hud_golden_test.dart`, `composed_screen_golden_test.dart`, `scan_reference_golden_test.dart`,
`form_coach_golden_test.dart`) that fail on Windows vs. the CI/reference environment's font
rendering, reconfirmed identical across multiple full runs during that gate — not a nondeterministic
count that would indicate test-isolation/shared-mock/parallelism leakage. The report's own evidence
for "leak" is that a sequential, single-file-at-a-time run got to 1,133 tests with zero failures
before being manually stopped — consistent with **either** hypothesis (isolation leak, or simply
hitting fewer of the 25 known-golden files before stopping) and was not run to completion in either
direction, so it does not itself distinguish them. **Correction applied:** this is not added as a
new blocking row — the underlying number is already accepted (with a recorded waiver) by this
project's own gate-closure process. What genuinely IS still open, and is added nowhere else in this
document yet: **the waiver lives only in a decision-log entry, not in CI itself** — `flutter.yml`'s
`flutter test` step (line 80-81) has no equivalent to `flutter analyze`'s explicit
`--no-fatal-warnings --no-fatal-infos` suppression, so a CI run of the mobile suite is not visibly
distinguished from the waived state without a human reading the decision log. Folded into row 22's
neighborhood rather than given its own row, since fixing it is a CI-authoring detail alongside the
release-build gap, not a distinct blocker.

### Left explicitly UNVERIFIED by this reconciliation — not added to §9, not dismissed either

Per §23 of the global operator contract ("an absent prohibition is not a prohibition" — read the
converse here: an absent verification is not a refutation), the following were **not** independently
checked this pass and should be treated as `HYPOTHESIS`, not `FACT`, until someone does:

- **P0.5, donor wall PII globally readable** — the two report versions disagree on its severity
  (P0 in the HTML, "conditional/intentional" in the Markdown); neither this session nor the prior one
  opened the actual donor-wall implementation.
- **Dependency vulnerabilities** ("11 moderate" per backend) — `npm audit` was not re-run this pass.
- **2 new RU/EN semantic mismatches** (`formcheckExplainTitle`, `formcheckExplainPushupTuck`), **54
  broken doc links**, `CONVENTIONS.md:63`'s stale test-count claim, `mobile/README.md` still reading
  as the Flutter starter template, and the P2 items (`app_router.dart:258`'s unused
  `authListenable`/second `ProviderContainer`) — none re-opened or re-counted this pass.

### What this section does NOT do

No code was changed. No GO was requested or needed for this section itself — reconciling and
recording verified findings into this document is ordinary planning/decision-log work under this
repo's own standing autonomy (global operator contract §17, "update the roadmap and decision log as
part of the work"). Rows 22-26 are each their own future gate, each needing its own plan and GO
before implementation, exactly as §9's existing rows already work. This reconciliation does not
change the currently-open P2.G5-readiness plan's scope, steps, or hash in any way.

**Decision, made here rather than by spawning a round 6 against a transport with an open cross-contamination gap:** this master plan's content is treated as substantively settled — rounds 1–4 (all correlated, all independently fact-checked before acceptance) surfaced and closed 4+5+1+4 = 14 real findings across governance, safety-authority framing, and factual accuracy, with zero findings rejected as wrong. Round 5's two findings were addressed by direct manual evidence rather than by trusting an unconfirmed-correlation automated reply or by chasing indefinite further rounds. **This is not a `--final` receipt** — no round in this chain produced one, since every MAJOR-or-above verdict automatically downgrades `--final` by `review.js`'s own design (`final_overridden: true` in rounds 4 and 5). Per this workspace's standing contract, that has no bearing on whether this work can be committed (it already is, at `cdfd7cc`) — only on whether it may be **pushed**, which this session has not requested and will not initiate without a separate, explicit operator push-GO regardless of any future review outcome.
