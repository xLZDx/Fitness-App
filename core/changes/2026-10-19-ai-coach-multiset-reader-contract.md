# AI Coach existing set-list and reader contract recheck

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Code baseline reviewed: `fcf90ca7` (`docs: correct AI Coach voice scope and status`)  
Change type: source-read recheck and documentation correction; no runtime behavior changed.

## Why this follow-up exists

The first status wording correctly observed that the current workout player writes at most one captured set per exercise, but described that as a model limitation. A broader source read showed the persisted model already has a set list. This record corrects the distinction: list storage exists; the current player completion action does not append multiple sets, and existing readers do not all present sets the same way.

## Verified source behavior

- `mobile/lib/features/workouts/data/workout_session.dart:29-105`: `WorkoutSessionExercise.sets` is `List<SetCapture>` and JSON serialization/deserialization preserve the list. Each `SetCapture` contains optional `weightKg` and `reps` (`set_capture.dart:8`). No new collection or set-list data model is needed merely to represent multiple sets.
- `mobile/lib/features/equipment/workout_player_page.dart:671-695`: the current completion writer derives one captured value pair and replaces that exercise's set list with zero or one item. On repeat tap it retains the session ID and overwrites that exercise entry; it is not an append-each-set workflow.
- `mobile/lib/features/workouts/data/workout_session.dart:339-398`: `asLogEntries()` selects one best set per exercise (weight, then repetitions) and emits one `WorkoutLogEntry` per exercise.
- `mobile/lib/features/workouts/state/workout_session_providers.dart:64-76,120-138` and `mobile/lib/features/data_export/data_export_providers.dart:83-96`: workout history/streak and export consume the `asLogEntries()` projection; these views therefore do not expose every set from a set list.
- `mobile/lib/features/progress/data/progress_charts.dart:70-76` and `mobile/lib/features/personalisation/data/volume_ledger.dart:96-133`: direct session metrics read all stored sets for session volume and weekly set counts.
- The source trace does not locate a whole-workout finish/cancel action in the reviewed player/route paths. This remains scoped as `NOT_FOUND IN REVIEWED PATHS`, not proof that no such behavior exists elsewhere.

## Changes made

- Corrected README, code map, backlog acceptance and design to distinguish the existing persisted list from the current one-set writer action.
- Updated Russian and English HTML status reports with that distinction and the mixed reader behavior.
- Corrected the preceding scope change record so its evidence no longer calls the list model itself a one-set persistence shape.

## Verification limits

- Read-only `rg` searches and direct source inspection only. No tests, checks, builds, CI, migrations, runtime behavior or production resources were run or changed.
- The complete action/repository map for every start/finish/cancel boundary and every consumer is still not claimed. The reported readers are the ones directly traced above.

## Remaining acceptance and next action

1. Finish mapping all requested voice intents to an existing visible action, state/controller/provider and repository result boundary.
2. Agree the required meaning of repeated sets against the existing list, and decide whether history/export projections should remain best-set views or expose every performed set.
3. Only after the documentation-only trace is accepted and a separate implementation GO exists, adapt the existing player/action path. Do not add a parallel store by default.

Task-local technical execution owner: Codex. GPT-PM owns product decisions. The operator is accountable for the delegated task. Implementation remains unauthorized by GPT-PM's `MODIFY` disposition.
