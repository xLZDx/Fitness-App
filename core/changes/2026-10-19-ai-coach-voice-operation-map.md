# AI Coach voice-to-existing-workout operation map

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Baseline HEAD: `fb80dd066116fa88a8c440adcb1e7d02c8dbdc33` (`docs: refresh AI Coach report provenance`)  
Branch: `docs/ai-coach-tdd-001`, 94 commits ahead of its upstream at baseline.  
Change type: documentation-only source trace; no runtime behavior changed.

## Operator scope and authorization

The requested product is voice as a second input to the existing Fitness App workout flow. Voice should reach the same operations, validation, state and persistence as touch. This work continues the accepted documentation-only scope correction and GPT-PM `MODIFY` disposition: map the current touch paths and evidenced gaps before proposing implementation. It does not authorize a voice adapter, runtime changes, a new store, tests, deployment or production action.

## Initial state and provenance

- At turn start, `git status --short --branch` showed the branch above and one pre-existing untracked file: `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md`.
- At turn start, no tracked files were modified. The initial source-map/backlog/report diff command returned no diff for its three existing targets; its English filename guess was wrong and did not include the actual `AI_COACH_STATUS_2026-10-19.html`. `git status` is the baseline evidence for the entire checkout. `03_DESIGN.md` was not part of that targeted diff. The pre-existing untracked file was not read, edited, staged or attributed to this turn.
- The operator-provided GPT-PM response is the `MODIFY` reply manually sent by the operator and later read via `gpt_session_peek` under request ID `d24c171a-94ef-446d-b891-14ce84e66071`. The prior Codex PM Bridge send attempt for that request was `ATTACHMENT_NOT_LANDED` with `sendPhase=not-started`; it was not a sent request or correlated approval. GPT-PM reported it had not independently verified repository HEAD.

## Source trace

- Workout entry buttons route to `/workout/:id` (optionally `?day=`); the router opens `WorkoutPlayerPage`. The route does not create a session. Sources: `mobile/lib/features/equipment/exercise_page.dart:66-71`, `mobile/lib/features/home/home_page.dart:708-710,1265-1268`, `mobile/lib/features/workouts/workouts_page.dart:1126-1129`, `mobile/lib/features/ai_planner/ai_planner_page.dart:134-137`, `mobile/lib/core/router/app_router.dart:474-485`.
- `SetTimerCard` can open `SetCaptureSheet` on a fresh load-bearing set and puts its result in `setLoadProvider`. Its primary control uses `setTimerProvider` / `SetTimerController.start`, pause and reset. The timer is transient state and reaching its done phase does not save a workout set. Sources: `mobile/lib/features/workouts/widgets/set_timer_card.dart:50-69,200-239`, `mobile/lib/features/workouts/state/set_timer_providers.dart:140-210,247-249`.
- The capture sheet opens before the set in this flow. Its reps field is labelled as target reps when planning and reps after the set, but the same value is returned in `SetCapture`; `_MarkCompleteButton` later writes that `reps` value. Therefore this flow does not establish that the persisted number is the number actually performed. Sources: `mobile/lib/features/workouts/widgets/set_capture_sheet.dart:50-60,154-185`, `mobile/lib/features/equipment/workout_player_page.dart:659-695`.
- `_MarkCompleteButton.onTap` is private to `workout_player_page.dart`. It constructs a completed `WorkoutSession`, calls `logSessionActionProvider.notifier.log`, checks the `AsyncValue` error and then starts rest. The provider suppresses a concurrent save, reads the signed-in UID and calls the repository. Sources: `mobile/lib/features/equipment/workout_player_page.dart:572-599,669-780`, `mobile/lib/features/workouts/state/workout_session_providers.dart:85-110`.
- Production wiring uses `FirestoreWorkoutSessionRepository` (`mobile/lib/main.dart:434-435`). `save` writes `users/{uid}/workout_sessions/{id}` with `doc(id).set(...)`; after four seconds its timeout handler returns normally, so a later server rejection is not reported to the caller. A success snackbar therefore proves that the local future returned without error, not server acknowledgement. Source: `mobile/lib/features/workouts/data/firestore_workout_session_repository.dart:61-70`.
- The player completion writer replaces an exercise's existing `sets` list with zero or one captured pair and marks its session completed on that action. The model already serializes `List<SetCapture>`. Sources: `mobile/lib/features/equipment/workout_player_page.dart:684-695,720-725`, `mobile/lib/features/workouts/data/workout_session.dart:29-105`.
- Set-list readers are not identical: `asLogEntries()` selects the best set per exercise; `workoutSessionHistoryProvider` consumers (Home, progress, suggestions, recovery, personalisation, equipment last-session and equipment type-history) and data export consume those projected rows. `DayResult`, session-volume/personal-record chart code and the weekly volume ledger iterate stored sets. Sources: `mobile/lib/features/workouts/data/workout_session.dart:339-398`, `mobile/lib/features/workouts/state/workout_session_providers.dart:61-76,120-138`, `mobile/lib/features/home/state/home_dashboard_providers.dart:18-64`, `mobile/lib/features/home/state/suggestion_providers.dart:26`, `mobile/lib/features/recovery/state/recovery_providers.dart:14`, `mobile/lib/features/personalisation/state/personalisation_providers.dart:14-66`, `mobile/lib/features/equipment/widgets/last_session_card.dart:22-55`, `mobile/lib/features/workouts/data/equipment_type_history.dart:84-94`, `mobile/lib/features/data_export/data_export_providers.dart:80-96`, `mobile/lib/features/workouts/data/day_result.dart:86-129`, `mobile/lib/features/progress/data/progress_charts.dart:70-76,151-166`, `mobile/lib/features/personalisation/data/volume_ledger.dart:96-133`.
- In a scheduled day, the day strip changes exercises through a GoRouter replace callback. No single-exercise next/previous action was found in the reviewed path. No whole-workout start/finish/cancel action was found in the reviewed player/route paths; the summary page is a result view. Sources: `mobile/lib/features/equipment/workout_player_page.dart:493-505`, `mobile/lib/core/router/app_router.dart:465-485`.
- `mobile/lib/features/voice/data/voice_command.dart` is a parser with no production caller. It returns intents but does not dispatch them to timer, rest, capture, route or log actions. It has no `startWorkout` or `finishWorkout` intent.

## Decisions recorded

1. Keep the existing route, session model, repository and timer as the source of truth. Do not add a parallel tracker/store based on this evidence.
2. A shared action is required for the current private log callback if both touch and voice must invoke the same save, duplicate-write and result path. Extracting it is a proposal for a separately authorized code sprint, not a change in this turn.
3. If the product needs multiple performed sets, the minimal storage path is to append each confirmed set to the existing `WorkoutSessionExercise.sets` list. Preserve the existing best-set projection for its consumers unless product acceptance intentionally changes those surfaces; direct set-based readers already consume every item.
4. Keep planned target reps distinct from performed reps; actual reps are captured after completion. Resolve the Firestore timeout acknowledgement before voice claims a durable/server-confirmed success.
5. Expose local/pending-sync versus server-acknowledged outcomes to the shared action. The current `AsyncValue<void>` plus timeout is insufficient to justify a server-durable success claim. Concurrent suppression is not replay idempotency.
6. Record whole-workout start/finish/cancel and single-exercise next/previous as `NOT_FOUND IN THE REVIEWED PATHS`, not universal absence. Do not map a generic voice `cancel` to timer reset.

## Files changed in this turn

- `docs/ai-coach/01b_CODE_MAP.md`: added the intent-to-operation table, shared-action conclusion, and the mixed set-reader contract.
- `docs/ai-coach/02_BACKLOG.md`: recorded evidence coverage and remaining AI-COACH-01 acceptance gaps while preserving the no-implementation authorization state.
- `docs/ai-coach/03_DESIGN.md`: replaced its stale “next input is the operation map” statement and added §0.1's explicitly unapproved, evidence-bounded proposal for the shared action, existing set list/readers, performed reps, honest persistence result and unsupported lifecycle; implementation remains unauthorized.
- `reports/AI_COACH_STATUS_2026-10-19.ru.html` and `.html`: updated the voice operation table, current work, remaining contract and next actions in both languages.
- `core/changes/2026-10-19-ai-coach-voice-operation-map.md`: this linked change record.

## Verification state and limits

- Read-only source inspection and scoped `rg` searches only; no tests, checks, builds, CI, migrations, runtime changes, production changes, push or merge were performed in this turn.
- The HTML report pair was conformed in this turn with `python C:\Users\koros\.claude\tools\report_conform.py D:\Repo\Fitness_App_aicoach\reports\AI_COACH_STATUS_2026-10-19.ru.html D:\Repo\Fitness_App_aicoach\reports\AI_COACH_STATUS_2026-10-19.html`; the tool reported both files refreshed. This formats provenance/copy controls and is not a test/build gate.
- No runtime acceptance has been demonstrated. Voice remains `NOT IMPLEMENTED`.

## Acceptance and next owner/action

- AI-COACH-01 AC-1 source mapping: documented for reviewed entry, timer, capture, logging, rest, navigation and set-reader paths; whole-workout start/finish/cancel and single-exercise next/previous are explicitly `NOT_FOUND IN THE REVIEWED PATHS`.
- AC-2: private logging callback and the required shared action boundary are documented. The boundary has not been implemented.
- AC-3: existing list writer and projection/direct reader differences are documented; §0.1 proposes appending confirmed performed sets to the existing list while retaining the best-set compatibility projection. Target-versus-performed rep capture still needs acceptance.
- AC-4: the existing concurrency guard and save result path are documented; §0.1 proposes an explicit local-versus-server acknowledgement result because the Firestore timeout can hide a later server rejection. No runtime proof exists.

Task owner: operator. Technical executor: Codex. GPT-PM owns product decisions. Codex does not claim qualified clinical signer or production on-call roles. Next step: review the proposal in `03_DESIGN.md` §0.1 and record product disposition; implementation remains `NOT AUTHORIZED` until the contract is accepted and a separate code-sprint GO exists.
