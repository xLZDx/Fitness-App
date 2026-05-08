import 'dart:async';

import 'subscription_models.dart';
import 'subscription_repository.dart';

class MockSubscriptionRepository implements SubscriptionRepository {
  MockSubscriptionRepository(
      {Duration latency = const Duration(milliseconds: 80)})
      : _latency = latency;

  final Duration _latency;
  final Map<String, Subscription> _store = {};
  final Map<String, StreamController<Subscription?>> _ctrls = {};

  StreamController<Subscription?> _ctrl(String uid) {
    return _ctrls.putIfAbsent(
      uid,
      () => StreamController<Subscription?>.broadcast(),
    );
  }

  @override
  Stream<Subscription?> watch(String uid) {
    final ctrl = _ctrl(uid);
    late StreamController<Subscription?> replay;
    StreamSubscription<Subscription?>? sub;
    replay = StreamController<Subscription?>(
      onListen: () {
        replay.add(_store[uid]);
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
  Subscription? cached(String uid) => _store[uid];

  @override
  Future<void> save(Subscription sub) async {
    await Future<void>.delayed(_latency);
    _store[sub.uid] = sub;
    _ctrl(sub.uid).add(sub);
  }

  @override
  Future<void> delete(String uid) async {
    await Future<void>.delayed(_latency);
    _store.remove(uid);
    _ctrl(uid).add(null);
  }

  void dispose() {
    for (final c in _ctrls.values) {
      c.close();
    }
    _ctrls.clear();
  }
}
