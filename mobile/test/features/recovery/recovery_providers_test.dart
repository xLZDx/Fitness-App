import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/recovery/state/recovery_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('acceptNext7Days halves duration of next 7 pending sessions',
      () async {
    final repo = MockScheduledSessionRepository();
    final container = ProviderContainer(overrides: [
      scheduledSessionRepositoryProvider.overrideWithValue(repo),
      authUserProvider.overrideWith(
        (ref) => Stream.value(
          const AuthUser(uid: 'me', displayName: 'Me'),
        ),
      ),
    ]);
    addTearDown(container.dispose);

    final now = DateTime.now();
    final inWindow = ScheduledSession(
      id: 's1',
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: now.add(const Duration(days: 2)),
      durationMinutes: 60,
    );
    final outWindow = ScheduledSession(
      id: 's2',
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: now.add(const Duration(days: 14)),
      durationMinutes: 60,
    );
    await repo.save('me', inWindow);
    await repo.save('me', outWindow);

    // Wait for the auth provider to actually emit so the action can
    // read a non-null current user.
    await container.read(authUserProvider.future);

    await container
        .read(deloadActionProvider.notifier)
        .acceptNext7Days(factor: 0.5);

    // Surface any silent error.
    final s = container.read(deloadActionProvider);
    if (s.hasError) {
      fail('deload action failed: ${s.error}');
    }

    final all = repo.cached('me');
    final updated =
        all.firstWhere((s) => s.id == 's1');
    expect(updated.durationMinutes, 30);

    final untouched = all.firstWhere((s) => s.id == 's2');
    expect(untouched.durationMinutes, 60,
        reason: 'sessions outside the 7-day window must be untouched');
  });
}
