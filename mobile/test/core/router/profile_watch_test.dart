import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';

/// The router's profile watcher, across a sign-out.
///
/// It used to delegate with `yield*` into a Firestore snapshot stream, which
/// never completes — so the `await for` over auth events parked on the first
/// sign-in and no later auth change was ever processed. The previous account's
/// listener was never cancelled and the new account's profile was never
/// watched, which meant the `/onboarding` redirect stopped firing for anyone
/// who switched users without restarting the app.
class _FakeAuth {
  final _controller = StreamController<Object?>.broadcast();
  Stream<Object?> authStateChanges() => _controller.stream;
  void emit(Object? user) => _controller.add(user);
  Future<void> dispose() => _controller.close();
}

class _FakeUser {
  const _FakeUser(this.uid);
  final String uid;
}

class _RecordingProfileRepo implements ProfileRepository {
  final watched = <String>[];
  final cancelled = <String>[];
  final _controllers = <String, StreamController<UserProfile?>>{};

  @override
  Stream<UserProfile?> watch(String uid) {
    watched.add(uid);
    final ctrl = StreamController<UserProfile?>(
      onCancel: () => cancelled.add(uid),
    );
    _controllers[uid] = ctrl;
    return ctrl.stream;
  }

  void emit(String uid, UserProfile? profile) => _controllers[uid]?.add(profile);

  @override
  UserProfile? cached(String uid) => null;

  @override
  Future<UserProfile?> load(String uid) async => null;

  @override
  Future<void> save(UserProfile profile) async {}

  @override
  Future<void> delete(String uid) async {}
}

UserProfile _profile(String uid) => UserProfile(uid: uid);

/// CAND-01. A profile repository whose subscription cancel does not complete
/// until the test says so -- what a real Firestore listener teardown looks like
/// under load. Auth events that arrive during that window must not leave a
/// stale or orphaned subscription behind.
class _SlowCancelRepo implements ProfileRepository {
  final watched = <String>[];
  final cancelStarted = <String>[];
  final cancelDone = <String>[];
  final _gates = <String, Completer<void>>{};
  final _ctrls = <String, StreamController<UserProfile?>>{};

  Completer<void> gate(String uid) =>
      _gates.putIfAbsent(uid, () => Completer<void>());

  bool isListening(String uid) => _ctrls[uid]?.hasListener ?? false;

  @override
  Stream<UserProfile?> watch(String uid) {
    watched.add(uid);
    late StreamController<UserProfile?> c;
    c = StreamController<UserProfile?>(
      onCancel: () async {
        cancelStarted.add(uid);
        await gate(uid).future;
        cancelDone.add(uid);
      },
    );
    _ctrls[uid] = c;
    return c.stream;
  }

  void emit(String uid, UserProfile? p) => _ctrls[uid]?.add(p);

  @override
  UserProfile? cached(String uid) => null;
  @override
  Future<UserProfile?> load(String uid) async => null;
  @override
  Future<void> save(UserProfile profile) async {}
  @override
  Future<void> delete(String uid) async {}
}

void _race() {
  group('CAND-01: rapid auth changes with a slow subscription cancel', () {
    test('A -> B -> sign-out leaves NO live profile subscription and emits no stale profile',
        () async {
      final slow = _SlowCancelRepo();
      final auth2 = _FakeAuth();
      final seen = <dynamic>[];
      final sub = profileWatchOf(auth2, slow).listen(seen.add);

      auth2.emit(const _FakeUser('a'));
      await pumpEventQueue();
      expect(slow.isListening('a'), isTrue);

      // B and the sign-out arrive while A's cancel is still in flight.
      auth2.emit(const _FakeUser('b'));
      auth2.emit(null);
      await pumpEventQueue();

      // Let the delayed cancels complete, in order.
      slow.gate('a').complete();
      slow.gate('b').complete();
      await pumpEventQueue();

      // Signed out: nothing may still be listening, for either account.
      expect(slow.isListening('a'), isFalse, reason: 'A was cancelled');
      expect(slow.isListening('b'), isFalse,
          reason: 'B was subscribed during the race and must not outlive the '
              'sign-out that followed it');

      // A late emission from either account must not reach the router.
      final before = seen.length;
      slow.emit('a', _profile('a'));
      slow.emit('b', _profile('b'));
      await pumpEventQueue();
      expect(seen.length, before,
          reason: 'a profile for a signed-out user was delivered');
      expect(seen.last, isNull, reason: 'the last thing the router saw is sign-out');

      await sub.cancel();
      await auth2.dispose();
    });

    test('A -> B: the router ends up watching B only', () async {
      final slow = _SlowCancelRepo();
      final auth2 = _FakeAuth();
      final seen = <dynamic>[];
      final sub = profileWatchOf(auth2, slow).listen(seen.add);

      auth2.emit(const _FakeUser('a'));
      await pumpEventQueue();
      auth2.emit(const _FakeUser('b'));
      await pumpEventQueue();
      slow.gate('a').complete();
      await pumpEventQueue();

      expect(slow.isListening('a'), isFalse);
      expect(slow.isListening('b'), isTrue);
      slow.emit('b', _profile('b'));
      slow.emit('a', _profile('a'));
      await pumpEventQueue();
      expect(seen.whereType<UserProfile>().map((p) => p.uid), ['b'],
          reason: 'only the current accounts profile may be delivered');

      await sub.cancel();
      slow.gate('b').complete();
      await auth2.dispose();
    });
  });
}

void main() {
  _race();
  late _FakeAuth auth;
  late _RecordingProfileRepo repo;

  setUp(() {
    auth = _FakeAuth();
    repo = _RecordingProfileRepo();
  });

  tearDown(() => auth.dispose());

  test('a second sign-in is watched, not ignored', () async {
    // The regression in one assertion: with `yield*` the loop never came back
    // for the second auth event, so `watched` stayed ['a'] forever.
    final seen = <dynamic>[];
    final sub = profileWatchOf(auth, repo).listen(seen.add);
    addTearDown(sub.cancel);

    auth.emit(const _FakeUser('a'));
    await pumpEventQueue();
    auth.emit(null);
    await pumpEventQueue();
    auth.emit(const _FakeUser('b'));
    await pumpEventQueue();

    expect(repo.watched, ['a', 'b']);
  });

  test('the previous account stops being watched', () async {
    final sub = profileWatchOf(auth, repo).listen((_) {});
    addTearDown(sub.cancel);

    auth.emit(const _FakeUser('a'));
    await pumpEventQueue();
    auth.emit(const _FakeUser('b'));
    await pumpEventQueue();

    expect(repo.cancelled, contains('a'),
        reason: 'a listener left on the old uid keeps failing the rules and '
            'retrying for the life of the process');
  });

  test('a sign-out emits null so the router can redirect', () async {
    final seen = <dynamic>[];
    final sub = profileWatchOf(auth, repo).listen(seen.add);
    addTearDown(sub.cancel);

    auth.emit(const _FakeUser('a'));
    await pumpEventQueue();
    repo.emit('a', _profile('a'));
    await pumpEventQueue();
    auth.emit(null);
    await pumpEventQueue();

    expect(seen.last, isNull);
  });

  test('profile updates for the signed-in user are forwarded', () async {
    final seen = <dynamic>[];
    final sub = profileWatchOf(auth, repo).listen(seen.add);
    addTearDown(sub.cancel);

    auth.emit(const _FakeUser('a'));
    await pumpEventQueue();
    repo.emit('a', _profile('a'));
    await pumpEventQueue();

    expect(seen.whereType<UserProfile>().single.uid, 'a');
  });

  test('cancelling the stream tears both subscriptions down', () async {
    final sub = profileWatchOf(auth, repo).listen((_) {});
    auth.emit(const _FakeUser('a'));
    await pumpEventQueue();

    await sub.cancel();
    await pumpEventQueue();

    expect(repo.cancelled, contains('a'));
  });
}
