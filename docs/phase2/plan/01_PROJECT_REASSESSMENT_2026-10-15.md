# Fitness App: project reassessment (planning document, not approved)

Date: 2026-10-15. Status: DRAFT FOR GPT-PM REVIEW, then operator approval. Nothing in this document has been executed: no branch, folder, tag, commit or code change follows from it until the operator approves the plan.

Evidence labels: FACT (read in a file or a command output this session), INFERENCE, HYPOTHESIS, UNKNOWN. Statuses are taken from project documents with their own dates; they were not re-run against devices or CI (operator rules: no full suites, no CI).

## 1. Inputs reviewed

| Input | What it is | Use in this plan |
|---|---|---|
| `D:\Downloads\FITNESS_APP_4_MODES_PRODUCT_BLUEPRINT_RU_2026-10-15.docx` | Product blueprint: four modes TRAIN / RIDE / EXPLORE / BODY, global dashboard, metrics, architecture, roadmap, 40 s ad script, design tokens | Product source of truth for Phase 2 (its own caveat: concept, not a claim of readiness) |
| `D:\Downloads\gemini_generated_video_18467594.mp4` (20 s, 1280x720, AI-generated concept film) | Mood and UI direction: HUD glass panels, lime accent, four-card mode carousel, route and scan overlays, dashboard | Analysed frame by frame in `04_UI_UX_DIRECTION` (UI text in the film is garbled by the generator: a mood board, not a spec) |
| `D:\Repo\APK_Research\analysis\10_full_reverse_engineering_ru.md` (+ parts 00..09) | Operator-supplied technical dossier on a third-party body-fat app (BodyFat AI 2.9.4) | Read for product behaviour and risk lessons only; see decision D-35 handling in section 9 |
| Project repository (`D:\Repo\Fitness_App`, worktree `D:\Repo\Fitness_App_bodyscan`) | 1,133 commits before 2026-10-10 on master plus the Body Scan sprint branch | State, gates, structure |
| Core documents | `FITNESS_APP_TASK_LIST.md` (75-item vision), `core/CURRENT_STATE.md`, `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md`, `core/plans/PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md`, `core/plans/ROADMAP_2026_V2.md` (STALE since 2026-07-28), `docs/Redisign/*` | History, backlog, design contract |
| Market scan (public web, standard search, 2026-10-15) | Route apps (Komoot, Ride with GPS, Strava), hiking (AllTrails, Komoot, Outdooractive, Wikiloc, Gaia, FarOut), yoga (Down Dog, Alo, Glo), onboarding patterns | Evidence grade C (blogs and roundups, some affiliate-driven); needs official-source confirmation per feature before it justifies a requirement |

## 2. Where the project stands (FACT unless marked)

- Code size: 530 Dart files in `mobile/lib`, 541 Dart test files, 59 server TypeScript source files, 47 server test files; 40 feature folders in `mobile/lib/features`.
- History: first commit 2026-05-07; 1,133 commits before 2026-10-10; 29 on master since (hardening PRs #2, #3, #4 merged 2026-10-13/14). Branch `feature/body-scan-nutrition-coach` has 227 commits over master; PR #5 is OPEN at head `cd9d7c3a` with GPT-PM APPROVE on that exact head.
- The product is built and was handed over for device checks, but commercial release readiness is NOT established: `core/CURRENT_STATE` and the 2026-10-07 review document state REVIEW_DOCUMENTED; independent audits (2026-08-16, 2026-08-25) returned NOT_RELEASE_READY. Remediation of the code review is closed locally; external gates remain.
- Open external or operator gates (from the generated ledger `core/CURRENT_STATE.md`): D1 and H3 (clinical review of the injury/safety tag catalogue; `kSafetyTagsClinicallyReviewed` stays false), CT1 human labels (HUMAN_REVIEW_LABELS = 0; equipment recognition measured 0/18..1/18 on real photos per project documents), S23 device acceptance of the form coach, Stripe price IDs, privacy and store items, App Check enforcement, scanner repository split.
- Body Scan + Nutrition Coach sprint (2026-10-15): code complete, 5,837 focused tests green (agent-run, one file at a time), five GPT-PM review rounds, approved head `cd9d7c3a`, all new features behind flags default OFF (`BODY_SCAN_CLOUD`, `FOOD_AI`, `FOOD_LOOKUP`). The body-fat number is a PROVISIONAL anthropometric estimate (Deurenberg, +/-5 points), photos do not affect it. Go-live gates Q-4, Q-5, Q-6, Q-10 and a real face detector are operator-owned.
- Navigation today: five bottom tabs (Home, Workouts, Scan, Progress, Profile) and about 45 routes. There is no mode concept, no GPS recording, no route model, no maps.
- UNKNOWN: current state of the HUD redesign (sub-gates close one at a time; open count unknown), O5..O10 onboarding status, G13..G17 form-coach gate status, whether the three older sprint branches and the QA branch still hold unmerged value.

## 3. Strategic assessment

1. **The blueprint is a different product shape, not a feature list.** Today the app is a gym and equipment product (QR/visual equipment recognition, catalogue of 1,887 clip-backed exercises, form coach, AI coach, subscriptions). The blueprint makes it a four-world product with one identity, one history and one dashboard. The bridge is the canonical `ActivitySession` (the sprint delivered the pure-Dart model and merger, no persistence, no UI).
2. **The riskiest assumption is GPS.** RIDE and EXPLORE require foreground/background location, battery, crash-safe recording, maps and a route catalogue with rights. None exists. This is the largest new engineering area and the main privacy surface (location history is more sensitive than workout logs).
3. **Route content is a data and rights problem before it is a code problem.** "Routes near me by skill" needs a route source (own users, OpenStreetMap-derived, partners), a tile provider with a licence that allows the use, and moderation. None is decided.
4. **TRAIN is mostly done and must not regress.** Gym, equipment and form coach are the existing moat; Home, Outdoor and Yoga are additions. Yoga needs its own session model (blueprint is explicit).
5. **BODY is built but gated.** It needs operator decisions (Q-4, Q-5, Q-6, Q-10), a real face detector and a real estimation model before it can claim more than a rough range.
6. **Medical and safety obligations are the hard constraint for the whole plan:** the injury filter, clinical review D1/H3, minors (under 18 get no nutrition plan), body-image safety, location privacy. These are not optional features.
7. **Process risk.** The previous sprints show the failure pattern of this programme: large scope, many branches, gates that only an outside party can close. The plan therefore starts with consolidation (one repo layout, one decision list) before new construction.

## 4. Phase definitions (operator instruction 2026-10-15, interpreted)

Operator rule, restated: Phase 1 is everything that was planned before 2026-10-10; everything planned after is Phase 2. If something belonging to Phase 2 lands in Phase 1 it is called an EXPERIMENT and is not developed further inside Phase 1. All of Phase 1 is cloned into Phase 2 for continued development. Phase 1 is the first production MVP and is synchronised with Phase 2 continuously.

Interpretation used in this plan (to be confirmed, see D-1):

- **Phase 1 = production MVP line.** Scope: the pre-2026-10-10 plan (gym/equipment QR, catalogue, scanner, workouts and programmes, form coach, AI coach, progress, profile, subscription, safety, deletion/export, onboarding). Work allowed in Phase 1: fixes, security, release readiness, store and legal gates. No new product features.
- **Phase 2 = development line.** Starts as a clone of Phase 1 and carries everything planned after 2026-10-10: the four-mode product, GPS modes, Body Scan + Nutrition Coach, activity foundation, devices, global dashboard, new UI.
- **Experiment** = a post-2026-10-10 feature that exists in the Phase 1 code line. Marker: feature-flag default OFF plus an entry in the experiments register. Experiments are frozen in Phase 1 and developed only in Phase 2.
- **Synchronisation** = one-way by default: every change accepted into Phase 1 (fix, security, release) is merged into Phase 2 promptly. Phase 2 work goes back to Phase 1 only as an explicit backport decision (e.g. a fix).

Classification of the current code (by feature folder; planning date from the documents):

| Class | Feature folders / items | Notes |
|---|---|---|
| Phase 1 core (planned before 2026-10-10) | auth, splash, about, onboarding, home, equipment, visual_equipment, scanner, catalog, workouts, programmes, training_context, recovery, personalisation, form_check, posture, voice, ai_coach, ai_planner, progress, progress_photos, profile, settings, legal, licences, subscription, safety, account_deletion, data_export | Release-readiness gates apply |
| Phase 1 dormant (planned, no caller or no screen) | marketplace, celebrity_plans, donor_wall, community, social_feed, buddy, cycle_aware, goal_photo, moments, sdk_export, insurance, body_comp | Kept compiled, dormant by operator decisions (N-04, N-07, F025); Phase 2 decides each |
| EXPERIMENT (planned 2026-10-09..15, present in the sprint branch, flags OFF) | body_scan, nutrition_plan, food_diary, activity (foundation) | PR #5. Frozen in Phase 1; developed in Phase 2 |
| Phase 2 new (not started) | modes shell, GPS recording, routes and discovery, RIDE, EXPLORE, yoga, home/outdoor training, global dashboard, device adapters, social route sharing, new UI | See roadmap |

### 4.1 Feature provenance inventory (answers GPT-PM F-04)

The operator's criterion is when a function was FIRST PLANNED, not when it was implemented or last touched. The table below gives measured Git facts (first and last commit touching the folder, Dart file count; FACT from `git log` on 2026-10-15) and the planning evidence. "Planned by" is taken from `FITNESS_APP_TASK_LIST.md` items or the named plan; where no pre-2026-10-10 planning document was found the cell says UNKNOWN and the class is a PROPOSAL for the operator (D-1b). Readiness is a separate column and is NOT a release certification (`phase1-baseline` is a historical Git cut, not a production-ready certificate).

| Folder | First / last commit | Files | Planned by (evidence) | Proposed class | Readiness note |
|---|---|---|---|---|---|
| auth | 05-07 / 08-29 | 7 | Task list 4, 13 | Phase 1 core | guest-upgrade closed |
| splash | 05-07 / 08-21 | 1 | foundation | Phase 1 core | |
| home | 05-07 / 10-15 | 5 | Task list 5; HUD plans | Phase 1 core | last touch is the sprint's entry card (flagged) |
| profile | 05-07 / 10-15 | 11 | Task list 3 | Phase 1 core | |
| progress | 05-07 / 10-15 | 3 | Task list 26 | Phase 1 core | |
| scanner | 05-07 / 09-17 | 9 | Task list 1, 9; ML platform P0-P6 | Phase 1 core | recognition accuracy claims blocked by CT1 labels |
| equipment | 05-08 / 10-14 | 30 | Task list 1, 8, 9 | Phase 1 core | |
| onboarding | 05-08 / 10-15 | 23 | Task list 3 (questionnaire), O-series plans | Phase 1 core | O5-O10 status UNKNOWN; last touch adds the nutrition-profile step (flagged) |
| subscription | 05-08 / 10-15 | 11 | Task list 4, 13, 17 | Phase 1 core | prices HELD |
| about, catalog, workouts, visual_equipment, personalisation, recovery, form_check, ai_planner | 05-10 / 10-13..14 | 1, 5, 39, 35, 5, 4, 39, 5 | Task list 2, 8, 11, 20, 38, 39, 40 | Phase 1 core | form coach beta; S23 acceptance open |
| ai_coach, licences, settings | 07-30 / 08-26..10-13 | 5, 1, 1 | Task list 41 and compliance | Phase 1 core | AI release gated by G4 |
| legal, account_deletion, data_export, safety | 08-05..08-15 / 10-15 | 3, 5, 8, 7 | Task list 35-39, 64, 65, 73 | Phase 1 core | clinical review D1/H3 external |
| programmes, posture | 08-08..09 / 10-15, 08-29 | 12, 4 | Task list 11, 20 | Phase 1 core | programmes touched by the sprint's nutrition hook (flagged) |
| progress_photos | 05-10 / 10-15 | 35 | Task list 26 | Phase 1 core | last touch adds the body-scan hand-off (flagged) |
| training_context | 10-13 / 10-14 | 3 | Hardening sprint of 10-13 (remediation of the 10-07 review) | BOUNDARY CASE | Planned 10-07..13: remediation of pre-10-10 scope, so Phase 1 by intent, post-10-10 by date; operator ruling D-1b |
| marketplace, celebrity_plans, donor_wall, community, social_feed, moments | 05-10 / 08-29..10-13 | 4, 4, 5, 4, 4, 5 | Task list 19, 32, 48, 2, 14, 74 | Phase 1 dormant | no caller or HELD; Phase 2 decides each |
| buddy, body_comp, cycle_aware, goal_photo, sdk_export, voice | 05-10 / 05-10..08-17 | 1 each | Task list 50, 45, 42, 58, 75, 43 | Phase 1 dormant | logic-only, no screens |
| body_scan, nutrition_plan, food_diary, activity | 10-15 / 10-15 | 48, 37, 32, 11 | Planned 2026-10-09..15 (`PHASE2_BODY_SCAN_COACH_REFERENCE_REVIEW_2026-10-09`, sprint plan 10-15) | EXPERIMENT | Flags OFF; frozen in Phase 1; PR #5 |

Count check: 40 feature folders in `mobile/lib/features`. Server-side and rules additions of the sprint (body scan, food, activity callables, collections) follow the same classification: experiment, flagged. The experiments register (`docs/EXPERIMENTS.md`, created in S00) is generated from this table plus a per-flag list, and each row names its removal path from Phase 1 delivery (flag OFF is the default; if the operator wants the code physically absent from the Phase 1 build, that is a build-profile decision, D-1c).

Experiments already in Phase 1 history: none of the code (FACT, `git ls-tree origin/master`: no `body_scan`, `nutrition_plan`, `food_diary` or `activity` folder). Only one planning document of the experiment family is on master (`core/plans/PHASE2_BODY_SCAN_COACH_REFERENCE_REVIEW_2026-10-09.md`); it is documentation, filed under `docs/phase2` navigation in S00. The experiment concept therefore applies to PR #5 only, which is why its target branch (D-2) matters.

Open question D-2: PR #5 currently targets `master`. Under the operator rule it is an experiment and belongs to the Phase 2 line (recommended: retarget the PR to the Phase 2 base branch after the split; the approved head does not change).

## 5. Review of existing planning documents (what to keep, what to retire)

| Document | Verdict |
|---|---|
| `FITNESS_APP_TASK_LIST.md` (75 items) | Keep as the historical vision. Its own banner says it is not a feature list. Items with a new home in this plan are mapped in `03_ROADMAP_AND_SPRINTS` section 9 |
| `core/plans/ROADMAP_2026_V2.md` | STALE since 2026-07-28 (flagged). Retire from forward planning; archive under Phase 1 docs |
| `core/MASTER_PLAN_2026-08-26.md` | Phase 1 plan of record for the gates P0..P6, OBS-1, MVP1; keep, mark as Phase 1 |
| `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` (E1..E12, 40 imported stories) | Becomes the device/sport epic source for Phase 2; re-sequenced here |
| `PRODUCT_PHASE2_EXPANSION_RECONCILIATION_2026-10-15.md` | Keep; its conflict resolutions (design wins) stay in force |
| Blueprint docx | Becomes the Phase 2 product vision; to be committed as Markdown by the technical writer after approval |
| Existing reports | Kept as history |
| Document registry | FACT: `core/INDEX.md` is the hand-maintained canonical entry point; `core/CURRENT_STATE.md` is generated and must not be hand-edited; no registry generator for `governance/DOCUMENT_REGISTRY.md` exists in the repository (only plan documents mention it). The workspace contract still requires a generated registry; S00 adds a small generator that writes `docs/DOCUMENT_REGISTRY.md` as a derived listing and never duplicates decisions. `docs/phase1/` and `docs/phase2/` hold navigation indexes only |

Contradictions found and how this plan resolves them:

1. Blueprint says "tab for mode switch in app shell, shared tabs Progress/Coach/Profile stay"; current shell has five tabs with Workouts and Scan as primary. Resolution: see `04_UI_UX_DIRECTION` (mode becomes a lens over Home and a context for the middle tabs).
2. The Phase 2 backlog lists sports as Android-first with iOS unverifiable (no device); the blueprint promises Android and iOS. Resolution: iOS is NOT_RUN until an iOS device and developer programme exist (operator-owned, D-12).
3. Blueprint P0 asks for "audit current Flutter/brand"; the repo already holds approved tokens and a handoff (`docs/Redisign`). Resolution: UI baseline sprint audits the implemented HUD migration rather than redesigning it.
4. The operator's APK dossier exists although decision D-35 (2026-10-15) refused reverse engineering of proprietary apps. Resolution: section 9.

## 6. Project risk register (top items)

| ID | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R-1 | Location privacy incident (public route reveals home, bad default visibility) | medium / severe | Private default, privacy zones, per-purpose consents, exportable and deletable raw samples, legal text before any public route sharing |
| R-2 | GPS recording unreliable (kill, drift, battery) | high / high | Foreground service, journaled samples, crash-resume tests, device lab on the operator's phone, accuracy gates |
| R-3 | Route/tile/POI data licence blocks release | medium / high | Decide data and tile sources first (D-6, D-7); attribution file; kill switch |
| R-4 | Scope explosion across four modes | high / high | Mode-by-mode release trains; flags default OFF; unified session first |
| R-5 | Medical/body-image claims (body scan, nutrition) | medium / severe | Keep PROVISIONAL labelling; minors lockout; clinical review before claims |
| R-6 | External gates never close (clinical D1/H3, labels CT1) | high / medium | They block Phase 1 release only for what they gate; Phase 2 work proceeds on independent parts |
| R-7 | Branch and worktree sprawl (7 worktrees, 9 local branches, stale branches) | high / medium | Split plan in `02_PHASE_SPLIT_AND_REPO_LAYOUT`, branch retirement list |
| R-8 | iOS never verified | high / medium | Android first; iOS marked NOT_RUN; decision D-12 |
| R-9 | Third-party app research becomes a legal liability | medium / high | Section 9 |

## 7. What is explicitly NOT changed by this plan

Safety clamps and the minors rule of the nutrition design; flags default OFF; the injury filter; operator-only actions (money, unrecoverable deletion); the rule that tests are written and run by the named test agents only after sprint coding; one PR per sprint; GPT-PM approval on the exact head before push.

## 8. Reassessment verdict

The project is large and mostly coherent, but it is a gym product with a finished safety and data backbone and an unfinished release story. The four-mode product is feasible as an evolution (blueprint's own conclusion), provided that (1) the repository and documents are split and cleaned first, (2) the unified session, consent matrix and shell are built before any GPS or route feature, (3) the route data/tile/legal decisions are made before GPS UI work, and (4) every mode ships as a flagged release train with its own design contract and UI sprint.

## 9. Third-party app research and decision D-35

D-35 (decision log, 2026-10-15): reverse engineering, decompiling and traffic interception of proprietary apps is refused. The operator-supplied dossier `D:\Repo\APK_Research\...` documents static decompilation of the BodyFat AI APK and an attempted traffic interception. How this plan treats it:

- The assistant did not perform that analysis and will not extend it (no further decompilation, traffic capture or paywall bypass).
- The dossier is read as an operator-supplied behaviour reference only: product patterns and risks (for example: three-pose capture, quality gate, trend smoothing, plan ownership modes, retention choices). No code, strings, endpoints, assets, constants or model details are reused; our estimator, formulas and copy remain independently derived, as the Body Scan design already states.
- Legal exposure of holding or using the dossier (terms of service, copyright, anti-circumvention law) is UNKNOWN and not assessed here. Operator decision D-10 asks whether to keep the dossier out of git (recommended: yes, keep it outside the repository like the videos) and whether counsel should review it.
