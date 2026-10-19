# GYM DIGITAL TWIN — Backlog Package

- Date: 2026-10-19
- Product: Fitness App
- Repository workspace: D:\Repo\Fitness_App
- Package status: PROPOSED BACKLOG / PRODUCT DIRECTION ACCEPTED / IMPLEMENTATION NOT AUTHORIZED BY THIS DOCUMENT
- Stage: design and planning only
- Target: mobile-first map of a real gym, machine recognition, optional spatial scan, equipment wayfinding during an existing workout
- Language: English to comply with repository text conventions
- Source of proposal: operator-approved hybrid concept and subsequent role-based adversarial analysis, not an independently executed multi-agent consensus or a measured production system

## Core product contract

**Map first; 3D optional.** A usable, verified 2D map is the product. Camera capture, AI detection, SLAM, 3D reconstruction and AR are optional map creation/improvement methods, not requirements to open or navigate an existing map.

**One workout source of truth.** Gym mapping/navigation is a spatial read/selection adapter to the EXISTING exercise, programme, equipment catalog and workout flows. Do not create an independent workout runtime, session lifecycle, logger, second exercise catalog, or AI authority for workout writes.

**No fictitious positioning.** An equipment type is not a physical equipment instance; a camera-relative pose is not a persistent map coordinate; a suggested path is not a verified walkable path. Expose provenance, uncertainty and fallback in UI and API.

**Private first.** Personal draft maps are separate from venue-verified shared maps. Raw bystander imagery is not published. No unverified client write may publish official maps.

## Reading order

1. [01_PRODUCT_SCOPE.md](01_PRODUCT_SCOPE.md) — personas, goals, MVP, modes, product exclusions, outcomes.
2. [02_ARCHITECTURE_CONTRACTS.md](02_ARCHITECTURE_CONTRACTS.md) — domain model, adapters, spatial/vision boundaries, data flow and security.
3. [03_BACKLOG.md](03_BACKLOG.md) — epics and implementable stories GDT-001 onward with acceptance criteria and dependencies.
4. [04_ACCEPTANCE_TEST_PLAN.md](04_ACCEPTANCE_TEST_PLAN.md) — scenarios, evaluation datasets, benchmark approach and release gates.
5. [05_OPEN_SOURCE_REGISTER.md](05_OPEN_SOURCE_REGISTER.md) — directly usable research leads, licenses and benchmark plan.
6. [06_RISKS_AND_DECISIONS.md](06_RISKS_AND_DECISIONS.md) — adversarial findings, mitigations, owners and open decisions.
7. [07_DELIVERY_HANDOFF.md](07_DELIVERY_HANDOFF.md) — recommended sequence, engineering handoff and DoR/DoD.
8. [08_BACKLOG_IMPORT.csv](08_BACKLOG_IMPORT.csv) — machine-readable story index for import; Markdown remains the acceptance source.

## Scope and source integrity

Baseline repo inspection on 2026-10-19: checkout contains existing unrelated modified and untracked files; this package intentionally creates only NEW files in this directory. No existing backlog, index, mobile application code, Firestore rules, test file, branch, commit or deployment is modified by this package.

Known relevant source paths in the Fitness App checkout:
- core/CODEMAP.md and core/CONVENTIONS.md (navigation/conventions, historically stale in parts)
- mobile/lib/features/equipment/data/equipment_models.dart
- mobile/lib/features/equipment/data/exercise_filter.dart
- mobile/lib/features/visual_equipment/data/gemini_equipment_service.dart
- functions/src/ai_equipment_recognition.ts
- mobile/lib/features/workouts/data/workout_session.dart
- mobile/lib/features/voice/data/voice_command.dart
- core/product/GATE_F_GYM_IDENTITY_D0_NOTE_2026-08-19.md
- core/product/GATE_G_SETUP_MEMORY_D0_NOTE_2026-08-19.md

The first implementation task must re-read these against its exact HEAD and check other in-flight Fitness App worktrees for compatibility. No test, device measurement, or external reviewer process was run when authoring this package.

## Backlog vocabulary

- GDT = Gym Digital Twin.
- Priorities: P0 foundational/MVP, P1 valuable follow-on, P2 research/advanced.
- Phases: GYM-00 through GYM-07.
- State of every item: PROPOSED; estimates are planning-only and must be calibrated by engineering.
- A story cannot be marked DONE solely because a design document exists.
- A story involving the camera, location, model weights, permissions or cross-user data must pass the matching security/privacy/license gate.
