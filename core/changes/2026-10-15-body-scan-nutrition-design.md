# Change record: Body Scan + Nutrition Coach technical design and Phase 2 backlog

## What changed
Documentation only, no code:
- `core/plans/BODY_SCAN_NUTRITION_TECH_DESIGN_2026-10-15.md` (new): repo recon, architecture and module layout, Firestore/Storage data model, `firestore.rules` and `storage.rules` diffs with the required emulator tests, Cloud Function contracts (signed upload URLs, estimate behind a swappable provider interface, purge, meal photo analysis, barcode, food search, label parsing), the PROVISIONAL estimator, on-device face blur, scan state machine, result math, nutrition maths with the safety-clamp table and exclusion rules, client-side weekly review, onboarding diff, food diary and food scanning, privacy/deletion/export, routes, l10n/accessibility/iOS notes, risks and open questions, decisions D-1..D-36, a numeric provenance table, the nutrition-aware programme level (section 30) and the sport-agnostic activity model with device sources (section 31).
- `core/plans/PHASE2_MULTISPORT_DEVICES_BACKLOG_2026-10-15.md` (new): priority Phase 2 backlog (multi-sport tracking, device ecosystem integration order with effort estimates, full nutrition-aware programmes, a legal-only competitive study plan, epics with Definition of Done, dependencies, risks).
- `core/DECISION_LOG.md`: four entries (design decisions D-1..D-36, the provisional-estimator limitation, the clean-room and reverse-engineering refusal, the Phase 2 backlog and foundations).
- `core/INDEX.md`: the two documents registered in the Plans table. The repository has no generated document registry script and no `governance/DOCUMENT_REGISTRY.md`; `core/INDEX.md` is the hand-maintained index named by `CLAUDE.md`, so it was updated by hand.

## Why
DEVELOPMENT RULES v4 step 1 (documentation first) for the Body Scan + Nutrition Coach sprint, including the operator's scope changes of 2026-10-15 (food scanning in scope; reference functionality adopted with explicit provenance for every number; a nutrition-aware programme hook; a sport-agnostic activity foundation; a Phase 2 priority backlog). The design is decision-complete so an implementer needs no further questions, and it records what is verified, what must be verified (VERIFY markers) and what is an open operator question.

## Affected contracts and paths
None changed yet. The design specifies future changes to: `firestore.rules` (wildcard carve-outs, new blocks, `flagsAreStripped` key list), a new `storage.rules` and `firebase.json`, `functions/src` (new callables, `QUOTAS`, `AI_GATEWAY_OPERATIONS`, `sweepAccountData`, `account_export.ts`), `HealthFlags`, `UserProfile`, onboarding order, `ScanRecord` v2, `scan_reminder.dart`, routes, `DATA_INVENTORY`, `data_lifecycle_policy.json`, `public/privacy.html`. Rollout order that matters: deploy the `flagsAreStripped` change before the client.

## Verification state
Nothing was executed: no tests, analyzer, build, lint or CI (prohibited by the workspace rules, and unnecessary for documentation). Facts about the repository come from reading the cited files at base commit 42d1b84. Not verified: the reference video frames (section 3 of the design is based on the operator brief and must be confirmed by the UX reviewer), every item marked VERIFY in the design, vendor capability statements (hypotheses), any accuracy of any estimator. Open-source and API facts about food data come from the researcher report `scratchpad/food_refs/FINDINGS.md` (curl-verified there on 2026-10-15, not re-run here).

## Review state
Not yet reviewed. Next: one review pass by architect, security-reviewer, database-reviewer, product-ux-reviewer and a11y-architect (allowed models only), then fixes.
