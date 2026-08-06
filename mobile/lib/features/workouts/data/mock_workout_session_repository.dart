import 'dart:async';

import 'workout_log_totals.dart';
import 'workout_session.dart';
import 'workout_session_repository.dart';

class MockWorkoutSessionRepository implements WorkoutSessionRepository {
  MockWorkoutSessionRepository(
      {Duration latency = const Duration(milliseconds: 80)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, List<WorkoutSession>> _store = {};
  final Map<String, StreamController<List<WorkoutSession>>> _ctrls = {};
  final Map<String, int> _records = {};

  StreamController<List<WorkoutSession>> _ctrl(String uid) {
    return _ctrls.putIfAbsent(
      uid,
      () => StreamController<List<WorkoutSession>>.broadcast(),
    );
  }

  List<WorkoutSession> _sorted(String uid) {
    final list = _store[uid] ?? const [];
    final sorted = [...list]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(sorted);
  }

  /// Same truncation the Firestore listener applies, per the
  /// `MockWorkoutLogRepository` convention this mirrors: a double that hands
  /// back more than the real thing is a double that hides the bug.
  List<WorkoutSession> _window(String uid) {
    final all = _sorted(uid);
    if (all.length <= kWorkoutSessionHistoryWindow) return all;
    return List.unmodifiable(all.take(kWorkoutSessionHistoryWindow));
  }

  @override
  Stream<List<WorkoutSession>> watch(String uid) {
    final ctrl = _ctrl(uid);
    late StreamController<List<WorkoutSession>> replay;
    StreamSubscription<List<WorkoutSession>>? sub;
    replay = StreamController<List<WorkoutSession>>(
      onListen: () {
        replay.add(_window(uid));
        sub = ctrl.stream
            .listen(replay.add, onError: replay.addError, onDone: replay.close);
      },
      onCancel: () async {
        await sub?.cancel();
      },
    );
    return replay.stream;
  }

  @override
  List<WorkoutSession> cached(String uid) => _window(uid);

  @override
  Future<WorkoutLogTotals> totals(String uid) async {
    await Future<void>.delayed(_latency);
    return WorkoutLogTotals(
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
  Future<void> save(String uid, WorkoutSession session) async {
    await Future<void>.delayed(_latency);
    final list = _store.putIfAbsent(uid, () => []);
    final i = list.indexWhere((s) => s.id == session.id);
    if (i == -1) {
      list.add(session);
    } else {
      list[i] = session;
    }
    _ctrl(uid).add(_window(uid));
  }

  @override
  Future<void> delete(String uid, String sessionId) async {
    await Future<void>.delayed(_latency);
    _store[uid]?.removeWhere((s) => s.id == sessionId);
    _ctrl(uid).add(_window(uid));
  }

  @override
  Future<List<WorkoutSession>> exportAll(String uid) async {
    return _sorted(uid);
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
