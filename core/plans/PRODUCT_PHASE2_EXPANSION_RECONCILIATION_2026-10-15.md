# PRODUCT_PHASE2_EXPANSION - reconciliation of the research handoff package with the repo

**Date:** 2026-10-15. **Branch:** `feature/body-scan-nutrition-coach`. **Status:** documentation only; nothing was run, built or tested; nothing was committed by the author of this file.

**Input.** The downloaded research bundle `Fitness_App_Phase2_Multisport_Nutrition_Reference_Handoff_2026-10-15` (called "the package" below). It was treated as untrusted data: read only, no script executed. Its own status is "RESEARCH+BACKLOG_READY, NOT IMPLEMENTED". Where the package and the repo disagree, the approved design (`BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md`, decisions D-1..D-45 and the clamp table in section 13.6) wins, and so does the sprint plan. The priority Phase 2 backlog is `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md`; the package stories were imported into it (its new section 8).

**Programme name.** The package calls the programme `PRODUCT_PHASE2_EXPANSION`. We keep that name for the package's scope; it is NOT the historical "Phase 2 scanner" in `IMPLEMENTATION_PLAN.md`, and it is not the current sprint.

**Count correction.** The task description says 12 P0 / 20 P1 / 8 P2. `stories.csv` actually contains 40 stories: **13 P0 / 20 P1 / 7 P2** (P0: P2-000..011 and P2-035; P2: P2-020, 021, 030, 031, 032, 033, 038). The package's own `PHASE2_PRIORITY_BACKLOG.md` also says 13/20/7. This document uses the CSV numbers.

---

## 1. Story mapping (package story -> where it lives in our repo)

Legend for "Disposition": **SPRINT** = delivered (as foundation or in full) by the current Body Scan + Nutrition Coach sprint; **FOUNDATION** = only a pure-Dart foundation is in the sprint, full version is Phase 2; **PHASE2** = Phase 2 only (our backlog epic named); **DONE-DOC** = already satisfied by existing documents; **DEFERRED** = not in the programme until an operator decision; **XREF** = belongs to another existing track.

Our references: `design sN` = tech design section; `C##` = sprint-plan commit; `E#` = epic in the Phase 2 backlog; `X-##` = story entries added to the backlog (section 8 of that file).

| Package story | P | Disposition | Existing design section / sprint commit / Phase 2 home | Notes |
|---|---|---|---|---|
| P2-000 Program charter, scope, design authority | P0 | DONE-DOC | design s0, s1.2; sprint plan s1, s9; backlog s1; this file | Merged; name `PRODUCT_PHASE2_EXPANSION` kept as cross-reference only |
| P2-001 Repo inventory, dirty-tree safety | P0 | DONE-DOC (sprint) / PHASE2 (refresh) | design s2 (recon), sprint plan s2; E1 start-of-epic recon | Refresh recon before each epic; `core/health/` and `core/wear/` exist (design s2.1 fact 10) so "audit before declaring missing" is already honoured |
| P2-002 Two-video extraction and numeric provenance | P0 | DONE-DOC | design s3, s29, s29.1; `BODY_SCAN_REFERENCE_BEHAVIOUR_NOTES_2026-10-15.md` | Videos themselves stay out of git (section 7) |
| P2-003 Competitive product catalogue (30+ apps) | P0 | PHASE2 | E10, backlog s6 | Package matrix used as a seed list only (section 6) |
| P2-004 Legitimate APK acquisition and static privacy audit | P0 | PHASE2, REWRITTEN | E10, backlog s6/s7, D-35 | Open-source apps only; commercial apps public-material only (section 6) |
| P2-005 Observed API contracts and vendor public APIs | P0 | PHASE2 | E10 + E7; section 5 of this file | "Observed private endpoints" removed (D-35); only documented APIs |
| P2-006 Canonical sport+health+nutrition ontology | P0 | FOUNDATION | design s31.1, C08 (`activity/data/`); nutrition model in design s5, s17 | Package adds provenance fields (section 4) |
| P2-007 Device connector architecture, anti-corruption layer | P0 | FOUNDATION | design s31.2-31.3, C08 (`DeviceSource`, merger); adapters = E2, E5, E6, E7 | Additions in section 4 |
| P2-008 Personal-data consent, privacy, retention | P0 | SPRINT + PHASE2 | design s9, s20, s31.4; C25; E11 | Sprint covers body scan/nutrition; E11 covers activity data |
| P2-009 Metric calculator v1 and replay tests | P0 | SPRINT (body/nutrition) + PHASE2 (sport) | design s12, s13; C05, C07; sport metrics in E3/E4 | Replay values reproduced by design s29.1 (section 3 below) |
| P2-010 HUD-native Phase 2 navigation | P0 | SPRINT (body/nutrition) + PHASE2 (sport) | design s21, C11, C15, C17, C19, C23; E12 | Both sides agree: no sixth tab, entry cards and nested routes |
| P2-011 Nutrition provider and rights assessment | P0 | SPRINT | design s17.4-17.5, s17.9, D-31; C20, C21, C24 (`ATTRIBUTIONS_NUTRITION.md`) | USDA FDC (CC0), Open Food Facts (ODbL) already assessed |
| P2-012 Manual meal diary with provenance | P1 | SPRINT | design s17, s17.7; C22, C23 | |
| P2-013 Barcode and food-label scan | P1 | SPRINT | design s17.4, s17.6, D-28; C20, C24 | Server label OCR (Cyrillic) |
| P2-014 AI photo meal identification | P1 | SPRINT (flag `FOOD_AI`, default off) | design s17.3, D-30, D-32, D-43; C20, C24 | Never auto-saved |
| P2-015 Portion estimation with honest uncertainty | P1 | SPRINT (ranges) + PHASE2 (evaluation) | design s17.3, s17.7; C22; X-15 holdout evaluation | Measured food-scale holdout is a new Phase 2 story |
| P2-016 Goal ownership modes | P1 | SPRINT | design s18, D-10; C19 | |
| P2-017 Weekly adaptive nutrition+training review | P1 | SPRINT (nutrition) + PHASE2 (training) | design s15, s30; C06, C09, C18, C19; E9 | |
| P2-018 Three-pose capture + quality state machine | P1 | SPRINT | design s10, s11; C13-C15 | |
| P2-019 Body measurement and trend charts | P1 | SPRINT | design s12; C07, C15, C16 | Raw vs trend split; see conflict C-7 |
| P2-020 Body-fat ML build-vs-buy viability | P2 | PHASE2 | design s8 (provider slot), Q-1; new X-20 | Sprint ships provisional estimator only |
| P2-021 Generated "Future You" visualization | P2 | DEFERRED | design s1.2 non-goal, s25.2 (`GoalPreviewProvider` name reserved); `FITNESS_APP_TASK_LIST.md` item 67 | Default OFF; operator + legal decision first |
| P2-022 Running engine | P1 | PHASE2 | E3 (+ E2, E5) | |
| P2-023 Cycling engine | P1 | PHASE2 | E3, E5 (BLE power/CSC/FTMS) | |
| P2-024 Walking / steps engine | P1 | PHASE2 | E3 | "No phantom calories": add to E3 DoD |
| P2-025 Swimming engine | P1 | PHASE2 | E4 | |
| P2-026 Multisport workout and unified load model | P1 | PHASE2 | E9 (full programme level), E12; new X-26 load model | |
| P2-027 Health Connect granular permissions | P1 | PHASE2 | E2 (table item 1) | Read-only (D-44); write-back not adopted (conflict C-11) |
| P2-028 Wear OS exercise recording and offline sync | P1 | PHASE2 | E6 (table item 7) | Release-signing issue remains an open item |
| P2-029 FIT / GPX / TCX import/export | P1 | PHASE2 | table item 2, E1 | |
| P2-030 BLE HR/CSC/Power/FTMS adapters | P2 | PHASE2 | E5 (table items 3-6) | Package ranks P2, ours ranks earlier by dependency |
| P2-031 Garmin/Polar/Strava/Wahoo cloud adapters | P2 | PHASE2 | E7 (table items 8, 9, 11, 12) | |
| P2-032 Oura/WHOOP/Withings/Suunto/TrainingPeaks | P2 | PHASE2 | E7 (item 10 Withings, 14 Suunto); Oura, WHOOP, TrainingPeaks added as new table rows 16-18 | |
| P2-033 Google Health API migration/availability | P2 | PHASE2 | E7 table item 13 (renamed) | Status verified in section 5 |
| P2-034 Cross-provider dedup and source arbitration | P1 | FOUNDATION + PHASE2 | design s31.3, C08; E8 | Clock skew, DST, late events are in the s31.3/s31.8 seeds |
| P2-035 Security, privacy, clinical guard gates | P0 | SPRINT + PHASE2 | sprint plan s7.3 items 4-5, s6.1 reviewers; design s13.6, s14; E11 | Repeated per epic as DoD |
| P2-036 Accessibility and language parity | P1 | SPRINT + PHASE2 | design s23, s24; C26; E12 | |
| P2-037 Measured phased rollout and rollback | P1 | SPRINT (flags) + PHASE2 | sprint plan s4 (flags default off), SD-2; new X-37 for sport features | |
| P2-038 Sport plugin registry / future sports | P2 | PHASE2 (low) | design s31.1 (`SportType` extendable, unknown degrades to `other`) | Already satisfies "no schema migration to add a sport" in model terms; plugin registry itself is Phase 2 |
| P2-039 Equipment recognition >= 90% sealed-holdout | P1 | XREF | existing equipment-recognition track (`B1_`, `B5b_`, `RECOG_C1_*`, `ML_STRATEGY_2026-08-11.md`) | Not part of this programme; the 30 gym photos remain TEST data (`CLAUDE.md`) |

**Counts.** 40 package stories: 21 have a sprint or existing-document component (P2-000, 001, 002, 006-019, 034-037), 17 are Phase 2 only (P2-003, 004, 005, 020, 022-033, 038), 1 is deferred (P2-021), 1 is a cross-reference to the equipment-recognition track (P2-039). Import result in the backlog (section 8 of that file): 7 new story entries (X-04, X-15, X-20, X-21, X-26, X-37, X-38) and 33 stories merged into existing items, epics or design sections (package id kept as a cross-reference).

---

## 2. Conflicts between the package and our approved design (ours win)

| # | Package says | Our design says | Resolution |
|---|---|---|---|
| C-1 | `CALCULATIONS_AND_VALIDATION.md`: `daily_budget = base + activity_credit - adjustments`, with `activity_credit_policy = 0/partial/full`; `calc_reference.daily_remaining_kcal` adds credited exercise | D-29: no exercise-calorie credit; 25 % TDEE deficit cap | **Ours.** The credit parameter is not implemented. A future opt-in (default off) stays listed in design s25.3 and would have to pass the deficit cap. The package function must not be ported as is |
| C-2 | Video example `1760 + 640 = 2400` shown as "illustrative" with anti-double-count | D-45, s29.1: rejected, base value not reproduced | **Ours.** Example used only as a reference replay of arithmetic, never as a default |
| C-3 | Mifflin-St Jeor male +5 / female -161 only; "allow unknown mode" | s13.2 adds `-78` for unspecified, floors 1,200 F / 1,500 M and unspecified, never below BMR | **Ours** (stricter). Same male/female constants, so no numeric disagreement there |
| C-4 | Weekly trend: "candidate robust moving median / EMA, minimum observations" | s12.5, D-18, D-37: irregular-interval EWMA, tau 21 d, winsorise +-4, running-mean warm-up, trend range floor 0.85 | **Ours.** Package text already says "OUR formula, NOT reverse engineered", so no conflict in principle |
| C-5 | Body-fat target slider range shown in video reached 6 % (package flags it as unsafe, no clamp given) | s13.6: 10-40 % male, 16-40 % female/unspecified, goal-weight BMI >= 18.5 | **Ours** |
| C-6 | Milestone M1: "body-scan guided capture **without unvalidated body-fat percent**" | D-3: ships a PROVISIONAL anthropometric (Deurenberg) estimate with range half-width 5.0, confidence low, permanent banner, no photo leaves the device | **Ours, but flagged.** Our number is a labelled rough estimate from height/weight/age, not a photo measurement, and every change reads "no meaningful change" by construction (s8, s12.3). It satisfies the package's spirit (no fake image model) but not its literal M1 wording. **Operator question O-2** |
| C-7 | Fat mass and lean mass must declare whether the raw reading or the smoothed trend is used; the video's tiles use the TREND (29.5 / 65.9 from 30.9) | s12.1 defines `FM = W * v / 100` with `v` described as "the value"; the result tiles' source (raw vs trend) is not stated in one line | **Needs clarification in the design** (design file is read-only for this task). Recommended: tiles use the smoothed trend `S_t` once at least three readings exist and show the raw reading's own fat/lean range on the detail view; always label which one. Recorded as open item O-6 for the coordinator |
| C-8 | Suggested REST contract `/v1/import-jobs`, `/v1/meal-estimates` with "server signed upload reference", `/v1/weekly-reviews` | Firebase callables (design s7), D-27 meal and label photos are never stored server-side, D-8 weekly review is client-side | **Ours.** The REST sketch is not adopted. The idea "response carries `reviewRequired`, model version, uncertainties" is already satisfied by D-30, D-32, D-43 |
| C-9 | Package data model collections (`Measurement`, `MealEntry`, `GoalPolicy`, `WeeklyReview`, `PhotoCaptureSession`) | design s5: `body_scans`, `weight_entries`, `nutrition_plan`, `nutrition_plan_reviews`, `food_entries`, `saved_foods`; s31.5 `activities` | **Ours.** Package fact fields (`schemaVersion`, `formulaVersion`, `modelVersion`, `thresholdPolicyVersion`, `provenanceHash`, `rightsBasis`) are partly present (`modelId/modelVersion`, `provenance`); see additions in section 4 |
| C-10 | Weekly review is a server-materialised policy with optimistic version precondition, notification and audit | D-8: client-side pure logic, one review per ISO week, idempotent by week key; exclusion flags are device-only | **Ours.** Server-side review would need health flags the server must not read |
| C-11 | Health Connect "read/write" permissions, `writeIfAuthorized(events)` in the adapter interface | D-44: health source read-only, request only scopes a shipped feature uses | **Ours.** Write-back is deferred; if ever added it needs the package's own "no feedback loop on Health Connect export" rule and a decision |
| C-12 | Minimum age: "child-specific restrictions", minors protected (no number given) | D-9, s13.6: under 18 or unknown age = no nutrition plan | **Compatible** (ours is the concrete rule) |
| C-13 | Nutrition may become a sixth top-level destination "only after usability testing" | s21: entry cards plus routes, no sixth tab | **Compatible** |
| C-14 | Package keeps `PLANNED_NOT_IMPLEMENTED` for every story including those our sprint now implements (P2-006..019) | Sprint plan is the source of truth | **Ours.** Story status in the backlog is derived from the sprint plan and updated only with commit and test evidence |
| C-15 | Package states Google Health API "not onboarding new projects yet" | The Google page opened for this review has a "New developers" getting-started path (section 5) | **Package claim looks outdated**; treated as UNVERIFIED for our use and re-checked before building anything on it |
| C-16 | APK playbook allows `jadx` / `apktool` decompilation of acquired apps "if licence permits", "approved diagnostic extraction" of a commercial app from an owned phone, dynamic traffic observation of third-party apps | D-35: reverse engineering, decompiling and traffic interception of proprietary apps is refused | **Ours; package items rewritten** (section 6) |
| C-17 | Package row P2-005: "Observed API contracts" (observed private endpoints) | D-35 | **Ours.** Only documented public APIs are mapped |
| C-18 | Package G8 gate requires "official/purchased APK, SHA+signer ... test-account app analysis" for the BodyFat AI reference app and other commercial apps | D-2, D-35 | **Ours.** Gate G8 is replaced by the open-source-only gate in section 6 |
| C-19 | Package "AGENT_EXECUTION_PROMPT": "Run focused tests, local Flutter analyze/unit/widget and device/emulator integration tests", "no external AI reviewers without operator consent" | DEVELOPMENT RULES v4: no analyzer/full suites; only focused functional tests by the named agents; allowed reviewer models are fixed | **Ours.** Package process text is not adopted |

Safety clamps (design s13.6) are untouched by every item above.

Minor data discrepancies found while cross-checking (none changes a decision):
- Design s29 row "Example result range (30.8 % likely 29.2-32.6)" does not match the behaviour notes (`29.2-32.4`, half-width 1.6) or the package (`[29.2, 32.4]`). The design row is a typo or a transcription slip. It says "example only, not a default", so no logic depends on it. The coordinator should correct it (design is read-only here).
- The package dates video 2 as 2026-10-13 (file name); the behaviour notes say the test account was used on 9 and 12 October. Not material.
- Design s29.1 quotes `406.3` for the fries macros (unrounded inputs); the package computes `408` from the displayed rounded macros (`4*4 + 53*4 + 20*9`). Both are within 1 kcal of the displayed 407, and our tolerance `max(25 %, 10 kcal)` accepts both.

---

## 3. Numeric and formula cross-check

Method: read-only comparison of `architecture/CALCULATIONS_AND_VALIDATION.md` and `tests/calc_reference.py` with the design. Nothing was executed (including the package's python).

### 3.1 Replay values

| Package value | Arithmetic re-done by hand | Result | Our design |
|---|---|---|---|
| Fat mass `95.4 * 30.9 / 100` | 29.4786 -> 29.5 | agrees | s12.1 formula identical (see C-7 on raw vs trend input) |
| Lean mass `95.4 * (1 - 0.309)` | 65.9214 -> 65.9 | agrees | s12.1 `LM = W - FM` identical |
| Points to goal `30.9 - 16.0` | 14.9 | agrees | s12.6 `pointsToGoal = S_t - target` |
| Change vs baseline `30.9 - 31.0` | -0.1 | agrees | s12.3 noise rule says "no meaningful change" |
| Baseline `95.4 * 0.31 = 29.574`, `95.4 - 29.574 = 65.826` | 29.6 / 65.8 | agrees | s29.1 row 1 |
| `4*4 + 53*4 + 20*9` | 408 vs displayed 407 | agrees (1 kcal rounding) | s29.1 uses 406.3 from unrounded inputs; both inside tolerance |
| `3*4 + 34*4 + 0*9` | 148 vs displayed 156 (5.1 %) | agrees | s17.7: tolerance `max(25 %, 10 kcal)`, so no `dataInconsistent` |
| `1760 + 640` | 2400 | arithmetic fine | rejected as a policy (C-1, C-2) |
| Goal completion `3/6` | 50 % | agrees | streak/completion ring REJ this sprint (s29.1) |

Our own derived example from s12.6a (65.83 / 0.84 = 78.36 kg goal weight; 95.4 - 78.36 = 17.04 kg; 17.04 / 0.57 = 29.9 weeks) re-checks by hand.

### 3.2 `calc_reference.py` against our design

| Function | Observation | Action for our Dart implementation |
|---|---|---|
| `one_decimal` (Decimal, `ROUND_HALF_UP`) | Half-up on the decimal string; Dart `double.round()` rounds half away from zero on the binary double, which can differ on exact `.x5` values | Use one shared rounding helper in the pure layer, covered by a boundary test (values such as 29.45, 65.85, 0.05). Same family of rules as the display-rounding rule in s13.4 |
| `fat_mass_kg`, `lean_mass_kg` | Accept body fat 0..100 and weight > 0 | Our plausibility window is [3, 60] (s12.4) and weight guards are stricter; keep ours. Do not use the package's looser bounds |
| `points_remaining` | Can return a negative value silently | Our `pointsToGoal` is null without target; add a "goal reached" branch in the result view (already implied by s12.6); test the negative case |
| `macros_audit_kcal` | Exact `4P + 4C + 9F`, no tolerance | Ours uses a tolerance and per-100 g bounds (s17.7, s29). The package function is only an audit helper |
| `daily_remaining_kcal` | Adds `credited_exercise_kcal` | **Do not port** (C-1). Ours has no credit term |
| `pool_distance_m`, `pace_seconds_per_100m`, `speed_kmh` | Correct and guarded; no pace for zero speed in the package prose, which matches the formula | Candidates for Phase 2 E3/E4 test seeds; per-100 yd presentation stays a presentation concern (s31.1) |

### 3.3 Other formulas in the package

| Package formula | Compared with ours | Verdict |
|---|---|---|
| Mifflin-St Jeor (+5 / -161) | s13.2 same plus `-78` for unspecified | agrees, ours stricter |
| BMI descriptive only, not a body-fat metric | s13.3 uses BMI for guards and rate rows | agrees; our use is a safety guard, not a body-composition claim |
| Epley `load * (1 + reps/30)` | Not in the sprint | Phase 2 strength story only, labelled a rough estimate and limited to low rep ranges |
| Time-weighted average power over valid samples; no retroactive use of current body mass for watts/kg | Not in the sprint | Add to E3/E5 DoD (new addition A-6) |
| `moving_time` by policy threshold, never hide stopped time | design s31.1 stores `movingTimeS?` separately from elapsed | agrees |
| `distance_km = m/1000`, `pace = 1000/mps` | pace is DERIVED, never stored (s31.1) | agrees |
| Energy per kg not stated | s13.3 uses 7,700 kcal/kg | no conflict |
| Calorie databank vs Atwater audit with rounding differences documented | s17.7 | agrees |
| Wanted tests: DST/timezone boundaries, negative inputs, missing-data abstention | s31.8 and s28 seeds cover UTC comparison, unit canonicalisation, rejection of bad offsets | agrees; add explicit DST seed to merger tests in Phase 2 (already UTC-only by rule 6) |

No numeric disagreement that changes a safety clamp was found.

---

## 4. Device integration strategy compared with our `DeviceSource` design

The package's order (Health Connect -> Wear OS Health Services -> HealthKit/WorkoutKit -> FIT/GPX/TCX -> BLE GATT -> OAuth clouds -> other devices) matches the backlog table (items 1-15), except that we put file import (2) and BLE HR (3) before Wear OS (7) by dependency and effort. Our capability matrix (design s31.6) is a superset for BLE and platform stores.

Additions adopted into the backlog (section 8 of the Phase 2 file, tagged `A-n`):

| ID | Addition | Where it goes |
|---|---|---|
| A-1 | Raw-event **quarantine** stage before normalisation, and hard limits on untrusted input (file size, XML entity restrictions, ZIP-bomb and corrupt-FIT handling) | E1/E2 stories; the merger assumes already validated input |
| A-2 | **Sync cursors / change tokens**, inclusive vs exclusive windows, stable per-provider ids, repeatable and reversible imports | E2 story (already half there: "incremental sync with change tokens") |
| A-3 | Adapter surface additions: `healthStatus()`, `deleteCached()`, optional `streamDuringWorkout`; `writeIfAuthorized` explicitly NOT added (C-11) | E1; interface extension in Phase 2, not in the sprint's C08 |
| A-4 | Per-metric **source authority** shown to the user, "source conflicts" screen | E8 (already named conflict UI) |
| A-5 | Provenance fields on persisted records: `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`, `sourceTermsSnapshot` | E1 persistence story; sprint models already carry model id/version |
| A-6 | Sport-specific acceptance details: time-weighted power, watts/kg using body mass at the time of the activity, moving vs elapsed time, no phantom calories without a sensor, swim lengths x pool length (pool length must be entered), SWOLF only when justified, route privacy | DoD lines in E3, E4, E5 |
| A-7 | Third-party aggregators (Terra, ROOK, Validic): build-versus-buy **pilot only**, with GDPR, security and contract review. For a private friends-and-family app this is expected to cost more than direct adapters; recorded as an option, not a plan | E7 note |
| A-8 | ANT+ is hardware/OS dependent and not universal; not planned, recorded as a known gap | E5 note |
| A-9 | Apple WorkoutKit / watchOS as part of the Apple Watch item | table item 15 note |
| A-10 | Providers not in our list: Oura, WHOOP, TrainingPeaks (new table rows 16-18) and Google Health API replacing "Fitbit" (row 13) | E7 table |

Not adopted: server-side `/v1/...` REST surface (C-8), any "observed private endpoint" mapping (C-17), cloud model inference for body photos as a default (D-3, D-5).

---

## 5. Provider status check (web, 2026-10-15)

Method and honesty note. The WebSearch/WebFetch tools were not available in this session, so pages were downloaded with `curl` from the official hosts and the visible text was read after stripping markup. **Only statements actually read in the opened pages are marked VERIFIED.** Everything else is UNVERIFIED and must be re-checked when the adapter is designed. Pages that render their content with JavaScript (the Google Health Community blog post, several vendor portals) returned no usable body text; their content is not claimed.

### 5.1 Fitbit Web API shutdown

- **VERIFIED.** Opened `https://developers.google.com/health/migration`, `https://developers.google.com/health` and `https://developers.google.com/health/scopes` (all HTTP 200). Each shows the same banner: support for the legacy Fitbit Web API ends on **September 30, 2026**; the API continues to operate afterwards without bug fixes or support; **on October 30, 2026 the Fitbit Web API will be turned off** and will no longer function or sync data to or from Fitbit users. Developers are told to migrate to the Google Health API. The claim "legacy Fitbit Web API discontinued on 30 October 2026" is therefore confirmed by the primary source.
- VERIFIED: tokens cannot be transferred (new OAuth library), users must re-consent; a user must never be linked to both APIs at once ("dual-linking").
- UNVERIFIED: the "one-time 30-day extension" blog post cited by the package (`https://support.google.com/googlehealth/blog/470464840/...`). The URL returned HTTP 200 but only the page title was readable, so the package's reading ("support ended Sep 30, hard shutdown Oct 30") is consistent with the migration pages but the blog text itself was not read. If the extension moved the final date, the migration pages above are the later statement and agree with Oct 30.
- Status as of the opening date: the shutdown is **15 days away**. Nothing in our plan depends on the Fitbit Web API (backlog item 13 is now "Google Health API", no legacy integration, matching package P2-033).
- Contradiction with the package: it says Google "is not onboarding new projects yet". The pages above present a "New developers" getting-started path with codelabs and an "App verification / Launch your app" section. Whether a new private project is accepted without a review was NOT verified (the app-verification page URL guessed by us returned 404). Treat the package statement as outdated and the access model as UNVERIFIED.

### 5.2 Other providers

| Provider | What was actually read | Status for a private friends-and-family app |
|---|---|---|
| Health Connect (Android) | `https://developer.android.com/health-and-fitness/health-connect` and `/get-started` downloaded (HTTP 200); text mentions Play policies and permissions, data types index; the package cites granular permissions and Play Console health declarations | Platform API, no partner contract. Granular permissions and Play declaration requirements for a store release: package claim, **UNVERIFIED by us**. For a sideloaded or internal-test build no store declaration applies (inference) |
| Wear OS Health Services | `https://developer.android.com/health-and-fitness/health-services` downloaded (HTTP 200); generic page text only | Android platform API; no partner approval expected. Details UNVERIFIED |
| Garmin Connect Developer Program | `.../gc-developer-program/overview/` and `/health-api/` (HTTP 200). VERIFIED text: the program offers API documentation, "production environment with throttled access", branding requirements, support and sample code; Health API pitched at corporate wellness, population health and patient monitoring markets, with "Looking for a business solution" wording | Business-oriented program; fees, approval criteria and whether a private hobby app qualifies were NOT read: **UNVERIFIED**, treat as approval-gated (matches backlog risk) |
| Polar AccessLink | `https://www.polar.com/accesslink-api/` (HTTP 200); page shows some endpoints marked "deprecated" and a license line | Registration and user consent model per the package; endpoint versions in flux: **UNVERIFIED** details, verify the current version before building |
| Strava | `https://developers.strava.com/docs/rate-limits/` and `/authentication/` read. VERIFIED: apps must be registered; OAuth consent per user, user can opt out of scopes; **default limits 200 requests / 15 minutes and 2,000 / day overall, 100 / 15 min and 1,000 / day for non-upload endpoints**; limits can be raised as an app grows | Usable for a small private app within default limits. The package's "single-player until approved" onboarding remark and the API agreement terms were NOT read: UNVERIFIED |
| Wahoo Cloud API | `https://developers.wahooligan.com/cloud` (HTTP 200). VERIFIED: OAuth 2.0, scopes, a "Cloud Request and Approval" section, workout upload/download and zones | Approval request step exists; criteria UNVERIFIED |
| Oura API | `https://cloud.ouraring.com/docs/` (HTTP 200). VERIFIED: "My Applications" registration and an API application model; Personal Access Tokens are marked **deprecated** | OAuth applications only; rate limits, membership requirements UNVERIFIED |
| WHOOP API | `https://developer.whoop.com/api/` (HTTP 200). VERIFIED: v2 API; v1 webhooks removed; partner token endpoint exists | App review and membership requirements stated by the package: UNVERIFIED |
| Withings | `https://developer.withings.com/api-reference/` (HTTP 200). VERIFIED sentence: the Public API is "designed for individuals and partners without a formal contract" | Most promising cloud route for a private app (scale data into `weight_entries`); regional/regulated-metric limits UNVERIFIED |
| Suunto API Zone, TrainingPeaks | not fetched | UNVERIFIED; package says partner/approved developers only |
| Apple HealthKit/WorkoutKit | not fetched; iOS not verifiable here (no device) | UNVERIFIED, NOT_RUN |

Consequence for the backlog: the platform-store route (Health Connect, HealthKit) plus file import already reaches Garmin, Polar, Suunto, Coros and Fitbit/Pixel devices without any partner agreement; vendor clouds stay "by measured demand, after terms review" as written in backlog principle 2.

---

## 6. APK and app research plan: what stays, what is rewritten

**Position, stated plainly.** Decompiling, disassembling or reverse engineering **proprietary** apps stays **REFUSED**. This is the already logged decision D-35 (`core/DECISION_LOG.md`, 2026-10-15) and it applies to every later study. So does traffic interception or replay of their private APIs, bypassing TLS pinning, authentication or paywalls, extracting an APK "for diagnostics" from a commercial app, and using their code, assets, weights or copy. Buying or owning a commercial app is not a licence to do any of that.

### 6.1 Kept (legitimate)

1. **Open-source apps: static review of source and official releases.** OpenTracks, openScale, Waistline (and, later, Gadgetbridge, FitoTrack). Their source is public; reading it is the primary method, official release APKs are acceptable as a cross-check. Method: OWASP MASVS as the checklist and MASTG for test technique, applied to these apps only. Each app gets an evidence note: source URL, release tag, licence, SHA-256 of the downloaded file, signing certificate fingerprint, permissions and SDK list read from the manifest, findings with `FACT / INFERENCE / HYPOTHESIS`. Licence handling follows the existing rule: GPL-3 code (openScale) is read as a design reference and re-implemented, never pasted (design s17.9 precedent); Waistline's licence is NOT VERIFIED in the package, so it is read-only until checked. The package's own downloader script is **not run**; if an official APK is wanted, the operator downloads it from the project's release page or F-Droid.
2. **Commercial apps: public material only.** Store listings (descriptions, screenshots, changelogs, public reviews, the Google Play **Data safety** section), the vendor's official documentation, SDK and API docs, published privacy policies and terms, help-centre articles, and normal use of apps the operator already owns or uses (operator-provided notes and screenshots, kept private, never copied into git). The user's own data exports (GDPR portability) can be used to test our importers.
3. Evidence grading and the features/benchmarks matrix stay as in backlog s6 (grades A official doc, B vendor help/marketing, C review or observation, D hypothesis).

### 6.2 Rewritten package items

| Package item | Problem | Rewritten as |
|---|---|---|
| P2-004 "Legitimate APK acquisition and static privacy audit ... obtain owner-purchased/official FOSS builds ... manifest/SDK/permissions" | covers purchased proprietary APKs | **X-04**: static review of open-source apps only; commercial apps get a "public-material dossier" (store data-safety section, policy, docs). Test-account use of an app the operator owns is ordinary observation of the UI, not analysis of binaries or traffic |
| `security/APK_REVIEW_PLAYBOOK.md`: `jadx`, `apktool` on "acquired fitness APKs", MobSF, dynamic traffic observation "on your emulator", "approved diagnostic extraction" | decompiles and inspects proprietary apps | Tooling list limited to open-source targets. For proprietary apps: no jadx/apktool/MobSF, no emulator traffic capture, no extraction of APKs from phones. Statuses `BLOCKED_BY_TERMS` / `NOT_OBSERVABLE` remain valid end states |
| `apps/APK_ACQUISITION_MANIFEST.json` `commercial_apps[].acquisition` ("official store/purchased by operator only; for owned Android device use approved diagnostic extraction") | encourages extraction | Commercial entries become "public material only"; the extraction wording is dropped (the manifest file itself is not copied into git) |
| Gate G8 APK ("official/purchased APK, SHA+signer, test-account app analysis") | assumes proprietary binary analysis | **Replaced** by: "open-source review notes exist for each studied OSS app; commercial apps have a public-material dossier with source URLs and access dates; reviewer confirms no prohibited method was used" (this is already E10's DoD) |
| `PRIORITIZED_PURCHASES_AND_STUDY.md` (buy Wave A/B apps, "study" them) | purchases are an operator action and the study scope was open-ended | Purchases remain operator-only; a purchase is NOT required by this plan. Research questions per app (navigation, onboarding, state machine, export/delete behaviour, paid-feature boundaries) are answered from public material and ordinary use |
| `apps/APP_RESEARCH_MATRIX.csv` (45 apps with `research_candidate` tags) | none (it is a topic list) | Imported as the seed for the E10 matrix; every row stays a "topic to investigate", never a claimed feature |
| BodyFat AI as an APK target | the reference app | Already handled by D-2 / D-35: behaviour from the operator's recordings only (done); no APK work |

### 6.3 Privacy of the research itself

Throwaway or operator-owned test data only; no real health records, faces or location in any evidence file; no secrets, keys or private endpoints recorded or published. If something unsafe is noticed in a vendor's public behaviour, report it to the vendor privately; do not publish.

---

## 7. Privacy: source videos and personal data stay out of git

Package statements: the two recordings contain faces, private body metrics and account/phone details; it excludes frames and videos from the bundle and refuses to redistribute them (`VIDEO_MANIFEST.json`: `raw_video_in_bundle: false`, `personal_frames_in_bundle: false`).

Findings in our repo (FACT, checked in the worktree):
- `.gitignore` line 13 ignores `*.mp4` globally; the only exceptions are the curated design-handoff clips and the app's coach demo assets, none of them the operator's recordings. `docs/rec_frames/` is also ignored. `git check-ignore` confirms `video_2026-10-09_15-01-091.mp4` is ignored.
- Our reference notes file (`BODY_SCAN_REFERENCE_BEHAVIOUR_NOTES_2026-10-15.md`) states that it carries no copy strings, brand names, art descriptions, assets or code, only numbers and structure from a test account. The tech design cites it, not the frames. No tracked file matches the body-fat reference app by name (search of tracked paths).
- Our docs mention only synthetic profile values (95.4 kg male test profile); no names, faces, phone or account details were found in the new plan files.

Remaining risks and rules (recorded as a decision entry below):
1. The package's `VIDEO_MANIFEST.json` records SHA-256 hashes and original paths of the videos. Hashes are not private content, but the original paths and file names are not needed in git; they are not copied into any of our files. Our docs refer to "the operator's two screen recordings" only.
2. Do not commit extracted frames, thumbnails, screenshots of the reference app, or the package's test fixtures that contain body numbers beyond the already-published example profile.
3. The package ZIP and its scratch copy live outside the repo (session scratchpad); they must not be added to the worktree.
4. The package asks that the videos be given to an executing agent only with the owner's approval. Our sprint does not need them again (the behaviour notes are the evidence base).

Conclusion: confirmed, our documents keep the videos and personal body data out of git; one guard rule is added to the decision list.

---

## 8. Open questions for the operator

| ID | Question | Default used meanwhile |
|---|---|---|
| O-1 | Is the Phase 2 backlog priority order acceptable (platform store reads, file import, BLE HR, BLE power/cadence, FTMS, Wear OS, Strava, then partner clouds)? Which sports matter first (running, cycling, walking, swimming)? | Order in backlog section 2 |
| O-2 | The package's M1 says "no unvalidated body-fat percent"; our sprint shows a clearly labelled provisional Deurenberg estimate (range half-width 5, banner). Keep it, or hide the percentage until a real model exists (show only capture, photos, weight trend)? Same as design Q-1 | Keep, with banner (D-3) |
| O-3 | Which devices does the household actually use (watch brand, bike sensors, scale)? This decides which adapters are worth building and which partner approvals are worth requesting | Standards first |
| O-4 | Do you want a Google Health API (Fitbit/Pixel) adapter at all, given the Fitbit Web API stops on 2026-10-30 and the new API's access model for a private project is unverified? | Not planned until O-3 says yes |
| O-5 | Partner programmes (Garmin, Suunto, TrainingPeaks) need applications under your name/organisation, possibly with fees. Authorise preparing applications, or rely on platform stores and file import? | Rely on stores and files |
| O-6 | Design clarification C-7: should fat-mass and lean-mass tiles use the smoothed trend or the raw reading? (Recommended: trend, labelled.) | Pending coordinator edit of design s12.1 |
| O-7 | Operator-owned commercial apps: do you want a public-material dossier for any of them (MacroFactor, Cronometer, Hevy, Strava, Garmin Connect, ...)? Purchases remain yours to make; none is needed | None purchased |
| O-8 | Confirm the open-source apps to study first (OpenTracks, openScale, Waistline) and that reading source is sufficient (no APK download needed) | Source reading only |
| O-9 | Nutrition-aware training (E9) and any claim beyond "sensible default" need a qualified professional review; who reviews? | Not claimed |
| O-10 | Package P2-021 "Future You" generated preview: keep deferred indefinitely? | Deferred, default OFF |
| O-11 | Retention of GPS and heart-rate streams (design s31.5 default "2 years" is open) and whether HR/sleep may sync to the cloud or stay device-only | Device-only doctrine until decided |

---

## 9. DECISION_LOG-ready entries (for the coordinator to paste; DECISION_LOG.md was not edited)

```
## 2026-10-15 - Commit: PRODUCT_PHASE2_EXPANSION research package reconciled

Decision (D-46): the downloaded Phase 2 research package (40 stories: 13 P0 / 20 P1 / 7 P2) is imported into core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md (section 8) with the package ids kept as cross-references; duplicates of existing design sections, sprint commits and epics are merged, not copied. The package is research input only: where it disagrees with the approved design (D-1..D-45) or the safety clamps (design s13.6), the design and the clamps win. Evidence: core/plans/PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md sections 1-3. Unverified: nothing was run.

Decision (D-47): conflicts resolved in favour of our design: no exercise-calorie credit (D-29, package credit policy not implemented), health sources read-only (D-44, no write-back), weekly review stays client-side (D-8), no server REST surface (callables, D-27 no meal photo storage), EWMA trend (D-18, D-37), body-fat target and pace clamps unchanged. Evidence: reconciliation file section 2.

Decision (D-48): the package's APK playbook is narrowed to what D-35 allows. Static review (OWASP MASVS/MASTG) applies to open-source apps only (OpenTracks, openScale, Waistline; source and official releases). Commercial apps are studied from public material only (store listings including the Play Data safety section, official docs/SDK docs, published privacy policies, ordinary use of apps the operator owns). Decompiling, extracting APKs, traffic interception or any reverse engineering of proprietary apps stays refused; package items P2-004, the playbook tooling, the acquisition manifest wording and gate G8 are rewritten accordingly. App purchases remain operator actions and are not required. Evidence: reconciliation file section 6.

Decision (D-49): the Fitbit Web API is not a target. Google's developer pages (opened 2026-10-15) state support ends 2026-09-30 and the API is turned off on 2026-10-30; backlog item 13 is "Google Health API" and is built only on an operator decision (O-4) after its access model for a private project is verified. Vendor-cloud adapters other than Withings/Strava stay behind terms review and partner approval; platform stores (Health Connect, HealthKit) and FIT/GPX/TCX import come first. Evidence: reconciliation file section 5. Unverified: access models of Garmin, Polar, Suunto, TrainingPeaks, Oura, WHOOP.

Decision (D-50): the operator's two reference recordings, any extracted frames, thumbnails or screenshots of the reference app, and the package ZIP stay outside git (.gitignore already ignores *.mp4 and docs/rec_frames/); committed documents refer to them only as "the operator's recordings" and carry no file paths, account details or faces. Evidence: reconciliation file section 7.

Decision (D-51): package milestone wording "no unvalidated body-fat percent" is not adopted literally; the PROVISIONAL estimator of D-3 stays with its banner pending operator answer O-2. Fat/lean tiles must label whether they use the raw reading or the smoothed trend (clarification of design s12.1 pending, O-6).
```
