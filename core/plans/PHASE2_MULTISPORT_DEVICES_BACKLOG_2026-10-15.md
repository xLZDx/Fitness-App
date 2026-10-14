# Phase 2 priority backlog: multi-sport tracking, device ecosystem, nutrition-aware programmes

**Status:** PRIORITY backlog, not started, not scheduled. Date 2026-10-15. Authored with the Body Scan + Nutrition Coach design (`BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md`), whose sections 30 and 31 deliver only the foundation (pure-Dart models, interfaces, merge/dedup, a minimal programme hook) in the current sprint. Everything below is what remains.

**Estimates** are order-of-magnitude engineering effort for one developer in person-weeks (pw), with the assumptions stated; they are planning inputs, not commitments, and exclude partner-approval waiting time and device-lab time. Capability statements about vendors are HYPOTHESES to be confirmed by the competitive/API study (epic E10) against official documentation.

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
| 13 | Fitbit / Google health APIs | Fitbit users | 3 | OAuth | API transition status must be verified in the study |
| 14 | Suunto API | Suunto devices | 3 | partner access | approval |
| 15 | Apple Watch companion | Apple Watch | 8+ | iOS build pipeline, 1 | needs an iOS device and developer programme |

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
