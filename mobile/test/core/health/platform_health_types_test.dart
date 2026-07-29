import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart' as h;

import 'package:fitness_app/core/health/platform_health_service.dart';

/// Builds a data point the way the plugin would.
///
/// [span] matters for sleep: HealthDataPoint's constructor OVERWRITES the value
/// of every SLEEP_* type with `dateTo - dateFrom` in minutes
/// (health_data_point.dart:81,91), ignoring whatever value is passed. Reading
/// numericValue for sleep is therefore correct in production — but a fixture
/// with a zero-length span measures a zero-minute night.
h.HealthDataPoint point(
  h.HealthDataType type,
  num value,
  DateTime when, {
  Duration span = Duration.zero,
}) {
  return h.HealthDataPoint(
    uuid: '$type-$value',
    value: h.NumericHealthValue(numericValue: value),
    type: type,
    unit: h.HealthDataUnit.NO_UNIT,
    dateFrom: when,
    dateTo: when.add(span),
    sourcePlatform: h.HealthPlatformType.googleHealthConnect,
    sourceDeviceId: 'dev',
    sourceId: 'src',
    sourceName: 'test',
  );
}

void main() {
  // The bug: Health Connect could never be granted. `_readTypes` asked for
  // HEART_RATE_VARIABILITY_SDNN, which exists only on Apple Health. The Android
  // plugin builds its permission list with `mapToType[typeKey]!!`
  // (HealthPlugin.kt), a non-null assertion with no SDNN entry — so the whole
  // request threw and the caller reported a flat "denied". One wrong enum, all
  // six permissions dead.
  group('requested types match what the platform actually declares', () {
    test('every Android read type is in the plugin Android list', () {
      final requested = healthReadTypes(android: true);
      final unsupported =
          requested.where((t) => !h.dataTypeKeysAndroid.contains(t)).toList();
      expect(unsupported, isEmpty,
          reason: 'an Android-unsupported type kills the ENTIRE permission '
              'request, it is not skipped');
    });

    test('every iOS read type is in the plugin iOS list', () {
      final requested = healthReadTypes(android: false);
      final unsupported =
          requested.where((t) => !h.dataTypeKeysIOS.contains(t)).toList();
      expect(unsupported, isEmpty);
    });

    test('write types are supported on both platforms', () {
      for (final t in healthWriteTypes) {
        expect(h.dataTypeKeysAndroid, contains(t));
        expect(h.dataTypeKeysIOS, contains(t));
      }
    });

    test('Android asks for RMSSD and never SDNN', () {
      final android = healthReadTypes(android: true);
      expect(android, contains(h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD));
      expect(android,
          isNot(contains(h.HealthDataType.HEART_RATE_VARIABILITY_SDNN)));
    });

    test('iOS asks for SDNN and never RMSSD', () {
      final ios = healthReadTypes(android: false);
      expect(ios, contains(h.HealthDataType.HEART_RATE_VARIABILITY_SDNN));
      expect(ios,
          isNot(contains(h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD)));
    });

    test('both platforms request the same metric count', () {
      expect(healthReadTypes(android: true),
          hasLength(healthReadTypes(android: false).length));
    });
  });

  group('supportedTypesOnly', () {
    test('drops what the platform does not declare', () {
      final out = supportedTypesOnly(
        [
          h.HealthDataType.STEPS,
          h.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
        ],
        (t) => t != h.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
      );
      expect(out, [h.HealthDataType.STEPS]);
    });

    test('keeps everything when all types are available', () {
      final requested = healthReadTypes(android: true);
      expect(supportedTypesOnly(requested, (_) => true), requested);
    });

    test('an all-unsupported platform yields an empty request', () {
      expect(supportedTypesOnly(healthReadTypes(android: true), (_) => false),
          isEmpty);
    });
  });

  group('HealthDayBucket', () {
    final when = DateTime.utc(2026, 7, 30, 9);

    // Second half of the same bug: even once the permission was granted, the
    // aggregator only recognised SDNN, so every Android HRV reading was
    // dropped and hrvMs stayed null forever.
    test('absorbs RMSSD readings into hrvMs', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD, 44, when))
        ..absorb(point(h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD, 46, when));
      expect(b.toSnapshot().hrvMs, 45.0);
    });

    test('absorbs SDNN readings into the same field', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.HEART_RATE_VARIABILITY_SDNN, 50, when));
      expect(b.toSnapshot().hrvMs, 50.0);
    });

    test('sums steps and derives the activity ring', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.STEPS, 3000, when))
        ..absorb(point(h.HealthDataType.STEPS, 2000, when));
      final s = b.toSnapshot();
      expect(s.steps, 5000);
      expect(s.activityRingPercent, 50);
    });

    test('caps the activity ring at 100', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.STEPS, 25000, when));
      expect(b.toSnapshot().activityRingPercent, 100);
    });

    test('converts sleep minutes into a score', () {
      // 4 h of the 8 h reference = 50.
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.SLEEP_ASLEEP, 0, when,
            span: const Duration(hours: 4)));
      expect(b.toSnapshot().sleepScore, 50);
    });

    test('caps the sleep score at 100 for a long night', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.SLEEP_ASLEEP, 0, when,
            span: const Duration(hours: 11)));
      expect(b.toSnapshot().sleepScore, 100);
    });

    test('leaves untouched metrics null rather than zero', () {
      final b = HealthDayBucket(day: when)
        ..absorb(point(h.HealthDataType.STEPS, 100, when));
      final s = b.toSnapshot();
      expect(s.hrvMs, isNull);
      expect(s.restingHeartRateBpm, isNull);
      expect(s.sleepScore, isNull);
    });

    test('ignores non-numeric values instead of throwing', () {
      final b = HealthDayBucket(day: when)
        ..absorb(
          h.HealthDataPoint(
            uuid: 'workout',
            value: h.WorkoutHealthValue(
              workoutActivityType: h.HealthWorkoutActivityType.OTHER,
            ),
            type: h.HealthDataType.WORKOUT,
            unit: h.HealthDataUnit.NO_UNIT,
            dateFrom: when,
            dateTo: when,
            sourcePlatform: h.HealthPlatformType.googleHealthConnect,
            sourceDeviceId: 'dev',
            sourceId: 'src',
            sourceName: 'test',
          ),
        );
      expect(b.toSnapshot().steps, isNull);
    });
  });
}
