// Journey J2: "Delete my account" end to end on the device. The real
// AccountDeletionAction runs with the real DeviceLocalDataWipe over a temp
// documents directory and in-memory SharedPreferences; fakes sit only at the
// platform edge (server call, Keystore, notification plugin, auth repository).
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/mock_notification_service.dart';
import 'package:fitness_app/core/notifications/notification_providers.dart';
import 'package:fitness_app/features/account_deletion/data/account_deletion_service.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';

class _AuthRepo implements AuthRepository {
  _AuthRepo(this.uid);
  final String uid;
  int signOuts = 0;
  @override
  Stream<AuthUser?> authStateChanges() =>
      Stream.value(AuthUser(uid: uid, displayName: uid));
  @override
  AuthUser? get currentUser => AuthUser(uid: uid, displayName: uid);
  @override
  Future<AuthUser> signInAnonymously() async => throw UnimplementedError();
  @override
  Future<SignInResult> signInWithGoogle() async => throw UnimplementedError();
  @override
  Future<void> signOut() async => signOuts++;
}

class _SpyWipe implements LocalDataWipe {
  _SpyWipe(this.inner, this.onWipe);
  final LocalDataWipe inner;
  final Future<void> Function(String uid) onWipe;
  @override
  Future<void> wipe(String uid) async {
    await onWipe(uid);
    await inner.wipe(uid);
  }
}

void main() {
  late Directory docs;
  late SharedPreferences prefs;
  late MockNotificationService notes;
  late PendingWipeMarker marker;
  late List<String> forgotten;
  late bool keyForgetFails;
  late _AuthRepo auth;
  late MockAccountDeletionService server;

  List<String> prefKeysOf(String uid) => [
        'profile.sensitive.$uid',
        trainingContextKeyFor(uid),
        'progress_photos.scan_reminder.v1.$uid',
        'progress_photos.consent.v1.$uid',
      ];

  setUp(() async {
    docs = await Directory.systemTemp.createTemp('deletion_journey');
    addTearDown(() async {
      if (await docs.exists()) await docs.delete(recursive: true);
    });
    final seeded = <String, Object>{'settings.language': 'ru'};
    for (final uid in ['A', 'B']) {
      for (final k in prefKeysOf(uid)) {
        seeded[k] = k.endsWith('v1.$uid') && k.contains('training')
            ? 'home'
            : (k.contains('sensitive') ? '{"x":1}' : true);
      }
      final scans = Directory('${docs.path}/progress_photos/$uid/scans')
        ..createSync(recursive: true);
      File('${scans.path}/scan1.bin').writeAsBytesSync([7, 7, 7]);
      File('${scans.path}/scan1.json').writeAsStringSync('{}');
      File('${docs.path}/progress_photos/$uid/index.json').writeAsStringSync('[]');
      final rec = Directory('${docs.path}/coach_recordings/$uid')
        ..createSync(recursive: true);
      File('${rec.path}/set1.json').writeAsStringSync('{}');
    }
    SharedPreferences.setMockInitialValues(seeded);
    prefs = await SharedPreferences.getInstance();
    notes = MockNotificationService();
    await notes.scheduleAt('body_scan_next',
        fireAt: DateTime.now().add(const Duration(days: 3)), title: 't', body: 'b');
    await notes.scheduleAt('session_1',
        fireAt: DateTime.now().add(const Duration(days: 1)), title: 't', body: 'b');
    marker = InMemoryPendingWipeMarker();
    forgotten = [];
    keyForgetFails = false;
    auth = _AuthRepo('A');
    server = MockAccountDeletionService();
  });

  DeviceLocalDataWipe wipeImpl() => DeviceLocalDataWipe(
        prefs: prefs,
        documentsDir: docs,
        forgetPhotoKey: (uid) async {
          if (keyForgetFails) throw StateError('keystore unavailable');
          forgotten.add(uid);
        },
      );

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(server),
      localDataWipeProvider.overrideWithValue(wipeImpl()),
      pendingWipeMarkerProvider.overrideWithValue(marker),
      authRepositoryProvider.overrideWithValue(auth),
      notificationServiceProvider.overrideWithValue(notes),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  void expectBIntact() {
    for (final k in prefKeysOf('B')) {
      expect(prefs.containsKey(k), isTrue, reason: '$k must remain');
    }
    expect(File('${docs.path}/progress_photos/B/scans/scan1.bin').readAsBytesSync(),
        [7, 7, 7]);
    expect(File('${docs.path}/coach_recordings/B/set1.json').existsSync(), isTrue);
    expect(prefs.getString('settings.language'), 'ru');
  }

  test('a successful deletion erases every item of A, keeps B, cancels notifications, signs out', () async {
    final c = container();

    await c.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    expect(server.callCount, 1);
    for (final k in prefKeysOf('A')) {
      expect(prefs.containsKey(k), isFalse, reason: '$k must be gone');
    }
    expect(Directory('${docs.path}/progress_photos/A').existsSync(), isFalse);
    expect(Directory('${docs.path}/coach_recordings/A').existsSync(), isFalse);
    expect(forgotten, ['A']);
    expect(notes.scheduled, isEmpty);
    expect(auth.signOuts, 1);
    expect(await marker.read(), isEmpty, reason: 'a finished wipe leaves no marker');
    expectBIntact();
  });

  test('a failing photo-key step still runs every other step, the marker keeps A for the retry, and the retry completes', () async {
    keyForgetFails = true;
    final c = container();

    await c.read(accountDeletionActionProvider.notifier).deleteAccount();

    // The deletion itself is reported as done: the account is gone server-side.
    expect(c.read(accountDeletionActionProvider).hasError, isFalse);
    // Everything except the key was erased anyway.
    for (final k in prefKeysOf('A')) {
      expect(prefs.containsKey(k), isFalse, reason: '$k must be gone');
    }
    expect(Directory('${docs.path}/progress_photos/A').existsSync(), isFalse);
    expect(Directory('${docs.path}/coach_recordings/A').existsSync(), isFalse);
    expect(notes.scheduled, isEmpty);
    expect(auth.signOuts, 1);
    // The failure is recorded, not hidden: A stays marked so the next launch retries.
    expect(await marker.read(), {'A'});
    expect(forgotten, isEmpty);
    expectBIntact();

    // Next launch with the Keystore working: the sweep finishes the job for A only.
    keyForgetFails = false;
    final done = await finishInterruptedWipe(
      marker: marker,
      wipe: wipeImpl(),
      signedInUid: 'B',
    );
    expect(done, isTrue);
    expect(forgotten, ['A']);
    expect(await marker.read(), isEmpty);
    expectBIntact();
  });

  test('F1: the being-deleted uid is set after server success and BEFORE the wipe, while auth still shows A', () async {
    String? seenInWipe;
    String? authUidInWipe;
    bool markerHadAInWipe = false;
    late ProviderContainer c;
    final inner = wipeImpl();
    c = ProviderContainer(overrides: [
      accountDeletionServiceProvider.overrideWithValue(server),
      localDataWipeProvider.overrideWithValue(_SpyWipe(inner, (uid) async {
        seenInWipe = c.read(accountBeingDeletedUidProvider);
        authUidInWipe = auth.currentUser?.uid;
        markerHadAInWipe = (await marker.read()).contains(uid);
      })),
      pendingWipeMarkerProvider.overrideWithValue(marker),
      authRepositoryProvider.overrideWithValue(auth),
      notificationServiceProvider.overrideWithValue(notes),
    ]);
    addTearDown(c.dispose);
    expect(c.read(accountBeingDeletedUidProvider), isNull,
        reason: 'precondition: nothing is being deleted');

    await c.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(seenInWipe, 'A', reason: 'set before the wipe runs');
    expect(authUidInWipe, 'A', reason: 'auth still reports A during the wipe');
    expect(markerHadAInWipe, isTrue);
    expect(c.read(accountBeingDeletedUidProvider), 'A',
        reason: 'never reset after a successful deletion');
    expect(auth.signOuts, 1);
  });

  test('F1: a failed server deletion does NOT set the being-deleted uid', () async {
    server.failWith = const AccountDeletionException('stripe down');
    final c = container();

    await c.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(c.read(accountBeingDeletedUidProvider), isNull);
  });

  test('a failed server deletion touches nothing on the device', () async {
    server.failWith = const AccountDeletionException('stripe down');
    final c = container();

    await c.read(accountDeletionActionProvider.notifier).deleteAccount();

    expect(c.read(accountDeletionActionProvider).hasError, isTrue);
    for (final uid in ['A', 'B']) {
      for (final k in prefKeysOf(uid)) {
        expect(prefs.containsKey(k), isTrue, reason: '$k must remain');
      }
      expect(Directory('${docs.path}/progress_photos/$uid/scans').existsSync(), isTrue);
      expect(Directory('${docs.path}/coach_recordings/$uid').existsSync(), isTrue);
    }
    expect(forgotten, isEmpty);
    expect(notes.scheduled, hasLength(2));
    expect(auth.signOuts, 0);
    expect(await marker.read(), isEmpty);
  });
}
