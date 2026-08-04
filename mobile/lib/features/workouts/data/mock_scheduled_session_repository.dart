import 'dart:async';

import 'scheduled_session.dart';
import 'scheduled_session_repository.dart';

class MockScheduledSessionRepository implements ScheduledSessionRepository {
  MockScheduledSessionRepository(
      {Duration latency = const Duration(milliseconds: 80)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, List<ScheduledSession>> _store = {};
  final Map<String, StreamController<List<ScheduledSession>>> _ctrls = {};

  StreamController<List<ScheduledSession>> _ctrl(String uid) {
    return _ctrls.putIfAbsent(
      uid,
      () => StreamController<List<ScheduledSession>>.broadcast(),
    );
  }

  /// The same shape the Firestore listener produces: the latest-dated
  /// [kScheduledSessionWindow] sessions, handed back in ascending order.
  ///
  /// The truncation is on the mock too, deliberately. A double that returns
  /// everything while production returns a window is a double that hides the
  /// only bug windowing can introduce.
  List<ScheduledSession> _sorted(String uid) {
    final list = _store[uid] ?? const [];
    final sorted = [...list]
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    if (sorted.length <= kScheduledSessionWindow) {
      return List.unmodifiable(sorted);
    }
    return List.unmodifiable(
      sorted.sublist(sorted.length - kScheduledSessionWindow),
    );
  }

  @override
  Stream<List<ScheduledSession>> watch(String uid) {
    final ctrl = _ctrl(uid);
    late StreamController<List<ScheduledSession>> replay;
    StreamSubscription<List<ScheduledSession>>? sub;
    replay = StreamController<List<ScheduledSession>>(
      onListen: () {
        replay.add(_sorted(uid));
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
  List<ScheduledSession> cached(String uid) => _sorted(uid);

  @override
  Future<void> save(String uid, ScheduledSession session) async {
    await Future<void>.delayed(_latency);
    final list = _store.putIfAbsent(uid, () => []);
    final i = list.indexWhere((s) => s.id == session.id);
    if (i == -1) {
      list.add(session);
    } else {
      list[i] = session;
    }
    _ctrl(uid).add(_sorted(uid));
  }

  @override
  Future<void> delete(String uid, String sessionId) async {
    await Future<void>.delayed(_latency);
    _store[uid]?.removeWhere((s) => s.id == sessionId);
    _ctrl(uid).add(_sorted(uid));
  }

  @override
  Future<void> clear(String uid) async {
    await Future<void>.delayed(_latency);
    _store.remove(uid);
    _ctrl(uid).add(const []);
  }

  @override
  Future<List<ScheduledSession>> exportAll(String uid) async {
    // Sorted, but NOT `_sorted(uid)` -- that name is the windowed view
    // despite what it says, truncated to kScheduledSessionWindow to mirror
    // the Firestore listener. Export is the one caller that must not be.
    final list = _store[uid] ?? const [];
    final all = [...list]
      ..sort((a, b) => a.scheduledFor.compareTo(b.scheduledFor));
    return List.unmodifiable(all);
  }

  void dispose() {
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
  }
}
