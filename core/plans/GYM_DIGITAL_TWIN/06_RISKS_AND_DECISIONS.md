# GYM DIGITAL TWIN — Risk Register, Devil's Advocate and Decision Log

Date: 2026-10-19. Status: PRE-IMPLEMENTATION REVIEW. This is a structured role-based review performed in the planning conversation, NOT an independently executed multi-agent run. No code change or test evidence is claimed.

## 1. Overall verdict

PRODUCT CONCEPT: CONDITIONAL GO for requirements and measurement.
MANUAL-FIRST PRIVATE 2D MVP: GO TO BACKLOG, subject to normal implementation authorization and review gates.
AUTOMATIC SPATIAL LOCATION, SHARED MAP PUBLICATION OR AR NAVIGATION: NO-GO until distinct evidence and approvals exist.
LEGAL RIGHTS FOR MODEL WEIGHTS/DATASETS: NOT CLEARED by this document.

## 2. Role-based review result (method disclosure)

Role lenses applied: product usability; Flutter/iOS; computer vision and instance identity; SLAM/navigation; security/Firestore; data rights/privacy; operational reliability; recommendation-safety adversary.

This review was not a set of separately executed specialized agents. Independent specialist signoffs and actual experiment results are outstanding. Do not present this as multi-agent consensus. Existing repository agent guides reviewed include .claude/agents/fitness-flutter-reviewer.md and recommendation-adversary.md in the AI Coach worktree (2026-10-19), plus repository AGENTS.md.

## 3. Blocking and high-severity findings

| ID | Severity | Counterexample / failure | Required mitigation | Regression/test IDs | Proposed owner | Status |
|---|---|---|---|---|---|---|
| F-01 | BLOCKER to panorama scan | Existing aiEquipmentRecognition intentionally classifies central single machine; a walkthrough frame contains multiple types | Keep centered Quick Scan only; new multiple-object detector measured separately | SCAN-01,02,05 | CV | OPEN |
| F-02 | BLOCKER to share | Legacy profile gymId is user free text; two branches or spelling variants collide or fail to match | New stable locationId, verified venue and explicit legacy bridge, no implicit merge | MAP-01,SEC-02 | Data/Product | OPEN |
| F-03 | BLOCKER to live location | AR camera pose after restart is a different local frame; mirrors/rows induce drift | Anchor to verified map control points, quantify uncertainty, no blue dot on lost alignment | SPAT-02..05 | Spatial | OPEN |
| F-04 | MAJOR | Voice parser exists but may not be wired end-to-end; command cannot safely call private workout callbacks | Share existing action seam first; no parallel runtime; navigation-only voice when available | VOICE-01..03,WORK-02 | Mobile/Workout | OPEN |
| F-05 | BLOCKER to routes | Straight visual path crosses wall, rack, stairs, locked area or blocked corridor | Independently verified graph and approach nodes; reject invalid route | NAV-01..03,08 | Navigation | OPEN |
| F-06 | BLOCKER to camera/share | Bystander faces, private video or signage captured and uploaded or made public | Foreground consent, no default media upload, local redaction/minimization, approved retention, human publish review | SCAN-06,SEC-04,05 | Privacy/Security | OPEN |
| F-07 | HIGH | Duplicate same-type machines either merged or one machine replicated across 10 camera views | Separate stable instance ID and evidence-based cross-frame reconciliation | MAP-02,SCAN-03,04 | Data/CV | OPEN |
| F-08 | HIGH | AI maps incorrect equipment label to a workout alternative unsafe for injuries | Existing canonical catalog ID, existing eligibility filter and confirmed user selection; unknown -> refuse | NAV-06,WORK-01 | Safety/Product | OPEN |
| F-09 | HIGH | Noncommercial pretrained weights copied from permissively licensed repo or external Roboflow asset | Per-artifact license/weight/data audit; build/release license gate | SEC-06 | Legal/Engineering | OPEN |
| F-10 | HIGH | Firestore broad rule means a specific restrictive rule may not block unauthorized writes | Design a strict non-overlapping policy, test Firestore OR semantics with rule emulator, role revocation tests | SEC-01..04 | Security/DB | OPEN |
| F-11 | HIGH | Offline edits sync into shared published map after reconnect without review | Local pending edits only, version compare/conflict UI, authorized publish transaction | MAP-07,SEC-03 | Data/Mobile | OPEN |
| F-12 | HIGH | 3D-heavy models drain battery, saturate network, incur uncontrolled cloud cost | Rate limits, bounded capture/backpressure, local preprocessing, explicit processing estimate, manual fallback | PERF-01,02 | Mobile/Infra | OPEN |
| F-13 | HIGH | User sees precise distance/ETA despite unknown floor scale | Calibrate scale or show qualitative route without meters/ETA | MAP-09,NAV-04 | Product/Nav | OPEN |
| F-14 | HIGH | User mistakes human-proposed map for officially verified public venue plan | Immutable published version, visibly separate private/proposed/verified statuses, distinct venue ownership | MAP-06,SEC-03 | Product/Security | OPEN |
| F-15 | MEDIUM | Instance setup notes keyed by (gymId, equipmentId) are silently treated as specific physical machine history | Keep legacy note scope; optional explicit user association to instance after confirmation | MAP-02,WORK-01 | Data | OPEN |
| F-16 | MEDIUM | Current code-map docs contain dated, inconsistent test counts; agent trusts obsolete inventory | Verify actual HEAD and file semantics, current build/test availability before implementation | GDT-001 | Tech Lead | OPEN |

## 4. Devil's-advocate counterexample suite

DA-01 — Perfect classifier, wrong map:
- Five machines classified correctly; spatial poses drift after a mirror turn; displayed positions swap.
- Expected: uncertainty flags; no verified route/localization until visual landmarks/control points reconcile.

DA-02 — One equipment type, three actual units:
- Name/alias/model IDs all identical, but machines have different locations and may be busy independently.
- Expected: three stable instances; selected concrete approach point; no merge on type key.

DA-03 — Apparent shortcut:
- Geometrically closer machine is behind a barrier; a direct line crosses a restricted corner.
- Expected: confirmed route graph is authority; no unreachable waypoint or dangerous shortcut.

DA-04 — Unsafe workout suggestion:
- Planned machine is occupied; nearest alternative supports a different movement contraindicated for the user.
- Expected: existing safety filter rejects alternative; map does not change exercise and does not claim a workout outcome.

DA-05 — Private camera exposure:
- Other visitors are visible in a panorama; model crop redacts face but preserves identifying tattoos/phone display/reflection.
- Expected: privacy-by-default minimization and cautious non-public storage; failed redaction -> discard image/not publish.

DA-06 — Forged venue owner:
- Client sends locationId and "role":"owner" in request to approve public map.
- Expected: reject; authorization comes from trusted server claim/role; audit and rate-limit.

DA-07 — False precise voice cue:
- Phone restarted; no alignment; voice says "2 meters ahead" based on stale local coordinate.
- Expected: "Current position not confirmed. Select an entrance or landmark"; no metric distance.

DA-08 — Captive offline state:
- User completed scan while offline, then logged out; second user opens app on same phone.
- Expected: encrypted/isolated private drafts and purged personal access; no unintended cross-account sync.

DA-09 — Layout changes mid-session:
- Venue moves a large machine and blocks passage after cached map download.
- Expected: map freshness display, "route may be outdated", approved version/closure handling, human confirmation when needed.

DA-10 — Vendor code license misconception:
- README hosted on GitHub says "open-source", model weights hosted elsewhere CC-BY-NC.
- Expected: no weights included in commercial build until artifact-specific legal clearance.

## 5. Decisions and unresolved questions (ADR backlog)

**Accepted scope decisions from operator discussion**
- AD-01: Hybrid Gym Digital Twin concept; useful 2D map first; optional camera/AR/3D improvements.
- AD-02: Gym navigation extends existing Fitness App workout experience and catalog; no second workout tracker.
- AD-03: Prototype should benchmark open-source alternatives rather than adopt blindly.
- AD-04: Adversarial risks are release gates, not just textual warnings.

**Still OPEN; do not treat as product/engineering approval**
- OQ-01: Venue identity/claim flow, business owner verification, moderation authority and cross-jurisdiction coverage.
- OQ-02: Whether user-private maps may be shared peer-to-peer without venue publication, and associated rights.
- OQ-03: Retention and redaction SLA for raw images, pose coordinates, EXIF data and server-side temporary processing.
- OQ-04: Map calibration quality threshold; allowed in-app statements when scale cannot be proven.
- OQ-05: Which tested Android and iOS devices/sensor configurations will be officially supported for spatial scan.
- OQ-06: Which checkpoint, dataset and model provider is production-licensed.
- OQ-07: Are user-reported busy marks private, time-scoped, or moderated shared state?
- OQ-08: Offline publication conflicts, map rollback rights and old-version invalidation.
- OQ-09: Whether instance-level setup notes become a user-requested separate history feature; no automatic migration.
- OQ-10: Screen capture/photo import rights and location image license terms.
- OQ-11: Accessibility path semantics for multi-floor, mobility restrictions and lifts (deferred beyond MVP).
- OQ-12: Whether existing voice feature reaches an authorized shared action seam; navigation voice depends on this.

## 6. Go/No-Go rules and review assignments

- Any F-01 / F-03 blocker open: automatic photo-to-position or real-time AR positioning stays disabled.
- Any F-02 / F-06 / F-09 / F-10 / F-14 blocker open: sharing and public maps stay disabled.
- Any F-05 open: route generation stays disabled; location-only map allowed.
- Any F-08 open: alternative exercise selection stays disabled.
- Voice routes may be enabled only if existing voice action contract is verified and user control is maintained.

Before each phase close: assigned mobile reviewer, data/security reviewer for persistence changes, spatial/CV reviewer for mapping, product/recommendation adversary for exercise and navigation suggestions, plus actual field evidence where required. The review author cannot substitute a role-lens write-up for independently executed signoff.

## 7. Risks deliberately deferred from MVP

Commercial operator tools, 3D model mesh quality, continuous localization, map coverage crowd-sourcing, camera-based occupancy and multi-floor assistance are not first-release dependencies. If proposed as must-have requirements, demand measured evidence of user value versus added privacy, rights, battery, crash and maintenance costs.
