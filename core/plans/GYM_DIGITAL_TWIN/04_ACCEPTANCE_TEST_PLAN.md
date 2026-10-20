# GYM DIGITAL TWIN — Acceptance, Benchmark and Test Plan

Date: 2026-10-19. Status: proposed; no tests have been executed for this initiative.

## 1. Testing principles

1. Validation must match the SPECIFIC built artifact and source HEAD; an historical passing test is not current proof.
2. Map rendering, machine classification, spatial positioning, route generation and actual workout persistence are independent results and must not share a single "success" badge.
3. Human-reviewed floor truth is the reference for spatial results, not model agreement with itself.
4. Do not create or upload private gym imagery merely to make a test pass; obtain appropriate consent/permissions or use synthetic fixtures.
5. Mandatory safety/authorization checks fail closed. Safe read-only map display must degrade gracefully.
6. Do not promise precise real-time location without supported device+venue evidence.
7. A usable manual-first MVP must pass without AR, AI, microphone, mobile data connection or working localization.
8. Reference devices include the operator's Samsung S23 where available and an iOS test device before claiming cross-platform parity. Device-specific results never generalize automatically.

## 2. Evaluation data protocol (GYM-00 / GDT-005)

Build a frozen, versioned corpus from consented private pilots:
- At least one compact gym and one larger, repetitive/reflection-prone gym; expansion required before broad claims.
- Floor geometry and walkable corridors manually reviewed and optionally surveyed; store reference metric scale/origin.
- List every equipment instance with ground-truth stable ID, catalog type and documented approach points.
- Include multi-instance duplicates, partial occlusion, reflective surfaces, low light, crowded frames, motion blur and similar machines.
- Include mapping sessions starting at different locations and revisiting the venue after app restart.
- Freeze training / calibration / validation / test splits by **venue and capture session**, not just random frames; avoid leaked views of the same instance.
- Preserve test manifest with data owner, consent, redaction policy, rights, checksums, annotation rubric and deletion workflow.
- Ground truth and annotations reviewed by at least two human checks for disputed labels/paths (roles assigned at GDT-005).
- No unapproved publishing of raw data, faces, recordings or user health context.

Metrics to record with denominators and confidence intervals when meaningful:
- Per-class classification and detection precision/recall/F1; mAP with a specified IoU threshold; confusion matrix.
- Physical-instance recall and duplicate rate; same-type distinct-instance collision count.
- Map coverage (confirmed/observed), obstacle false-negative rate, reprojection/rescan drift and median/p90 position error in meters when calibrated.
- Route validation: % routes that avoid obstacles and restricted areas; % cases correctly returning no-route; manual confirmation count.
- Scan duration per equipment/area; user correction effort; false certainty statements.
- Device CPU/GPU/memory, power/thermal, frame rate, app stability; cloud calls, bytes transferred, cost per scan; failure rate.
- Accessibility success, ability to understand directions with 2D only, offline task completion.

**Numeric targets: UNSET.** GDT-005 proposes pre-registered, realistically feasible thresholds after a baseline, with explicit product approval. No cherry-picking later test results to retrofit targets.

## 3. Test trace matrix

| Test ID | Scenario / negative case | Stories | Required outcome |
|---|---|---|---|
| MAP-01 | Two gyms with same name, different branches | 002,010,060 | Different stable IDs, no data bleed |
| MAP-02 | Three identical leg presses in one gym | 014,018,042 | Three independently editable instances |
| MAP-03 | Reopen cached map with camera denied and no connection | 013,017,019 | Full usable 2D inventory and route |
| MAP-04 | Change orientation, scale or floor coordinates | 011,012 | Coherent transform or explicit rejection |
| MAP-05 | Remove/retire instance and reload map | 014,016 | Retired instance not shown as usable |
| MAP-06 | Proposed/unknown location | 016,023 | Visible uncertainty; no verified route |
| MAP-07 | Stale map/revision modified during route view | 011,045,062 | Pin version or invalidate route; no silent warp |
| MAP-08 | Unknown equipment ID in imported data | 014,018 | Explicit unresolved state, no fabricated catalog entry |
| MAP-09 | Import image with uncalibrated scale | 012,045 | No fabricated meter distances |
| NAV-01 | Short straight line crosses wall | 015,040 | Planner uses verified corridor or no-route |
| NAV-02 | Disconnected walkable graph | 015,040,045 | No-route; target remains locatable |
| NAV-03 | Different floor without transition | 040,045,073 | No cross-floor path |
| NAV-04 | User location unknown | 041,045 | Ask for start, never show live blue dot |
| NAV-05 | Route to same-type alternative after "busy" | 042,044 | Different verified physical instance or none |
| NAV-06 | Alternative exercise contraindicated | 043,044 | Existing injury filter blocks it |
| NAV-07 | Screen reader and color-independent route legend | 013,046 | Equivalent navigation detail accessible |
| NAV-08 | Orientation of approach node obstructed | 015,040 | Destination only if approach reachable |
| WORK-01 | Navigation from existing planned exercise | 042,043 | No workout mutation; same existing player |
| WORK-02 | Abort map navigation mid-set | 043,045 | Timer, set data and workout saving unaffected |
| WORK-03 | Workout backend write timeout/error while map is open | 043,053 | No false success; existing save contract preserved |
| SCAN-01 | One centered machine, valid consent | 020,021 | Canonical existing type or explicit unknown |
| SCAN-02 | Five machines in one image | 021,024 | Single-center adapter not called multi-object |
| SCAN-03 | Same machine across 10 frames | 022 | One candidate instance, evidence retained appropriately |
| SCAN-04 | Two adjacent identical machines | 022,023 | No type-ID-only merging |
| SCAN-05 | Low-quality/blurred/mirrored/obscured camera view | 020,024 | Retry/unknown; no forced positive |
| SCAN-06 | Capture canceled, privacy consent revoked | 003,020,031 | Stop capture; remove uncommitted media |
| SCAN-07 | Offline cloud recognition unavailable | 007,021 | Manual equipment entry remains usable |
| SPAT-01 | Device has no supported AR/depth API | 030,036 | Manual/Quick Scan works |
| SPAT-02 | Tracking is lost mid-aisle | 031,035,036 | Proposal marked uncertain; no live route |
| SPAT-03 | Reseed after app restart from new start point | 035,070 | No old local frame assumed global |
| SPAT-04 | Mirror or repeated rows cause wrong alignment | 032,035 | Rejected or human correction required |
| SPAT-05 | Same floor viewed at different image scales | 033,034,035 | Calibration/rejection; no silent metric drift |
| VOICE-01 | "Where is next machine?" | 050,051 | Navigation request only |
| VOICE-02 | Similar-sounding gym names / no microphone | 051,053 | Ask/disambiguate; text fallback |
| VOICE-03 | Repeated voice utterance or STT failure | 051,053 | No duplicate workout writes |
| SEC-01 | UID A requests UID B private scan media | 003,006,063 | Deny, audit without sensitive content |
| SEC-02 | Client claims moderator role in payload | 006,060,063 | Deny; role from trusted source |
| SEC-03 | Publish private map without venue authorization | 006,061,062 | Deny and preserve draft |
| SEC-04 | Storage bucket object read via guessed URL | 003,006,063 | Deny unauthorized access |
| SEC-05 | Public-read map has bystander photo | 003,061,062 | Do not publish; require redacted review |
| SEC-06 | Reject noncommercial checkpoint in release manifest | 004,025,034 | Build/release gate blocks |
| PERF-01 | Long capture/low-memory/thermal state | 007,020,030 | Bounded work; safe pause/fallback |
| PERF-02 | Cloud quota exhaustion/timeout | 007,021,024 | No runaway retry billing or data loss |
| PERF-03 | Sign-out / switch account offline | 010,017,064 | Data access correctly separated |

## 4. Minimum release gates

**GATE-M0 — 2D manual-first MVP**
- Source-level integration and domain contract review at exact HEAD.
- Stable venue IDs and private-map ACLs; no cross-user leakage.
- Map import/manual editing, separate physical instances, verified walkable graph, deterministic routing.
- Existing exercise safety filtering and workout writes unchanged; full regression tests passing.
- Offline/no-camera fallback, accessible directions, unverified state messaging.
- Frozen field-test evidence for one-floor scenarios and explicit open limitations.
- Reviewer approval (product, mobile, security and functional).
- Run relevant Flutter analyzer, unit/widget tests, hardware E2E for new camera/native paths if any; never assume test pass without running.

**GATE-QS — Quick Scan**
- Consent/retention verified; centered recognition contract preserved.
- Quotas, image validation, remote model failure and correction workflow tested.
- Real-machine recognition measured against frozen ground truth; thresholds approved.
- Manual mode intact.

**GATE-SP — Spatial proposal**
- Device support and iOS path known.
- Alignment uncertainty quantified; drift/reflection cases captured.
- Recovery after tracking loss; no wrong-global-coordinate claims.
- Human confirmation before a placement becomes verified.
- Separate permission and data safety approval.

**GATE-VOICE — Spoken navigation**
- Existing speech-to-existing-workout action route is actually implemented and verified or voice remains disabled.
- No duplicate workouts, skipped safety screen or fictitious persistence acknowledgements.

**GATE-SHARE — Shared venues**
- Role/owner proof, moderation audit and map versions.
- Security rules/property tests against Firestore wildcard hazards.
- Contribution consent, image redaction, deletion, publication revocation handling.
- Separate privacy and venue-rights approval.

**GATE-AR3D — Advanced AR/3D**
- Documented position error thresholds met for tested device classes and venues; failed tracking removes overlay.
- Route graph still authoritative; 2D fallback on every device.
- Advanced UX usability benefit verified; resource budgets approved.

## 5. Test implementation guidance

Pure algorithms first: graph, geometry, model validation, IDs, transforms and route-plan invalidation in Dart data-layer unit tests; no Flutter import.

Widget tests: map selection, uncertainty labels, machine duplicates, permission/refusal, navigation-to-workout backstack, accessibility semantics.

Integration: Firebase rules emulator tests for role/auth/cache isolation, API contract for existing aiEquipmentRecognition, and device-level camera/AR tests only in explicitly supported environments.

Adversarial: unknown pose, wrong floor, fake model confidence, blocked route, old version, revoked rights, safety-filter bypass, GPS/BLE unavailable, repeated voice command, malicious map contribution, excessive payload. Every BLOCKER in 06_RISKS_AND_DECISIONS.md gets a red-before-fix regression.

Evidence package per release: git SHA, device/OS, app/SDK/model versions, license manifest, dataset checksum, metrics report, reproducible commands, failures/limitations, signed review verdict. Code review and documentation alone are not release evidence.
