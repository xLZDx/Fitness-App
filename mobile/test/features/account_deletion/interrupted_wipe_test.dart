import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';

class _AuthRepo implements AuthRepository {
  _AuthRepo({this.user = const AuthUser(uid: 'u1', displayName: 'U')});
  final AuthUser? user;
  int signOutCalls = 0;

  @override
  Stream<AuthUser?> authStateChanges() => Stream.value(user);
  @override
  AuthUser? get currentUser => user;
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async => signOutCalls++;
}

class _ThrowingWipe implements LocalDataWipe {
  final List<String> attempts = [];
  @override
  Future<void> wipe(String uid) async {
    attempts.add(uid);
    throw StateError('disk locked');
  }
}

/// Records, at the moment the wipe runs, whether the marker was already set.
class _MarkerProbingWipe implements LocalDataWipe {
  _MarkerProbingWipe(this.marker);
  final PendingWipeMarker marker;
  final List<String> wiped = [];
  String? markerSeenDuringWipe;

  @override
  Future<void> wipe(String uid) async {
    markerSeenDuringWipe = await marker.read();
    wiped.add(uid);
  }
}

/// In-memory marker with a synchronous view, for condition polling.
class _TrackedMarker extends InMemoryPendingWipeMarker {
  String? current;
  bool get hasPending => current != null;
  @override
  Future<void> write(String uid) async {
    current = uid;
    await super.write(uid);
  }

  @override
  Future<void> clear() async {
    current = null;
    await super.clear();
  }
}

class _ThrowingMarkerWrite extends InMemoryPendingWipeMarker {
  @override
  Future<void> write(String uid) async => throw StateError('prefs down');
}

/// Waits (bounded, condition-based) for the unawaited sweep to finish.
Future<void> _until(bool Function() done) async {
  for (var i = 0; i < 200 && !done(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  expect(done(), isTrue, reason: 'condition not reached in time');
}

/// Lets any wrongly-scheduled work run so a "nothing happened" check is real.
Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('finishInterruptedWipe', () {
    test('wipes the marked uid and clears the marker when signed out',
        () async {
      final marker = InMemoryPendingWipeMarker();
      await marker.write('old');
      final wipe = RecordingLocalDataWipe();

      final ran = await finishInterruptedWipe(
          marker: marker, wipe: wipe, signedInUid: null);

      expect(ran, isTrue);
      expect(wipe.wiped, ['old']);
      expect(await marker.read(), isNull);
    });

    test('wipes the marked uid when a different account is signed in',
        () async {
      final marker = InMemoryPendingWipeMarker();
      await marker.write('old');
      final wipe = RecordingLocalDataWipe();

      final ran = await finishInterruptedWipe(
          marker: marker, wipe: wipe, signedInUid: 'someone-else');

      expect(ran, isTrue);
      expect(wipe.wiped, ['old']);
      expect(await marker.read(), isNull);
    });

    test('does nothing and returns false when there is no marker', () async {
      final marker = InMemoryPendingWipeMarker();
      final wipe = RecordingLocalDataWipe();

      final ran = await finishInterruptedWipe(
          marker: marker, wipe: wipe, signedInUid: 'u1');

      expect(ran, isFalse);
      expect(wipe.wiped, isEmpty);
      expect(await marker.read(), isNull);
    });

    test('leaves the marker and the data alone for the still-signed-in uid',
        () async {
      final marker = InMemoryPendingWipeMarker();
      await marker.write('u1');
      final wipe = RecordingLocalDataWipe();

      final ran = await finishInterruptedWipe(
          marker: marker, wipe: wipe, signedInUid: 'u1');

      expect(ran, isFalse);
      expect(wipe.wiped, isEmpty,
          reason: 'that account is still signed in; wiping would destroy '
              'a live account\'s data');
      expect(await marker.read(), 'u1');
    });

    test('keeps the marker and returns false when the wipe throws', () async {
      final marker = InMemoryPendingWipeMarker();
      await marker.write('old');
      final wipe = _ThrowingWipe();

      final ran = await finishInterruptedWipe(
          marker: marker, wipe: wipe, signedInUid: null);

      expect(ran, isFalse);
      expect(wipe.attempts, ['old']);
      expect(await marker.read(), 'old',
          reason: 'the next launch must be able to retry');
    });
  });

  group('PrefsPendingWipeMarker', () {
    test('round trips a uid under the documented key, and clears it',
        () async {
      SharedPreferences.setMockInitialValues({});
      final marker = PrefsPendingWipeMarker();

      expect(await marker.read(), isNull);

      await marker.write('uid-42');
      expect(await marker.read(), 'uid-42');
      final prefs = await SharedPreferences.getInstance();
      expect(PrefsPendingWipeMarker.key, 'account_deletion.pending_wipe_uid');
      expect(prefs.getString('account_deletion.pending_wipe_uid'), 'uid-42');
      expect(prefs.getKeys(), {'account_deletion.pending_wipe_uid'},
          reason: 'the marker stores the uid only');

      await marker.clear();
      expect(await marker.read(), isNull);
      expect(prefs.getKeys(), isEmpty);
    });

    test('reads a marker persisted by an earlier process', () async {
      SharedPreferences.setMockInitialValues(
          {'account_deletion.pending_wipe_uid': 'left-over'});

      expect(await PrefsPendingWipeMarker().read(), 'left-over');
    });
  });

  group('AccountDeletionAction marker handling', () {
    ProviderContainer build({
      required AccountDeletionService service,
      required LocalDataWipe wipe,
      required PendingWipeMarker marker,
      required _AuthRepo repo,
    }) {
      final c = ProviderContainer(overrides: [
        accountDeletionServiceProvider.overrideWithValue(service),
        localDataWipeProvider.overrideWithValue(wipe),
        pendingWipeMarkerProvider.overrideWithValue(marker),
        authRepositoryProvider.overrideWithValue(repo),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('success: marker is set before the wipe, then cleared; wipe recorded',
        () async {
      final marker = InMemoryPendingWipeMarker();
      final wipe = _MarkerProbingWipe(marker);
      final repo = _AuthRepo();
      final c = build(
          service: MockAccountDeletionService(),
          wipe: wipe,
          marker: marker,
          repo: repo);

      await c.read(accountDeletionActionProvider.notifier).deleteAccount();

      expect(wipe.wiped, ['u1']);
      expect(wipe.markerSeenDuringWipe, 'u1',
          reason: 'the marker must exist before the wipe starts');
      expect(await marker.read(), isNull);
      expect(repo.signOutCalls, 1);
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    });

    test('wipe throws: marker stays set, deletion is still reported as done',
        () async {
      final marker = InMemoryPendingWipeMarker();
      final repo = _AuthRepo();
      final c = build(
          service: MockAccountDeletionService(),
          wipe: _ThrowingWipe(),
          marker: marker,
          repo: repo);

      await c.read(accountDeletionActionProvider.notifier).deleteAccount();

      expect(await marker.read(), 'u1');
      expect(repo.signOutCalls, 1);
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    });

    test('server call throws: no marker is written and nothing is wiped',
        () async {
      final marker = InMemoryPendingWipeMarker();
      final wipe = RecordingLocalDataWipe();
      final repo = _AuthRepo();
      final c = build(
          service: MockAccountDeletionService()
            ..failWith = const AccountDeletionException('boom'),
          wipe: wipe,
          marker: marker,
          repo: repo);

      await c.read(accountDeletionActionProvider.notifier).deleteAccount();

      expect(await marker.read(), isNull,
          reason: 'a marker while the account is alive could later erase a '
              'live account\'s data');
      expect(wipe.wiped, isEmpty);
      expect(repo.signOutCalls, 0);
      expect(c.read(accountDeletionActionProvider).hasError, isTrue);
    });

    test('a marker write failure does not block the wipe or the deletion',
        () async {
      final wipe = RecordingLocalDataWipe();
      final repo = _AuthRepo();
      final c = build(
          service: MockAccountDeletionService(),
          wipe: wipe,
          marker: _ThrowingMarkerWrite(),
          repo: repo);

      await c.read(accountDeletionActionProvider.notifier).deleteAccount();

      expect(wipe.wiped, ['u1']);
      expect(repo.signOutCalls, 1);
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    });

    test('no uid at deletion time: no marker is written and no wipe runs',
        () async {
      final marker = InMemoryPendingWipeMarker();
      final wipe = RecordingLocalDataWipe();
      final c = build(
          service: MockAccountDeletionService(),
          wipe: wipe,
          marker: marker,
          repo: _AuthRepo(user: null));

      await c.read(accountDeletionActionProvider.notifier).deleteAccount();

      expect(await marker.read(), isNull);
      expect(wipe.wiped, isEmpty);
      expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    });
  });

  group('interruptedWipeSweepProvider', () {
    ProviderContainer build({
      required StreamController<AuthUser?> auth,
      required PendingWipeMarker marker,
      required LocalDataWipe wipe,
    }) {
      final c = ProviderContainer(overrides: [
        authUserProvider.overrideWith((ref) => auth.stream),
        pendingWipeMarkerProvider.overrideWithValue(marker),
        localDataWipeProvider.overrideWithValue(wipe),
      ]);
      addTearDown(c.dispose);
      return c;
    }

    test('waits for the first auth value, then wipes a leftover marker once',
        () async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      final marker = _TrackedMarker();
      await marker.write('old');
      final wipe = RecordingLocalDataWipe();
      final c = build(auth: auth, marker: marker, wipe: wipe);

      c.read(interruptedWipeSweepProvider);
      await _settle();
      expect(wipe.wiped, isEmpty, reason: 'auth state is still unknown');
      expect(await marker.read(), 'old');

      auth.add(null);
      await _until(() => wipe.wiped.isNotEmpty);
      await _until(() => !marker.hasPending);
      expect(wipe.wiped, ['old']);

      // Further auth emissions must not re-run the sweep.
      await marker.write('second');
      auth.add(const AuthUser(uid: 'other', displayName: 'O'));
      auth.add(null);
      await _settle();
      expect(wipe.wiped, ['old']);
      expect(await marker.read(), 'second');
    });

    test('wipes the leftover marker for a different signed-in user', () async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      final marker = _TrackedMarker();
      await marker.write('old');
      final wipe = RecordingLocalDataWipe();
      final c = build(auth: auth, marker: marker, wipe: wipe);

      c.read(interruptedWipeSweepProvider);
      auth.add(const AuthUser(uid: 'new-user', displayName: 'N'));

      await _until(() => wipe.wiped.isNotEmpty);
      await _until(() => !marker.hasPending);
      expect(wipe.wiped, ['old']);
    });

    test('does not wipe when the marker belongs to the signed-in user',
        () async {
      final auth = StreamController<AuthUser?>();
      addTearDown(auth.close);
      final marker = InMemoryPendingWipeMarker();
      await marker.write('u1');
      final wipe = RecordingLocalDataWipe();
      final c = build(auth: auth, marker: marker, wipe: wipe);

      c.read(interruptedWipeSweepProvider);
      auth.add(const AuthUser(uid: 'u1', displayName: 'U'));
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(wipe.wiped, isEmpty);
      expect(await marker.read(), 'u1');
    });
  });
}
