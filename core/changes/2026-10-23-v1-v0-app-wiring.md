# Change record: wire the V0 offline queue into set completion (2026-10-23)

Base: master 7b557f68. The V0 slice, the SQLite store and the deployed callable exist but nothing in the app used them. This change connects "Mark complete" to the durable queue behind a local flag that is OFF by default.

## What changed
- mobile/lib/core/config/workout_queue_flag.dart: compile-time flag WORKOUT_COMMAND_QUEUE (default false) and an overridable provider.
- mobile/lib/features/workouts/offline/app_wiring.dart: queue binding provider (store, acceptor, sender, 15 s retry), field mapping from the UI set to a MarkComplete command, device install id, per-session writer token, collision-safe id sanitising (queueSafeId: valid ids unchanged; empty, reserved, bad or too long ids become a prefix plus a hash of the raw value).
- mobile/lib/features/workouts/state/workout_session_providers.dart: log() accepts the set into the durable queue first; on failure the legacy save and the rest timer are skipped and the error is shown.
- mobile/lib/features/equipment/workout_player_page.dart: sync status chip; l10n strings in app_en.arb and app_ru.arb; mobile/lib/main.dart watches the binding.
- docs/v1/design/V0_APP_WIRING_2026-10-23.md: flag, behaviour, field mapping, known gaps, test scenario.
- Tests (test agent): app_wiring_test.dart, log_session_queue_test.dart, workout_player_queue_test.dart.

## Affected contracts and paths
With the flag off the app behaves as before. With the flag on, the server also needs WORKOUT_COMMANDS_ENABLED=true and a migration policy document in SERVER_ONLY or SEALED; neither is touched here (operator-only live changes).

## Verification state
Test agent ran only its own three files: 80 passed, 0 failed. Not run: other mobile tests, analyzer, CI, a real callable send, a device. No GPT review (operator ended review rounds).
