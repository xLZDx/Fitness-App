# Real repository binding

- Repository: `xLZDx/Fitness-App`
- Branch: `master`
- Audited remote HEAD: `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`
- Audit date: `2026-08-15`
- Local working tree: **NOT VERIFIED by GitHub connector**

## Important rule

Before any write gate, the local Claude Code/main session must verify:

```text
branch
HEAD
upstream
git status
unpushed commits
untracked files
concurrent work
```

Do not reset/stash/discard shared work automatically.

## Exact current recommendation surfaces

See `real_repo_map.json`.

Key split-brain paths found by G0:

- `home/state/suggestion_providers.dart`
- `personalisation/data/for_you_ranker.dart`
- `ai_planner/data/plan_builder.dart`
- `programmes/state/programme_providers.dart`
- `workouts/data/progression.dart`
- `recovery/data/deload_detector.dart`
- `ai_coach/ai_coach_context.dart`

The engine migration converges these one gate at a time.
