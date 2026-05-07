import 'dart:async';

import 'profile_models.dart';
import 'profile_repository.dart';

class MockProfileRepository implements ProfileRepository {
  MockProfileRepository({Duration latency = const Duration(milliseconds: 120)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, UserProfile> _store = {};
  final Map<String, StreamController<UserProfile?>> _controllers = {};

  StreamController<UserProfile?> _controllerFor(String uid) {
    return _controllers.putIfAbsent(
      uid,
      () => StreamController<UserProfile?>.broadcast(),
    );
  }

  @override
  Stream<UserProfile?> watch(String uid) {
    final ctrl = _controllerFor(uid);
    late StreamController<UserProfile?> replay;
    replay = StreamController<UserProfile?>(
      onListen: () {
        replay.add(_store[uid]);
        ctrl.stream.listen(replay.add,
            onError: replay.addError, onDone: replay.close);
      },
    );
    return replay.stream;
  }

  @override
  UserProfile? cached(String uid) => _store[uid];

  @override
  Future<UserProfile?> load(String uid) async {
    await Future<void>.delayed(_latency);
    return _store[uid];
  }

  @override
  Future<void> save(UserProfile profile) async {
    await Future<void>.delayed(_latency);
    _store[profile.uid] = profile;
    _controllerFor(profile.uid).add(profile);
  }

  @override
  Future<void> delete(String uid) async {
    await Future<void>.delayed(_latency);
    _store.remove(uid);
    _controllerFor(uid).add(null);
  }

  void dispose() {
    for (final c in _controllers.values) {
      c.close();
    }
    _controllers.clear();
  }
}
