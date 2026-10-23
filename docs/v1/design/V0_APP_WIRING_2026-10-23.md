# V0 app wiring (2026-10-23)

Status: wired behind a local flag, OFF by default. Test agent: 80 wiring tests passed (app_wiring, log_session_queue, workout_player_queue). Not verified: a real callable send, the real 15 s timer, a device.

## Flag
`mobile/lib/core/config/workout_queue_flag.dart`: `bool.fromEnvironment('WORKOUT_COMMAND_QUEUE', defaultValue: false)` plus `workoutCommandQueueEnabledProvider` (override in tests).

    flutter run --dart-define=WORKOUT_COMMAND_QUEUE=true

The server callable additionally needs `WORKOUT_COMMANDS_ENABLED=true` (apply.ts `workoutCommandsEnabled`) and a migration policy document in state `SERVER_ONLY` or `SEALED` (apply.ts `policyGate`); otherwise every command is answered with a hold code and stays pending.

Flag off: no provider of the queue is built, `LogSessionAction.log` receives `queued: null`, the player page returns the original widget. Behaviour is unchanged.

## What happens with the flag on
1. `workoutQueueBindingProvider` (watched in `FitnessApp.build`) opens the SQLite store for the signed-in uid, builds acceptor and sender, starts a 15 s retry timer (the sender's own per-session backoff limits real sends). Sign-out or account change disposes the store; no data is deleted.
2. Tap on "Mark complete": `log(entry, queued: ...)` first calls `CompleteSetAcceptor.accept` (durable local commit). If that throws (no account, queue not open, cap, store error) the existing error snackbar is shown, `repo.save` is not called, and no rest timer starts.
3. After acceptance the legacy `repo.save` still runs (history, streak and totals read `workout_sessions`; V0 has no server projection into it, see apply.ts header). Snackbar, rest timer and difficulty sheet continue as before. The difficulty re-log does not enqueue a second command.
4. A chip under the button shows "Saved on this device, waiting to sync" / "Synced" / "Could not sync..." from the session status.

## Field mapping
- sessionId: UI session id (`day_<dayId>` or `<micros>_<key>`), non `[A-Za-z0-9_-]` characters replaced by `_`, max 128.
- exerciseId: `exercise.id`, same sanitising.
- setIndex / setId: always 1 / `set_0001` (the UI logs one set per exercise per session).
- intentKey: `markComplete:<sessionId>:<exerciseId>:1`, so a repeat tap creates nothing new.
- sessionGeneration 1, acceptedEpoch 0, dependsOn empty, mode APPEND, source `app`.
- sessionInit (on every command of a session): titleKey `default` or `day:<dayId>`, dayId, startedAtClientMs = session start.
- actualReps = captured reps, actualRepsConfirmed = reps != null, targetReps null, loadGrams = round(kg * 1000) or null, performedConfirmed true, performedAtClientMs = tap time.
- originDeviceInstallId / envelope deviceInstallId: random id `i<22 chars>` in shared preferences (`workout_queue_install_id_v1`).
- writer proof: random 32 byte base64url token per (uid, session) in secure storage, created on first read. apply.ts step 6a lets the first proof claim a session without a token hash, so no takeover is needed for the first command; the sender reads it at send time.
- clientBuild: `--dart-define=APP_VERSION`, default `dev`.
- Transport: callable `submitWorkoutCommands` (europe-west1), one item per call.

## Known gaps
- No server projection into `workout_sessions`: the legacy save remains the source for history and streak, so the set is written twice (legacy doc and typed session).
- Re-editing an already logged set (second tap with a changed weight) is not synced; only the first completion is a command.
- Rating (difficulty) is not part of V0 and is not sent.
- If secure storage is wiped while the queue file survives, the server answers NOT_WRITER for that session (no takeover exists).
- No connectivity stream dependency was added; resume/app-start and the 15 s timer drive retries.
- Offline, `repo.save` still waits for its own 4 s timeout.

## Scenario: 20 minutes offline, 15 sets, 0 lost, 0 duplicated
Prepare: emulator with Auth + Firestore + Functions, `WORKOUT_COMMANDS_ENABLED=true`, policy doc `SERVER_ONLY`; run the app with the define above and sign in.
1. Start a day workout, complete one set online. Chip goes to "Saved on this device..." then "Synced". Firestore: `users/{uid}/workout_command_receipts/{operationId}` (COMMITTED) and `users/{uid}/workout_typed_sessions/{sessionId}` with the set under `exercises.<id>.sets.1`.
2. Turn the network off (airplane mode). Complete 15 sets across exercises for about 20 minutes (the day's exercises, re-entering the player as needed). Each tap shows success at once, chip stays "waiting to sync". Force-stop and reopen the app once: chips still show waiting.
3. Turn the network on, wait up to about 30 s (backoff) or bring the app to the foreground. Chips go to "Synced".
4. Check the server: exactly 15 (plus the one from step 1 if separate) receipts, each operationId once; `resolvedOps` of the typed session equals the number of sets; no `DUPLICATE_LOGICAL_SET`. Taps repeated on the same exercise add no receipt.
5. Pass criteria: receipts == sets tapped, no duplicates, no pending left in the chip.
