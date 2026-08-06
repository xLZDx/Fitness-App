import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/state/auth_providers.dart';
import '../../workouts/data/scheduled_session.dart';
import '../../workouts/state/scheduled_session_providers.dart';
import '../../workouts/state/workout_session_providers.dart';
import '../data/deload_detector.dart';

/// Live deload verdict computed from logs + scheduled sessions in the
/// last 14 days. HRV inputs are omitted until C1 (Health Connect)
/// surfaces them.
final deloadVerdictProvider = Provider<DeloadVerdict>((ref) {
  // F3.3 read-convergence: sourced from workout_sessions, see progress_page.
  final logs = ref.watch(workoutSessionHistoryProvider);
  final sessions =
      ref.watch(scheduledSessionsProvider).valueOrNull ?? const [];
  final cutoff = DateTime.now().subtract(const Duration(days: 14));
  final recentSessions =
      sessions.where((s) => s.scheduledFor.isAfter(cutoff)).toList();
  return detectDeload(
    recentLogs: logs,
    scheduledLast14Days: recentSessions,
  );
});

/// Imperative controller for "accept deload" — halves the next 7 days
/// of pending sessions' duration in place. Idempotent on reload because
/// the action just rescales the durations; pressing twice in 7 days
/// would shrink them again, which the UI prevents by hiding the action
/// once the verdict clears (no longer two-of-three signals firing).
final deloadActionProvider =
    NotifierProvider<DeloadAction, AsyncValue<void>>(DeloadAction.new);

class DeloadAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> acceptNext7Days({double factor = 0.5}) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot accept deload while signed out');
      }
      final repo = ref.read(scheduledSessionRepositoryProvider);
      final all = repo.cached(user.uid);
      final now = DateTime.now();
      final cutoff = now.add(const Duration(days: 7));
      for (final s in all) {
        if (s.status != ScheduledSessionStatus.pending) continue;
        if (s.scheduledFor.isBefore(now)) continue;
        if (s.scheduledFor.isAfter(cutoff)) continue;
        final scaled = (s.durationMinutes * factor).round().clamp(5, 240);
        await repo.save(
          user.uid,
          s.copyWith(durationMinutes: scaled, notes: 'Auto-deload week'),
        );
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
