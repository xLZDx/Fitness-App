import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/state/equipment_providers.dart';
import '../../profile/state/profile_providers.dart';
import '../../workouts/state/workout_session_providers.dart';
import '../data/suggestion_builder.dart';

/// Home's Suggestions section.
///
/// Built from real inputs: the injury-filtered, tier-sorted catalog
/// ([forYouExercisesProvider]), the intake profile, and the workout log. The
/// section used to be five hardcoded strings with an empty onTap.
final suggestionsProvider =
    FutureProvider<List<WorkoutSuggestion>>((ref) async {
  final candidates = await ref.watch(forYouExercisesProvider.future);
  final profile = ref.watch(currentProfileProvider).valueOrNull;
  // A log that has not loaded yet is treated as "no history", which only
  // costs a slightly less tailored first paint. F3.3 read-convergence:
  // sourced from workout_sessions, see progress_page.
  final logs = ref.watch(workoutSessionHistoryProvider);
  return buildSuggestions(
    candidates: candidates,
    profile: profile,
    recentLogs: logs,
  );
});
