# TDD-001: Live AI Coach and Hands-Free Workout Engine (input draft v0.1)

Status: DRAFT / REVIEW REQUIRED. Implementation: NOT YET APPROVED. Production: NOT AUTHORIZED.
Date of input: 2026-10-17. Project: Fitness App (`xLZDx/Fitness-App`). MVP target platform: Android.
This file is the operator-supplied input draft, translated to English without changing its meaning. It is the source for the requirements, design and test plan in this folder. Where it disagrees with the real code, the code wins and the disagreement is listed in the design document.

## 1. Summary

Add a voice-first personal AI trainer inside the existing app. The AI Coach talks in natural language, collects and clarifies personal information, builds 1, 2, 3 or 4 week programmes, explains exercise choice, loads and order, leads the user through a workout, manages sets, timers and rest, records real results, adapts future sessions from history and feedback, integrates with Form Coach, shows an animated avatar, and lets the user train with almost no screen use.

Product goal: move from "the user runs the workout alone" to "the AI trainer leads, the user performs". Main scenario: the user arrives at the gym, starts a voice session, puts the phone in a pocket and trains with headphones.

Core principle: the AI owns dialogue and personalisation; a deterministic Workout Engine owns workout state and persistence. The language model never writes to the database directly, never assigns dangerous loads on its own and never bypasses safety limits.

## 2. Scope

MVP functions (P0 mandatory for MVP, P1 extended version, P2 later):

| ID | Function | Priority |
|---|---|---|
| AC-001 | Voice dialogue with the AI | P0 |
| AC-002 | Use the user questionnaire | P0 |
| AC-003 | Get workout history | P0 |
| AC-004 | Generate a 1 to 4 week plan | P0 |
| AC-005 | Explain exercise choice | P0 |
| AC-006 | Start a workout by voice | P0 |
| AC-007 | Move between exercises | P0 |
| AC-008 | Record sets and repetitions | P0 |
| AC-009 | Start, stop and change timers | P0 |
| AC-010 | Replace an unavailable machine | P0 |
| AC-011 | Voice feedback | P0 |
| AC-012 | Work with a locked screen | P0 |
| AC-013 | Resume an interrupted workout | P0 |
| AC-014 | Contraindication and restriction checks | P0 |
| AC-015 | Minimal visual avatar | P1 |
| AC-016 | Long-term personal memory | P1 |
| AC-017 | Post-workout analysis | P1 |
| AC-018 | Deep Form Coach integration | P2 |
| AC-019 | Extra personalities and voices | P2 |
| AC-020 | Wear OS integration | P2 |

Out of the first MVP: autonomous disease diagnosis; medical prescriptions; technique correctness without camera or sensors; continuous video of the whole workout; mandatory 3D avatar on a locked screen; guaranteed AI without internet; starting microphone capture from geolocation alone; iOS and Wear OS without separate verification.

## 3. Integration with the existing system

Stack from the sources: Flutter/Dart, Riverpod, GoRouter, Firebase Authentication, Cloud Firestore, Cloud Functions, Firebase AI Logic, ML Kit, Android platform integration, existing speech-to-text and text-to-speech dependencies.

Reused modules: `features/ai_planner` (planning), `features/ai_coach` (current AI consultations), `features/workouts` (log and execution), `workout_session.dart` (saving workouts), `set_session.dart` (timer state machine), `features/form_check` (technique analysis), `features/safety` (safety limits), `features/training_context` (session context), `features/profile`, `features/recovery`, `features/visual_equipment`. No duplication of existing business logic without a separate architectural reason.

Compatibility: additive module; no destructive migration of user data; old workout routes keep working; manual execution and logging stays; feature flag `live_ai_coach_enabled`; turning the new UI off loses no workout results; the unfinished AI Coach is not mixed with the mandatory Phase 2 stabilisation tasks.

## 4. Target architecture

Components: Live Coach UI (avatar renderer, conversation view, workout HUD, hands-free controls); Voice Runtime (audio capture, streaming transport, voice playback, interruption handling, Android foreground service); AI Coach Orchestrator (dialogue manager, context builder, action router, tool permission validator, explanation generator); Coach Domain Services (workout planner, workout executor, timer adapter, exercise selector, safety engine, memory manager, progress analyzer); existing services (Auth, Firestore, WorkoutSession, AI Planner, Form Coach, exercise catalog).

Proposed source root `mobile/lib/features/live_coach/` with sub-folders `data`, `state`, `voice`, `orchestrator`, `runtime`, `planning`, `safety`, `memory`, `avatar`, `widgets` and `live_coach_page.dart`. Exact names and placement must be confirmed against the current Phase 2 branch before implementation.

## 5. Voice architecture

Requirements: streaming recognition; streaming playback; user can interrupt a reply; partial phrases handled; protection from repeated command execution; Bluetooth headphones; resume after a short connection loss; explicit end of the voice session; microphone off on request.

Two modes to compare for MVP: Mode A realtime speech-to-speech through a server session controller; Mode B STT then LLM then TTS. Mode A is preferred for natural dialogue, Mode B stays as a fallback for command mode. The final choice depends on measured latency, cost, API availability, Android lifecycle and noisy-gym trials.

Voice state machine: STOPPED, INITIALIZING, LISTENING, PROCESSING, SPEAKING, INTERRUPTED, RECONNECTING, PAUSED, back to STOPPED. Audio state is separate from workout state: a network loss moves voice to RECONNECTING while the local rest timer keeps running.

Android background operation: native foreground service of a suitable type; explicit microphone permission; start only from an allowed user scenario; persistent notification while recording; correct screen-lock handling; incoming calls and audio focus changes; recovery after Bluetooth disconnect; battery control. Verify on Android 13 to 16 and currently supported devices. The OS must not be assumed to allow arbitrary microphone restart from the background.

## 6. Workout execution engine

The AI does not keep authoritative workout state in dialogue history. The Workout Runtime and its event journal are authoritative. The AI receives a state snapshot, interprets user intent and requests an allowed action.

Workout state machine: NOT_STARTED, PREPARING, ACTIVE_EXERCISE, SET_IN_PROGRESS, SET_RECORDED, RESTING, back to ACTIVE_EXERCISE, NEXT_EXERCISE, PAUSED, COMPLETED, ABANDONED.

Commands: get_today_plan(), start_workout(plan_id), get_current_exercise(), start_set(exercise_id), record_set(exercise_id, reps, weight_kg, effort), start_rest(duration_seconds), pause_rest(), resume_rest(), skip_rest(), complete_exercise(exercise_id), replace_exercise(exercise_id, replacement_id), pause_workout(), resume_workout(), finish_workout(), get_progress_summary().

Every state-changing command carries an envelope: command_id (idempotency), session_id, expected_revision (stale-state protection), action, payload.

Set record fields: set_id (stable, one per set), exercise_id, session_id, repetitions, weight_kg, effort (optional), completed_at, source (manual, voice, form_coach, wearable), command_id. Must stay compatible with the existing `WorkoutSession` model.

Idempotency: check repeats before changing state; command and result are written atomically; a repeated request returns the original result; a version conflict forces a state re-read; no unconfirmed command counts as executed.

## 7. AI workout planning

Inputs: goal, age category, fitness level, frequency, available time, equipment, history, questionnaire restrictions, wellbeing, recovery, preferences, last actual loads. Horizons: 1, 2, 3 or 4 weeks. A plan holds, per workout, goals, intensity ranges, recovery advice and adaptation conditions. Plan structure: TrainingPlan (plan_id, user_id, duration_weeks, goal, status, version, created_at) with TrainingWeek[] with TrainingDay[] (day_id, planned_date, objective) with PlannedExercise[] (exercise_id, sets, reps_range, rest_seconds, rationale).

Explainability: every personal recommendation has machine-readable reasons (for example user_goal, experience, available_equipment, recent_training, safety_status). The AI may phrase the explanation but must not invent reasons absent from the data.

Adaptive planning only after checking actual repetitions, subjective difficulty, completion of earlier sessions, recovery time, known restrictions and safe progression rules. The user can reject a suggestion.

## 8. Personal memory

Categories: Profile Memory, Training Memory, Preference Memory, Session Memory, Safety Context. Source priority on conflict: (1) current mandatory safety restrictions, (2) confirmed user changes, (3) authoritative stored results, (4) current plan, (5) derived personal memory, (6) language model assumptions. The AI may not change confirmed restrictions on a guess.

Privacy: store the minimum; explicit consent for voice data; separate consent for audio storage if ever needed; deletion of user memory; export; owner separation by Firebase UID; protected transfer; retention policy; minimal sensitive data in logs. Raw audio is not stored by default.

## 9. Safety

The Safety Engine runs independently of the AI model and checks actions before execution, refusing when needed. The AI Coach may not: ignore contraindications; assign loads outside the allowed range; replace missing results with invented ones; claim it saw technique without analysis; bypass unfinished screening; change safety restrictions without confirmation; auto-continue after dangerous symptoms. On chest pain, marked dizziness, fainting or other potentially dangerous symptoms the workout stops and the user is advised to seek medical help.

Fail-closed: if a mandatory safety check is unavailable, a potentially dangerous recommendation is blocked. Safe helper actions stay allowed: explain the interface, view recorded history, stop a timer, finish the session.

## 10. Living avatar

States: idle, listening, speaking, thinking, positive feedback, exercise explanation, warning. The avatar receives events from the controller and never changes the Workout Runtime directly (Coach Event, Avatar State Mapper, Animation Controller, Avatar Renderer). MVP: one character, one base voice, idle animation, mouth sync with speech, a small set of emotional reactions, ability to hide the avatar fully. 3D quality must not block the voice engine.

## 11. Offline and recovery

On internet loss these keep working: local timer, exercise display, saving local commands, cached plan, manual result entry. The cloud AI dialogue may become unavailable; the app must say so honestly and not imitate successful command handling. After reconnect: check the active session, restore local state, sync unconfirmed events, remove duplicate commands, refresh AI context, resume conversation only if the audio session state allows. After a crash the user can continue or finish the workout without losing confirmed results.

## 12. Non-functional requirements

Initial prototype targets (design requirements, not measurements): first audio acknowledgement of a command P95 at most 2 s; local set record P95 at most 300 ms; local timer command reaction P95 at most 300 ms; voice reconnect time to be measured and an SLO set; duplicated confirmed sets 0; lost confirmed sets 0; workout recovery after a crash mandatory.

Reliability: deterministic runtime, idempotent operations, event journal, state versioning, per-user session isolation, manual continuation when AI fails, separate AI cost control. Observability: response time, audio connection errors, command execution errors, version conflicts, safety refusals, session duration, recovery success, compute and AI API usage; no full conversations or sensitive personal data in diagnostic logs without need.

## 13. Security

All server operations bind to a verified user identity; an arbitrary UID from an AI command is never proof of ownership. Each AI tool checks: user authorisation, ownership of the workout session, right to the operation, allowed state transition, argument validity, safety restrictions. Long-lived AI API keys are forbidden in the mobile app; streaming voice uses a server mechanism issuing short-lived credentials or server proxying after a separate security review. User text, catalogue data and external material are untrusted input; instructions inside them cannot override system limits or tool permissions.

## 14. Verification strategy

Unit: state transitions, command validation, idempotency, timer transitions, plan validation, safety rules, context construction, memory projection. Integration: Firebase auth, Firestore persistence, voice-to-command processing, reconnection, concurrent updates, duplicate commands, account switching, session recovery, permission revocation. E2E scenarios: E2E-01 full workout by voice; E2E-02 busy machine, safe replacement; E2E-03 internet loss during rest; E2E-04 repeated recognised voice command; E2E-05 incoming call during conversation; E2E-06 Bluetooth headphones disconnect; E2E-07 app crash; E2E-08 user reports pain; E2E-09 attempt to reach another user's session; E2E-10 AI unavailable, manual workout continues; E2E-11 locked screen and allowed background audio mode; E2E-12 finish workout and reconcile saved results. Device acceptance: first target device Samsung Galaxy S23; real gym testing is mandatory because an emulator does not reproduce background noise, Bluetooth routing, microphone behaviour or power saving.

## 15. Roadmap

AI-COACH-00 Architecture and contracts (refined TDD, voice engine ADR, workout runtime contracts, event schema, safety policy, privacy policy, dependency map, test plan, feature flag specification; exit: design review approved). AI-COACH-01 Workout runtime foundation (command dispatcher, idempotency, session state, timer adapter, persistence, recovery, unit tests; exit: all critical runtime tests pass). AI-COACH-02 Voice vertical slice (audio capture, AI conversation, tool calling, Bluetooth, Android lifecycle, hands-free flow; exit: full demo workout without manual control after start). AI-COACH-03 Planner and memory (personal context, training plans, adaptive suggestions, explanations, persistent memory; exit: reproducible and safe decisions on given profiles). AI-COACH-04 Living avatar (renderer, lip sync, animation states, coach UI, battery and performance testing; exit: avatar does not degrade the critical voice and workout runtime). AI-COACH-05 Pilot and acceptance (device testing, gym noise testing, user acceptance, security review, reliability review, cost validation, rollback plan; exit: separate pilot readiness decision; production needs its own permission).

## 16. Open architecture decisions

ADR-001 realtime voice provider (compare latency, cost, privacy); ADR-002 audio transport (streaming with reconnect); ADR-003 server orchestration (isolated backend service); ADR-004 memory storage (Firestore plus minimal projections); ADR-005 local event journal (durable local storage); ADR-006 avatar implementation (light renderer inside Flutter); ADR-007 WorkoutSession migrations (additive, backward compatible); ADR-008 hands-free lifecycle (Android foreground audio service); ADR-009 offline commands (limited safe set); ADR-010 AI provider fallback (safe switch or manual mode). No option is approved just because the initial draft lists it.

## 17. Critical risks

Duplicated sets (critical; idempotent command execution). Lost workout result (critical; durable journal and recovery). Dangerous AI recommendation (critical; independent Safety Engine). Personal data leak (critical; auth, isolation, minimisation). Background microphone not working (high; native Android lifecycle testing). Gym noise (high; real-device voice acceptance). High streaming AI cost (high; usage controls and fallback). Damage to existing history (high; additive data changes). Workout depends on the AI server (high; local deterministic runtime). Battery drain (medium; audio and avatar profiling).

## 18. Definition of done for the initial MVP

The user starts a workout through the AI Coach; the AI uses the confirmed profile and restrictions; the AI explains the proposed plan; the user trains by voice; all confirmed sets are saved correctly; timers work independent of the network AI; repeated commands do not duplicate; the workout recovers after allowed failures; the user can stop or disable the AI at any time; the Safety Engine blocks forbidden actions; existing app functions keep working; Android E2E and real-device trials pass; the feature flag disables the AI Coach without data loss; all found blockers are documented. Security, data protection, accessibility, battery use and AI API economics are verified separately.

## 19. Initial decision

Recommendation: APPROVE FOR DESIGN REVIEW. Do not build a separate app; do not rewrite AI Planner and WorkoutSession without need; build a deterministic Workout Runtime and a voice layer; use one AI Coach Orchestrator; separate personal memory, workout facts and dialogue; integrate Form Coach as an independent source of confirmed technique findings; ship under a feature flag; start with Android while keeping the architecture portable; no production release before separate verification gates. The document does not authorise production changes, deployment, migration of user data or closing of existing Phase 2 tasks. Status: TDD-001 v0.1 DRAFT, ready for technical review; priority questions before implementation: the WorkoutSession contract, safety of recording voice commands, background microphone operation, streaming dialogue cost (ADR-001 to ADR-010).
