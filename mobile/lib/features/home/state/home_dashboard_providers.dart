import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../equipment/data/equipment_models.dart';
import '../../equipment/state/equipment_providers.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/state/scheduled_session_providers.dart';
import '../../workouts/state/workout_session_providers.dart';
import '../data/home_dashboard.dart';

/// Riverpod wiring for the R11a Home rebuild.
///
/// Each provider is a thin adapter over the pure functions in
/// `home_dashboard.dart` — the arithmetic is tested there without a Flutter
/// binding, and these exist so the widget watches a value rather than
/// recomputing over the whole history on every repaint.
///
/// All of them read the same two streams Home already watched before R11a
/// (`workoutSessionHistoryProvider`, `scheduledSessionsProvider`), so the
/// rebuild added no new reads to the screen.

/// Muscle-recovery strip rows, most-recently-trained first.
///
/// Empty until the catalogue resolves: recovery is derived by looking each
/// logged exercise up in it, so an unresolved catalogue means "not known yet",
/// which the strip renders as absent rather than as everything being ready.
final muscleRecoveryProvider = Provider<List<MuscleRecovery>>((ref) {
  final logs = ref.watch(workoutSessionHistoryProvider);
  final catalog =
      ref.watch(safeCatalogProvider).valueOrNull ?? const <ExerciseItem>[];
  if (catalog.isEmpty) return const [];
  return deriveRecovery(
    logs,
    {for (final e in catalog) e.id: e},
  );
});

/// Seven Monday-first cells for the current week.
final weekStripProvider = Provider<List<WeekDayCell>>((ref) {
  final logs = ref.watch(workoutSessionHistoryProvider);
  final scheduled =
      ref.watch(scheduledSessionsProvider).valueOrNull ??
          const <ScheduledSession>[];
  return deriveWeekStrip(logs, scheduled);
});

/// Workouts / volume / records for the current week.
final weekTotalsProvider = Provider<WeekTotals>((ref) {
  return deriveWeekTotals(ref.watch(workoutSessionHistoryProvider));
});

/// This week's schedule completion, for the header bar.
final planProgressProvider = Provider<PlanProgress>((ref) {
  final scheduled =
      ref.watch(scheduledSessionsProvider).valueOrNull ??
          const <ScheduledSession>[];
  return derivePlanProgress(scheduled);
});
