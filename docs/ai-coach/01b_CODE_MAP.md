# AI Coach code map: draft claims versus the real code

Initial source: code-explorer run on 2026-10-17 over `origin/phase2/main` at `14513a87` (worktree `Fitness_App_aicoach`). Read-only; git state of that explorer run was not captured. Relevant interfaces below were re-read on 2026-10-18 at source head `bdf089c83b23ef35569ec09fc8ff117ac52b1194`. Paths are relative to the repo root; line numbers can drift as files change.

## Verified facts

- `WorkoutSession` has `id, title, exercises, startedAt, completedAt?, status, durationMinutes?, notes?` (`mobile/lib/features/workouts/data/workout_session.dart:192-219`). No revision, version, owner uid, event list or command id.
- `WorkoutSessionStatus { pending, completed, abandoned }` (`workout_session.dart:11`); nothing writes `pending` or `abandoned`; the player writes `completed` on the first set tap (`mobile/lib/features/equipment/workout_player_page.dart:724-725`). History filters on `completed` (`mobile/lib/features/workouts/state/workout_session_providers.dart:73-76`).
- A set is `SetCapture = ({double? weightKg, int? reps})` (`set_capture.dart:8`); serialised as `weightKg` and `reps` only (`workout_session.dart:74-79`). The player keeps at most one set per exercise (`workout_player_page.dart:671-695`); `asLogEntries` collapses to the heaviest set (`workout_session.dart:339-398`).
- Persistence: `users/{uid}/workout_sessions/{sessionId}`, plain `doc(id).set(...)` with a 4 s timeout that swallows a late rejection (`firestore_workout_session_repository.dart:20-21,62-70`). No transaction, no revision check, no command ledger; the only double-tap guard is `if (state.isLoading) return;` (`workout_session_providers.dart:96`). Offline persistence is the Firestore SDK default; no local journal.
- `set_session.dart` is a clock-free interval timer for timed sets (phases idle, gettingReady, work, rest, done; `:21-38`), not a workout state machine. `RestTimerController` uses a wall-clock `endsAt` with an injectable clock (`rest_timer_providers.dart:53-153`).
- Voice: `mobile/lib/features/voice/data/voice_command.dart` is an English-only substring parser with 12 command kinds and no production caller. `speech_to_text` is declared but never imported; `RECORD_AUDIO` is deliberately absent from `AndroidManifest.xml` (`:30-35`), to be added only with the feature, privacy text and Play declaration. TTS: `TtsVoiceCoach` (`form_check/data/tts_voice_coach.dart:22`), default `ru-RU`.
- Android: no foreground service, no `FOREGROUND_SERVICE*`, no `BLUETOOTH_CONNECT`. Impeller is disabled on the S23 Ultra (`AndroidManifest.xml:98-105`).
- AI path: callables to Vertex AI with Application Default Credentials; no API key in repo or app (`functions/src/ai_gateway.ts:34-43`). `aiCoachAdvice` is one-shot text, 40 per day, 512 output tokens, 45 s timeout (`functions/src/ai_coach_advice.ts`, `abuse_guard.ts:425`). A global server kill switch exists (`abuse_guard.ts:268-324`). No realtime, streaming or ephemeral-token surface exists.
- `features/ai_planner` is a deterministic on-device single-session builder with typed `PlanReason` codes and `PlanRefused` (`ai_planner/data/workout_plan.dart:21-68`). No multi-week plan type exists.
- Safety: `SafetyContext`, `evaluateExercise`, `allowsAnyTraining`, fail-closed `safetyContextProvider` (`safety/data/eligibility.dart`, `safety/state/eligibility_providers.dart:38-44`). No mid-session symptom stop path.
- Health answers are device-only; Firestore rules strip them (`firestore.rules:209-250`), so a server orchestrator cannot read contraindications.
- Rules: `users/{uid}/{coll}/{document=**}` owner wildcard, `workout_sessions` not excluded, no schema or revision fence (`firestore.rules:83-127`). Patterns to copy: activity `rev` fence (`:989-1007`), `nutrition_plan` `planVersion + 1` (`:714`), closed-schema helpers.
- Conventions: Riverpod 2.6, go_router 16, `features/<name>/{data,state,widgets}`, repositories overridden in `main.dart:434-435`, injectable clocks, callable pattern with injectable `CoachAsk`.

## Disagreements with the draft

| # | Draft claim | Reality |
|---|---|---|
| D1 | `set_session.dart` is the workout timer state machine | It is an interval timer for timed sets; the draft workout state machine does not exist |
| D2 | A set has set_id, completed_at, source, command_id, effort | Only weight and reps exist; serialiser would drop extras |
| D3 | Event journal and state versioning exist | Neither exists; nearest analogues are activity `rev` and `planVersion` |
| D4 | WorkoutSession supports a resumable active workout | `pending` and `abandoned` never written; completed on first set; no owner field |
| D5 | Atomic idempotent command plus result | Plain upsert with a swallowed 4 s timeout; no ledger |
| D6 | Existing speech-to-text dependency | Declared, never imported; no RECORD_AUDIO; no adapter |
| D7 | Firebase AI Logic is in the stack | Client calls removed; callables to Vertex only; `firebase_ai` unused |
| D8 | ai_planner builds 1 to 4 week plans | Deterministic single-session builder; TrainingPlan hierarchy is new |
| D9 | ai_coach can carry dialogue | One-shot, 512 tokens, 40 per day, "deliberately not a chat" |
| D10 | `features/live_coach/` | Does not exist in the locally available `origin/phase2/main` snapshot `85e7e91ed042b0395b7442839868a35975b62905` checked for Phase 9 on 2026-10-18. The existing `features/ai_coach/` directory contains `ai_coach_context.dart`, `ai_coach_service.dart`, `ai_coach_sheet.dart`, `ai_exercise_generator.dart`, and `generated_exercise_repository.dart`. The proposed `live_coach/` layout is new design intent, not a current repository layout. Other neighbors: `marketplace` (holds `coach_marketplace_service.dart`; corrected 2026-10-17), `form_check/coach_*`. |
| D11 | Feature flag `live_ai_coach_enabled` | No client flag mechanism; only a global server AI kill switch |
| D12 | Android foreground service, Bluetooth recovery | None exist; new native work plus Play declaration |
| D13 | Safety Engine stops on chest pain, dizziness | Safety is profile-based eligibility only |
| D14 | AI uses confirmed profile and restrictions | Health data is device-only; server cannot read it |
| D15 | Short-lived credentials for realtime voice | No such function; all AI callables are request/response |
| D16 | Avatar renderer with mouth sync | Only a pose skeleton painter in `form_check` |
| D17 | Additive data needs no rules change | Wildcard allows any shape; a revision fence or schema needs a carve-out |

## Reusable seams

1. `SetSession`/`SetPlan`/`SetCue` pure core as a template for a testable reducer.
2. `RestTimerController` with wall-clock `endsAt` and injectable clock.
3. `CuePlayer`, `VoiceCoach`, `GatedVoiceCoach`, `TtsVoiceCoach` output seams.
4. `parseCommand` as a Mode B fallback grammar after normalisation and a confirmation policy.
5. `WorkoutSessionRepository` interface and provider override as the persistence seam.
6. `asLogEntries` read adapter: new data must stay readable through it.
7. `SafetyContext`/`evaluateExercise`/`safetyContextProvider` as the action gate.
8. `PlanReason` sealed codes as the explainability pattern.
9. `eligibleForTrainingContext`, `visual_equipment`, `deload_detector` for substitution and recovery.
10. The `aiCoachAdvice` callable pattern (auth, App Check, non-anonymous, kill switch, quota, parse, generate).
11. Rules templates: `rev` fence, `planVersion + 1`, closed-schema helpers, wildcard carve-out convention.
12. `functionsForRegion` helper and App Check activation.

## Interface facts rechecked 2026-10-18 (OQ-18)

- **`ai_planner`** — `buildPlan` in `mobile/lib/features/ai_planner/data/plan_builder.dart` is a pure synchronous function. Required inputs are a candidate exercise pool, weekly deficit map, `DeloadVerdict` and `SafetyContext`; optional inputs include cycle state/self-report, target minutes, recommendation hints and `TrainingContext`. It returns `PlanReady(GeneratedPlan)` or `PlanRefused`; `GeneratedPlan` is a single session with exercises, intensity factor and typed reasons, not a multi-week plan. `generatedPlanProvider` in `mobile/lib/features/ai_planner/state/ai_planner_providers.dart` resolves auth/profile, safety, deficit, deload, context and equipment repository inputs before calling it.
- **`training_context`** — `mobile/lib/features/training_context/data/training_context.dart` defines gym, outdoor-minimal, home and yoga contexts; pure helpers derive equipment access, narrow candidates, preserve safety fields and apply shared eligibility. `mobile/lib/features/training_context/state/training_context_providers.dart` stores the user's answer in per-UID SharedPreferences and exposes Riverpod providers. This is local context/filtering, not a server or model API.
- **`recovery`** — `detectDeload` in `mobile/lib/features/recovery/data/deload_detector.dart` takes recent workout logs, scheduled sessions and optional HRV averages/time, and returns a typed verdict with signal codes and a volume factor. `deloadVerdictProvider` in `mobile/lib/features/recovery/state/recovery_providers.dart` currently supplies logs and scheduled sessions but no HRV. A separate explicit `acceptNext7Days` action changes eligible pending scheduled sessions; the action is not part of the pure detector.
- **`visual_equipment`** — `VisualEquipmentService.classifyFile` in `mobile/lib/features/visual_equipment/data/visual_equipment_service.dart` accepts a file path and optional top-K limit and returns `VisualMatch` values (catalog equipment id, confidence, optional label and source). The controller can combine printed-text recognition, classifier fallback and a separate describer. This is equipment-photo recognition; no current live-coach API or caller was found in the reviewed interfaces.
- **Integration limit** — these are existing mobile seams, not proof of a live-coach integration. A multi-week deterministic composer and its weekly progression/set-rep-rest rules remain new design work; do not assign that selection to the model or infer it from `buildPlan`.

## Risks and gaps

- Two writers (voice and UI tap) race with last-write-wins and no revision; the swallowed timeout means `save()` returning is not confirmation.
- No durable local command journal; a live session written as `completed` would count toward history, streaks and progression at once.
- `asLogEntries` hides multiple sets from progression and recovery; changing the set shape can silently alter readers.
- Safety input exists only on the device; either the device approves every model proposal or minimal derived flags are sent (privacy decision needed).
- The voice runtime is a greenfield native build (manifest, foreground service type, permissions, audio focus, Bluetooth, Play declaration, privacy text).
- AI quota is request-count based; a stream needs session-minute cost control.
- Prompt-injection mitigation today is explicitly partial; tool calling on workout state widens the surface.

## Unknowns

Git state of the explorer run; router details for `/workout/:id` and `s03_routes.dart`; account deletion coverage of `workout_sessions`; the Wear module's use of session state; other readers of `WorkoutSession` (export, backfill script, scheduled sessions); server-side validation of session writes; Vertex AI realtime availability, cost and region; Play Console policy status; Android 13 to 16 runtime behaviour; whether the 4 s timeout and last-write-wins are an intended contract.
