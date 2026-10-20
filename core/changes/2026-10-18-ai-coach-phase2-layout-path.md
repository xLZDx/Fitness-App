# AI Coach: clarify root-relative Phase 2 layout evidence

Date: 2026-10-18. Documentation-only correction to the ACS-010 code map and acceptance evidence.

## What changed and why

The D10 code-map row used `features/live_coach/` and `features/ai_coach/` even though the code map says paths are repo-root-relative. The actual paths in the locally available `origin/phase2/main` snapshot are under `mobile/lib/features/`. Updated D10 and ACS-010 to state the root-relative paths and to identify the evidence precisely as the local remote-tracking ref at commit `85e7e91ed042b0395b7442839868a35975b62905`; no fetch or claim about the remote server's latest state was made.

## Evidence and scope

- `git rev-parse origin/phase2/main` returned `85e7e91ed042b0395b7442839868a35975b62905`.
- `git ls-tree` on that ref showed `mobile/lib/features/ai_coach/` and no `mobile/lib/features/live_coach/`.
- The existing AI Coach directory contains `ai_coach_context.dart`, `ai_coach_service.dart`, `ai_coach_sheet.dart`, `ai_exercise_generator.dart`, and `generated_exercise_repository.dart`.
- No application code, product decision, or branch ref changed.

## Verification state

- Read-only Git tree inspection: performed as listed above.
- Registry generation: `python scripts/dev/gen_document_registry.py` completed and wrote `docs/DOCUMENT_REGISTRY.md` with 362 documents.
- Product tests, checks, builds, migrations and runtime/device runs: NOT_RUN; documentation-only change.
- Push and merge: not performed.

## Remaining acceptance

This evidence verifies only the locally available remote-tracking snapshot, not that the remote branch has not advanced. ACS-010 remains a proposed operator acceptance, and exact-head GPT-PM review remains outstanding for later documentation changes.
