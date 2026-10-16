# Fitness App: product roadmap, sprints, epics and priorities (planning, not approved)

> **CURRENT STATE (2026-10-15, after S00 execution).** This document is the approved planning baseline (GPT-PM APPROVE on revision 3; operator approval on 2026-10-15). Wording below such as "draft", "nothing has been executed" or "PR #5 is open" is historical. Executed so far: the snapshot, tag `phase1-baseline`, branches `phase1/main` and `phase2/main`, PR #5 retargeted to `phase2/main` and merged as `5137ccda`, the worktrees, and the S00 documentation and deploy-line guard work (still under review). Recorded operator decisions: D-1, D-2, D-4, D-5 (see `core/DECISION_LOG.md` and `docs/phase2/README.md`). Where this text and those two files disagree, the decision log and the README win.

Date: 2026-10-15 (revision 2 after GPT-PM planning review round 1: F-01, F-07, F-08, F-09, F-10, F-11). Status: DRAFT FOR GPT-PM VERIFICATION, then operator approval. Estimates are order-of-magnitude person-weeks (pw) of engineering, planning inputs and not commitments; external waits are listed separately in section 7. Statements about third-party products are HYPOTHESES until confirmed from official sources (epic E10).

## 1. Product statement and goals

One account, one history, one dashboard, four worlds chosen at start (changeable in 1-2 taps):

| Mode | Contains | Core job |
|---|---|---|
| TRAIN | Gym (existing equipment QR, catalogue, form coach), Home, Outdoor strength, Yoga | Start a session, follow a programme, learn technique |
| RIDE | Road, MTB, gravel, city, e-bike | Find or build a route, record GPS, share |
| EXPLORE | Walk, run, hike | Find a route near me by level, record, share |
| BODY | Body Scan, Nutrition Coach, weight trend | See progress, log food, understand trend |
| Shared | Global dashboard ("My progress"), Coach, Profile, settings, consent centre | Everything across modes, one history |

Goals (thresholds set from a measured baseline, not invented now): G-1 first recorded session in one mode within 3 minutes of first run; G-2 no loss of an in-progress recording on app kill; G-3 every activity carries a source id (no double counting); G-4 location, photo and health data private by default, exportable, deletable; G-5 no regression in existing gym flows; G-6 every claim shows source and uncertainty.

Non-goals until the operator decides: marketplace payouts, live-streamed classes, deepfakes (task 12, 67), insurance, CGM, supplement store, AR, kids mode, prenatal programmes.

## 2. Priority model

| Tier | Meaning | Content |
|---|---|---|
| T0 | Prerequisites | Split, contracts (GPS privacy, data lifecycle, rights), UI baseline, unified activity persistence |
| T1 | Connectivity | Shell, mode chooser, dashboard skeleton, unified history, provenance and dedup of native sessions |
| T2 | New modes, lowest rights risk | Recording without any map service: EXPLORE walk/run, then RIDE |
| T3 | Content-dependent | Route catalogue, discovery, publication and moderation, offline maps and navigation |
| T4 | TRAIN expansion | Home, outdoor, yoga |
| T5 | BODY go-live | Operator gates, flags ON by stages |
| T6 | Devices | Platform stores, files, BLE, Wear OS, vendor clouds by demand |
| T7 | Personalisation | Cross-mode adaptation, route re-ranker, growth features |
| T8 | Release and operations | Hardening, beta, release, post-launch operations |

Release trains with explicit subsets (F-09):

| Train | Contains | Does NOT contain |
|---|---|---|
| R1 Phase 1 MVP | Existing scope, fixes, release gates | Any new feature |
| R2 Phase 2 alpha | Shell, chooser, dashboard skeleton, EXPLORE walk/run recording without a map service dependency (map optional), unified history, consents | Routes catalogue, sharing, offline maps |
| R3 Phase 2 beta | RIDE recording, route catalogue and discovery (online), publication with moderation, TRAIN Home/Outdoor/Yoga, BODY flags staged | Offline maps and turn-by-turn navigation (separate sprint S11 and its own gate), external-device dedup guarantees |
| R4 Phase 2 release | Offline navigation (if licences allow), devices (platform stores and files at least), personalisation, accessibility pass, release operations | Vendor clouds without approval |

## 3. Sprint rules

- One sprint = one PR into `phase2/main` (Phase 1 fixes: one PR per independently reviewed change set into `phase1/main`; unrelated fix sprints are not merged into one PR).
- Every interface task has a design sprint (`-D`: journeys, states, copy, tokens, prototype; ui-designer authoring, product-ux and a11y review, GPT-PM approval) BEFORE its build sprint. Independent journeys have independent design sprints (F-10).
- Order inside a sprint: documentation first, implementation, then the named test agents write and run focused functional tests, specialist reviews, GPT-PM approval on the exact head, push and PR (DEVELOPMENT RULES v4). Every commit has a change record; decisions go to `core/DECISION_LOG.md`.
- Every sprint DoD includes: sync lag check against `phase1/main` (`02_PHASE_SPLIT` section 5), lifecycle policy rows for any new collection, deletion and export coverage, EN and RU strings, accessibility checklist, no open BLOCKER/MAJOR.

## 4. Phase 1 plan: production MVP (maintenance line)

| ID | Sprint | Scope | Exit criteria | Blockers (owner) |
|---|---|---|---|---|
| P1-S1 | Fix PRs | Coach-form fixes (22 commits) and scan-mapping fix (1 commit) as separate PRs into `phase1/main`, each with its own focused tests and review | Merged and synced to Phase 2 | GPT-PM review |
| P1-S2 | Release readiness (internal) | targetSdk 36 check, Stripe price IDs, release artifact job, privacy and store declaration alignment | Release candidate evidence | Operator (Stripe, store accounts) |
| P1-S3 | Device acceptance | S23 acceptance of the form coach, labelled run for T1/T2 | Evidence or re-scope | Operator/external (EXT-01) |
| P1-S4 | Clinical and labels | D1/H3 clinical submission, CT1 labels, accuracy statement | Closed by an outside authority or claims stay disabled | External authority |
| P1-S5 | Store release R1 | Closed test, listing, monitoring owner | Release or conscious deferral | Operator |

Phase 1 receives no new features; items needing only operator or external action are BLOCKED, not engineering work.

## 5. Phase 2 plan: sprints, epics and priorities

Epic ids: EP-* are new; E# and P2-nnn refer to `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` and its 40 imported stories. "ENTRY decisions" are the decisions (section 10) that must be closed before the sprint starts.

### Stage 0. Split and contracts (T0)

| Sprint | Name and scope | Est. | ENTRY decisions | Exit / DoD |
|---|---|---|---|---|
| S00 | **Split and migration** (bootstrap, `02_PHASE_SPLIT` section 4): snapshot, tag and branches, PR #5 decision and re-verification, worktrees, documentation PRs, registry generator, `docs/EXPERIMENTS.md`, `docs/SYNC_LOG.md`, provenance inventory ruling, backend separation gate (deploy allowlist, alias, release-guard test), decision register in `docs/phase2/` | 2 | D-1, D-2, D-4, D-5 | Two lines exist; first sync entry; gate passes; no Phase 2 cloud write before the gate |
| S01 | **Contracts and UI baseline**: (a) `GPS_LOCATION_PRIVACY_CONTRACT` and the data lifecycle matrix of section 11 (collected, local, cloud, shared, retained, exported, deleted, logged for raw samples, derived geometry, published routes, previews, caches, route photos with EXIF, background location, friends, minors); (b) rights study for tiles, route data and POI (official sources only, grade A/B), including the published OSM tile-server policy that forbids offline pre-fetching from the community tile servers; (c) UI-0 baseline audit (verify tokens and implemented HUD, component and screen inventory, state list) | 3 | D-16, D-17 (needed for the contract), D-6/D-7 (study only) | Contract and matrix reviewed by GPT-PM and approved by the operator; UI-0 report; rights options with recommendation; no code |

### Stage A. Foundation (T0, T1)

| Sprint | Name and scope | Est. | ENTRY decisions | DoD highlights |
|---|---|---|---|---|
| S02 | **Unified activity (E1)**: `ActivitySession` persistence (summary in Firestore, streams as compressed private objects), rules with shape validation, retention per contract, deletion, export, provenance fields (A-5), tolerant schema migration, merger performance, FIT/GPX export; consent matrix per source and datatype (E11 start); native-session dedup | 4 | S01 approved contracts | Round trip of 100 real-shaped sessions; deletion removes streams; lifecycle rows; no external-source dedup promise |
| S03-D | **UI design: shell, mode chooser, dashboard skeleton** (resolves U-1, U-2) | 2 | U-1 (before approval of the contract) | Approved contract and prototype |
| S03 | **Shell, chooser, dashboard skeleton** (EP-1 mode state, EP-2 chooser and per-mode first-run questions, EP-3 Today/This week/Progress from `ActivitySession`, EP-4 sources panel) | 4 | S03-D approved | Existing five-tab flows unchanged; mode switch never resets a running session; missing shown as missing |

### Stage B. GPS recording and routes (T2, T3)

| Sprint | Name and scope | Est. | ENTRY decisions | DoD highlights |
|---|---|---|---|---|
| S04-D | **UI design: GPS permission and recording-state contract** (foreground then background permission journey with denial paths; recording states: acquiring, poor accuracy, offline, paused manual/auto, background, restoring after kill, recovery failed, battery critical, permission revoked mid-recording; shared by EXPLORE and RIDE) | 1.5 | S01 contract | Approved contract; S04 builds only this |
| S04 | **GPS core without a map** (implements the approved S04-D contract; recorder, not map): foreground-service recorder, journaled samples (crash-safe resume), auto-pause, smoothing and accuracy gate, calculators with replay tests (P2-009), permission flow (foreground first; background only while recording), battery protocol; recording works with no map service | 5 | Contract (S01), S04-D approved, D-12 for iOS scope | Survives app kill and screen off; tolerance and battery recorded on the operator's phone |
| S05-D | UI design: EXPLORE journey (walk/run live, summary, history, manual walk), reusing the S04-D recording-state contract | 1.5 | S03-D, S04-D | Approved contract |
| S05 | **EXPLORE v1 (walk, run)**: walking (steps source priority, no phantom calories) and running engines, summaries, history, manual walk without GPS | 4 | S05-D | Fixtures replay; privacy zones default on; unified credit counted once |
| S06-D | UI design: RIDE live, summary, sensor sheet preview, maintenance counters; reuses S04-D | 1.5 | S03-D, S04-D | Approved contract |
| S06 | **RIDE v1**: cycling engine (bike types, e-bike energy unknown unless source gives it, time-weighted power when a sensor exists), summary, GPX import/export, bike and shoe mileage counters | 4 | S06-D | Valid track after crash; GPX round trip |
| S07 | **Route catalogue and rights**: route entity and storage, ownership, versions, own-track to route conversion, attribution file, source labels and freshness, region gate (first-release region) | 4 | D-6, D-7, contract | Rights recorded per source; every route shows source and freshness; no external data without a recorded licence |
| S08 | **Discovery and ranking (online)**: nearby query, filters (distance, duration, elevation, surface, loop), Route Fit Score v1 (hard safety filters then explainable weighted score; weights are starting hypotheses), reason line on every suggestion | 4 | S07 | Every recommendation shows its reason; unknown metadata shown as unknown |
| S09 | **Publication protocol, privacy and moderation (backend and data contract, no screens)**: server-side visibility model private/unlisted/public/friends, publish and unpublish endpoints, derived-artefact tracking so deleting a track deletes or detaches every public copy, trimmed endpoints plus re-identification risk handling (trimming alone is not treated as protection), photo EXIF stripping on upload, report/takedown records, moderation queue and operator runbook, minors rule (D-17) enforced server-side | 4 | D-17 (decided in S01), S07 | Protocol tests with fakes; deleting an activity removes or detaches all derived public artefacts per the lifecycle matrix; takedown path tested; no UI acceptance criteria here |
| S10-D | UI design: discovery lists/map, route card, filters, reason line, privacy preview and revoke journeys, route trust states (unknown surface, unknown safety, stale source, unverified accessibility, reported route) | 2 | S08, S09 data contract | Approved contract |
| S10 | **Discovery and sharing UI**: nearby list/map, filters, route card, trust states, and the user-facing publish flow (geometry preview before publish, visibility choice, revoke, delete shared copy, report) on top of the S09 protocol | 5 | S10-D | Sharing default private; geometry preview and revoke journeys work; trust states visible |
| S11-D | UI design: offline downloads and navigation (ready-offline status, size, licence, off-route and recovery without connectivity) | 1.5 | S10 | Approved contract |
| S11 | **Offline maps and navigation** (own gate; only if the licence study allows offline use): downloaded route/area with explicit "ready offline" status, size control, off-route alert, basic turn guidance, optional live-location share with an emergency contact for outdoor modes (promoted from original task 36 as a proposal) | 5 | D-6 final, rights (S07) | Works offline for a downloaded route; no tiles pre-fetched from a provider that forbids it |

### Stage C. TRAIN and BODY inside the shell (T4, T5)

| Sprint | Name and scope | Est. | DoD highlights |
|---|---|---|---|
| S12-D | UI design: TRAIN lens (Gym entry unchanged, Home filters, Outdoor stations) | 1.5 | Approved contract |
| S12 | **TRAIN lens, Home, Outdoor**: TRAIN home routing into existing gym flows unchanged; Home library (no equipment, small space, quiet); Outdoor strength and public stations (QR/NFC proposal); schedule and unified credit | 4 | Gym QR and form coach scenarios keep working; video licence and exact exercise binding |
| S13-D | UI design: Yoga session player (separate journey) | 1 | Approved contract |
| S13 | **Yoga engine**: sequence model, hold timer, styles, pace, safe substitutions, optional voice, offline fallback | 4 | Practice time not sets; contraindications respected |
| S14-D | UI design: BODY lens and consent centre rows (provisional estimate, consent withdrawn, professional referral, provider unavailable, photo-free progress states) | 1 | Approved contract |
| S14 | **BODY integration and staged go-live**: experiment features into BODY, flag staging after operator gates Q-4/Q-5/Q-6/Q-10 and a real face detector; open MINORs FL-F4, FL-F5, FL-F7, P-6 | 3 | Flags OFF until each gate closes |
| S15-D | UI design: global dashboard (+ large-screen variant if U-2 yes) | 1.5 | Approved contract |
| S15 | **Global dashboard v1**: cross-mode aggregates, personal bests per discipline, goals and plan calendar, sources, double-count rules | 4 | Native sessions counted once with visible provenance; missing shown as missing; the "native + imported counted once" acceptance case is NOT part of S15 (it belongs to S17, followed by a dashboard regression check) |

### Stage D. Devices and ecosystem (T6)

| Sprint | Name | Scope | Est. |
|---|---|---|---|
| S16 | Health platforms and files | E2 Health Connect and HealthKit session reads (read-only, granular permissions, change tokens), FIT/GPX/TCX import with quarantine and limits | 5 |
| S17 | Dedup with external sources | E8 conflicts UI, source priority, undo, corpus measurement; full acceptance case "one imported and one native session counted once"; focused regression check of the S15 dashboard totals after S16/S17 | 3 |
| S18 | BLE sensors | E5 HR, power, CSC, running SC, FTMS read-only | 5 |
| S19 | Wear OS companion | E6; needs signing decision D-13 | 6-8 |
| S20 | Vendor adapters by demand | E7 Strava, Withings, Polar; partner-gated Garmin/Wahoo/Suunto; Google Health API only on O-4 | 6+ |
| S21 | Swimming | E4 | 3 |

### Stage E. Personalisation and release (T7, T8)

| Sprint | Name | Scope | Est. |
|---|---|---|---|
| S22 | Cross-mode plan and adaptation | E9, X-26; recovery guard never raises load against the injury filter | 5 |
| S23 | Route personalisation v2 | Calibrated Route Fit weights, reranker behind flag | 3 |
| S24 | Growth features | Annual recap, coach-shareable view, streaks, challenges | 3 |
| S25 | Hardening | Accessibility pass, performance and battery budgets, security and privacy review, store and data-safety forms | 3 |
| S26 | Beta | Staged flags, closed test | 3 |
| S27 | Release R4 | Store release, ad film after claims check | 3 |
| S28 | **Release operations and post-launch workstream** | Monitoring and incident response, cost limits (tiles, AI, storage), rollback, deletion SLA for location data, moderation staffing and takedown SLA, support, regional expansion, map-service maintenance; recurring after release | 3 + ongoing |

### Effort total

Engineering estimate: about 130 pw (sum of the sprint estimates above using the lower bound of ranges, design sprints included, excluding the ongoing part of S28 and all external waits), roughly two developers for 15-17 months with the agent workflow. UNKNOWN until S02-S04 calibrate throughput.

## 6. Execution graph and critical path

Dependencies (A -> B means B needs A). One DAG, no alternative readings:

- S00 -> S01 -> S02 (unified activity). S01 -> S04-D -> S04 (GPS core). S01 -> S07 (rights) and S09 (privacy protocol).
- S02 -> S03-D -> S03 (shell). S03 and S04 are INDEPENDENT of each other after S01 and may run in parallel; they meet at S05 and S06.
- S05-D needs S03-D and S04-D; S05 needs S03, S04 and S05-D. S06-D needs S03-D and S04-D; S06 needs S03, S04 and S06-D.
- S05 and S06 -> S07 (route catalogue) -> S08 (discovery) -> S09 (publication protocol) -> S10-D -> S10 (UI, publish flow) -> S11-D -> S11 (offline navigation).
- S03 -> S12-D -> S12; S12-D -> S13-D -> S13; S03 -> S14-D -> S14; S03 and the native sources of S05/S06/S12/S13/S14 -> S15-D -> S15 (dashboard, native sessions only).
- S02 -> S16 (health platforms and files) -> S17 (dedup with external sources, then dashboard regression); S18 and S19 follow S16 conventions; S20 needs S17 and the token vault.
- S22 needs S15 and S12-S14; S23 needs S10 telemetry; S25 -> S26 -> S27 -> S28.

Representative delivery sequence along the longest chain (not a calendar computation; the true longest path with design sprints and release prerequisites is computed in S00 once dates and waits are known): S00 -> S01 -> S02 -> S03-D -> S03 (in parallel with S01 -> S04-D -> S04) -> S06-D -> S06 -> S07 -> S08 -> S09 -> S10-D -> S10 -> S15 -> S25 -> S26 -> S27.

Independent chains that can run in parallel with a second developer: TRAIN (S12, S13), BODY (S14), devices (S16-S21 after S02), Phase 1 fixes.

## 7. Calendar view: external waits (separate from effort)

| Wait | Needed before | Owner | Typical dependency |
|---|---|---|---|
| Operator decisions in section 10 | per sprint (see ENTRY column) | Operator | none |
| Tile provider and route data licences / accounts | S07, S11 | Operator | provider terms, possibly fees |
| Clinical reviewer for body and nutrition-aware training claims | S14 claims, S22 | Operator/external | contracting |
| Q-4, Q-5, Q-6, Q-10 and a face detector | S14 flags | Operator/external | keys, bucket IAM, legal text |
| iOS device and developer account | any iOS claim | Operator | purchase and enrolment |
| Wear OS release signing | S19 | Operator | key management |
| Partner programmes (Garmin, Suunto, TrainingPeaks) | S20 | Operator | approval |
| Photography, yoga media and music licences | S12, S13, S27 | Operator | rights |
| Legal review of privacy text for location | S09 | Operator/counsel | text approval |
| Device lab time (operator phone) | S04, S19, S25 | Operator | availability |

Calendar duration = engineering critical path plus the longest unresolved wait on each sprint; it is not computed here because the dates of the waits are UNKNOWN.

## 8. Stage gates

| Gate | Condition |
|---|---|
| G-0 | S00 migration complete and backend separation gate green; S01 contracts approved |
| G-A | S02 persistence and consent matrix reviewed; no open BLOCKER/MAJOR |
| G-B (alpha R2) | Shell, chooser, dashboard skeleton, EXPLORE recording on the operator's device; consents verified; deletion/export cover raw samples |
| G-C (beta R3) | RIDE, route catalogue, discovery, publication with working moderation and takedown, TRAIN lens, BODY staged; location privacy text approved |
| G-D (release R4) | Offline navigation decision executed, devices subset, accessibility pass, store/data-safety forms, monitoring owner, GPT-PM approval on exact head |

## 9. Epic catalogue and original-vision traceability

Epic catalogue:

| Epic | Name | Sprints | Backlog link |
|---|---|---|---|
| EP-0 | Split, contracts, baseline | S00, S01 | new |
| EP-1..EP-4 | Mode state, chooser, dashboard skeleton, sources | S03 | P2-010, P2-036 |
| E1 | Activity foundation | S02 | P2-006, P2-007 |
| E3 | GPS recording, walk, run, cycle | S04-S06 | P2-009, P2-022..024 |
| EP-8a..d | Route catalogue, discovery, publication and moderation, offline navigation | S07-S11 | new (blueprint) |
| EP-9, EP-10 | TRAIN lens, Yoga | S12, S13 | blueprint section 03 |
| EP-11 | BODY integration | S14 | P2-018, P2-019 |
| EP-12 | Global dashboard | S15 | blueprint section 02 |
| E2, E8, E5, E6, E7, E4 | Devices and ecosystem | S16-S21 | P2-027..033 |
| E9, X-26 | Cross-mode adaptation | S22 | P2-017, P2-026 |
| E10 | Competitive/ecosystem study (legal methods) | S01 and alongside S02-S08, timeboxed | P2-003..005 |
| E11 | Privacy, consent, retention | every sprint | P2-008, P2-035 |
| EP-13 | Release operations | S28 | new |

Traceability of all 75 original items (`FITNESS_APP_TASK_LIST.md`): status I = included (Phase 1 done or planned), P2 = Phase 2 sprint, D = deferred (needs operator decision or later), R = rejected for now (reason), X = dormant code kept.

| Items | Status and home | Reason / note |
|---|---|---|
| 1, 6, 8, 9 | I, Phase 1 core (QR, catalogue, scraper pilot) | built |
| 2 | X, `celebrity_plans`; D | rights and cost |
| 3, 11 | I, Phase 1 onboarding/plans; P2 per-mode questions S03; BODY S14; S22 | |
| 4, 13 | I, subscription; prices HELD; D-9 | |
| 5 | P2, UI-0 and the whole UI programme | |
| 7 | D; outdoor stations in S12 as a first step | sponsor network needs business decisions |
| 10 | P2, S15 calendar, S22 | |
| 12, 67 | R until a legal framework exists | consent and legal exposure |
| 14, 15, 18, 30, 31, 32, 61, 62, 63 | D (business) | operator business decisions |
| 16, 22, 24 (support), 55, 57, 74, 75 | P2, S24 (and accessibility every sprint) | growth features; safe incentives only |
| 17 | D; cryptocurrency payments R | real-money actions are operator-only |
| 19, 50 | P2 partial: route community S09; buddy dormant | full social network deferred |
| 20, 38 | I, Phase 1 form coach | device acceptance open |
| 21, 44, 45 | P2, S16-S20 | |
| 23, 34 | D | needs venue/event data and partners |
| 25, 59 | D (B2B) | |
| 26 | P2, S15 | |
| 27 | P2, S12 | |
| 28, 56, 58, 60, 66 (partially), 71, 72 | D/R | out of focus; moderation for routes is S09 |
| 29 | P2, S27 | |
| 33 | D (EN and RU parity first) | |
| 35, 37, 39 | I, Phase 1 safety and recovery; extended S22 | clinical review external |
| 36 | P2 proposal in S11 (live location share with emergency contact) | outdoor modes raise its value |
| 40, 41 | I, Phase 1 ai_planner and ai_coach; S22 adaptation | |
| 42 | X, `cycle_aware` dormant | |
| 43 | I, voice; used in S05, S06, S13 | |
| 46, 51, 52, 53, 54 | R/D | clinical and legal scope |
| 47, 48, 49 | D | marketplace and live classes |
| 64, 65, 68, 73 | Every sprint (E11, accessibility) | |
| 69 | I, Phase 1 offline; P2 S11 | |
| 70 | P2 proposal in S12 | |

## 10. Operator decision register (answers F-01; fields: owner, deadline, blocks, default, status)

Groups: **S00 ENTRY** (needed to start S00), **SPRINT ENTRY** (needed before the named sprint), **GO-LIVE** (needed before release of the named feature). All owners are the operator unless noted. Status of all: OPEN.

| ID | Decision | Group | Deadline (before) | Blocks | Default if not decided |
|---|---|---|---|---|---|
| D-1 | Phase rule interpretation in `01` section 4; D-1b boundary cases (e.g. `training_context`); D-1c delivery of experiments (flag only vs physically absent) | S00 ENTRY | S00 | S00 | Interpretation as written; boundary cases stay Phase 1; flag only | **ANSWERED 2026-10-15: yes as written; boundary case training_context stays in Phase 1; experiments flag-only** |
| D-2 | PR #5 target: retarget to `phase2/main` (recommended) or merge into Phase 1 behind flags | S00 ENTRY | S00 step 3 | PR #5 landing | Retarget | **ANSWERED 2026-10-15: retarget PR #5 to phase2/main** |
| D-4 | Separate Firebase project alias for Phase 2 | S00 ENTRY | S00 exit | any Phase 2 cloud write | Emulator only until decided | **ANSWERED 2026-10-15: yes, separate Firebase alias** |
| D-5 | Option A / B / C for the split | S00 ENTRY | S00 | S00 | Option A | **ANSWERED 2026-10-15: Option A** |
| D-3 | Fate of the `master` name | SPRINT ENTRY | S25 | nothing | Keep `master` as Phase 1 default |
| D-10 | Legal status of the third-party app dossier (keep outside git; counsel review?) | SPRINT ENTRY | S01 | S01 E10 study | Dossier not used as a technical source; kept outside git |
| D-16 | Retention of GPS and heart-rate streams (design default two years is open) | SPRINT ENTRY | S01 contract | S02 | Device-only until decided |
| D-17 | Minors, sharing and public routes; age rules | SPRINT ENTRY | S01 contract | S01 contract, S09, S10 | Under-18 and unknown age: no public sharing |
| D-6 | Map tile provider and licence (offline use allowed?) | SPRINT ENTRY | S07 (study in S01) | S07, S11 | No map service; recording and lists only |
| D-7 | Route data sources and first-release region | SPRINT ENTRY | S07 | S07, S08 | Own users' tracks only |
| D-12 | iOS scope and device availability | SPRINT ENTRY | S04 | iOS claims | Android first; iOS NOT_RUN |
| D-8 | Product name and branding rights | GO-LIVE | S27 | public assets | Working name Fitness App |
| D-9 | Monetisation per mode (free/Standard/Celebrity gates) | SPRINT ENTRY | S03 (entitlement design) | S03 gates | All new modes behind flags, no new paywall |
| D-11 | Yoga content strategy and media licences | SPRINT ENTRY | S13-D | S13 | Own text sequences without video |
| D-13 | Wear OS release signing | SPRINT ENTRY | S19 | S19 | S19 deferred |
| D-14 | Partner applications (Garmin, Suunto, TrainingPeaks) | SPRINT ENTRY | S20 | partner adapters | Platform stores and files only |
| D-15 | Clinical reviewer for body and nutrition-aware training claims | GO-LIVE | S14 claims, S22 | claims | No claims beyond "sensible default" |
| D-18 | Nutrition database region | SPRINT ENTRY | S14 | food lookup go-live | Existing sources, flags OFF |
| D-19 | Body-fat number: keep provisional with banner, or hide until a real model | GO-LIVE | S14 | BODY activation | Keep with banner |
| D-20 | Sprint cadence and start date | SPRINT ENTRY | S00 | calendar | No fixed dates |
| U-1 | Replace the Scan tab with a context-sensitive Record action | SPRINT ENTRY | S03-D approval | S03-D | Keep five tabs, Record as a shell action. **ANSWERED 2026-10-16: keep five tabs, Record as a button over the screen** |
| U-2 | Tablet and large layouts now or later | SPRINT ENTRY | S15-D | responsive scope (the tablet chooser in S03-D is a design-only variant, not built in S03, while U-2 is OPEN) | Phone first. **ANSWERED 2026-10-16: NOW, and wider than tablets: the design covers Android phone, iPhone, iPad, Android tablet and MacBook, that is both the Android and the Apple families. The repository has only an `android` platform folder today (no ios, macos, web); whether and when iOS, iPadOS and macOS builds are created is a separate open question** |
| U-3, U-5 | Photo policy; lime corner wedges in app or marketing only | SPRINT ENTRY | UI-M | visual asset contract | Licensed photography; wedges in marketing only |
| U-4 | Voice and music licensing | SPRINT ENTRY | S13-D / S06-D audio | audio features | No licensed music |
| U-6 | Final name and logo | GO-LIVE | S27 | brand assets | Working name |

Of these, only D-1, D-2, D-4 and D-5 block starting S00.

## 11. Release and data-lifecycle matrix (one row per data class; completed in S01)

| Data class | Mode | Collected | Local | Cloud | Shared | Retained | Exported | Deleted on account/record delete | Logged |
|---|---|---|---|---|---|---|---|---|---|
| Raw GPS samples | RIDE, EXPLORE | on recording only | journal until synced | private object | never | per D-16 | yes (GPX/FIT) | yes | counts only, no coordinates |
| Derived route geometry (private) | RIDE, EXPLORE | on save | cache | private | no | with the activity | yes | yes | no coordinates |
| Published route and previews | RIDE, EXPLORE | on publish | cache | public/unlisted | by visibility | until unpublished | yes | detached or deleted per contract | ids only |
| Route photos | RIDE, EXPLORE | optional | cache | private/public | by visibility | until deleted | yes | yes; EXIF stripped on upload | no |
| Background location | RIDE, EXPLORE | only during an active recording | n/a | n/a | never | n/a | n/a | n/a | permission state only |
| Health and heart-rate streams | all | per source consent | device-only default | only with consent (D-16) | never | per D-16 | yes | yes | no values |
| Workout logs (gym/home/yoga) | TRAIN | per session | yes | yes | no | account lifetime | yes | yes | no |
| Body photos | BODY | on scan, consent | local | only with `BODY_SCAN_CLOUD` | never | per setting | links only | yes | no |
| Meal and label photos | BODY | on capture | not stored | never stored server-side (D-27) | never | n/a | n/a | n/a | no |
| Nutrition diary and weight | BODY | on entry | yes | yes | no | account lifetime | yes | yes | no |
| Friends and groups (future) | RIDE, EXPLORE | opt-in | yes | yes | to members | until left | yes | yes | ids only |
| Minors | all | rules from D-17 | | | no public sharing | | | | |

Release and operations obligations (post-launch workstream S28): monitoring and incident response, cost limits, rollback, deletion SLA, moderation and takedown SLA, region expansion process, support channel.

## 12. Market scan and what we adopt (evidence grade C unless noted; official-source confirmation required before a requirement)

| Reference | Pattern (source) | What we adapt |
|---|---|---|
| Komoot | Discipline-aware route planning with distance, elevation and surface; user "Highlights"; offline needs a paid tier ([cyclingweekly/ma-voie-verte roundups](https://www.ma-voie-verte.fr/en/the-mag/our-2026-comparison-of-the-best-gps-apps-for-cycling/); [support.komoot.com](https://support.komoot.com/hc/en-us/articles/10257335663130-Understand-komoot-route-suggestions)) | Reason line, elevation and surface card, separate discovery and navigation flows |
| Ride with GPS | Large route library, turn-by-turn and offline maps on the paid tier ([cyclingweekly](https://cyclingweekly.com/group-tests/best-cycling-apps-143222)) | Explicit "ready offline" status, size control |
| Strava | Suggested routes, segments, social ([bikeradar](https://www.bikeradar.com/features/best-cycling-apps/); onboarding with a sport picker [screensdesign](https://screensdesign.com/articles/strava-onboarding-design/)) | Mode picker at start, share defaults private |
| AllTrails, Outdooractive, Wikiloc, Gaia, FarOut | Nearby trails, offline maps, trail conditions, wrong-turn alerts ([outdoorsmagic roundup](https://outdoorsmagic.com/article/best-hiking-apps/)) | Verified-only condition warnings, recovery without signal |
| Down Dog | Personalised yoga by duration, level, focus, voice, music ([appetiser roundup](https://appetiser.com.au/blog/best-yoga-app/)) | Yoga sequence model, pace and voice choices, no copied content |
| Onboarding patterns | Every choice should visibly change the experience; changeable later ([screensdesign](https://screensdesign.com/articles/fitness-app-onboarding-examples/)) | Chooser questions per mode that change the home |

The scan used standard web search only (blog roundups, some affiliate-driven); it does not prove current feature sets or pricing. The accessible-route question returned nothing useful, so accessible routes stay verified-metadata-only.

## 13. Additions and improvements proposed

Unchanged list of 15 proposals: mode as lens; adaptive Today; cross-mode readiness with reasons; weekly plan calendar across modes; route safety layer; accessibility routes (verified only); walk/ride buddies after privacy review; bike and shoe wear tracking; weather-aware suggestions; outdoor QR/NFC stations (the moat); voice and glanceable live screens; Wear tile and widgets; data-portability promise; read-only reuse of open-source designs; honest ad film. New proposal: optional live-location share with an emergency contact for outdoor modes (original task 36), placed in S11.
