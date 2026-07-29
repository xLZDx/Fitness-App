import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:health/health.dart' as h;

import 'health_models.dart';
import 'health_service.dart';

/// The metrics we read, chosen per platform.
///
/// HRV is deliberately branched: `HEART_RATE_VARIABILITY_SDNN` exists only in
/// Apple Health (`dataTypeKeysIOS`) and `HEART_RATE_VARIABILITY_RMSSD` only in
/// Health Connect (`dataTypeKeysAndroid`). Sending the wrong one is not
/// ignored — the Android plugin resolves the permission list with
/// `mapToType[typeKey]!!` (HealthPlugin.kt), a non-null assertion, so a single
/// unmapped name throws and takes the ENTIRE authorization request down with
/// it. That one wrong enum is why Health Connect could never be granted.
@visibleForTesting
List<h.HealthDataType> healthReadTypes({required bool android}) => [
      h.HealthDataType.STEPS,
      h.HealthDataType.ACTIVE_ENERGY_BURNED,
      h.HealthDataType.RESTING_HEART_RATE,
      h.HealthDataType.SLEEP_ASLEEP,
      android
          ? h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD
          : h.HealthDataType.HEART_RATE_VARIABILITY_SDNN,
    ];

@visibleForTesting
const List<h.HealthDataType> healthWriteTypes = [h.HealthDataType.WORKOUT];

/// Structural guard: never hand the platform a type it does not declare.
///
/// The per-platform lists above are the intent; this is the safety net that
/// makes a future mistake degrade (one metric missing) instead of detonate
/// (no permissions at all). Both layers are wanted — the branch documents what
/// we mean, the filter makes it survivable.
@visibleForTesting
List<h.HealthDataType> supportedTypesOnly(
  Iterable<h.HealthDataType> requested,
  bool Function(h.HealthDataType) isAvailable,
) =>
    requested.where(isAvailable).toList(growable: false);

/// Real platform impl of [HealthService] backed by the `health` package
/// (Health Connect on Android, HealthKit on iOS).
///
/// Web / desktop land on the `unsupported` branch and degrade gracefully.
class PlatformHealthService implements HealthService {
  PlatformHealthService();

  bool get _isSupported => Platform.isAndroid || Platform.isIOS;

  String? _lastError;
  bool _configured = false;
  List<h.HealthDataType>? _readTypesCache;

  @override
  String? get lastErrorMessage => _lastError;

  /// `configure()` is documented as required before any other plugin call
  /// (health_plugin.dart:65). It used to run only inside
  /// requestAuthorization, so a cold `currentAuthStatus` — which is what the
  /// Home card calls first — went through unconfigured.
  Future<void> _ensureConfigured() async {
    if (_configured) return;
    await h.Health().configure();
    _configured = true;
  }

  List<h.HealthDataType> get _readTypes => _readTypesCache ??= supportedTypesOnly(
        healthReadTypes(android: Platform.isAndroid),
        h.Health().isDataTypeAvailable,
      );

  List<h.HealthDataType> get _writeTypes => supportedTypesOnly(
        healthWriteTypes,
        h.Health().isDataTypeAvailable,
      );

  /// Records + logs a swallowed platform error so "does not work" is
  /// diagnosable instead of silently degrading to denied/notDetermined.
  void _recordError(String op, Object e) {
    _lastError = e.toString();
    debugPrint('PlatformHealthService.$op failed: $e');
  }

  /// On Android the whole API is unusable unless the Health Connect provider
  /// is present and current. Returning [HealthAuthStatus.unsupported] with a
  /// message beats reporting "denied" for something the user never refused.
  Future<HealthAuthStatus?> _providerBlocker() async {
    if (!Platform.isAndroid) return null;
    final status = await h.Health().getHealthConnectSdkStatus();
    switch (status) {
      case h.HealthConnectSdkStatus.sdkAvailable:
        return null;
      case h.HealthConnectSdkStatus.sdkUnavailableProviderUpdateRequired:
        _lastError = 'Health Connect needs an update before it can share data.';
        return HealthAuthStatus.unsupported;
      case h.HealthConnectSdkStatus.sdkUnavailable:
      case null:
        _lastError = 'Health Connect is not available on this device. '
            'Install it, then connect again.';
        return HealthAuthStatus.unsupported;
    }
  }

  @override
  Future<bool> platformSetupRequired() async {
    if (!Platform.isAndroid) return false;
    try {
      await _ensureConfigured();
      final status = await h.Health().getHealthConnectSdkStatus();
      return status != h.HealthConnectSdkStatus.sdkAvailable;
    } catch (e) {
      _recordError('platformSetupRequired', e);
      return false;
    }
  }

  @override
  Future<void> openPlatformSetup() async {
    if (!Platform.isAndroid) return;
    try {
      await h.Health().installHealthConnect();
    } catch (e) {
      _recordError('openPlatformSetup', e);
    }
  }

  @override
  Future<HealthAuthStatus> currentAuthStatus() async {
    if (!_isSupported) return HealthAuthStatus.unsupported;
    try {
      await _ensureConfigured();
      final blocked = await _providerBlocker();
      if (blocked != null) return blocked;
      final has = await h.Health().hasPermissions(_readTypes) ?? false;
      return has ? HealthAuthStatus.granted : HealthAuthStatus.notDetermined;
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
      await _ensureConfigured();
      final blocked = await _providerBlocker();
      if (blocked != null) return blocked;
      final requested = [..._readTypes, ..._writeTypes];
      if (requested.isEmpty) {
        _lastError = 'No health metrics are readable on this platform.';
        return HealthAuthStatus.unsupported;
      }
      final ok = await h.Health().requestAuthorization(requested);
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
      final buckets = <String, HealthDayBucket>{};
      for (final p in raw) {
        final day = DateTime.utc(
          p.dateFrom.toUtc().year,
          p.dateFrom.toUtc().month,
          p.dateFrom.toUtc().day,
        );
        final key = day.toIso8601String();
        final bucket = buckets.putIfAbsent(key, () => HealthDayBucket(day: day));
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

/// Aggregates raw health data points into a single per-day snapshot.
///
/// Public (rather than private) purely so the suite can execute it: reaching it
/// through [PlatformHealthService.readSnapshots] would need a live platform,
/// and an untestable aggregator is how the HRV field silently stayed null.
@visibleForTesting
class HealthDayBucket {
  HealthDayBucket({required this.day});
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
        // Translate minutes asleep into a rough 0-100 score
        // (480 min = 100, capped). Better than nothing.
        final mins = n.toInt();
        sleepScore = ((mins / 480) * 100).clamp(0, 100).round();
        break;
      // Both HRV flavours land in the same field: the request asks for
      // whichever one the platform supports, so a bucket that handled only
      // SDNN dropped every Android reading on the floor even once the
      // permission was granted.
      case h.HealthDataType.HEART_RATE_VARIABILITY_SDNN:
      case h.HealthDataType.HEART_RATE_VARIABILITY_RMSSD:
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
