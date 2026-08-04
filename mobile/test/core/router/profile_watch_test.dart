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

void main() {
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
