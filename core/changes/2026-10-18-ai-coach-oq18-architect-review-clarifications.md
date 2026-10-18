# AI Coach: clarify OQ-18 composer proposal after architect review

Date: 2026-10-18. Documentation-only follow-up to `2026-10-18-ai-coach-oq18-composer-contract.md`.

## Why

A read-only architect review of the proposed deterministic multi-week composer found two MAJOR specification gaps and two MINOR ambiguities. The proposal needed to distinguish observed workout history from projected plan volume, preserve the existing context/safety transformation, state the recovery input horizon, and describe `buildPlan` output accurately.

## Changes

- `docs/ai-coach/03_DESIGN.md` §13.1 now requires `narrowToTrainingContext` and `safetyContextForTrainingContext` before each per-day `buildPlan` call, and requires selected IDs to be members of that filtered input pool. Missing or stale safety/context data refuses composition.
- The observed weekly deficit (from completed sessions) is explicitly separate from projected plan volume. Whether scheduled sessions are included and how planned sets affect later selection remain an unresolved, versioned TR projection rule; no feedback rule is invented.
- The current 14-day deload input window and separate 7-day user action are recorded. No later-week projection/recomputation behavior is assumed. Visual matches with confidence are not treated as confirmed equipment access without an approved user-confirmation rule.
- OQ-18 status, backlog, acceptance and state records point to these clarified boundaries and keep TR review open.

## Evidence and verification

The review was performed read-only against source HEAD `a4dafe052e86215b5c2b175260954e9c7d73c53d`. Relevant source interfaces were inspected in `plan_builder.dart`, `ai_planner_providers.dart`, `personalisation_providers.dart`, `training_context.dart`, `recovery_providers.dart`, `deload_detector.dart`, and `visual_equipment_service.dart`. No source code changed. No tests, checks, builds, CI, or migrations were run; this is documentation work only.

## Remaining decisions

TR must approve the deficit projection, recovery horizon, policy/snapshot contract, and persistence/idempotency behavior. The operator/product owner must resolve the plan intent and day-slot product decisions; OQ-07 still requires approved prescription values. No earlier GPT-PM decision covers this new proposal revision.
