import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether a completed set is also committed to the local offline command
/// queue (V0 slice) and sent to the `submitWorkoutCommands` callable.
///
/// OFF by default: with the flag off the set-completion path is exactly the
/// legacy one (`LogSessionAction.log` -> `repo.save`). Enable it only for a
/// manual or emulator run:
///
///   flutter run --dart-define=WORKOUT_COMMAND_QUEUE=true
///
/// See `docs/v1/design/V0_APP_WIRING_2026-10-23.md`.
const bool kWorkoutCommandQueueEnabled =
    bool.fromEnvironment('WORKOUT_COMMAND_QUEUE', defaultValue: false);

/// The flag as a provider; tests override it.
final workoutCommandQueueEnabledProvider =
    Provider<bool>((ref) => kWorkoutCommandQueueEnabled);
