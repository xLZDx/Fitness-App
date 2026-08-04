import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session_repository.dart'
    show kScheduledSessionWindow;

ScheduledSession _s(String id, DateTime when, {String exId = 'pushup'}) {
  return ScheduledSession(
    id: id,
    exerciseId: exId,
    exerciseTitle: exId,
    scheduledFor: when,
    durationMinutes: 10,
  );
}

void main() {
  group('MockScheduledSessionRepository', () {
    late MockScheduledSessionRepository repo;

    setUp(() => repo =
        MockScheduledSessionRepository(latency: Duration.zero));
    tearDown(() => repo.dispose());

    test('save then watch returns the session, sorted by scheduledFor',
        () async {
      final later = _s('s_later', DateTime.utc(2026, 5, 10));
      final earlier = _s('s_earlier', DateTime.utc(2026, 5, 1));

      await repo.save('u', later);
      await repo.save('u', earlier);

      final list = await repo.watch('u').first;
      expect(list.map((s) => s.id), ['s_earlier', 's_later']);
    });

    test('save is idempotent on id', () async {
      final base = _s('s_1', DateTime.utc(2026, 5, 1));
      await repo.save('u', base);
      await repo.save('u', base.copyWith(durationMinutes: 99));

      final list = await repo.watch('u').first;
      expect(list, hasLength(1));
      expect(list.first.durationMinutes, 99);
    });

    test('watch is per-user', () async {
      await repo.save('alice', _s('s_a', DateTime.utc(2026, 5, 1)));
      await repo.save('bob', _s('s_b', DateTime.utc(2026, 5, 2)));

      expect((await repo.watch('alice').first).map((s) => s.id), ['s_a']);
      expect((await repo.watch('bob').first).map((s) => s.id), ['s_b']);
    });

    test('delete removes the session', () async {
      await repo.save('u', _s('s_1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _s('s_2', DateTime.utc(2026, 5, 2)));

      await repo.delete('u', 's_1');
      final list = await repo.watch('u').first;
      expect(list.map((s) => s.id), ['s_2']);
    });

    test('clear empties the schedule', () async {
      await repo.save('u', _s('s_1', DateTime.utc(2026, 5, 1)));
      await repo.save('u', _s('s_2', DateTime.utc(2026, 5, 2)));
      await repo.clear('u');
      expect(await repo.watch('u').first, isEmpty);
    });

    group('exportAll', () {
      // L0c. `watch()`/`cached()` cap at kScheduledSessionWindow (N2), by
      // design named `_sorted` despite being the windowed view. exportAll
      // must read the true, unwindowed store.
      test('returns more than the window when there is more than the window',
          () async {
        for (var i = 0; i < kScheduledSessionWindow + 5; i++) {
          await repo.save('u', _s('s_$i', DateTime.utc(2026, 1, 1 + i)));
        }
        final all = await repo.exportAll('u');
        expect(all, hasLength(kScheduledSessionWindow + 5));
      });

      test('sorted ascending by scheduledFor, same as watch', () async {
        await repo.save('u', _s('later', DateTime.utc(2026, 5, 10)));
        await repo.save('u', _s('earlier', DateTime.utc(2026, 5, 1)));
        final all = await repo.exportAll('u');
        expect(all.map((s) => s.id), ['earlier', 'later']);
      });
    });
  });
}
