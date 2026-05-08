import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/notifications/notification_providers.dart';
import '../../auth/state/auth_providers.dart';
import '../data/mock_scheduled_session_repository.dart';
import '../data/scheduled_session.dart';
import '../data/scheduled_session_repository.dart';

/// Persistence provider for scheduled sessions. Default is the in-memory
/// mock; `main.dart` overrides it with the Firestore-backed impl.
final scheduledSessionRepositoryProvider =
    Provider<ScheduledSessionRepository>((ref) {
  final repo = MockScheduledSessionRepository();
  ref.onDispose(() {
    if (repo is MockScheduledSessionRepository) repo.dispose();
  });
  return repo;
});

/// Live history of every scheduled session for the signed-in user, sorted
/// ascending by [ScheduledSession.scheduledFor].
final scheduledSessionsProvider =
    StreamProvider<List<ScheduledSession>>((ref) {
  final user = ref.watch(authUserProvider).valueOrNull;
  if (user == null) return Stream.value(const <ScheduledSession>[]);
  final repo = ref.watch(scheduledSessionRepositoryProvider);
  return repo.watch(user.uid);
});

/// Filters [scheduledSessionsProvider] down to upcoming pending sessions
/// in the next 14 days, sorted ascending. Used by the Home tab.
final upcomingSessionsProvider = Provider<List<ScheduledSession>>((ref) {
  final all = ref.watch(scheduledSessionsProvider).valueOrNull ?? const [];
  return filterUpcoming(all);
});

/// Pure helper exposed so the page widget logic stays trivially testable.
List<ScheduledSession> filterUpcoming(
  Iterable<ScheduledSession> sessions, {
  DateTime? now,
  Duration window = const Duration(days: 14),
}) {
  final t = now ?? DateTime.now();
  final cutoff = t.add(window);
  final out = sessions
      .where((s) =>
          s.status == ScheduledSessionStatus.pending &&
          !s.scheduledFor.isBefore(t) &&
          !s.scheduledFor.isAfter(cutoff))
      .toList();
  out.sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
  return List.unmodifiable(out);
}

/// Imperative controller for "Schedule" / "Cancel" actions. Surfaces an
/// AsyncValue so the UI can render loading / error.
final scheduleSessionActionProvider =
    NotifierProvider<ScheduleSessionAction, AsyncValue<void>>(
        ScheduleSessionAction.new);

class ScheduleSessionAction extends Notifier<AsyncValue<void>> {
  @override
  AsyncValue<void> build() => const AsyncValue.data(null);

  Future<void> schedule(ScheduledSession session) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot schedule a session while signed out');
      }
      final repo = ref.read(scheduledSessionRepositoryProvider);
      await repo.save(user.uid, session);
      // Notification scheduling is best-effort — surface the schedule
      // success even if the platform later refuses to deliver the alert.
      try {
        final notifications = ref.read(notificationServiceProvider);
        await notifications.scheduleReminder(session);
      } catch (_) {
        // Swallow — the user-visible save succeeded.
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }

  Future<void> cancel(String sessionId) async {
    state = const AsyncValue.loading();
    try {
      final user = ref.read(authUserProvider).valueOrNull;
      if (user == null) {
        throw StateError('Cannot cancel a session while signed out');
      }
      final repo = ref.read(scheduledSessionRepositoryProvider);
      await repo.delete(user.uid, sessionId);
      try {
        final notifications = ref.read(notificationServiceProvider);
        await notifications.cancelReminder(sessionId);
      } catch (_) {
        // Same best-effort treatment as above.
      }
      state = const AsyncValue.data(null);
    } catch (e, st) {
      state = AsyncValue.error(e, st);
    }
  }
}
