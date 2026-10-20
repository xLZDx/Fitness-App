# AI Coach report wording correction: set-list contract

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Code baseline in report: `89f4a50b`  
Change type: Russian status report wording correction; no source/runtime change.

## Why

The English status report and source documents had been corrected to distinguish the persisted set list from the player's current one-set writer. Two rows in the Russian report still incorrectly called the model itself one-set-only. This correction aligns the executive acceptance matrix and the repeated-set table with the source evidence.

## Changes

- State that `WorkoutSessionExercise.sets` already stores a list.
- Identify the current workout player as the layer that replaces that list with zero or one capture per exercise.
- State that `asLogEntries()` projects the best set while direct volume metrics count all sets.
- Keep the next step limited to reconciling existing writer/reader semantics; no separate store is proposed.

## Verification limits

Only the existing Russian report HTML and provenance block were edited. No tests, checks, builds, CI, migrations, source/runtime behavior, production resources or service traffic changed.

Detail: `reports/AI_COACH_STATUS_2026-10-19.ru.html`, sections “Что уже есть в коде”, “Повторные подходы”, and “Матрица принятия”.
