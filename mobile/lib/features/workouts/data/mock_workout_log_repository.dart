import 'dart:async';

import 'workout_log.dart';
import 'workout_log_repository.dart';
import 'workout_log_totals.dart';

class MockWorkoutLogRepository implements WorkoutLogRepository {
  MockWorkoutLogRepository({Duration latency = const Duration(milliseconds: 80)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, List<WorkoutLogEntry>> _store = {};
  final Map<String, StreamController<List<WorkoutLogEntry>>> _ctrls = {};

  StreamController<List<WorkoutLogEntry>> _ctrl(String uid) {
    return _ctrls.putIfAbsent(
      uid,
      () => StreamController<List<WorkoutLogEntry>>.broadcast(),
    );
  }

  final Map<String, int> _records = {};

  List<WorkoutLogEntry> _sorted(String uid) {
    final list = _store[uid] ?? const [];
    final sorted = [...list]
      ..sort((a, b) => b.completedAt.compareTo(a.completedAt));
    return List.unmodifiable(sorted);
  }

  /// The same window the Firestore listener applies, so a test that exercises
  /// the mock exercises the production truncation too. A double that hands
  /// back more than the real thing is a double that hides the bug.
  List<WorkoutLogEntry> _window(String uid) {
    final all = _sorted(uid);
    if (all.length <= kWorkoutHistoryWindow) return all;
    return List.unmodifiable(all.take(kWorkoutHistoryWindow));
  }

  @override
  Stream<List<WorkoutLogEntry>> watch(String uid) {
    final ctrl = _ctrl(uid);
    late StreamController<List<WorkoutLogEntry>> replay;
    StreamSubscription<List<WorkoutLogEntry>>? sub;
    replay = StreamController<List<WorkoutLogEntry>>(
      onListen: () {
        replay.add(_window(uid));
        sub = ctrl.stream.listen(replay.add,
            onError: replay.addError, onDone: replay.close);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return replay.stream;
  }

  @override
  List<WorkoutLogEntry> cached(String uid) => _window(uid);

  @override
  Future<WorkoutLogTotals> totals(String uid) async {
    await Future<void>.delayed(_latency);
    return WorkoutLogTotals(
      // The whole store, not the window -- this is what the aggregation query
      // returns in production, and a mock that returned the window instead
      // would make the windowing bug invisible in every test that uses it.
      total: (_store[uid] ?? const []).length,
      longestStreakDays: _records[uid] ?? 0,
    );
  }

  @override
  Future<void> recordStreak(String uid, int days) async {
    await Future<void>.delayed(_latency);
    if (days > (_records[uid] ?? 0)) _records[uid] = days;
  }

  @override
  Future<void> save(String uid, WorkoutLogEntry entry) async {
    await Future<void>.delayed(_latency);
    final list = _store.putIfAbsent(uid, () => []);
    final i = list.indexWhere((e) => e.id == entry.id);
    if (i == -1) {
      list.add(entry);
    } else {
      list[i] = entry;
    }
    _ctrl(uid).add(_window(uid));
  }

  @override
  Future<void> delete(String uid, String entryId) async {
    await Future<void>.delayed(_latency);
    _store[uid]?.removeWhere((e) => e.id == entryId);
    _ctrl(uid).add(_window(uid));
  }

  @override
  Future<void> clear(String uid) async {
    await Future<void>.delayed(_latency);
    _store.remove(uid);
    _records.remove(uid);
    _ctrl(uid).add(const []);
  }

  void dispose() {
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
  }
}
