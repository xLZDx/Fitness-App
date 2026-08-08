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
import 'package:fitness_app/features/workouts/state/session_digest_providers.dart';
import 'package:fitness_app/features/workouts/state/session_screening_providers.dart';

/// R4.2 — the wiring between the arithmetic and the screen.
///
/// `session_digest_test.dart` pins the arithmetic itself. These pin the part
/// that can be wrong without it being wrong: which list is counted. The hero
/// must count the same rows the list under it renders, and it must keep
/// counting a session the screening flagged — the user still has it on their
/// calendar, and a hero that said "2 exercises" over a list of 3 would be a
/// worse lie than the single-exercise hero this replaces.

/// Every fixture carries a [videoUrl], and that is load-bearing rather than
/// decoration: `_allExercisesProvider` ends in `withDemonstration(...)`
/// (`equipment_providers.dart:185`), the clip-only rule, so an exercise with no
/// footage never reaches the catalog at all. A first draft of these fixtures
/// omitted it and the muscle assertions came back empty while every count was
/// right — the catalog was correctly empty, and the counts come from the
/// schedule, not from it.
const _row = ExerciseItem(
  id: 'row',
  title: 'Seated row',
  equipmentId: null,
  muscles: ['back'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/row.mp4',
);

const _curl = ExerciseItem(
  id: 'curl',
  title: 'Biceps curl',
  equipmentId: null,
  muscles: ['biceps'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/curl.mp4',
);

const _squat = ExerciseItem(
  id: 'squat',
  title: 'Back squat',
  equipmentId: null,
  muscles: ['quadriceps'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  videoUrl: 'https://example.test/squat.mp4',
  contraindications: ['knee'],
);

const _injured = UserProfile(
  uid: 'u1',
  health: HealthHistory(injuries: [Injury(bodyPart: 'knee', type: 'strain')]),
);

class _SilentNotifications implements NotificationService {
  @override
  Future<void> cancelReminder(String sessionId) async {}
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

void main() {
  late MockScheduledSessionRepository sessions;
  late DateTime morning;
  late DateTime evening;

  setUp(() {
    sessions = MockScheduledSessionRepository(latency: Duration.zero);
    final day = DateTime.now().add(const Duration(days: 2));
    morning = DateTime(day.year, day.month, day.day, 8);
    evening = DateTime(day.year, day.month, day.day, 19);
  });

  tearDown(() => sessions.dispose());

  ProviderContainer container({UserProfile? profile}) {
    final repo = AssetEquipmentRepository()
      ..seedForTests(
        equipment: const [],
        exercises: const [_row, _curl, _squat],
      );
    final c = ProviderContainer(overrides: [
      effectiveLanguageCodeProvider.overrideWithValue('en'),
      equipmentRepositoryProvider.overrideWithValue(repo),
      screeningProfileProvider.overrideWith((ref) async => profile),
      authUserProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(uid: 'u1', displayName: 'U')),
      ),
      scheduledSessionRepositoryProvider.overrideWithValue(sessions),
      notificationServiceProvider.overrideWithValue(_SilentNotifications()),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  ScheduledSession session(String id, String exerciseId, DateTime when,
          {int minutes = 30}) =>
      ScheduledSession(
        id: id,
        exerciseId: exerciseId,
        exerciseTitle: exerciseId,
        scheduledFor: when,
        durationMinutes: minutes,
        status: ScheduledSessionStatus.pending,
      );

  /// Both halves the digest reads resolve asynchronously, and it reads them
  /// through `valueOrNull` — so before they land the digest is legitimately
  /// empty and a test that read once would assert on the wrong frame. The app
  /// never sees that frame as a final answer: the digest recomputes and Home
  /// repaints when either half arrives. Waiting for BOTH is what reproduces
  /// the state the user actually looks at.
  ///
  /// The listener is opened first and kept so the digest and its dependencies
  /// stay alive across the awaits below rather than being rebuilt per `read`.
  Future<void> settle(ProviderContainer c) async {
    final sub = c.listen(todayDigestProvider, (_, __) {});
    addTearDown(sub.close);
    await c.read(scheduledSessionsProvider.future);
    await c.read(safeCatalogProvider.future);
    await c.read(screenedUpcomingSessionsProvider.future);
  }

  test('nothing scheduled leaves the digest empty, not zeroed', () async {
    final c = container();
    await settle(c);
    expect(c.read(todayDigestProvider).isEmpty, isTrue);
  });

  test('the day is summed from the screened list Home renders', () async {
    await sessions.save('u1', session('s1', 'row', morning, minutes: 12));
    await sessions.save('u1', session('s2', 'curl', evening, minutes: 8));
    final c = container();
    await settle(c);

    final digest = c.read(todayDigestProvider);
    expect(digest.exerciseCount, 2);
    expect(digest.totalMinutes, 20);
    expect(digest.muscles, containsAll(['back', 'biceps']));
  });

  test('a session flagged for injury is still part of the day', () async {
    // Flagged, not dropped (`session_screening_providers.dart`). The card
    // beneath the hero renders it struck through; the hero has to agree that
    // it exists.
    await sessions.save('u1', session('s1', 'row', morning, minutes: 12));
    await sessions.save('u1', session('s2', 'squat', morning, minutes: 30));
    final c = container(profile: _injured);
    await settle(c);

    final digest = c.read(todayDigestProvider);
    expect(digest.exerciseCount, 2);
    expect(digest.totalMinutes, 42);
  });

  test('an exercise the catalog screened out still counts', () async {
    // `safeCatalogProvider` removes contraindicated exercises, so the squat is
    // absent from the map the digest is given. It is still scheduled, so it
    // counts — the muscles are what goes unnamed, not the exercise.
    await sessions.save('u1', session('s2', 'squat', morning, minutes: 30));
    final c = container(profile: _injured);
    await settle(c);

    final digest = c.read(todayDigestProvider);
    expect(digest.exerciseCount, 1);
    expect(digest.totalMinutes, 30);
    expect(digest.muscles, isEmpty);
  });
}
