import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';

ScheduledSession _row(
  String id, {
  required DateTime scheduledFor,
  String? programmeId,
  ScheduledSessionStatus status = ScheduledSessionStatus.pending,
}) =>
    ScheduledSession(
      id: id,
      exerciseId: 'squat',
      exerciseTitle: 'Squat',
      scheduledFor: scheduledFor,
      durationMinutes: 30,
      programmeId: programmeId,
      status: status,
    );

void main() {
  group('nextProgrammeSlot', () {
    test('is tomorrow when the programme has no rows yet', () {
      final now = DateTime(2026, 1, 1);
      final slot = nextProgrammeSlot('p1', const [], now: now);
      expect(slot, DateTime(2026, 1, 2));
    });

    test('is the day after the latest pending row for this programme', () {
      final now = DateTime(2026, 1, 1);
      final existing = [
        _row('a', scheduledFor: DateTime(2026, 1, 5), programmeId: 'p1'),
        _row('b', scheduledFor: DateTime(2026, 1, 3), programmeId: 'p1'),
      ];
      expect(nextProgrammeSlot('p1', existing, now: now), DateTime(2026, 1, 6));
    });

    test('ignores rows belonging to a different programme', () {
      final now = DateTime(2026, 1, 1);
      final existing = [
        _row('a', scheduledFor: DateTime(2026, 3, 1), programmeId: 'other'),
      ];
      expect(nextProgrammeSlot('p1', existing, now: now), DateTime(2026, 1, 2));
    });

    test('ignores completed and cancelled rows, only pending pushes the date',
        () {
      final now = DateTime(2026, 1, 1);
      final existing = [
        _row('a', scheduledFor: DateTime(2026, 6, 1), programmeId: 'p1',
            status: ScheduledSessionStatus.completed),
        _row('b', scheduledFor: DateTime(2026, 6, 2), programmeId: 'p1',
            status: ScheduledSessionStatus.cancelled),
      ];
      expect(nextProgrammeSlot('p1', existing, now: now), DateTime(2026, 1, 2));
    });

    test('never lands in the past when the latest row is already behind now',
        () {
      final now = DateTime(2026, 6, 1);
      final existing = [
        _row('a', scheduledFor: DateTime(2026, 1, 1), programmeId: 'p1'),
      ];
      expect(nextProgrammeSlot('p1', existing, now: now), DateTime(2026, 6, 2));
    });
  });

  group('programmesProvider auth-restore window (MVP-1)', () {
    test('stays loading during the restore window, never a false empty list',
        () async {
      final auth = StreamController<AuthUser?>.broadcast();
      addTearDown(auth.close);
      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
      ]);
      addTearDown(container.dispose);

      final sub = container.listen(programmesProvider, (_, __) {});
      addTearDown(sub.close);
      await Future<void>.delayed(Duration.zero);

      final duringRestore = container.read(programmesProvider);
      expect(duringRestore.isLoading, isTrue,
          reason: 'a still-resolving auth stream must not be reported as '
              'signed-out (no programmes)');

      auth.add(null);
      await Future<void>.delayed(Duration.zero);
      expect(container.read(programmesProvider).valueOrNull, isEmpty);
    });
  });
}
