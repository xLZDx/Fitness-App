// Test-only fakes and harness for the S03 mode state tests (EP-1):
// FakeModeStore (in-memory, write spy with sequence numbers, failing and
// delayed writes, delayed or failing reads), ControlledProfileRepo and
// ModeEnv (a ProviderContainer wired with them).
import 'dart:async';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/modes/data/mode_codec.dart';
import 'package:fitness_app/features/modes/data/mode_models.dart';
import 'package:fitness_app/features/modes/data/mode_store.dart';
import 'package:fitness_app/features/modes/state/mode_flags.dart';
import 'package:fitness_app/features/modes/state/mode_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class SeqClock {
  int _n = 0;
  int next() => ++_n;
}

class WriteRec {
  WriteRec(this.seq, this.uid, this.state);
  final int seq;
  final String uid;
  final ModeState state;
}

class FakeModeStore implements ModeStore {
  FakeModeStore({SeqClock? clock}) : clock = clock ?? SeqClock();

  final SeqClock clock;

  /// What `read` returns per uid (default: missing).
  final Map<String, ModeRead> stored = {};

  /// Completed, effective writes in order.
  final List<WriteRec> writes = [];

  /// Every `write` call, including failed and refused ones.
  int writeCalls = 0;
  int reads = 0;

  /// `write` returns `failed` (the real store never throws).
  bool failWrites = false;

  /// `write` THROWS (a misbehaving store; the notifier must still cope).
  bool throwOnWrite = false;

  /// `read` throws this when set.
  Object? readError;

  /// Next `read` waits for it (one shot).
  Completer<void>? readGate;

  /// Next `write` waits for it (one shot), before it takes effect.
  Completer<void>? writeGate;

  final Set<String> _wiped = {};

  /// Seeds the stored value from a raw string through the REAL codec.
  void seedRaw(String uid, String? raw) => stored[uid] = decodeModeState(raw);

  @override
  Future<ModeRead> read(String uid) async {
    reads++;
    final g = readGate;
    readGate = null;
    if (g != null) await g.future;
    final e = readError;
    if (e != null) throw e;
    if (_wiped.contains(uid)) return const ModeReadMissing();
    return stored[uid] ?? const ModeReadMissing();
  }

  @override
  Future<ModeWriteResult> write(String uid, ModeState state) async {
    writeCalls++;
    if (uid.isEmpty) return ModeWriteResult.refusedInvalidUid;
    if (_wiped.contains(uid)) return ModeWriteResult.refusedWipedUid;
    final g = writeGate;
    writeGate = null;
    if (g != null) await g.future;
    if (throwOnWrite) throw StateError('store write threw');
    if (failWrites) return ModeWriteResult.failed;
    if (_wiped.contains(uid)) return ModeWriteResult.refusedWipedUid;
    stored[uid] = ModeReadValue(state);
    writes.add(WriteRec(clock.next(), uid, state));
    return ModeWriteResult.written;
  }

  @override
  void markUidWiped(String uid) {
    if (uid.isNotEmpty) _wiped.add(uid);
  }

  @override
  bool isUidWiped(String uid) => _wiped.contains(uid);

  ModeState? stateOf(String uid) {
    final r = stored[uid];
    return r is ModeReadValue ? r.state : null;
  }
}

/// A profile repository whose emissions the test controls.
class ControlledProfileRepo implements ProfileRepository {
  final Map<String, StreamController<UserProfile?>> _ctl = {};
  final Map<String, UserProfile?> _latest = {};
  final Set<String> _has = {};

  StreamController<UserProfile?> _c(String uid) =>
      _ctl.putIfAbsent(uid, () => StreamController<UserProfile?>.broadcast());

  /// Emits [p] (null = no profile) for [uid].
  void emit(String uid, UserProfile? p) {
    _latest[uid] = p;
    _has.add(uid);
    _c(uid).add(p);
  }

  void emitOnboarded(String uid) =>
      emit(uid, UserProfile.empty(uid).copyWith(completedAt: DateTime(2026, 1, 1)));

  void emitNotOnboarded(String uid) => emit(uid, UserProfile.empty(uid));

  @override
  Stream<UserProfile?> watch(String uid) async* {
    if (_has.contains(uid)) yield _latest[uid];
    yield* _c(uid).stream;
  }

  @override
  UserProfile? cached(String uid) => _latest[uid];

  @override
  Future<UserProfile?> load(String uid) async => _latest[uid];

  /// Saved profiles are emitted like a real repository does.
  final List<UserProfile> saved = [];

  /// When set, `save` waits for it (a slow save).
  Completer<void>? saveGate;

  @override
  Future<void> save(UserProfile profile) async {
    final g = saveGate;
    if (g != null) await g.future;
    saved.add(profile);
    emit(profile.uid, profile);
  }

  @override
  Future<void> delete(String uid) async => emit(uid, null);

  void dispose() {
    for (final c in _ctl.values) {
      c.close();
    }
  }
}

AuthUser testUser(String uid) =>
    AuthUser(uid: uid, displayName: 'n', provider: AuthProvider.google);

/// A container wired with a fake store, a controlled profile repository and a
/// replaying auth stream. [signIn] / [signOut] emit auth values.
class ModeEnv {
  ModeEnv({
    FakeModeStore? store,
    ModeStore? realStore,
    ControlledProfileRepo? profiles,
    ModeFlags flags = const ModeFlags(),
    List<Override> extra = const [],
    String? initialUid,
  })  : fake = store ?? FakeModeStore(),
        profiles = profiles ?? ControlledProfileRepo() {
    _current = initialUid == null ? null : testUser(initialUid);
    _hasValue = initialUid != null;
    container = ProviderContainer(overrides: [
      authUserProvider.overrideWith((ref) => _stream()),
      modeStoreProvider.overrideWithValue(realStore ?? fake),
      profileRepositoryProvider.overrideWithValue(this.profiles),
      modeFlagsProvider.overrideWithValue(flags),
      ...extra,
    ]);
    addTearDown(() {
      container.dispose();
      _auth.close();
      this.profiles.dispose();
    });
  }

  final FakeModeStore fake;
  final ControlledProfileRepo profiles;
  late final ProviderContainer container;
  final StreamController<AuthUser?> _auth = StreamController<AuthUser?>.broadcast();
  AuthUser? _current;
  bool _hasValue = false;
  final List<ModeChanged> events = [];
  StreamSubscription<ModeChanged>? _eventSub;

  Stream<AuthUser?> _stream() async* {
    if (_hasValue) yield _current;
    yield* _auth.stream;
  }

  Future<void> signIn(String uid) async {
    _current = testUser(uid);
    _hasValue = true;
    _auth.add(_current);
    await pumpEventQueue();
  }

  /// Synchronous auth emission (for fakeAsync tests); the caller flushes.
  void emitAuth(String? uid) {
    _current = uid == null ? null : testUser(uid);
    _hasValue = true;
    _auth.add(_current);
  }

  Future<void> signOut() async {
    _current = null;
    _hasValue = true;
    _auth.add(null);
    await pumpEventQueue();
  }

  ModeNotifier get notifier => container.read(modeStateProvider.notifier);

  /// Waits for the state of the CURRENT auth value to load.
  Future<ModeState> load() async {
    await pumpEventQueue();
    return container.read(modeStateProvider.future);
  }

  ModeState get state => container.read(modeStateProvider).requireValue;

  /// Subscribes to mode change events.
  void recordEvents() {
    _eventSub ??= container
        .read(modeChangeBusProvider)
        .stream
        .listen(events.add);
    addTearDown(() => _eventSub?.cancel());
  }

  /// Starts the warm-up provider the app root watches.
  void warmUp() {
    container.listen<void>(modeWarmUpProvider, (_, __) {});
  }
}
