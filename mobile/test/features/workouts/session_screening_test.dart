import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/session_screening_providers.dart';

/// A scheduled session is a snapshot, and nothing re-examined it.
///
/// [ScheduledSession] carries an id, a title, a time and a duration and
/// nothing about the exercise itself; `filterUpcoming` screens on status and
/// date only. So the squat scheduled last week survived a knee injury logged
/// yesterday: it rendered on Home, it linked into the player, and its reminder
/// was still armed.

const _squat = ExerciseItem(
  id: 'squat',
  title: 'Back squat',
  equipmentId: 'rack',
  muscles: ['quads'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/squat.mp4',
  contraindications: ['knee'],
);

const _row = ExerciseItem(
  id: 'row',
  title: 'Seated row',
  equipmentId: 'rack',
  muscles: ['back'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/row.mp4',
);

const _rack = EquipmentItem(
  id: 'rack',
  name: 'Rack',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

const _injured = UserProfile(
  uid: 'u1',
  health: HealthHistory(injuries: [Injury(bodyPart: 'knee', type: 'strain')]),
);

class _RecordingNotifications implements NotificationService {
  final cancelled = <String>[];

  @override
  Future<void> cancelReminder(String sessionId) async =>
      cancelled.add(sessionId);

  @override
  Future<bool> init() async => true;

  @override
  Future<bool> ensurePermission() async => true;

  @override
  Future<void> cancelAll() async {}

  @override
  Future<void> scheduleReminder(
    ScheduledSession session, {
    required String title,
    required String body,
    Duration leadTime = const Duration(minutes: 30),
  }) async {}
}

ScheduledSession _session(String id, String exerciseId, DateTime when,
        {ScheduledSessionStatus status = ScheduledSessionStatus.pending}) =>
    ScheduledSession(
      id: id,
      exerciseId: exerciseId,
      exerciseTitle: exerciseId,
      scheduledFor: when,
      durationMinutes: 30,
      status: status,
    );

void main() {
  late MockScheduledSessionRepository sessions;
  late _RecordingNotifications notifications;
  late DateTime soon;

  setUp(() {
    sessions = MockScheduledSessionRepository(latency: Duration.zero);
    notifications = _RecordingNotifications();
    soon = DateTime.now().add(const Duration(days: 2));
  });

  tearDown(() => sessions.dispose());

  ProviderContainer container({UserProfile? profile = _injured}) {
    final repo = AssetEquipmentRepository()
      ..seedForTests(equipment: const [_rack], exercises: const [_squat, _row]);
    final c = ProviderContainer(overrides: [
      effectiveLanguageCodeProvider.overrideWithValue('en'),
      equipmentRepositoryProvider.overrideWithValue(repo),
      screeningProfileProvider.overrideWith((ref) async => profile),
      authUserProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
      ),
      scheduledSessionRepositoryProvider.overrideWithValue(sessions),
      notificationServiceProvider.overrideWithValue(notifications),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  /// Waits for the session stream's first emission before screening.
  ///
  /// `upcomingSessionsProvider` reads `scheduledSessionsProvider.valueOrNull`,
  /// so before the stream emits it is legitimately empty and the screened list
  /// resolves to empty with it. The app sees the same two frames; a test that
  /// read only the first would assert on the wrong one.
  Future<List<ScreenedSession>> screenedFrom(ProviderContainer c) async {
    final sub = c.listen(screenedUpcomingSessionsProvider, (_, __) {});
    addTearDown(sub.close);
    await c.read(scheduledSessionsProvider.future);
    return c.read(screenedUpcomingSessionsProvider.future);
  }

  group('upcoming sessions', () {
    test('a session that is now contraindicated is flagged', () async {
      await sessions.save('u1', _session('s1', 'squat', soon));
      final c = container();
      final screened = await screenedFrom(c);
      expect(screened.single.hiddenForInjury, isTrue);
    });

    test('and is flagged rather than deleted', () async {
      // The user put it on their own calendar. A session that vanishes reads
      // as a bug in the app; one that says why is a fact they can act on.
      await sessions.save('u1', _session('s1', 'squat', soon));
      final c = container();
      final screened = await screenedFrom(c);
      expect(screened.single.session.id, 's1');
    });

    test('an unaffected session is untouched', () async {
      await sessions.save('u1', _session('s2', 'row', soon));
      final c = container();
      final screened = await screenedFrom(c);
      expect(screened.single.hiddenForInjury, isFalse);
    });

    test('nothing is flagged for a user with no injuries', () async {
      await sessions.save('u1', _session('s1', 'squat', soon));
      final c = container(profile: null);
      final screened = await screenedFrom(c);
      expect(screened.single.hiddenForInjury, isFalse);
    });
  });

  group('reminders', () {
    test('the reminder for a now-contraindicated session is cancelled',
        () async {
      // A local notification fires from the OS with the app closed, so there
      // is no render pass to screen it. Cancelling before it fires is the only
      // mechanism there is.
      await sessions.save('u1', _session('s1', 'squat', soon));
      final c = container();
      final sub = c.listen(scheduledSessionsProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(scheduledSessionsProvider.future);

      final n = await c.read(sessionReminderReconcilerProvider).reconcile();

      expect(n, 1);
      expect(notifications.cancelled, ['s1']);
    });

    test('a safe session keeps its reminder', () async {
      await sessions.save('u1', _session('s2', 'row', soon));
      final c = container();
      final sub = c.listen(scheduledSessionsProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(scheduledSessionsProvider.future);

      await c.read(sessionReminderReconcilerProvider).reconcile();

      expect(notifications.cancelled, isEmpty);
    });

    test('a cancelled session is not touched again', () async {
      await sessions.save(
        'u1',
        _session('s3', 'squat', soon,
            status: ScheduledSessionStatus.cancelled),
      );
      final c = container();
      final sub = c.listen(scheduledSessionsProvider, (_, __) {});
      addTearDown(sub.close);
      await c.read(scheduledSessionsProvider.future);

      await c.read(sessionReminderReconcilerProvider).reconcile();

      expect(notifications.cancelled, isEmpty);
    });
  });
}
