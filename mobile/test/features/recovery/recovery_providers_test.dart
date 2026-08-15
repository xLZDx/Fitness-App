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

  /// The write is the thing that has to be idempotent.
  ///
  /// The old comment on `acceptNext7Days` claimed it was, on the grounds that
  /// it "just rescales the durations" — which is the reason it was not. The
  /// safeguard it named (the banner disappears once the verdict clears) lives
  /// in a widget and does not survive a retry after a partial failure, an
  /// offline replay, or the same account on a second device.
  test('accepting a deload twice does not halve the session twice', () async {
    final repo = MockScheduledSessionRepository();
    final container = ProviderContainer(overrides: [
      scheduledSessionRepositoryProvider.overrideWithValue(repo),
      authUserProvider.overrideWith(
        (ref) => Stream.value(const AuthUser(uid: 'me', displayName: 'Me')),
      ),
    ]);
    addTearDown(container.dispose);

    await repo.save(
      'me',
      ScheduledSession(
        id: 's1',
        exerciseId: 'squat',
        exerciseTitle: 'Squat',
        scheduledFor: DateTime.now().add(const Duration(days: 2)),
        durationMinutes: 60,
        notes: 'bring the belt',
      ),
    );
    await container.read(authUserProvider.future);

    final action = container.read(deloadActionProvider.notifier);
    await action.acceptNext7Days(factor: 0.5);
    await action.acceptNext7Days(factor: 0.5);
    await action.acceptNext7Days(factor: 0.5);

    final row = repo.cached('me').firstWhere((s) => s.id == 's1');
    expect(row.durationMinutes, 30,
        reason: 'three presses compounded to 60 -> 30 -> 15 -> 8');
    expect(row.deloadFactor, 0.5,
        reason: 'the row has to carry what was applied, or nothing can skip it');

    // The second half of the same defect: the write used to replace `notes`
    // with 'Auto-deload week'. Nothing reads that string; the user wrote the
    // one it overwrote.
    expect(row.notes, 'bring the belt');
  });

  test('a deload marker survives a round trip through storage', () {
    // Absence of the key is "never deloaded", so an existing row reads back
    // null and is eligible exactly once — no migration has to run.
    final json = ScheduledSession(
      id: 's1',
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: DateTime.utc(2026, 1, 1),
      durationMinutes: 30,
      deloadFactor: 0.5,
    ).toJson();
    expect(ScheduledSession.fromJson(json).deloadFactor, 0.5);

    final legacy = Map<String, dynamic>.from(json)..remove('deloadFactor');
    expect(ScheduledSession.fromJson(legacy).deloadFactor, isNull);
  });
}
