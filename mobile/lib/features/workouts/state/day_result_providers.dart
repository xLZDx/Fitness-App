import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../data/day_result.dart';
import '../data/workout_session.dart';
import 'workout_session_providers.dart';

/// The day being summarised, so the screen does not change under the user at
/// midnight and tests do not depend on when they run.
///
/// Overridden in tests; in the app it is simply today. A `Provider` rather
/// than a `DateTime.now()` inside [todayResultProvider] because a summary that
/// silently became yesterday's while open would be the kind of defect nobody
/// reproduces on purpose.
final summaryDayProvider = Provider<DateTime>((ref) => DateTime.now());

/// Everything the user completed today.
///
/// Same construction as `todayDigestProvider`: the catalogue map is built here
/// so Riverpod rebuilds it only when the catalogue changes, not on every frame
/// the summary repaints.
final todayResultProvider = Provider<DayResult>((ref) {
  final sessions = ref.watch(workoutSessionsProvider).valueOrNull ??
      const <WorkoutSession>[];
  final catalog =
      ref.watch(safeCatalogProvider).valueOrNull ?? const <ExerciseItem>[];

  return resultForDay(
    sessions,
    {for (final e in catalog) e.id: e},
    ref.watch(summaryDayProvider),
  );
});
