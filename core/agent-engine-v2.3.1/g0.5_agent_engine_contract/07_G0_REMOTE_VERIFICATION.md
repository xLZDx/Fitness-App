# G0 remote verification — 2026-08-15

The G0 anchor was re-verified independently against the private GitHub repository.

- repository: `xLZDx/Fitness-App`
- branch context: `master`
- exact commit exists: `5b7c9acc7acdd00db502e1934afd2c75983eaeb9`
- `mobile/lib/features/workouts/data/progression.dart` at that exact SHA contains:
  - `tooHard` -> 5% decrease;
  - three `tooEasy` sessions + target reps -> 5% increase;
  - two `justRight` sessions + target reps -> fixed 2.5/1.25 kg increment;
  - global 2.5 kg rounding.
- RE-B01 is confirmed at that exact SHA:
  - `fitness_model.dart`: `tooHard` contributes 0 to `good` and documentation says lower score should downweight/recover;
  - `for_you_ranker.dart`: `priority = 1 - muscleScore`, then sorts descending.

Therefore the remote G0 findings remain valid.

**Still not verified by remote GitHub access:** the operator's local shared working tree.
Before G1, local branch/HEAD/upstream/status/unpushed/untracked/concurrent work must be checked.
