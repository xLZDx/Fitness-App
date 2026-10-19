# AI Coach scope correction: voice over the existing workout flow

Date: 2026-10-19  
Repository: `D:\Repo\Fitness_App_aicoach`  
Baseline HEAD: `f7aeddc1` (`docs: publish complete AI Coach status report`)  
Branch at baseline: `docs/ai-coach-tdd-001`, ahead 90 of `origin/docs/ai-coach-tdd-001`  
Change type: documentation and code-comment correction; no runtime behavior changed.

## Operator intent

The operator clarified that the AI Coach should be a voice assistant inside the existing Fitness App workout flow. Voice should invoke the same operations, validation, state and persistence as touch. The product is one workout flow with two input methods, not a second workout tracker, lifecycle or storage system.

## Product-owner disposition and provenance

GPT-PM returned `MODIFY`: accept the operator's scope, correct the architecture assumptions, trace existing screen/action/provider/repository paths, and require evidence for any missing capability before proposing infrastructure. The reply also said implementation was not authorized.

The operator reported manually sending the request and asked Codex to retrieve the reply. PM Bridge `gpt_session_peek` read a response containing request ID `d24c171a-94ef-446d-b891-14ce84e66071` from the bound conversation. The separate PM Bridge `send-and-await` attempt for that ID failed with `ATTACHMENT_NOT_LANDED`; its durable job explicitly says `Nothing was sent`, has no user turn/reply correlation, and is not the source or a correlated approval. GPT-PM also stated the response was based on supplied files and did not independently authenticate the exact repository HEAD. The product scope is directly stated by the operator; the GPT-PM response is recorded as the requested disposition, with those transport/head limits.

## Code evidence checked in this turn

- `mobile/lib/features/ai_coach/ai_coach_sheet.dart` is a machine-specific one-shot advice sheet. `mobile/lib/features/ai_coach/ai_coach_service.dart` calls `aiCoachAdvice` with context fields and returns one text answer; it does not execute workout operations.
- `mobile/lib/features/voice/data/voice_command.dart` contains a pure parser for set, rest, navigation, help and numeric entry intents. It has no production caller. `VoiceCommandKind` does not include whole-workout start or finish.
- `speech_to_text` is declared in `mobile/pubspec.yaml`; a scoped `rg` over `mobile/lib` and `mobile/test` found no `SpeechToText` or `speech_to_text` use. `mobile/lib/features/voice/` contains only the parser file.
- `/workout/:id` opens the existing exercise player; `?day=` groups exercise entries for a scheduled day, and the day strip changes the selected exercise route (`app_router.dart:474-485`, `workout_player_page.dart:185-196,493-505`). This is not a separate workout start/finish API.
- `SetTimerCard` opens `SetCaptureSheet`, writes optional load/reps capture to `setLoadProvider` and starts the existing timer (`set_timer_card.dart:58-68,210-238`). Timer completion alone does not persist a set.
- `mobile/lib/features/equipment/workout_player_page.dart` renders the existing set timer and completion action. `_MarkCompleteButton` builds a `WorkoutSession`, calls `LogSessionAction.log`, checks the result, and starts the existing rest timer after the write. It retains the same session id on repeat tap and stores at most one captured set for that exercise (`:400-411`, `:572-780`). The existing rest UI binds pause/resume, add-time and skip buttons to `RestTimerController` (`rest_timer.dart:180-219`).
- `mobile/lib/features/workouts/state/workout_session_providers.dart` routes `LogSessionAction.log` to `WorkoutSessionRepository.save`; `mobile/lib/main.dart:434-435` binds the application provider to `FirestoreWorkoutSessionRepository`. The provider fallback is a mock.
- `mobile/lib/features/workouts/state/rest_timer_providers.dart` contains `RestTimerController`; `mobile/lib/features/workouts/data/set_session.dart` models a timed set, not a workout-wide live-session runtime.

This is a partial trace, not a complete operation map. No whole-workout finish/cancel action was located in the examined workout/equipment player and route paths; the player marks its exercise/session record complete during logging, and the summary page is a read view. Broader start/finish/cancel mapping and exact multi-set semantics still need a complete path review before implementation choices are made. The current one-set-per-exercise persistence shape is a concrete limitation to reconcile with the requested workout behavior; it does not by itself justify a parallel store.

## Changes made

- `docs/ai-coach/00_README.md`: records the operator's scope correction, current implementation boundary, and the limited GPT-PM transport provenance.
- `docs/ai-coach/01b_CODE_MAP.md`: adds evidence from the current checkout and identifies the parser, persistence and operation-map limits.
- `docs/ai-coach/03_DESIGN.md`: marks the standalone runtime, journal and separate collection design as superseded and not approved absent gap evidence.
- `docs/ai-coach/02_BACKLOG.md`: replaces the AI-COACH-01/02 roadmap summaries and adds evidence-first acceptance criteria; the legacy story blocks are retained but explicitly marked not to implement.
- `mobile/lib/features/voice/data/voice_command.dart`: corrects a stale comment that implied a speech adapter already exists.
- `reports/AI_COACH_STATUS_2026-10-19.ru.html` and `.html`: updated the full status report to state clearly that voice control is not implemented; mapped the reviewed exercise navigation, set capture/logging, rest, finish/cancel, and repeated-set limits; added the operator-requested one-flow acceptance criterion and GPT-PM's manually returned `MODIFY` disposition with transport provenance.
- The same report records the latest read-only Cloud Monitoring windows: no series in the 17-minute window ending `2026-10-19T09:47:53Z`; the 7-day query returned 44 points per readiness status, latest at `2026-10-16T11:32:00Z`. No synthetic `aiCoachAdvice` request was made.
- Refreshed both HTML files with `report_conform.py` using Python 3.14.3; `py -3` could not launch because its configured interpreter path was missing.

## Verification and limits

- Read-only source searches and file review only; no tests, checks, builds, CI, migrations, deployment or production/runtime changes were run.
- No implementation was made or authorized by the GPT-PM disposition.
- Initial worktree evidence: only the pre-existing untracked `core/changes/2026-10-18-ai-coach-phase9-gptpm-transport-followup.md` was present. It was not edited or staged. Its origin is not established here.

## Remaining acceptance and next action

1. Finish the read-only call-path map for each requested command, UI result/confirmation boundary, and every `WorkoutSession` reader; the current review is explicitly partial for whole-workout finish/cancel and reader coverage.
2. Compare the complete map with the operator's required workout behavior and list only evidenced gaps; assess any set-model extension through the existing `WorkoutSession`/repository and its readers.
3. Update design/backlog acceptance from complete evidence. Keep implementation blocked until a code-sprint GO; implementation and device tests remain `NOT_RUN`.

Task-local technical execution owner: Codex. Product decision owner: GPT-PM. The operator is accountable for the delegated task. These roles do not imply clinical qualification or a continuously operating production on-call rotation.
