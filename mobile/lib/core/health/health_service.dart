import 'health_models.dart';

/// Cross-platform health-data service. Implementations:
///   - [MockHealthService]            — in-memory, used by tests + dev mode.
///   - HealthConnectHealthService     — Android / Health Connect.
///   - HealthKitHealthService         — iOS / HealthKit.
///
/// All methods are async and never throw on unsupported platforms; instead
/// `requestAuthorization` returns [HealthAuthStatus.unsupported] and the
/// reads return empty lists. Callers can branch on auth status rather than
/// catching platform exceptions.
abstract class HealthService {
  Future<HealthAuthStatus> currentAuthStatus();
  Future<HealthAuthStatus> requestAuthorization();

  /// Returns a snapshot per day in the requested window (most recent first).
  /// Empty list when permission has not been granted or no data exists.
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  });

  /// Convenience for the Today card on the Home page.
  Future<HealthSnapshot?> readTodaySnapshot();

  /// Best-effort write of a completed workout into the platform's
  /// activity history. Returns true on success, false on
  /// permission-denied or unsupported platform.
  Future<bool> writeWorkout(HealthWorkoutWrite workout);
}

/// In-memory mock used by tests and the default Provider binding. Seeds
/// with a believable 7-day stretch so the UI has data to render before
/// real platform permissions are wired.
class MockHealthService implements HealthService {
  MockHealthService({HealthAuthStatus initialStatus = HealthAuthStatus.granted})
      : _status = initialStatus;

  HealthAuthStatus _status;
  final List<HealthSnapshot> _snapshots = _seed();

  static List<HealthSnapshot> _seed() {
    final today = DateTime.now().toUtc();
    final base = DateTime.utc(today.year, today.month, today.day);
    return List.generate(7, (i) {
      final day = base.subtract(Duration(days: i));
      return HealthSnapshot(
        dateUtc: day,
        steps: 7000 + (i * 250) - (i.isEven ? 600 : 0),
        activeMinutes: 22 + (i % 3) * 5,
        restingHeartRateBpm: 58 + (i % 4),
        sleepScore: 78 - (i % 5) * 2,
        hrvMs: 52.0 + ((i.isEven ? -3 : 4)),
        activityRingPercent: 60 + (i * 4),
      );
    });
  }

  @override
  Future<HealthAuthStatus> currentAuthStatus() async => _status;

  @override
  Future<HealthAuthStatus> requestAuthorization() async {
    if (_status == HealthAuthStatus.unsupported) return _status;
    _status = HealthAuthStatus.granted;
    return _status;
  }

  @override
  Future<List<HealthSnapshot>> readSnapshots({
    required DateTime from,
    required DateTime to,
  }) async {
    if (_status != HealthAuthStatus.granted) return const [];
    final fromUtc = from.toUtc();
    final toUtc = to.toUtc();
    return _snapshots
        .where((s) =>
            !s.dateUtc.isBefore(fromUtc) && !s.dateUtc.isAfter(toUtc))
        .toList();
  }

  @override
  Future<HealthSnapshot?> readTodaySnapshot() async {
    if (_status != HealthAuthStatus.granted) return null;
    final today = DateTime.now().toUtc();
    return _snapshots.firstWhere(
      (s) =>
          s.dateUtc.year == today.year &&
          s.dateUtc.month == today.month &&
          s.dateUtc.day == today.day,
      orElse: () => _snapshots.first,
    );
  }

  @override
  Future<bool> writeWorkout(HealthWorkoutWrite workout) async {
    return _status == HealthAuthStatus.granted;
  }
}
