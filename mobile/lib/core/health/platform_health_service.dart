import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:health/health.dart' as h;

import 'health_models.dart';
import 'health_service.dart';

/// Real platform impl of [HealthService] backed by the `health` package
/// (which wraps Health Connect on Android and HealthKit on iOS — same
/// abstraction layer the v2 catch-up plan calls for).
///
/// Web / desktop / Android <8 / older iOS versions land on the
/// `unsupported` branch and degrade gracefully. The `health` package
/// itself catches platform errors; we just normalise into our enums.
class PlatformHealthService implements HealthService {
  PlatformHealthService();

  static const _readTypes = <h.HealthDataType>[
    h.HealthDataType.STEPS,
    h.HealthDataType.ACTIVE_ENERGY_BURNED,
    h.HealthDataType.RESTING_HEART_RATE,
    h.HealthDataType.SLEEP_ASLEEP,
    h.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
  ];

  static const _writeTypes = <h.HealthDataType>[
    h.HealthDataType.WORKOUT,
  ];

  bool get _isSupported {
    if (Platform.isAndroid || Platform.isIOS) return true;
    return false;
  }

  String? _lastError;

  @override
  String? get lastErrorMessage => _lastError;

  /// Records + logs a swallowed platform error so "does not work" is
  /// diagnosable instead of silently degrading to denied/notDetermined.
  void _recordError(String op, Object e) {
    _lastError = e.toString();
    debugPrint('PlatformHealthService.$op failed: $e');
  }

  @override
  Future<HealthAuthStatus> currentAuthStatus() async {
    if (!_isSupported) return HealthAuthStatus.unsupported;
    try {
      final has = await h.Health().hasPermissions(_readTypes) ?? false;
      return has
          ? HealthAuthStatus.granted
          : HealthAuthStatus.notDetermined;
    } catch (e) {
      _recordError('currentAuthStatus', e);
      return HealthAuthStatus.notDetermined;
    }
  }

  @override
  Future<HealthAuthStatus> requestAuthorization() async {
    if (!_isSupported) return HealthAuthStatus.unsupported;
    // Clear the previous failure: a clean user-denied is NOT an error
    // and must not surface a stale message on the sync card.
    _lastError = null;
    try {
      await h.Health().configure();
      final ok = await h.Health().requestAuthorization(
        [..._readTypes, ..._writeTypes],
      );
      return ok ? HealthAuthStatus.granted : HealthAuthStatus.denied;
    } catch (e) {
      _recordError('requestAuthorization', e);
      return HealthAuthStatus.denied;
    }
  }

  @override
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  }) async {
    if (!_isSupported) return const [];
    final granted = await currentAuthStatus();
    if (granted != HealthAuthStatus.granted) return const [];

    try {
      final raw = await h.Health().getHealthDataFromTypes(
        types: _readTypes,
        startTime: from,
        endTime: to,
      );
      // Group raw points into per-day buckets.
      final buckets = <String, _DayBucket>{};
      for (final p in raw) {
        final day = DateTime.utc(
          p.dateFrom.toUtc().year,
          p.dateFrom.toUtc().month,
          p.dateFrom.toUtc().day,
        );
        final key = day.toIso8601String();
        final bucket = buckets.putIfAbsent(key, () => _DayBucket(day: day));
        bucket.absorb(p);
      }
      final out = buckets.values.map((b) => b.toSnapshot()).toList();
      out.sort((a, b) => b.dateUtc.compareTo(a.dateUtc));
      return out;
    } catch (e) {
      _recordError('readSnapshots', e);
      return const [];
    }
  }

  @override
  Future<HealthSnapshot?> readTodaySnapshot() async {
    final now = DateTime.now();
    final start = DateTime(now.year, now.month, now.day);
    final end = start.add(const Duration(days: 1));
    final list = await readSnapshots(from: start, to: end);
    return list.isEmpty ? null : list.first;
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutWrite workout) async {
    if (!_isSupported) return false;
    final granted = await currentAuthStatus();
    if (granted != HealthAuthStatus.granted) return false;
    try {
      return await h.Health().writeWorkoutData(
        activityType: h.HealthWorkoutActivityType.OTHER,
        start: workout.startedAt,
        end: workout.startedAt
            .add(Duration(minutes: workout.durationMinutes)),
        totalEnergyBurned: workout.estimatedCalories,
      );
    } catch (e) {
      _recordError('writeWorkout', e);
      return false;
    }
  }
}

/// Internal helper that aggregates raw health data points into a single
/// per-day snapshot.
class _DayBucket {
  _DayBucket({required this.day});
  final DateTime day;

  int? steps;
  int? activeMinutes;
  double? hrvSum;
  int hrvCount = 0;
  int? restingHr;
  int? sleepScore;

  void absorb(h.HealthDataPoint p) {
    final v = p.value;
    if (v is! h.NumericHealthValue) return;
    final num n = v.numericValue;
    switch (p.type) {
      case h.HealthDataType.STEPS:
        steps = (steps ?? 0) + n.toInt();
        break;
      case h.HealthDataType.ACTIVE_ENERGY_BURNED:
        // Approximate "active minutes" from kcals (5 kcal/min baseline).
        activeMinutes = (activeMinutes ?? 0) + (n / 5).round();
        break;
      case h.HealthDataType.RESTING_HEART_RATE:
        restingHr = n.toInt();
        break;
      case h.HealthDataType.SLEEP_ASLEEP:
        // Translate minutes asleep into a rough 0–100 score
        // (480 min = 100, capped). Better than nothing.
        final mins = n.toInt();
        sleepScore = ((mins / 480) * 100).clamp(0, 100).round();
        break;
      case h.HealthDataType.HEART_RATE_VARIABILITY_SDNN:
        hrvSum = (hrvSum ?? 0) + n.toDouble();
        hrvCount += 1;
        break;
      default:
        break;
    }
  }

  HealthSnapshot toSnapshot() {
    return HealthSnapshot(
      dateUtc: day,
      steps: steps,
      activeMinutes: activeMinutes,
      restingHeartRateBpm: restingHr,
      sleepScore: sleepScore,
      hrvMs: (hrvSum != null && hrvCount > 0) ? hrvSum! / hrvCount : null,
      activityRingPercent: steps != null
          ? ((steps! / 10000) * 100).clamp(0, 100).round()
          : null,
    );
  }
}
