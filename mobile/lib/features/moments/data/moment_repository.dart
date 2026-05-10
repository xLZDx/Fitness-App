import 'dart:async';

import 'moment.dart';

/// Persistence boundary for "have we shown moment X yet?" + supporting
/// counters. Implementations: an in-memory mock for tests, and a
/// SharedPreferences-backed real impl for production.
abstract class MomentRepository {
  Future<bool> hasShown(MomentId id);
  Future<void> markShown(MomentId id);

  /// Total times the app has been opened (cold-start). Persisted across
  /// process restarts.
  Future<int> launchCount();
  Future<void> bumpLaunchCount();

  /// First time the app was opened on this device. Set on the first
  /// `bumpLaunchCount` and never overwritten.
  Future<DateTime?> firstLaunchAt();

  /// Times the user has actively used the injury-aware exercise filter.
  Future<int> injuryFilterUses();
  Future<void> bumpInjuryFilterUses();
}

class MockMomentRepository implements MomentRepository {
  MockMomentRepository({DateTime Function()? clock})
      : _now = clock ?? DateTime.now;

  final Set<MomentId> _shown = {};
  int _launchCount = 0;
  int _injuryFilterUses = 0;
  DateTime? _firstLaunchAt;
  final DateTime Function() _now;

  void seedFirstLaunchAt(DateTime t) => _firstLaunchAt = t;

  @override
  Future<bool> hasShown(MomentId id) async => _shown.contains(id);

  @override
  Future<void> markShown(MomentId id) async {
    _shown.add(id);
  }

  @override
  Future<int> launchCount() async => _launchCount;

  @override
  Future<void> bumpLaunchCount() async {
    _launchCount += 1;
    _firstLaunchAt ??= _now();
  }

  @override
  Future<DateTime?> firstLaunchAt() async => _firstLaunchAt;

  @override
  Future<int> injuryFilterUses() async => _injuryFilterUses;

  @override
  Future<void> bumpInjuryFilterUses() async {
    _injuryFilterUses += 1;
  }
}
