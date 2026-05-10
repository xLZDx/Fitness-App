import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/health/health_models.dart';
import 'package:fitness_app/core/health/health_service.dart';

void main() {
  group('MockHealthService', () {
    test('granted by default and seeds 7 days', () async {
      final s = MockHealthService();
      expect(await s.currentAuthStatus(), HealthAuthStatus.granted);
      final today = DateTime.now();
      final past = today.subtract(const Duration(days: 7));
      final list = await s.readSnapshots(from: past, to: today);
      expect(list, isNotEmpty);
      expect(list.length, lessThanOrEqualTo(7));
    });

    test('returns empty when not granted', () async {
      final s = MockHealthService(initialStatus: HealthAuthStatus.denied);
      final list = await s.readSnapshots(
        from: DateTime.now().subtract(const Duration(days: 7)),
        to: DateTime.now(),
      );
      expect(list, isEmpty);
      expect(await s.readTodaySnapshot(), isNull);
    });

    test('requestAuthorization promotes to granted', () async {
      final s = MockHealthService(initialStatus: HealthAuthStatus.notDetermined);
      expect(await s.requestAuthorization(), HealthAuthStatus.granted);
    });

    test('writeWorkout returns true on granted', () async {
      final s = MockHealthService();
      final ok = await s.writeWorkout(HealthWorkoutWrite(
        id: 'w1',
        title: 'Test',
        startedAt: DateTime.now(),
        durationMinutes: 30,
      ));
      expect(ok, isTrue);
    });
  });
}
