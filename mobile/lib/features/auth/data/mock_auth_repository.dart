import 'dart:async';
import 'dart:math';

import 'auth_repository.dart';
import 'auth_user.dart';

/// In-memory [AuthRepository] used during development and in tests. Keeps
/// at most one signed-in user at a time. Adds a small artificial latency so
/// the UI's loading states are exercised the same way they will be against
/// the real backend.
class MockAuthRepository implements AuthRepository {
  MockAuthRepository({Duration latency = const Duration(milliseconds: 250)})
      : _latency = latency {
    _controller.add(_current);
  }

  final Duration _latency;
  final _controller = StreamController<AuthUser?>.broadcast();
  final _rng = Random();
  AuthUser? _current;

  @override
  Stream<AuthUser?> authStateChanges() {
    late StreamController<AuthUser?> replay;
    replay = StreamController<AuthUser?>(
      onListen: () {
        replay.add(_current);
        _controller.stream.listen(replay.add,
            onError: replay.addError, onDone: replay.close);
      },
    );
    return replay.stream;
  }

  @override
  AuthUser? get currentUser => _current;

  @override
  Future<AuthUser> signInAnonymously() async {
    await Future<void>.delayed(_latency);
    final user = AuthUser(
      uid: _newUid(),
      displayName: 'Guest',
      provider: AuthProvider.anonymous,
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<AuthUser> signInWithGoogle() async {
    await Future<void>.delayed(_latency);
    final user = AuthUser(
      uid: _newUid(),
      displayName: 'Demo Athlete',
      email: 'demo.athlete@example.com',
      photoUrl: null,
      provider: AuthProvider.google,
    );
    _current = user;
    _controller.add(user);
    return user;
  }

  @override
  Future<void> signOut() async {
    await Future<void>.delayed(_latency);
    _current = null;
    _controller.add(null);
  }

  String _newUid() {
    final bytes = List<int>.generate(16, (_) => _rng.nextInt(256));
    return bytes
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  void dispose() => _controller.close();
}
