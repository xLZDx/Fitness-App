# S02-01 note: SportType-to-model table (design 3.6)

Status: verified at S02-01 build time, 2026-10-16.

Design 3.6 left the exact table OPEN. It only said that `ActivitySession` owns endurance and device-recorded sports, and that `WorkoutSession` and `WorkoutLogEntry` keep gym and plan-driven logging.

What the code shows (FACT, read in this worktree):

- `SportType` has 12 values (`mobile/lib/features/activity/data/sport_type.dart`) and is referenced only inside `activity/data`.
- `WorkoutSession` (`mobile/lib/features/workouts/data/workout_session.dart`) holds a title, a list of exercises with sets, start and completion time, status, duration and notes. `WorkoutLogEntry` is its one-exercise legacy mirror. Neither has a sport, heart-rate, GPS or source field.

Pinned table (`mobile/lib/features/activity/data/workout_model_ownership.dart`, constant `kSportModel`):

| Model | Sports |
|---|---|
| `activitySession` | running, trailRunning, walking, hiking, cycling, indoorCycling, mountainBiking, swimmingPool, swimmingOpenWater, rowing, other (and every unknown name, which `SportType.parse` turns into `other`) |
| `workoutSession` (with its legacy mirror `WorkoutLogEntry`) | strength |

Difference from the design text: none contradicts it, but the design named no table. Two judgement calls are recorded here: `rowing` is endurance and goes to `activitySession`; `other` and unknown names go to `activitySession` because the old workout model cannot store a session without exercises and sets.
