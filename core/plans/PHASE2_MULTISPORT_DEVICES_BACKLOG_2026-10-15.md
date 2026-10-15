# Phase 2 priority backlog: multi-sport tracking, device ecosystem, nutrition-aware programmes

**Status:** PRIORITY backlog, not started, not scheduled. Date 2026-10-15. Authored with the Body Scan + Nutrition Coach design (`BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md`), whose sections 30 and 31 deliver only the foundation (pure-Dart models, interfaces, merge/dedup, a minimal programme hook) in the current sprint. Everything below is what remains.

**Estimates** are order-of-magnitude engineering effort for one developer in person-weeks (pw), with the assumptions stated; they are planning inputs, not commitments, and exclude partner-approval waiting time and device-lab time. Capability statements about vendors are HYPOTHESES to be confirmed by the competitive/API study (epic E10) against official documentation.

**Research package import (2026-10-15).** Section 8 imports the 40 stories of the PRODUCT_PHASE2_EXPANSION research package (`P2-000..P2-039`; 13 P0 / 20 P1 / 7 P2) with their package ids as cross-references. Reconciliation, conflicts and the provider status check are in `PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md`. Where the package and the approved design disagree, the design wins.

## 1. Principles

1. Android first, nothing blocks iOS (`core/CONVENTIONS.md`); all device data enters through abstractions (`HealthService`, `DeviceSource`), never a platform API called from feature code.
2. Breadth through standards first: platform health stores and standard BLE profiles cover the most devices per unit of effort; vendor clouds are adapters added by measured demand.
3. Clean-room and legal study only (section 6): public documentation, store listings, official APIs/SDKs and terms, published research, ordinary observation of apps the operator uses. Reverse engineering of proprietary apps is refused (decision D-35).
4. Privacy: GPS and heart-rate data are sensitive; per-source, per-datatype consent, no analytics SDK receives them, deletion and export from day one.
5. Honest uncertainty carries over: derived metrics (pace, energy, swim distance) show their source and confidence.

## 2. Integration order and effort (device ecosystem)

Priority is by coverage per effort and by dependency on earlier items.

| # | Integration | Covers | Effort (pw) | Depends on | Main risks |
|---|---|---|---|---|---|
| 1 | Health Connect + HealthKit session reads through the `HealthService` seam (exercise sessions, routes, HR/speed/power/cadence series; new interface methods in `MockHealthService`, `PlatformHealthService`) | every watch/band/app that syncs to the platform store (Garmin, Fitbit, Samsung, Polar, Suunto, Coros and others sync there) | 4-6 | design section 31 model | data richness depends on the writing app; permission UX; iOS cannot be verified without a device |
| 2 | File import FIT / GPX / TCX (pure parsers + importer UI) | any device that exports files; also a test corpus for the merger | 2-3 | model | FIT SDK licence terms (verify); malformed files |
| 3 | BLE Heart Rate profile (0x180D) incl. RR intervals | chest straps, watches in broadcast mode | 2 | model, permissions | OS BLE quirks, background limits, reconnect |
| 4 | BLE Cycling Power (0x1818) and Cycling Speed & Cadence (0x1816) | power meters, speed/cadence sensors | 3 | 3 | calibration, wheel size, crank/wheel revolution wraparound |
| 5 | BLE Running Speed & Cadence (0x1814) | foot pods | 1 | 3 | few devices |
| 6 | BLE FTMS (0x1826) | smart trainers, treadmills, rowers | 3 | 3 | control point scope (read-only first), vendor deviations |
| 7 | Wear OS companion tracking app (run/bike/walk, HR, GPS, pool-swim lengths where hardware allows) | Wear OS watches | 6-8 | 1, existing `wear/` scaffold, `WearSyncService` | battery, sensor access, Data Layer reliability; release signing is an open item (CLAUDE.md) |
| 8 | Strava API import (activities and streams) | Strava users, most watches via Strava | 3 | model, server OAuth | API terms (storage/display limits), rate limits, app review |
| 9 | Polar AccessLink | Polar devices | 2-3 | server OAuth | consent per transaction model |
| 10 | Withings (scales, body composition) into `weight_entries` | smart scales | 2 | OAuth | partner access |
| 11 | Garmin Health / Activity API | Garmin devices | 4+ | partner programme approval | approval time, business terms |
| 12 | Wahoo Cloud API | Wahoo devices | 2-3 | OAuth | partner access |
| 13 | Google Health API (successor of the Fitbit Web API; NO legacy Fitbit integration: the Fitbit Web API is turned off on 2026-10-30 per Google's developer pages, see the reconciliation file section 5) | Fitbit and Pixel Watch users | 3 | OAuth, operator decision O-4 | access model for a private project unverified; users must re-consent; never link one user to both APIs |
| 14 | Suunto API | Suunto devices | 3 | partner access | approval |
| 15 | Apple Watch companion (HealthKit / WorkoutKit / watchOS) | Apple Watch | 8+ | iOS build pipeline, 1 | needs an iOS device and developer programme |
| 16 | Oura API v2 (sleep, readiness) | Oura users | 2 | OAuth | membership and rate limits unverified; added from package P2-032 |
| 17 | WHOOP API v2 (recovery, sleep, workouts) | WHOOP users | 2 | OAuth | app review and membership unverified; added from package P2-032 |
| 18 | TrainingPeaks API | TrainingPeaks users | 3 | partner access | approved developers only per the package; added from package P2-032 |

Cross-cutting: server-side OAuth token vault (Secret Manager/Firestore with owner-only deletion on disconnect) for items 8-14, about 2 pw once.

## 3. Epics, stories and Definition of Done

Every epic DoD includes: focused functional tests green (authored by the functional/e2e agents), specialist reviews with no valid BLOCKER/MAJOR, rules and lifecycle policy rows for any new collection, deletion and export coverage, EN + RU strings, `core/CODEMAP.md` updated, a change record per commit, GPT approval before push.

### E1 Activity foundation hardening
Stories: persist `ActivitySession` (summary in Firestore, streams as compressed objects in the private bucket); rules with shape validation; retention setting; deletion and export; tolerant schema migration; merger performance on year-long histories; FIT/GPX export of a merged session.
DoD: round-trip of 100 real-shaped sessions; deletion removes streams; export contains sessions; merger property tests green on a corpus built from item 2 of the table.

### E2 Health-platform sessions (table item 1)
Stories: extend `HealthService` with session/route/series reads; Health Connect permissions per datatype with explanation screens; HealthKit equivalent behind the same interface; incremental sync with change tokens; echo detection against other sources.
DoD: Mock and platform implementations conform to one contract test suite; the merger dedups a watch-app record echoed through the platform store; manual fallback when permission is denied.

### E3 Phone-based tracking: run, walk, cycle
Stories: foreground-service GPS recording with auto-pause, smoothing and accuracy filtering; live metrics (pace, distance, elevation); route map (tile-provider choice and its terms are a decision); crash-safe recording (resume after kill); audio cues through the existing voice coach; battery budget measured on the operator's device.
DoD: a recorded outdoor session survives app kill and screen-off; distance within an agreed tolerance of a reference watch on a measured route (tolerance to be set from the E10 benchmarks, not invented here); battery cost per hour recorded.

### E4 Swimming
Stories: pool swim - length and lap entry from watch data and manual entry, stroke type, SWOLF derivation, rest intervals; open water - GPS with known smoothing limits; unit handling (per 100 m / 100 yd).
DoD: pool sessions import from the platform store with lap structure intact; manual pool-session entry works offline; open-water distance shows its confidence.

### E5 BLE sensors (table items 3-6)
Stories: scan/pair/reconnect, per-profile parsers as pure Dart with fixtures, wraparound handling, sensor selection per sport, permissions with reasons, graceful absence.
DoD: parsers verified against recorded characteristic fixtures; a simulated sensor drives a full recording in tests; no crash on permission denial.

### E6 Watch companion apps (table items 7 and 15)
Stories: Wear OS recording app and Data Layer protocol (extends the existing generic phone-side sync interface); standalone recording when the phone is absent; later, Apple Watch. Prerequisite: fix or consciously defer the known release-signing issue.
DoD: a watch-recorded session appears on the phone with provenance `companionApp` and merges with the platform echo.

### E7 Vendor cloud adapters (table items 8-14)
Stories per vendor: OAuth connect/disconnect, token vault, webhook or polling ingestion, normalisation to `ActivitySession`, terms compliance check, rate-limit handling, per-vendor kill switch.
DoD per adapter: fixtures from the vendor's public documentation, disconnect revokes tokens and (on request) deletes imported data, terms review recorded in the decision log.

### E8 Dedup/merge in production
Stories: conflict UI (why two records were merged, undo), per-user source priority settings, split/join controls, merge audit trail, test corpus of real multi-source workouts (operator's own data).
DoD: false-merge and missed-merge rates measured on the corpus and recorded; undo restores the originals.

### E9 Nutrition-aware programme level (full version)
Builds on design section 30. Stories: periodised cut/maintain/bulk blocks consuming the plan phase; automatic deload scheduling with user confirmation; per-exercise volume adaptation; training-day nutrition guidance (carbohydrate and protein distribution around sessions) as ranges with sources; Health Connect expenditure and sleep inputs; an in-app "why your training changed" explanation; opt-out toggle; interaction rules with age/screening/injury caps (minimum of caps, never bypass the injury filter).
DoD: decision-table tests per phase; advice always explains itself; neutral behaviour on missing or stale data; reviewed by a qualified professional before any claim beyond "sensible default" is made (clinical acceptance remains an operator gate).

### E10 Competitive and ecosystem study (see section 6)
### E11 Privacy, permissions, retention for activity data
Stories: consent matrix per source and datatype, GPS redaction defaults and editing, retention controls, export formats, privacy page update, data-safety form inventory.
DoD: lifecycle policy rows, deletion/export tests, privacy text approved.

### E12 Sport UI and plans
Stories: sport picker and live screens, summaries with splits/laps, history and filters, basic running and cycling plans, unit and locale settings, accessibility pass.
DoD: screens verified on the Pixel emulator and the operator's device; EN + RU; accessibility checklist as in the body-scan design section 24.

## 4. Dependencies

E1 -> E2/E3/E5/E7; E2 and E8 before E7; item 2 (file import) early because its corpus is the test bed for E8; E6 depends on E2/E5 conventions and on the signing decision; E9 depends on the body-scan design's plan and review being implemented; E11 runs alongside each source added.

## 5. Risks

| Risk | Mitigation |
|---|---|
| Vendor API terms restrict storage, display or commercial use | terms review per adapter before building; kill switch; private-use status is not assumed to hold forever |
| Partner programmes (Garmin, Suunto) delay or refuse | rely on platform stores and file import for those devices |
| Data quality and duplicates across sources | E8 corpus, provenance, undo |
| GPS/BLE battery and background limits, especially iOS | foreground-service design, measured budgets, honest limits |
| Location and heart-rate privacy | E11, redaction defaults, no analytics, deletion/export |
| Scope explosion | priority table above; every adapter is independently shippable |
| No iOS device for verification | marked NOT_RUN until available |

## 6. Competitive study plan (legal methods only)

**Purpose.** Learn best practices in multi-sport tracking, device integration and adaptive nutrition/training, and turn them into a features/benchmarks matrix that feeds the epics above.

**Allowed sources (and only these).** Official documentation, API/SDK references and terms of service; developer portals and partner programme pages; store listings (descriptions, screenshots, changelogs, public reviews); vendor help centres and blogs; published research papers and whitepapers; open-source projects under their licences (study and, where the licence allows, reuse with attribution); the operator's own accounts and ordinary observation of apps the operator already uses (operator-provided screenshots and notes); the user's own data exports from those apps (to test importer compatibility); public datasets under their licences.

**Not allowed.** Decompiling or disassembling proprietary apps, intercepting or replaying their private APIs to clone behaviour, scraping content behind a login against its terms, bypassing paywalls or licence checks, using leaked source or documents. This is DECISION D-35 and is also recorded in `core/DECISION_LOG.md`.

**Apps and projects to study (initial list, to be confirmed with the operator).** Multi-sport and platforms: Strava, Garmin Connect, Polar Flow, Suunto app, Wahoo, Fitbit, Apple Fitness, Google Fit/Health Connect documentation, Komoot, Nike Run Club-style run apps, TrainingPeaks, intervals.icu (public API). Nutrition and adaptive coaching: MyFitnessPal, Cronometer, Lose It, YAZIO, MacroFactor (its publicly described adaptive-expenditure approach), Hevy/Strong-style training logs. Open source for reading under licence: GoldenCheetah, OpenTracks, FitTrackee, wger, OpenNutriTracker (GPL-3: read-only reference, re-implement).

**Method.** Timebox one sprint. For each subject fill one row per feature with evidence: source URL, access date, evidence grade (A official doc, B vendor marketing/help, C review or observation, D hypothesis). Record, never copy, wording; screenshots are used only as private notes.

**Features/benchmarks matrix (template; one sheet per domain).**

| Dimension | What to capture | Evidence grade source |
|---|---|---|
| Device coverage | platform stores, BLE profiles, vendor APIs, file formats supported | A/B |
| Data model | session structure, laps, streams, units, dedup behaviour | A/C |
| Recording quality | GPS sampling/smoothing described, auto-pause, battery claims | A/B/C |
| Merge/dedup | how duplicates from multiple sources are handled | A/B |
| Nutrition adaptation | how expenditure/targets adapt, data needed, published validation | A + papers |
| Training adaptation | volume/deload logic, recovery inputs | A/B + papers |
| Privacy | data stored, retention, sharing defaults, GPS redaction | A (policy) |
| UX patterns | onboarding, permission flows, empty states, explanations | C |
| Business | pricing tiers and what is gated (information only) | B |
| Gaps/opportunities | what users complain about (public reviews), what we can do better | C |

**Outputs.** (1) `core/plans/COMPETITIVE_MATRIX_<date>.md` with the matrices and sources; (2) a short list of adopted practices, each tagged with its evidence grade and mapped to an epic; (3) numeric benchmarks (for example the GPS distance tolerance used in E3's DoD) with their source; (4) a decision-log entry per adopted practice that changes a threshold.

**DoD (E10).** Every matrix cell has a source or is marked unknown; no proprietary code, assets or copy reproduced; a reviewer confirms that no prohibited method was used.

## 7. Legal alternatives to reverse engineering (reference list)

Official APIs and SDKs; partner programmes; documented file formats (FIT, GPX, TCX); documented BLE GATT profiles; published academic validation studies; open-source projects read under their licences; user-initiated data exports (GDPR portability) from apps the user owns, used to test importers; direct vendor contact for data-sharing agreements.

## 8. Imported stories from the PRODUCT_PHASE2_EXPANSION research package

Source: package `backlog/stories.csv` (40 stories). Every package story has one row. "Home" says where the story lives in our plan: **S** = delivered or covered by the current sprint (sprint-plan commit or design section), **E#** = a Phase 2 epic above, **X-nn** = a NEW story entry defined in 8.2. Status of all rows is the one derived from the sprint plan: rows with an S home are "in current sprint (not yet implemented)", every other row is "not started". No package story is marked done without commit and test evidence. All are subject to the epic DoD in section 3 and to DEVELOPMENT RULES v4 (no automatic checks beyond focused functional tests).

### 8.1 Story table (id, title, priority, dependency, acceptance)

| Package id | Title | P | Depends on (package ids) | Home | Acceptance (ours; package acceptance in brackets where it adds something) |
|---|---|---|---|---|---|
| P2-000 | Program charter, scope, design authority | P0 | none | S (design s0, s1.2; this file s1) | Scope and out-of-scope lists exist and match the sprint plan s9; flags default off |
| P2-001 | Repo inventory and dirty-tree safety | P0 | P2-000 | S (design s2); E1 start | Recon fact sheet refreshed at the start of each epic; no overwrite of other sessions' edits |
| P2-002 | Two-video extraction and numeric provenance | P0 | P2-000 | S (design s3, s29; behaviour notes) | Every adopted reference number tagged OBS/PUB/OWN; no hidden-algorithm claim; recordings stay out of git |
| P2-003 | Competitive product catalogue | P0 | P2-000 | E10 | Matrix cells sourced or "unknown"; package app list used as seed; evidence grades A-D |
| P2-004 | APK acquisition and static privacy audit | P0 | P2-003 | X-04 (rewritten) | Open-source apps only (OWASP MASVS/MASTG); commercial apps: public-material dossier; reviewer confirms no prohibited method (D-35) |
| P2-005 | Observed API contracts and vendor public APIs | P0 | P2-003 | E10, E7 | Documented public APIs only: scopes, rate limits, terms, partner blockers marked FACT / UNVERIFIED; no private endpoints |
| P2-006 | Canonical sport+health+nutrition ontology | P0 | P2-001 | S (design s31.1, C08; s5, s17) | Unknown sport degrades to `other`; tolerant JSON; schema round-trip seeds (s31.8); E1 adds persistence provenance fields (A-5) |
| P2-007 | Device connector architecture, anti-corruption layer | P0 | P2-006 | S (design s31.2-31.3, C08); E1, E2 | Fake source drives merge; idempotent re-import; capability discovery; E1 adds quarantine, cursors, `healthStatus` (A-1..A-3) |
| P2-008 | Personal-data consent, privacy, retention | P0 | P2-006 | S (design s9, s20, C25); E11 | Deny/revoke/delete/export tests per collection; no non-consensual upload; GPS redaction default |
| P2-009 | Metric calculator v1 and replay tests | P0 | P2-006 | S (design s12, s13; C05, C07); E3/E4 for sport metrics | Replay values reproduced (reconciliation s3); formulas versioned; sport formulas per A-6 |
| P2-010 | HUD-native navigation integration | P0 | P2-001 | S (design s21; C11, C15, C17, C19, C23); E12 | Entry cards and nested routes, no sixth tab; EN + RU; accessibility checklist (s24) |
| P2-011 | Nutrition provider and rights assessment | P0 | P2-008 | S (design s17.9, D-31; C20, C24) | Attribution file lists source, licence, what is used; ODbL share-alike noted for any public release |
| P2-012 | Manual meal diary with provenance | P1 | P2-006, P2-011 | S (design s17; C22, C23) | Offline CRUD, exact sums with ranges, per-item source tag, per-user separation |
| P2-013 | Barcode and food-label scan | P1 | P2-011, P2-012 | S (design s17.4, s17.6; C20, C24) | GTIN check digit; unknown-product path; label parse always confirmed by the user before save |
| P2-014 | AI photo meal identification | P1 | P2-011, P2-012 | S (design s17.3; C20, C24; flag `FOOD_AI`) | Never auto-saved; closed "Check these" codes; flag-off fallback works |
| P2-015 | Portion estimation with honest uncertainty | P1 | P2-014 | S (ranges, design s17.3, s17.7); X-15 (evaluation) | Ranges not false grams; Phase 2: measured food-scale holdout with error and coverage before any accuracy claim |
| P2-016 | Goal ownership modes | P1 | P2-009, P2-008 | S (design s18; C19) | Coached/Shared/Manual semantics tested; clamps bind every mode |
| P2-017 | Weekly adaptive nutrition + training review | P1 | P2-016, P2-012 | S (design s15, s30; C06, C09, C18, C19); E9 | One review per ISO week; bounded change; neutral when data is missing; training side only lowers load |
| P2-018 | Three-pose capture and quality state machine | P1 | P2-008, P2-010 | S (design s10, s11; C13-C15) | Works locally; manual shutter recorded; permission and camera errors handled |
| P2-019 | Body measurement and trend charts | P1 | P2-009, P2-018 | S (design s12; C07, C15, C16) | Raw reading, smoothed trend, target separated; raw vs trend labelled on every derived mass (reconciliation C-7) |
| P2-020 | Body-fat ML build-vs-buy viability | P2 | P2-018, P2-008 | X-20 | No medical claim; calibrated independent holdout and subgroup coverage before showing a photo-based percent (design Q-1) |
| P2-021 | Generated "Future You" visualisation evaluation | P2 | P2-020 | X-21 (deferred) | Default OFF; no minors; explicit operator and legal decision first (design s1.2) |
| P2-022 | Running workout engine | P1 | P2-006, P2-007 | E3 | Recording survives app kill and clock change; pace/splits/moving vs elapsed; route privacy; replay of a FIT/GPS fixture |
| P2-023 | Cycling engine | P1 | P2-006, P2-007 | E3, E5 | Indoor/outdoor; time-weighted power; sensor drop and duplicate import tested |
| P2-024 | Walking / steps engine | P1 | P2-006, P2-007 | E3 | No phantom calories without a sensor or on a duplicate import; indoor/manual path |
| P2-025 | Swimming engine | P1 | P2-006, P2-007 | E4 | Pool length entered, no GPS for pool; lengths x pool length; open-water confidence and route privacy |
| P2-026 | Multisport workout and unified load model | P1 | P2-022..P2-025 | X-26, E9, E12 | Separate load per modality, never collapsed to calories; recovery guard never raises load against injury filter |
| P2-027 | Health Connect granular permissions | P1 | P2-007, P2-008 | E2 | Per-datatype permission and revoke on a real Android device; manual fallback; account switch test; read-only (D-44) |
| P2-028 | Wear OS exercise recording and offline sync | P1 | P2-027 | E6 | Session saved after disconnect with original timestamps; provenance `companionApp`; signing issue decided first |
| P2-029 | FIT / GPX / TCX import and export | P1 | P2-007 | E1 (table item 2) | Same file twice gives one session; corrupt file handled; size/XML/zip limits (A-1) |
| P2-030 | BLE HR / CSC / Power / FTMS adapters | P2 | P2-007 | E5 | Pure parsers with recorded fixtures; wraparound; drop/reconnect; permission denial does not crash |
| P2-031 | Garmin / Polar / Strava / Wahoo cloud adapters | P2 | P2-007, P2-005 | E7 | Terms review recorded; contract tests from public docs; token vault; kill switch; no unapproved production use |
| P2-032 | Oura / WHOOP / Withings / Suunto / TrainingPeaks adapters | P2 | P2-007, P2-005 | E7 (items 10, 14, 16-18) | No support claimed before an approved end-to-end smoke test |
| P2-033 | Google Health API migration / availability | P2 | P2-007, P2-005 | E7 (item 13) | No dependency on the Fitbit Web API (off 2026-10-30); never dual-link a user; built only on operator decision O-4 |
| P2-034 | Cross-provider dedup and source arbitration | P1 | P2-007, P2-009 | S (design s31.3, C08); E8 | Clock skew, DST (UTC compare), late events, user edits win; false-merge and missed-merge rates measured on a real corpus |
| P2-035 | Security, privacy and clinical guard gates | P0 | P2-008 | S (sprint plan s7.3, design s13.6, s14); E11 | Zero critical leakage; deletion/export coverage per collection; no diagnostic wording; under-18 lockout |
| P2-036 | Accessibility and language parity | P1 | P2-010 | S (design s23-s24; C26); E12 | EN/RU key parity and plurals; screen-reader semantics; 200 % text scale |
| P2-037 | Measured phased rollout and rollback | P1 | P2-035, P2-034 | S (flags, SD-2); X-37 | Per-feature flags default off; staged enabling; rollback path recorded; no PII in telemetry |
| P2-038 | Sport plugin registry / future sports | P2 | P2-006, P2-026 | X-38 | One new sport added without changing existing sport contracts (model already tolerant, design s31.1) |
| P2-039 | Equipment recognition >= 90 % sealed-holdout research | P1 | P2-001 | XREF (existing recognition track) | Not part of this programme; no accuracy claim until an independent sealed holdout reports it |

### 8.2 New story entries (no existing home)

| ID | Story | Priority | Depends on | Acceptance |
|---|---|---|---|---|
| X-04 | Open-source app review and commercial public-material dossiers (replaces package P2-004) | P0 for the study | E10 | One note per OSS app (OpenTracks, openScale, Waistline): source URL, tag, licence, SHA-256, signer, manifest permissions, SDK list, findings graded FACT/INFERENCE/HYPOTHESIS; one dossier per commercial app from public sources with access dates; no proprietary binary analysis, no traffic capture, no APK extraction |
| X-15 | Meal photo and portion evaluation holdout | P1 | E5 flags on, real provider | Scale-weighed meals across cuisines, plates, lighting; food top-1/top-3, gram MAE, kcal %APE, per-macro MAE, abstention rate; wrong-food and wrong-portion reported separately; no accuracy claim before this report |
| X-20 | Body-fat provider build-vs-buy study | P2 | design Q-1, consent flow | Comparator device ground truth, age/sex coverage, photo privacy review, vendor terms; estimator stays provisional until a calibrated holdout exists |
| X-21 | "Future You" preview evaluation (deferred) | P2 | operator and legal decision | Not started; default OFF; no minors |
| X-26 | Unified training-load model across sports | P1 | E3, E4, E9 | Per-modality load, cross-day planning, transitions, recovery guard; reviewed by a qualified professional before any claim beyond "sensible default" |
| X-37 | Phased rollout for sport and device features | P1 | per-epic | Per-feature compile-time and server flags default off, staged enabling, rollback documented, no PII in telemetry |
| X-38 | Sport plugin registry | P2 | E3, X-26 | Adding rowing, hiking or triathlon needs no schema migration |

### 8.3 Additions to existing epics from the package (details in the reconciliation file section 4)

A-1 quarantine and untrusted-input limits (E1, E2); A-2 sync cursors and reversible imports (E2); A-3 adapter surface `healthStatus`, `deleteCached`, optional workout stream, no write-back (E1); A-4 per-metric source authority and conflicts screen (E8); A-5 provenance fields `formulaVersion`, `metricDefinitionVersion`, `thresholdPolicyVersion`, `sourceTermsSnapshot` (E1); A-6 sport DoD details: time-weighted power, watts/kg with body mass at activity time, moving vs elapsed, no phantom calories, swim pool length entered, SWOLF only when justified (E3, E4, E5); A-7 aggregator build-vs-buy pilot, option only (E7); A-8 ANT+ not planned (E5); A-9 WorkoutKit/watchOS (item 15); A-10 Oura, WHOOP, TrainingPeaks, Google Health API (items 13, 16-18).

### 8.4 Import summary

40 package stories imported: 7 new entries (X-04, X-15, X-20, X-21, X-26, X-37, X-38) and 33 merged into existing items, epics or design sections. Package priorities: 13 P0, 20 P1, 7 P2 (CSV count; the request text said 12/20/8).
