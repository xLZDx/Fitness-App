# S04 documentation readiness (GPS core without a map)

Status: DRAFT, prepared 2026-10-17 while sprint S03 is in its test phase. Documentation only; no code, no commands run. Author role: technical-writer.

Labels: FACT (read in the cited file, path:line), INFERENCE (drawn from facts, stated as such), UNKNOWN (not found or not verifiable in this worktree). Paths are relative to the repository root. "Roadmap" means `docs/phase2/plan/03_ROADMAP_AND_SPRINTS_2026-10-15.md`.

## 1. S04 scope as the roadmap states it

FACT, Roadmap line 89, the S04 row (estimate 5):

> **GPS core without a map** (implements the approved S04-D contract; recorder, not map): foreground-service recorder, journaled samples (crash-safe resume), auto-pause, smoothing and accuracy gate, calculators with replay tests (P2-009), permission flow (foreground first; background only while recording), battery protocol; recording works with no map service

Entry column: "Contract (S01), S04-D approved, D-12 for iOS scope". Exit/DoD: "Survives app kill and screen off; tolerance and battery recorded on the operator's phone".

FACT, Roadmap line 88, the design sprint that S04 depends on (S04-D, estimate 1.5, entry "S01 contract", exit "Approved contract; S04 builds only this"):

> **UI design: GPS permission and recording-state contract** (foreground then background permission journey with denial paths; recording states: acquiring, poor accuracy, offline, paused manual/auto, background, restoring after kill, recovery failed, battery critical, permission revoked mid-recording; shared by EXPLORE and RIDE)

Related facts:
- FACT, Roadmap lines 146-148: the chain is S01 -> S04-D -> S04. S03 and S04 are independent after S01 and may run in parallel; they meet at S05 and S06.
- FACT, Roadmap line 140: the roadmap total uses "pw" for estimates; the unit is not defined in the rows read (INFERENCE: person-weeks). The S04 value 5 is UNKNOWN in calendar terms; throughput is "UNKNOWN until S02-S04 calibrate".
- FACT, Roadmap line 171: S04 needs "Device lab time (operator phone)", owner Operator, dependency "availability".
- FACT, `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` line 94: S04-D deliverable is "State diagram; glanceable rules; battery guard copy; approved before S04".
- FACT, Roadmap line 194: epic E3 (GPS recording, walk, run, cycle) spans S04-S06 and links to backlog items P2-009 and P2-022..024.
- INFERENCE: S04-D is a prerequisite document sprint that is NOT yet written (no `docs/phase2/s04/` file existed before this one; the glob of `docs/phase2/**` shows none). The roadmap does not say whether S04-D has its own branch or is folded into the S04 documentation phase. UNKNOWN.

## 2. Inputs that already exist

| Area | Existing input | Where | Label |
|---|---|---|---|
| Privacy rules for permission flow | Foreground-first flow; background only while a recording is active; denial leaves the app usable; revocation stops collection at once and offers keep, export or delete; no prompt at launch or in onboarding | `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` lines 75-90 (GPS-PRIV-005 to 011) | FACT, all requirements still "PROPOSED" |
| Purpose limitation, least data | Location only while recording or on an explicit feature; sample rate and fields "decided in S04-D" | same file, lines 68-70 (GPS-PRIV-002, 003) | FACT |
| Recording journal retention | Crash-safe journal deleted after confirmed sync, on discard, on sign-out; a journal left by a crash is offered for recovery | same file, line 101 (GPS-PRIV-014) | FACT |
| Raw-sample rules | Owner-only; cloud upload follows the operator's retention answer (section 4); background samples are a collection mode of the same class | same file, lines 99-102, 141 (GPS-PRIV-012 to 015, 034) | FACT |
| Privacy zones | Default trim radius and zone editor "defined in S04-D/S10-D"; value deliberately not fixed in the contract | same file, line 166 (GPS-PRIV-046) | FACT |
| Logging | No coordinates, geohashes, place names or heart-rate values in logs, metrics or crash reports | same file, line 176 (GPS-PRIV-048) | FACT |
| Telemetry guarantee (a precondition for any GPS code) | Server-side closed schema for debug telemetry (GPS-PRIV-050, 098). S02 built the sanitising callable and the `create: false` rule; acceptance is "ACCEPTED WITH LIMIT" because the real callable was not run on a device or emulator | contract lines 178, 338; `docs/phase2/s02/S02_ACCEPTANCE.md` line 33; `docs/phase2/s02/S02_RELEASE_NOTES.md` lines 62, 79 | FACT; real-environment behaviour UNKNOWN |
| Data lifecycle | Row C1 raw samples and C7 background location with collected / local / cloud / retained / deleted / logged columns; matrix rows for the S03 journal and mode state | `docs/phase2/s01/DATA_LIFECYCLE_MATRIX.md` (C7 at line 20) | FACT |
| Data model | `ActivitySession` with `summary`, 8 `StreamKind` values including gps and heartRate, laps, provenance; validation bounds (200 000 samples per stream, lat/lon ranges, strictly increasing offsets) | `docs/phase2/s02/S02_DESIGN.md` lines 28, 256 | FACT |
| Writer seam | One repository owns the journal behind a mutex; "the S04 recorder submit[s] mutations through it and never touch[es] files directly" | `docs/phase2/s02/S02_DESIGN.md` line 452 | FACT |
| Consent in the upload path | PROPOSED consent matrix row "Native recording (app GPS, S04)": GPS needs GPS consent; permission prompts belong to S04 | `docs/phase2/s02/S02_DESIGN.md` lines 415-419 | FACT (PROPOSED) |
| Heart rate in cloud | Hard-denied in the stream payload and rejected by the server validator | `docs/phase2/s02/S02_DESIGN.md` line 63 | FACT |
| Shell integration | Recording strip in the dock above the nav bar; strip derived from `ActiveSessionStatus`; process death clears timers and "no copy claims recovery (crash-safe GPS resume is S04)"; Explore and Ride are "coming later" with no recorder until S04 | `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` lines 88-89, 187, 322-346; `docs/phase2/s03/S03_DESIGN.md` line 45 | FACT; S03 still in test, so these may still change (INFERENCE) |
| Refresh seam for S04+ writers | A bump of `activityJournalRevisionProvider` is the seam for later writers | `docs/phase2/s03/S03_DESIGN.md` line 753 | FACT |
| UI direction | Permission asked at "Start GPS" tap with a one-line reason; no modal dialogs while recording; live ride shows GPS signal state, auto-pause indicator, battery guard; bracket and scan-line motion never on live recording screens; offline-first; denial path fully working | `docs/phase2/plan/04_UI_UX_DIRECTION_2026-10-15.md` lines 54, 63, 76-82, 110, 115 | FACT |
| UI baseline | No recorder, no location package, no foreground service in the audited tree; two token layers (`AppSemanticColors`, `HudTokens`) coexist | `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` line 49 (F18); `docs/phase2/s01/UI0_BASELINE_AUDIT.md` | FACT |
| Current platform state | `permission_handler` is declared; no location package; Android manifest declares only Health Connect permissions (no location, no foreground-service entry) | `mobile/pubspec.yaml` line 75; `mobile/android/app/src/main/AndroidManifest.xml` lines 12-31 (grep for location and foreground-service terms found none) | FACT |
| Map | Recording needs no map; if a map is wanted before S11, interim is a paid hosted plan, not OSM community servers | `docs/phase2/s01/RIGHTS_STUDY_TILES_ROUTES_POI.md` lines 12, 157 | FACT |
| Apple backup rule | Any Apple build target requires `isExcludedFromBackup` marking of the journal before shipping | `core/DECISION_LOG.md` line 57853 | FACT |

## 3. Gaps to fill before a design can be written

Owner = the document type and the agent role that should write it. Agents are the allowed-model roles of the repository workflow.

| # | Gap | Evidence | Document type | Role |
|---|---|---|---|---|
| G1 | No S04-D UI contract exists. Permission journey, denial paths and the nine recording states have no screens, copy, state diagram or glance rules. Without it S04 cannot start ("S04 builds only this"). | Roadmap line 88; UX direction line 94 | UI design contract (`S04D_UI_DESIGN_CONTRACT.md`): journeys, state diagram, RU/EN copy, accessibility spec, battery-guard copy | ui-designer (with product-owner for acceptance wording) |
| G2 | Requirements for the recorder itself are not written as stories with acceptance criteria. The contract covers privacy only; sampling rate, accuracy gate thresholds, smoothing, auto-pause rule, journal flush interval, kill-recovery behaviour, and "tolerance" (what error is acceptable) are not defined. The "calculators with replay tests (P2-009)" story text was not read. | Roadmap line 89; contract line 70 defers rate and fields to S04-D; backlog file `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` not located in this worktree (UNKNOWN) | Requirements and stories with acceptance criteria | business-analyst (requirements), product-owner (stories, DoD, tolerance numbers) |
| G3 | Recording journal vs the S02 activity journal is unspecified. The contract says "crash-safe recording journal of S04" is distinct from the permanent S02 store; the S02 design says the recorder writes through the S02 repository. Format, location, sealing, hand-off at stop, and recovery offer are not decided. | Contract line 101; S02 design lines 137, 452 | Technical design section (data model + failure modes) | architect |
| G4 | Android platform constraints are unverified: foreground-service type for location, required manifest entries, Play declarations for background location, Android 13+ notification permission for the persistent notification, battery-optimisation behaviour. The contract states intent only. | Contract line 267 ("not checked against official sources"); manifest has none of these | Platform study note (official sources only, grade A/B, like the rights study) | architect, with technical-writer for the record |
| G5 | Battery protocol undefined: what is measured, how, on which phone, over what duration, what counts as "battery critical" and what the app does at that point (state exists in S04-D, behaviour not specified). | Roadmap line 89 "battery protocol", DoD "battery recorded on the operator's phone" | Test protocol plus battery-guard rules | functional-test-reviewer (protocol), architect (thresholds), ui-designer (copy) |
| G6 | Privacy-zone and trim defaults: contract defers the default radius and zone editor to S04-D/S10-D; the S04 scope row does not mention zones, so ownership (S04-D designs the rule, S10-D the editor?) is unclear. | Contract line 166; Roadmap line 91 (S05 DoD "privacy zones default on") | Decision record plus contract note | product-owner (scope split), ui-designer |
| G7 | Consent centre has no sprint. The S03 design assumes "consent centre is its own sprint before S04"; the roadmap has no such sprint, and the UX direction lists it only as a principle. Permission flow needs a stored consent record per purpose (GPS, background location). | `docs/phase2/s03/S03_DESIGN.md` line 977; Roadmap line 17 (name only); contract line 88 (GPS-PRIV-009) | Scope decision, then UI contract and story | product-owner (placement), ui-designer, business-analyst |
| G8 | Test mapping missing: requirement -> story -> acceptance -> test map, replay fixtures (real-shaped tracks, GPS noise, tunnels, kill mid-run), device-lab protocol. | Roadmap line 89 "replay tests" | Test plan | functional-test-reviewer |
| G9 | Interface to S03 shell not frozen. S03 is untested; the recording strip's `ActiveSessionStatus` currently derives only from gym timers, so how a GPS recording feeds the strip and the mode lens is not specified. | `docs/phase2/s03/S03D_UI_DESIGN_CONTRACT.md` lines 327-346 | Integration section of the S04 design, after S03 closes | architect; technical-writer to reconcile after S03 acceptance |
| G10 | Performance gate carried over from S02: payload build, gzip, SHA-256 and journal seal/open must move off the UI isolate with a 100k-sample frame-budget test before any recorder ships. | `docs/phase2/s02/S02_RELEASE_NOTES.md` line 104 | Story plus test | architect, functional-test-reviewer |
| G11 | Privacy wording for location is a DRAFT without approver; background location declaration must equal the used set. | Contract lines 89-90 (GPS-PRIV-010, 011); `docs/sdlc/STATE.md` line 52 | Privacy text request | technical-writer (text), operator or counsel (approval) |
| G12 | iOS is out of scope unless the operator says otherwise; if included, Apple background modes, backup marking and permission strings need their own study. Repository has only an `android` platform folder. | Roadmap line 257 (iOS row); Roadmap line 268 | Scope statement in the design | architect |

## 4. Entry decisions that only the operator can make

Each is stated in words, with the options and what each changes. Defaults come from the roadmap register and the design documents, not from this file.

1. **Does S04 include iPhone?** FACT, Roadmap line 257: default "Android first; iOS NOT_RUN". Option A (default): Android only. Consequence: smaller sprint, one permission model, one device-lab target; no claim of iOS support anywhere. Option B: include iOS now. Consequence: the repository has no iOS project today (FACT, Roadmap line 268), so a platform target, background-location rules, a backup-exclusion fix and a physical iPhone plus developer account are all needed first (FACT, Roadmap line 166 lists the account as an external wait); S04 grows and the DoD cannot be met without that hardware.
2. **Which phone is the reference device, and when is it available?** UNKNOWN (Roadmap line 171 names it as a wait, no model or date). Consequence of no answer: the DoD "tolerance and battery recorded on the operator's phone" cannot be closed, so S04 can be coded and reviewed but not accepted.
3. **Where does the consent centre get built?** The S03 design assumes a separate sprint before S04; the roadmap has none (section 3, gap 7). Option A: add a small design-and-build sprint before S04. Consequence: location consent has one findable home, S04 starts later. Option B: S04 builds only the two location consent rows it needs and the full centre waits. Consequence: S04 stays on schedule, but the centre must later absorb those rows. Option C: no stored consent beyond the system permission. Consequence: contradicts the contract requirement for a consent record per purpose, so not recommended (INFERENCE).
4. **Default privacy-zone trim radius and who owns the zone editor.** Contract leaves the value open (GPS-PRIV-046). Option A: S04-D sets only the default and the setting entry, S10-D designs the editor. Consequence: privacy is on by default early, editor arrives late. Option B: full editor in S04-D. Consequence: larger design sprint and a UI the S04 build does not use. Any radius number is UNKNOWN and must come from the operator.
5. **Default cloud expiry for GPS tracks shown to the user** (the operator already chose: GPS in the cloud with a user-set expiry, heart rate on the phone only; FACT, contract line 232). Still open inside that answer: the default expiry (proposal: 2 years), whether the clock runs from the activity date (proposal) or the upload date, and whether the derived route follows the same setting. Consequence: the recorder itself is unaffected, but the stop-and-save screen and the privacy text cannot be finalised without it.
6. **Upload at launch of the recorder, or device-only first?** The cloud-stream flag is OFF by default and S02 release notes tie enabling it to a performance gate and a deploy order (FACT, `docs/phase2/s02/S02_RELEASE_NOTES.md` lines 104, 111). Option A: S04 ships recording that stays on the device (no upload code path enabled). Consequence: lower risk, no multi-device history until a later sprint. Option B: enable cloud upload in S04. Consequence: needs the server deploy steps, privacy text approval and the performance gate done first.
7. **Who approves the location privacy wording and when?** FACT, contract line 89: approval is required before any route is visible beyond the owner. For S04 (owner-only) the question is whether the permission pre-prompt wording needs the same approval. UNKNOWN. Consequence: if yes, a text approval step lands before the S04 release; if no, the S04 copy is released as draft and approved before sharing in S09.
8. **Is S04-D a separate approved contract, or part of the S04 documentation phase?** The roadmap lists it as its own sprint (estimate 1.5) with an approval gate. Option A: separate, operator approves the contract before S04 design starts. Consequence: clean gate, serial work. Option B: fold it into the S04 documentation phase with one review. Consequence: faster, but the roadmap rule "S04 builds only this" loses its independent approval point.

Decisions already answered and not re-asked: GPS in cloud with user expiry and heart rate device-only; minors and friends rule; open-source map tiles and routes (FACT, contract lines 232-235). The first-release region is not needed for S04 (INFERENCE: it blocks S07 only, Roadmap line 94).

## 5. Proposed order and size of the documentation work

Sizes are INFERENCE from comparable S03 documents (S03 UI contract about 960 lines, design about 1030 lines, test plan about 400 test rows) and are working estimates only, not roadmap values.

| Step | Output | Role | Size (INFERENCE) | Depends on |
|---|---|---|---|---|
| 1 | Operator answers for section 4 items 1-3 and 8 (scope shape, device, consent placement) | operator | one reply | none |
| 2 | Platform study for Android location and foreground service (G4) | architect, technical-writer | small, about 100-150 lines | none; runs in parallel with step 3 |
| 3 | Requirements and stories with acceptance criteria and tolerance numbers (G2, G6) | business-analyst, product-owner | medium, about 300-400 lines | step 1 |
| 4 | S04-D UI design contract (G1, G7, privacy zone defaults) | ui-designer | large, about 600-900 lines; counts as the roadmap's 1.5 estimate | steps 1, 3 |
| 5 | Review of the S04-D contract by internal reviewers, fix pass, GPT review, operator approval | product-ux-reviewer, security-reviewer, then operator | one round plus one fix pass | step 4 |
| 6 | S04 design: recorder architecture, journal hand-off, state machine, failure modes, rollout and rollback, shell integration (G3, G9, G10, G12) | architect | large, about 700-1000 lines | steps 2, 4, S03 acceptance for the integration part |
| 7 | S04 test plan with replay fixtures, device-lab and battery protocol (G5, G8) | functional-test-reviewer | large, about 300-400 rows | steps 3, 6 |
| 8 | Privacy text request for location wording (G11) | technical-writer | small | steps 4, 6 |
| 9 | Reconcile with S03 final design after S03 acceptance; documentation PR | technical-writer, doc-updater | small | S03 closed |

INFERENCE: steps 2 and 3 can start now; step 6's shell-integration section must wait for S03 acceptance, so the S04 design should be drafted in two parts. Total about five to seven agent-days of writing plus review rounds; UNKNOWN until throughput is calibrated.

## 6. Stale or inconsistent documents found, not changed

- `docs/phase2/s03/S03_DESIGN.md` line 977 (consent centre "its own sprint before S04") does not match the roadmap, which has no such sprint (section 3, gap 7). Settled S03 document; left unchanged.
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` lines 100, 210 still describe the GPS and heart-rate retention decision as open ("Until [the retention decision] is decided ... device only") while line 5 and line 232 record the operator's answer. The requirement GPS-PRIV-013 text is therefore stale; the option table is kept as record by design. Needs a doc-updater pass.
- `docs/phase2/s01/GPS_LOCATION_PRIVACY_CONTRACT.md` line 338 says the telemetry task is "scheduled ... in S02"; S02 acceptance reports it done with a limit. Wording on the contract side not updated.
- The backlog file `PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` cited by the roadmap was not found under `docs/phase2/`; the content of P2-009 is UNKNOWN here.
