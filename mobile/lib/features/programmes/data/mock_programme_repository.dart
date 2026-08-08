import 'dart:async';

import 'programme.dart';
import 'programme_repository.dart';

class MockProgrammeRepository implements ProgrammeRepository {
  MockProgrammeRepository({Duration latency = const Duration(milliseconds: 80)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, List<Programme>> _store = {};
  final Map<String, StreamController<List<Programme>>> _ctrls = {};

  StreamController<List<Programme>> _ctrl(String uid) {
    return _ctrls.putIfAbsent(
      uid,
      () => StreamController<List<Programme>>.broadcast(),
    );
  }

  List<Programme> _sorted(String uid) {
    final list = _store[uid] ?? const [];
    final sorted = [...list]
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return List.unmodifiable(sorted);
  }

  @override
  Stream<List<Programme>> watch(String uid) {
    final ctrl = _ctrl(uid);
    late StreamController<List<Programme>> replay;
    StreamSubscription<List<Programme>>? sub;
    replay = StreamController<List<Programme>>(
      onListen: () {
        replay.add(_sorted(uid));
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
  List<Programme> cached(String uid) => _sorted(uid);

  @override
  Future<void> save(String uid, Programme programme) async {
    await Future<void>.delayed(_latency);
    final list = _store.putIfAbsent(uid, () => []);
    final i = list.indexWhere((p) => p.id == programme.id);
    if (i == -1) {
      list.add(programme);
    } else {
      list[i] = programme;
    }
    _ctrl(uid).add(_sorted(uid));
  }

  @override
  Future<void> delete(String uid, String programmeId) async {
    await Future<void>.delayed(_latency);
    _store[uid]?.removeWhere((p) => p.id == programmeId);
    _ctrl(uid).add(_sorted(uid));
  }

  @override
  Future<List<Programme>> exportAll(String uid) async {
    final list = _store[uid] ?? const [];
    final all = [...list]..sort((a, b) => a.startedAt.compareTo(b.startedAt));
    return List.unmodifiable(all);
  }

  void dispose() {
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
  }
}
