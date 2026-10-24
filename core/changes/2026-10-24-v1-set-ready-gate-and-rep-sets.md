# Change record: ready gate before the set and rep-based sets (2026-10-24)

Base: master 06479b94. Operator reports from a real phone: (3) the spoken instruction was cut off at the start and the person had no time to prepare; (4) every exercise was a fixed 30 s timed set although most sets are counted in repetitions with a load.

## What changed
- mobile/lib/features/workouts/data/set_session.dart: new SetPhase.briefing gate (no clock, no ticks or gong); confirmReady() starts a 3 s countdown (readySeconds default 10 -> 3); new finishRepSet() ends a rep set even while paused.
- mobile/lib/features/form_check/data/voice_coach.dart, tts_voice_coach.dart: GatedVoiceCoach.sayAndWait() waits for the speech to finish (cap 15 s + text length / 8, then the speech is stopped and the gate opens); voice off or muted opens the gate at once; form-coach cues stay fire-and-forget.
- mobile/lib/features/workouts/state/set_timer_providers.dart, active_session_status.dart: introSpeaking flag, confirmReady, finishRepSet, clock stops when the session finishes; the status strip treats briefing as an active phase.
- mobile/lib/features/workouts/data/set_prescription.dart (new): SetMode (reps or timed), SetPrescription, exerciseIsTimed() (stretch, yoga and mobility groups, cardio machines, plank-like titles stay timed; everything else is rep based), default target reps by tier (beginner 12, intermediate 10, advanced 8).
- mobile/lib/features/workouts/widgets/set_timer_card.dart: "I am ready" button after the speech, rep-based work phase with "N reps at X kg" and a Done button, which writes reps and load to the existing capture providers so "Mark complete" and the V0 offline queue keep receiving them; no capture is written for a loaded move without a weight, so the weight question stays.
- mobile/lib/l10n/app_en.arb, app_ru.arb: new strings.
- Tests (test agent): four new files, TTS tests, and eight existing test files moved past the gate with confirmReady().

## Affected contracts and paths
No Firestore schema or programme builder change. Only the first completion of a set is queued, as before.

## Verification state
Test agent: 39 files run; all passed except app_shortcuts_test.dart (1 failure), which fails identically on a clean master. Not verified: a real TTS engine, localized_tts_voice_coach.dart, Russian reps-line wording, analyzer, a device; reps of a loaded move logged without a weight are not recorded.
