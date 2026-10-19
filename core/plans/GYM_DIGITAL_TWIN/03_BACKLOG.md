# GYM DIGITAL TWIN — Execution Backlog

Date: 2026-10-19. State: PROPOSED. No implementation GO, commit, deployment or approval of technical details is implied.

## Backlog ground rules

Each story is separately estimable and testable. Priority P0 = prerequisite for first usable private 2D release, P1 = follow-on value, P2 = conditional R&D/advanced. Acceptance criteria are minimum gates, not claims that implementation already passes. ID is stable even if phase/order changes. Epics are GYM-00 through GYM-07 and are not existing program sprint numbers. All code is English, conforms to core/CONVENTIONS.md, and must preserve existing workout, safety, auth and CI checks.

MVP launch does NOT depend on live camera, ML detection or 3D reconstruction. Sequence: foundational GYM-00 -> private 2D GYM-01 -> 2D navigation GYM-04. In parallel/after: guided scan GYM-02, spatial PoC GYM-03, voice GYM-05, shared venues GYM-06, advanced AR/3D GYM-07.

## Epic GYM-00 — Ground truth, ownership, safety and feasibility

**GDT-001 — Exact-HEAD repository contract map | P0 | Depends: none**
- Story: As an implementing engineer, I need documented read/write seams for catalog, scanner, profile gymId, workout action, voice and Firebase rules to avoid duplicate flows.
- Acceptance: paths and current HEAD recorded; current actual behavior separated from prior proposals; equipment type vs physical instance distinction traced; own repo changes not overwritten; reviewer signoff from feature and security surfaces.
- Evidence: source references, trace table, compatibility notes and unresolved gaps.

**GDT-002 — Stable gym identity and legacy display-name bridge | P0 | Depends: GDT-001**
- Story: As a user, I need the same real venue to be unambiguous even if people spell its name differently.
- Acceptance: generated locationId (not profile gymId) and optional branch/floor identity; duplicate names and branches tested; no automatic migration from free text; clear mapping/unmapped state; no third-party venue creation by guessing a slug.

**GDT-003 — Privacy/consent and retention design for gym capture | P0 | Depends: GDT-001**
- Story: As a gym member/bystander, my image or audio is not silently collected or published.
- Acceptance: foreground capture only; separate capture/transmit/share choices; deletion and retention policy documented; no raw images or voice in logs; background camera disabled; redaction and failure handling tested; privacy-law review scheduled for applicable jurisdictions.

**GDT-004 — OSS code/weights/data licensing clearance process | P0 | Depends: none**
- Story: As an owner, I can ship only components licensed for a commercial app.
- Acceptance: every shortlisted code package, model checkpoint and dataset has source, version, rights, obligations and decision owner; unknown/noncommercial components blocked from production; runtime dependency SBOM/license check defined; no "GitHub public = commercially licensed" shortcut.

**GDT-005 — Frozen field-evaluation dataset and measurement protocol | P0 | Depends: GDT-003**
- Story: As a product reviewer, I can compare recognition and mapping methods on real representative venues.
- Acceptance: consented scenes, survey-quality machine instance inventory, floor plan and reference landmarks; distinct identical machines, reflective walls, people, low light and rescan cases; no training/test leakage; measures and accept/reject thresholds proposed for approval before evaluation.

**GDT-006 — Firestore/storage and cross-user ownership threat model | P0 | Depends: GDT-002,GDT-003**
- Story: As a private mapper, my drafts cannot be published or edited by strangers.
- Acceptance: collection-level scope, auth/App Check/claims and server writes defined; wildcards reviewed with Firestore OR semantics; negative tests cover forged owner, arbitrary venue claims, role escalation, untrusted published revisions, ID enumeration and image access.

**GDT-007 — Feature flags, rollout and capability downgrade contract | P0 | Depends: GDT-001**
- Story: As an operator, I can disable risky scan/AR/shared features independently without disabling the existing workout.
- Acceptance: map read, map edit, cloud recognition, spatial capture, voice nav, map sharing and AR flags independently gated; Android/iOS graceful downgrade; map-only mode tested under no network/camera/model.

## Epic GYM-01 — Private map MVP (one floor, no camera dependency)

**GDT-010 — Private gym draft repository | P0 | Depends: GDT-002,GDT-006**
- Acceptance: user-scoped create/read/update of draft with stable generated ID; no read access across UIDs; sign-out invalidates cached personal data; user can continue draft after app restart; never auto-publish.

**GDT-011 — Floor coordinates and immutable map revision model | P0 | Depends: GDT-010**
- Acceptance: documented meters/axes/origin/scale; new revision for geometry changes; published revisions immutable in design; invalid transform and mixed units rejected; one-floor UI but floorId in schema.

**GDT-012 — Import image and draw/calibrate one-floor plan | P0 | Depends: GDT-011,GDT-003**
- Acceptance: authorized image import, scale via reference segment, correct rotation, no implied accurate scale when unknown; editing boundary/obstacles; save/reload preserves coordinates; unauthorized/invalid plan fails visibly.

**GDT-013 — Readable Flutter 2D map viewer | P0 | Depends: GDT-011**
- Acceptance: pan/zoom, floor label, machine selection/highlight, outline/obstacles visible, respect app visual system and accessibility; good behavior on Android and iOS-compatible code; no dependency on camera or AR.

**GDT-014 — Physical equipment instance editor | P0 | Depends: GDT-011**
- Acceptance: users can place/move/rotate/retire independent instanceId items with existing equipmentId; three same-type machines stay distinct; invalid catalog ID is marked unresolved, not stored as pretend existing catalog type; audit provenance.

**GDT-015 — Walkway graph and approach node editor | P0 | Depends: GDT-011,GDT-012**
- Acceptance: nodes/edges and machine approaches explicitly modeled; edges crossing walls/restricted polygons blocked; unreachable components detectable; stairs/floors not silently connected; edits versioned.

**GDT-016 — Confirm/proposed/stale verification UI | P0 | Depends: GDT-014,GDT-015**
- Acceptance: position source and verifier status per element; unconfirmed content never appears as fully navigable; user can approve/correct or clear proposed placements; quality warnings preserved after reload.

**GDT-017 — Offline map read-through cache | P0 | Depends: GDT-010,GDT-011**
- Acceptance: previously downloaded draft/map opens offline; no upload required for reading; version/conflicts handled on reconnection; secure sign-out clears personal map access; failed sync does not lose draft changes.

**GDT-018 — Equipment inventory, search and type filter | P0 | Depends: GDT-014**
- Acceptance: search lists distinct instances with their floor/area and catalog type; duplicates remain visible; missing/no-compatible equipment state explicit; no health/injury claims from map inventory.

**GDT-019 — Private-map usability acceptance | P0 | Depends: GDT-012..GDT-018**
- Acceptance: map a real small single-floor gym, reopen and find all confirmed machines on a fresh session, including duplicates, without asking for camera/network permission; pass screen reader and visible error states; record completion time and corrections.

## Epic GYM-02 — Quick Scan and optional multi-object recognition

**GDT-020 — Foreground guided photo capture | P1 | Depends: GDT-003,GDT-007,GDT-014**
- Acceptance: explicit camera start/stop and permission, cancel/retry, quality prompts, foreground only, no raw media transmission by default; low battery/thermal fallback to manual placement.

**GDT-021 — Reuse existing single-center recognition callable | P1 | Depends: GDT-001,GDT-020**
- Acceptance: only one centered intended machine per call; existing gateway auth, App Check, quota, timeout, format validation and catalog alias resolution preserved; failure yields manual selection; not represented as multi-object detector.

**GDT-022 — Candidate observation and de-duplication workflow | P1 | Depends: GDT-014,GDT-021**
- Acceptance: one physical machine from repeated frames does not create duplicates; two identical machines do not collapse solely because equipmentId equals; user prompted on ambiguous cases; observations carry model/scan provenance.

**GDT-023 — Review placement and edit recognized type | P1 | Depends: GDT-016,GDT-022**
- Acceptance: recognition creates proposed instance only; user verifies/corrects physical position on known plan; rejected candidate not saved as verified; no automatic public publishing.

**GDT-024 — Multi-object detector benchmark | P1 | Depends: GDT-004,GDT-005**
- Acceptance: Grounding DINO and appropriately licensed RF-DETR variant evaluated for recall/precision, latency, memory, false positives and cost; existing center-photo recognizer baseline included; report unscanned classes and confusion cases.

**GDT-025 — Licensed gym training dataset and model pipeline | P2 | Depends: GDT-004,GDT-005,GDT-024**
- Acceptance: image rights/consent and train/validation partitions documented; class map to canonical equipmentId versioned; checkpoint rights verified; rollback and on-device/server inference choice justified by measurements.

## Epic GYM-03 — Spatial capture and mapping R&D

**GDT-030 — Spatial capability and iOS parity adapter | P1 | Depends: GDT-007**
- Acceptance: platform-neutral interface reports AR, depth, calibration and camera support; ARCore/ARKit implementations hidden behind interface; unsupported devices fallback to Quick Scan/manual map without exceptions.

**GDT-031 — Spatial scan observation schema and consent | P1 | Depends: GDT-003,GDT-011,GDT-030**
- Acceptance: camera intrinsics, local poses, depth units and tracking quality recorded as non-authoritative observations; per-session coordinate frame explicit; raw media TTL and redaction enforced; abandon deletes unsaved source media.

**GDT-032 — ARCore depth/pose bench experiment | P2 | Depends: GDT-005,GDT-030,GDT-031**
- Acceptance: reference Android device test across angles, mirrors and drift; output localization and depth error distributions; camera tracking lost/recovered without silently verifying any position.

**GDT-033 — RTAB-Map reconstruction experiment | P2 | Depends: GDT-004,GDT-005,GDT-031**
- Acceptance: reproducible pipeline with pinned license/dependencies, output map and trajectory per pilot set, GPU/CPU/battery budget, failure analysis; no requirement to embed RTAB-Map into Flutter.

**GDT-034 — MapAnything Apache checkpoint experiment | P2 | Depends: GDT-004,GDT-005,GDT-031**
- Acceptance: only authorized Apache weights used; reproducible images-to-geometry run, measured resource consumption and geometry accuracy, rejection on insufficient overlap; NC models excluded.

**GDT-035 — Cross-session map alignment and uncertainty | P2 | Depends: GDT-032..GDT-034**
- Acceptance: align scan frames to floor coordinates through validated control points/anchors, detect wrong-floor/mirrored/loop-drift cases; confidence or failure returned; never silently show user as precisely located after a reset.

**GDT-036 — Guided spatial capture draft proposal UI | P2 | Depends: GDT-016,GDT-030,GDT-035**
- Acceptance: guided walking/stop/change-angle instructions, progress and missing regions; geometry/instances proposed only; user can reject, return to manual 2D and retain valid progress.

## Epic GYM-04 — Verified wayfinding and workout attachment

**GDT-040 — Deterministic route planner on confirmed graph | P0 | Depends: GDT-015,GDT-016**
- Acceptance: A*/Dijkstra follows confirmed edges/obstacles and approach nodes; no graph -> no route; no unapproved shortcuts; route has mapVersionId; tests include disconnected floors/obstacles.

**GDT-041 — Manual origin and destination selection | P0 | Depends: GDT-013,GDT-040**
- Acceptance: starts from explicitly picked entrance/landmark/current confirmed instance; unknown origin never defaults to a fabricated blue dot; destination can be viewed without any route.

**GDT-042 — Canonical equipment type -> physical instances resolver | P0 | Depends: GDT-014,GDT-018**
- Acceptance: eligible existing equipmentId resolves to 0..N independent instances in selected venue/version; candidates filtered by verified availability of approach node and floor; unsupported/no instance explained, never guessed.

**GDT-043 — Read-only existing-workout navigation adapter | P0 | Depends: GDT-001,GDT-040,GDT-042**
- Acceptance: accepts existing current/planned exercise without mutating it; respects existing exercise ID/equipment type mapping and safety eligibility; existing workout storage and timers unchanged; return to player; navigation failure does not block workout logging.

**GDT-044 — User-reported busy machine and alternative | P1 | Depends: GDT-042,GDT-043**
- Acceptance: busy state time-scoped/user-reported, not inferred from image; prefer same-type different unit; any different exercise runs existing injury-aware eligibility and explicit confirmation; no uncontrolled plan reorder.

**GDT-045 — Honest route/position failures | P0 | Depends: GDT-040,GDT-041**
- Acceptance: stale map, missing scale, failed tracking, no origin, blocked edges, floor mismatch and unknown target return distinct states; show verified target only when route is unavailable; never show fictional distance/ETA.

**GDT-046 — Accessibility and route UX hardening | P0 | Depends: GDT-040,GDT-041,GDT-043,GDT-045**
- Acceptance: turn-by-turn written alternative to visual line, label/contrast/screen reader support, reachable back navigation, temporary barriers modeled or route invalidated, disabled-AR/no-network walkthrough.

## Epic GYM-05 — Voice navigation (no new workout state)

**GDT-050 — Confirm existing voice-to-workout action contract | P1 | Depends: GDT-001**
- Acceptance: current exact HEAD reviewed; working speech recognizer, supported actions and shared touch path verified, or dependency explicitly BLOCKED; parser-only code never treated as live voice; no separate workout runtime proposal.

**GDT-051 — Navigation-only voice intents | P1 | Depends: GDT-041,GDT-042,GDT-050**
- Acceptance: "Where is next machine?" and "show me that equipment" navigate only; ambiguous gym/equipment requests ask for user selection; voice does not log sets or advance exercises without an existing authorized action.

**GDT-052 — Spoken location cues and confirmations | P1 | Depends: GDT-045,GDT-051**
- Acceptance: voice uses same verified target and path as map, does not invent live position/distance, names uncertainty, works in silent/text fallback, cancels when user stops recording.

**GDT-053 — Voice regression and safety tests | P1 | Depends: GDT-051,GDT-052**
- Acceptance: ASR errors, duplicate command, network outage, consent withdrawal and workout write errors do not mutate workout or bypass screening; touch and voice route to one validated action where an action is actually supported.

## Epic GYM-06 — Shared and venue-approved gym maps

**GDT-060 — Venue verification, roles and claims | P1 | Depends: GDT-002,GDT-006**
- Acceptance: secure venue owner/manager/moderator designation, branch collision tests, no self-claimed ownership by free-text; role revocation immediate and auditable.

**GDT-061 — Consent-aware contribution workflow | P1 | Depends: GDT-003,GDT-060**
- Acceptance: private draft contribution only with user action; remove identifying imagery, location rights checked, moderation request explicit, author can withdraw if permitted by policy.

**GDT-062 — Immutable publish/moderate/version/rollback | P1 | Depends: GDT-011,GDT-016,GDT-060,GDT-061**
- Acceptance: human-approved published snapshot immutable, diff review and immutable audit, rollback by selecting a prior version, unverified updates cannot silently alter a route.

**GDT-063 — Tenant, role, user access and abuse tests | P1 | Depends: GDT-006,GDT-062**
- Acceptance: negative tests for venue hijack, public write, cross-user raw frame reads, replayed contributions, moderation races and revoked access; quotas and rate limits proven.

**GDT-064 — Shared map distribution and offline caching | P1 | Depends: GDT-017,GDT-062**
- Acceptance: only verified/published maps available to non-editors, cached revision integrity and update prompts, removing publication invalidates future reads and follows documented cache policy.

**GDT-065 — Merge duplicate locations and branch resolution | P1 | Depends: GDT-002,GDT-060**
- Acceptance: merge is audited, owner-reviewed and reversible; old locationIds handled as aliases/mappings without silently rewriting workout history or notes.

## Epic GYM-07 — Advanced localization, 3D and multi-floor (conditional)

**GDT-070 — Landmarks and optional QR/AprilTag localization | P2 | Depends: GDT-030,GDT-035,GDT-060**
- Acceptance: only authorized fixed markers, repeatable between sessions, tamper/unavailable cases and camera-only fallback, tested for target venue without false certainty.

**GDT-071 — AR target overlay | P2 | Depends: GDT-035,GDT-040,GDT-070**
- Acceptance: overlay only when alignment confidence passes approved threshold; turn off immediately on lost tracking; confirmed navigation graph remains authority for safe path.

**GDT-072 — Optional 3D map viewer | P2 | Depends: GDT-034,GDT-016**
- Acceptance: reads vetted geometry consistent with 2D map/version, never implicitly authoritative, 2D accessible fallback, performance and model-size budget approved.

**GDT-073 — Multi-floor links and accessibility constraints | P2 | Depends: GDT-011,GDT-015,GDT-040,GDT-060**
- Acceptance: floor changes only through verified stairs/elevator/ramp nodes; physical accessibility flags never guessed; unreachable routes return clear no-route; tests cover wrong floor and lift unavailability.

## Dependency and release gate summary

- FIRST USABLE PRIVATE MVP: GDT-001..007, GDT-010..019, GDT-040..043, GDT-045..046 with measurable evidence; GDT-044 optional.
- OPTIONAL PHOTO MAP AUTHORING: GDT-020..023; multi-object alternative not required.
- SPATIAL AUTO-MAPPING EXPERIMENT: GDT-030..035 before considering GDT-036.
- VOICE NAV: GDT-050 must clear separate existing-workout voice action readiness before GDT-051.
- SHARED VENUE: GDT-060..064 with explicit privacy/owner review; do not preemptively publish.
- AR/3D: GDT-070..073 behind proven location precision and product value.
- Every field/ML deliverable: frozen benchmark data, sourced model artifacts, device E2E and red-team validation.

## Estimation and ownership

No fictional effort/duration, staffing or sprint close is assigned. During sprint planning, each item receives one accountable implementer, reviewer, estimate based on an exact HEAD and evidence links. The independent roles recommended for review are product, Flutter, spatial mapping, CV, security/DB, privacy/legal and recommendation adversary. They are NOT represented as having independently executed this document.
