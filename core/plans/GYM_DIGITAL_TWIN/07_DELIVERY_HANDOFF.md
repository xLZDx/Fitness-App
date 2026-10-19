# GYM DIGITAL TWIN — Sprint Pickup and Delivery Handoff

Date: 2026-10-19. Status: ready for backlog grooming; NOT authorized for implementation, production changes, tests, merge or push by this document.

## 1. Exact workspace and worktree safety

Preferred repository: D:\Repo\Fitness_App, remote: https://github.com/xLZDx/Fitness-App. At time of authoring, the local checkout was on sprint/hardening-followups-2026-10 and contained an ahead-of-upstream commit and many unrelated modifications/untracked files. Those changes were not touched. This package was written in a NEW isolated directory only.

Before implementing, capture exact source HEAD, remote tracking state, working-tree status, build flavor and unmerged worktrees. Coordinate with ongoing AI Coach voice work; treat in-flight designs as proposals until merged/accepted. Never assume the current repository files match a previous conversation's HEAD.

These documents are written in English per the repo's Git text language convention.

## 2. Proposed work packages, not calendar promises

**Package A — Architecture and truth, GYM-00**
Deliver GDT-001..007: exact source map, stable gym identity, privacy/consent, OSS registry, measurement ground truth, security model, rollback/flags.
Terminal outcome: separate approve/modify/reject design review. No Firestore change until authorized.

**Package B — First usable private map, GYM-01**
Deliver GDT-010..019: one-floor map import/editor, physical equipment instances, walkable graph, status/revision tracking, offline map, catalog search and usability test.
Terminal outcome: map with repeated machines and confirmed corridors survives restart without camera/cloud.

**Package C — Verified wayfinding, GYM-04**
Deliver GDT-040..043,045..046: deterministic route on confirmed graph, explicit origin, equipment-instance resolver and READ-ONLY workout adapter, accessibility/fallback tests.
Terminal outcome: show planned/current eligible exercise's actual location and valid path without new workout records.
Notes: GDT-044 busy alternative is P1, not mandatory for first MVP.

**Package D — Quick Scan, GYM-02**
Deliver GDT-020..024, optionally 025. Reuse the single-center callable before evaluating replacement, insist on physical-instance evidence and optional manual positioning.
Terminal outcome: user-guided recognition speeds map authoring while preserving consent/quotas and ability to correct.

**Package E — Spatial research, GYM-03**
Deliver GDT-030..035; GDT-036 only after valid alignment evidence. Run separate benchmark of ARCore, RTAB-Map and Apache-enabled MapAnything; iOS portability evidence.
Terminal outcome: go/no-go on automatic map placement with quantified errors and license clearance.

**Package F — Voice Navigation, GYM-05**
Deliver GDT-050..053 only after separate voice-as-input source contract is accepted. Voice must not bypass existing workout operations or assert false persistence.

**Package G — Venue maps, GYM-06**
Deliver GDT-060..065 only after venue authority and privacy/design acceptance. Sharing is not a prerequisite for private MVP.

**Package H — Advanced AR/3D, GYM-07**
Deliver GDT-070..073 only with successful spatial and graph precision evidence. Multi-floor accessibility and tracking claims are later features.

Order may be reorganized for engineering efficiency, but no dependent item may close solely because an upstream document was written.

## 3. Definition of Ready for story implementation

Every story requires:
- One accountable owner; one reviewer independent of implementer for security/safety-sensitive changes.
- Updated exact HEAD/code-map trace and source link.
- Explicit user behavior, trust boundary, scope/non-goals, testable acceptance.
- Dependency closure evidence, with relevant ADR decisions.
- Clear UI/error/offline behavior and telemetry privacy considerations.
- Any data migration, permissions, native package, model weights or financial costs flagged.
- Tool/platform availability checked; no false promise of an agent run or unsupported device.
- Engineering estimate/sprint assignment based on a current implementation plan, not generic dates.

## 4. Definition of Done for a completed code story

- Change satisfies acceptance criteria and has direct automated tests (pure Dart domain, widget, rule emulators, device E2E where relevant).
- Workout logging/sets, safety filtering and existing rest timer behavior untouched or explicitly regression-tested.
- Flutter analyze/test for current code, plus UI visual device verification; no claims without actually running.
- Security/rule tests for any cross-user data, including Firebase wildcard OR-rule behavior.
- Camera/sensor permission revocation, offline failure and server quota cases have deterministic fallback.
- Model and dataset license/checkpoint/version recorded and any new third-party dependency scanned.
- New feature mapped in core/CODEMAP.md in same code commit; doc links verified.
- Change reviewed by applicable domain specialists and red team; BLOCKER/HIGH cases closed with regression evidence.
- Traceable tests with command, exact source hash and outcome.
- Owner authorizes specific commit/push/deploy separately; no implicit release from a passed test.

## 5. Suggested review routing

Product/UX: camera friction, user flow, map creation completion, accessibility.
Fitness Flutter reviewer: go_router, Riverpod, iOS parity, existing player integration and injury-aware filtering.
Database reviewer: venue vs type vs physical instance identity, immutable revision policy, transaction bounds.
Security reviewer: auth/App Check, Firebase rules, consent, role claiming, moderation and storage.
Computer vision reviewer: multi-object detector, confidence calibration, dataset split and duplicate detection.
Spatial engineer: coordinate frames, alignment, drift, loop closure and sensor capabilities.
Reliability reviewer: offline/cache, rejection of unknown positions, recoverability and cloud quota exhaustion.
Recommendation adversary: occupied machines/alternatives, contraindications, false tracking/precision claims.

Project reviewer definitions are role specifications; they were not executed as independent agents by the writing of this handoff.

## 6. Implementation entrypoint: next tangible step

Start with GDT-001, GDT-002, GDT-003, GDT-005, GDT-006 and a small prototype of GDT-011/GDT-014/GDT-015/GDT-040 in a separate authorized worktree. Use a synthetic one-floor gym fixture containing repeated machines and obstacles to prove the data contract, without camera, cloud AI or Firestore. Then add actual private persistence/2D screen when contracts pass. This removes the most severe risks early and retains full optionality for expensive 3D R&D.

No commit, push, mutation of existing source, production deployment or new workflow assignment was performed as part of this documentation package.

## 7. Useful original project anchors

- AGENTS.md — current engineering and Git rules.
- core/CODEMAP.md — feature navigation; check dated inventory and current files.
- core/CONVENTIONS.md — implementation style; has some stale test count claims, verify exact code.
- core/product/GATE_F_GYM_IDENTITY_D0_NOTE_2026-08-19.md — existing free-text gym identity.
- core/product/GATE_G_SETUP_MEMORY_D0_NOTE_2026-08-19.md — type+gym setup memory, not instance precision.
- functions/src/ai_equipment_recognition.ts — one-centered-machine server AI recognition.
- mobile/lib/features/visual_equipment/data/gemini_equipment_service.dart — mobile recognition path.
- mobile/lib/features/equipment/data/equipment_models.dart — canonical exercise and machine type models.
- mobile/lib/features/equipment/data/exercise_filter.dart — existing injury safety filter.
- mobile/lib/features/workouts/data/workout_session.dart — authoritative workout history types.
- mobile/lib/features/voice/data/voice_command.dart — parser-only voice command definition, not proof of active mic dispatcher.
- docs/ai-coach in separate AI Coach worktree (if present) — latest accepted voice-as-second-input contract must be checked before GYM-05.

## 8. Status handoff template (fill for future executions)

    Date:
    Package/story IDs:
    Repository / branch / HEAD:
    Worktree dirty state / concurrent work:
    Implementation scope and exclusions:
    Test command / exact results:
    Security, safety, license evidence:
    Specialist review / adversarial findings:
    Unresolved blockers:
    Release decision: PASS / MODIFY / NO-GO
    Commit SHA(s) and explicit push authorization:
    Next actionable step:
