// MAJOR-02: a body-scan save is bound to the account that started it.
//
// If the signed-in account changes (switch, sign-out, deletion) while the save
// is in flight, the screen must stop writing, remove everything this save
// already wrote through the ORIGINAL account's repositories, touch nothing that
// belongs to the new account, and say nothing to the user.
//
// Groups 1-2 use recording fakes with a Completer per write, so the exact
// moment of the account change is controlled. Group 3 uses the real encrypted
// stores on a temp directory and the real `DeviceLocalDataWipe`.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/account_deletion/state/account_deletion_providers.dart'
    show accountBeingDeletedUidProvider;
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/data/aes_photo_cipher.dart';
import 'package:fitness_app/features/progress_photos/data/local_progress_photos_repository.dart';
import 'package:fitness_app/features/progress_photos/data/photo_store.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_reminder.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_store.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_capture_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

const _userA = AuthUser(uid: 'user_a', displayName: 'A');
const _userB = AuthUser(uid: 'user_b', displayName: 'B');

class _NoopReminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async => null;
}

class _PopCounter extends NavigatorObserver {
  int pops = 0;
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}

/// Recording photo repository. Every `save` can be held on a Completer (keyed
/// by the 1-based call number) or made to fail.
class _Photos implements ProgressPhotosRepository {
  _Photos(this.name);
  final String name;
  int saves = 0;
  final List<String> savedIds = [];
  final List<String> deleted = [];
  final Map<int, Completer<void>> holds = {};
  final Set<int> failOn = {};

  /// Any call at all, including reads.
  int touches = 0;

  @override
  Future<ProgressPhoto> save(Uint8List bytes,
      {required ProgressPhotoAngle angle, double? weightKg, String? note}) async {
    touches++;
    final n = ++saves;
    final hold = holds[n];
    if (hold != null) await hold.future;
    if (failOn.contains(n)) throw StateError('disk full on photo $n');
    final id = '${name}_p$n';
    savedIds.add(id);
    return ProgressPhoto(
      id: id,
      takenAt: DateTime(2026, 10, 14),
      storagePath: 'mem://$id',
      keyFingerprint: 'fp',
      angle: angle,
    );
  }

  @override
  Future<void> delete(String id) async {
    touches++;
    deleted.add(id);
  }

  @override
  Stream<List<ProgressPhoto>> watch() {
    touches++;
    return Stream.value(const []);
  }

  @override
  Future<Uint8List?> takeShot() async {
    touches++;
    return null;
  }

  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) async {
    touches++;
    throw StateError('no pixels');
  }
}

class _Scans implements ScanRepository {
  _Scans(this.name);
  final String name;
  final List<ScanRecord> saved = [];
  final List<String> deleted = [];
  int saveCalls = 0;
  Completer<void>? hold;
  int touches = 0;

  @override
  Future<void> save(ScanRecord r) async {
    touches++;
    saveCalls++;
    final h = hold;
    if (h != null) await h.future;
    saved.add(r);
  }

  @override
  Future<void> delete(String id) async {
    touches++;
    deleted.add(id);
    saved.removeWhere((r) => r.id == id);
  }

  @override
  Future<List<ScanRecord>> list() async {
    touches++;
    return const [];
  }
}

/// Shared harness: auth is a controllable stream, and the repository providers
/// resolve per signed-in uid exactly like production (A's fakes for user A,
/// "other" fakes for anyone else), so a write routed to the live account after
/// a switch would land in the `other*` fakes and be caught.
class _Rig {
  _Rig() {
    addTearDown(auth.close);
  }
  final auth = StreamController<AuthUser?>.broadcast();
  final camera = FakeScanCamera();
  final pops = _PopCounter();
  int nowMs = 0;

  Future<void> pump(WidgetTester t,
      {required ProgressPhotosRepository photosA,
      required ScanRepository scansA,
      required ProgressPhotosRepository photosOther,
      required ScanRepository scansOther,
      bool vetoPop = false}) async {
    String? uid(Ref ref) => ref.watch(authUserProvider).valueOrNull?.uid;
    await t.pumpWidget(ProviderScope(
      overrides: [
        // Replays user A first so the value exists whenever the provider is
        // first listened to, then follows the controllable stream.
        authUserProvider.overrideWith((ref) async* {
          yield _userA;
          yield* auth.stream;
        }),
        progressPhotosRepositoryProvider.overrideWith(
            (ref) => uid(ref) == _userA.uid ? photosA : photosOther),
        scanRepositoryProvider
            .overrideWith((ref) => uid(ref) == _userA.uid ? scansA : scansOther),
        scanReminderEnabledProvider.overrideWith(_NoopReminder.new),
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanCameraProvider.overrideWith((ref) => camera),
        scanSpeakerProvider.overrideWithValue(FakeSpeaker()),
        scanHapticsProvider.overrideWithValue(FakeHaptics()),
        scanClockProvider.overrideWithValue(() => nowMs),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        navigatorObservers: [pops],
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const Key('test.open'),
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => vetoPop
                      ? const PopScope(
                          canPop: false, child: ScanCaptureScreen())
                      : const ScanCaptureScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    // Subscribe to auth (like the running app does) so user A is delivered
    // before anything runs.
    final sub = ProviderScope.containerOf(t.element(find.byType(MaterialApp)))
        .listen(authUserProvider, (_, __) {});
    addTearDown(sub.close);
    await t.pump();
    await t.pump();
    await t.pump();
  }

  Future<void> frame(WidgetTester t, PoseFrame f) async {
    nowMs += 250;
    camera.ctrl.add(f);
    await t.pump();
    await t.pump();
  }

  Future<void> drive(WidgetTester t, PoseFrame f,
      {required bool Function() until}) async {
    final end = nowMs + 20000;
    while (!until() && nowMs < end) {
      await frame(t, f);
    }
  }

  /// Opens the screen and shoots all three poses, ending on the review page.
  Future<void> reachReview(WidgetTester t) async {
    await t.tap(find.byKey(const Key('test.open')));
    await t.pumpAndSettle();
    await drive(t, frontFrame(), until: () => camera.stills == 1);
    await drive(t, sideFrame(), until: () => camera.stills == 2);
    await t.tap(find.byKey(const Key('scan.facingAway')));
    await t.pump();
    await drive(t, backFrame(), until: () => camera.stills == 3);
    expect(find.byKey(const Key('scan.review')), findsOneWidget,
        reason: 'precondition: on the review page');
    pops.pops = 0;
  }

  Future<void> tapSave(WidgetTester t) async {
    await t.tap(find.byKey(const Key('scan.save')));
    await t.pump();
    await t.pump();
  }
}

Future<void> _flush(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump();
  }
}

/// F2: an aborted save pops the screen silently (it must not keep the old
/// account's photos on screen), so the expectation is exactly one pop and no
/// message of any kind.
Future<void> _expectSilent(WidgetTester t, _Rig r) async {
  await t.pumpAndSettle();
  expect(find.byType(SnackBar), findsNothing, reason: 'no snackbar of any kind');
  expect(r.pops.pops, 1, reason: 'the aborted screen pops itself, once');
  expect(find.byType(ScanCaptureScreen), findsNothing,
      reason: 'the screen is gone from the stack');
  expect(find.byKey(const Key('scan.saveError')), findsNothing,
      reason: 'no error text');
  expect(find.textContaining('was not saved'), findsNothing);
  expect(find.textContaining('Scan saved'), findsNothing);
}

void _expectNothingThroughOther(_Photos po, _Scans so) {
  expect(po.touches, 0, reason: 'the new account\'s photo repo is never used');
  expect(so.touches, 0, reason: 'the new account\'s scan repo is never used');
}

void main() {
  group('account changes during a scan save (fake repositories)', () {
    testWidgets('switch A -> B while the FIRST photo write is pending',
        (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[1] = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      expect(pa.saves, 1, reason: 'the first write is in flight');

      r.auth.add(_userB);
      await _flush(t);
      pa.holds[1]!.complete();
      await _flush(t);

      expect(pa.saves, 1, reason: 'no further photo write after the switch');
      expect(sa.saveCalls, 0);
      expect(sa.saved, isEmpty);
      expect(pa.deleted, ['A_p1'],
          reason: 'the photo written by this save is removed via A');
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets('switch A -> B while the SECOND photo write is pending',
        (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[2] = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      expect(pa.saves, 2, reason: 'first written, second in flight');

      r.auth.add(_userB);
      await _flush(t);
      pa.holds[2]!.complete();
      await _flush(t);

      expect(pa.saves, 2, reason: 'the third photo is never written');
      expect(sa.saveCalls, 0);
      expect(pa.deleted.toSet(), {'A_p1', 'A_p2'});
      expect(pa.deleted, hasLength(2));
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets(
        'account deleted / signed out (auth -> null) while the second photo '
        'write is pending', (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[2] = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      expect(pa.saves, 2);

      r.auth.add(null);
      await _flush(t);
      pa.holds[2]!.complete();
      await _flush(t);

      expect(pa.saves, 2);
      expect(sa.saveCalls, 0);
      expect(pa.deleted.toSet(), {'A_p1', 'A_p2'});
      expect(pa.deleted, hasLength(2));
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets('switch while the scan sidecar write itself is pending',
        (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      sa.hold = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      await _flush(t);
      expect(pa.saves, 3, reason: 'all photos written before the sidecar');
      expect(sa.saveCalls, 1, reason: 'the sidecar write is in flight');

      r.auth.add(_userB);
      await _flush(t);
      sa.hold!.complete();
      await _flush(t);

      expect(sa.saved, isEmpty,
          reason: 'the sidecar that just landed was removed again');
      expect(sa.deleted, hasLength(1), reason: 'sidecar deleted by its id');
      expect(pa.deleted.toSet(), {'A_p1', 'A_p2', 'A_p3'});
      expect(pa.deleted, hasLength(3));
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets('control: no account change -> normal save, unchanged',
        (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      await _flush(t);
      await t.pumpAndSettle();

      expect(pa.saves, 3, reason: 'exactly three photo writes');
      expect(sa.saveCalls, 1, reason: 'exactly one sidecar write');
      expect(sa.saved, hasLength(1));
      expect(sa.saved.single.shots.values.map((s) => s.photoId).toSet(),
          {'A_p1', 'A_p2', 'A_p3'});
      expect(pa.deleted, isEmpty);
      expect(sa.deleted, isEmpty);
      expect(find.text('Scan saved on this phone.'), findsOneWidget,
          reason: 'success snackbar');
      expect(r.pops.pops, 1, reason: 'the screen pops after a good save');
      expect(find.byType(ScanCaptureScreen), findsNothing);
      _expectNothingThroughOther(po, so);
    });

    testWidgets(
        'control: same-account failure on the second photo shows the error; '
        'the retry reuses the first photo', (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.failOn.add(2);
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      await _flush(t);

      expect(find.byKey(const Key('scan.saveError')), findsOneWidget,
          reason: 'a same-account failure is still reported');
      expect(find.textContaining('disk full on photo 2'), findsOneWidget);
      expect(pa.saves, 2);
      expect(pa.deleted, isEmpty,
          reason: 'a same-account failure keeps the first photo for the retry');
      expect(sa.saveCalls, 0);
      expect(r.pops.pops, 0);

      await r.tapSave(t);
      await _flush(t);
      await t.pumpAndSettle();

      expect(pa.saves, 4,
          reason: 'retry writes only the two missing photos (calls 3 and 4)');
      expect(sa.saved, hasLength(1));
      expect(sa.saved.single.shots[ScanPose.front]!.photoId, 'A_p1',
          reason: 'the first photo id is reused, not re-written');
      expect(sa.saved.single.shots.values.map((s) => s.photoId).toSet(),
          {'A_p1', 'A_p3', 'A_p4'});
      expect(pa.deleted, isEmpty);
      expect(find.text('Scan saved on this phone.'), findsOneWidget);
      expect(r.pops.pops, 1);
      _expectNothingThroughOther(po, so);
    });
  });

  group('F1/F2: account being deleted (auth still reports the same uid)', () {
    ProviderContainer containerOf(WidgetTester t) =>
        ProviderScope.containerOf(t.element(find.byType(MaterialApp)));

    testWidgets(
        'deletion flag set while the SECOND photo write is pending, auth '
        'unchanged: no sidecar, both photos deleted via A, silent, popped',
        (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[2] = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      expect(pa.saves, 2, reason: 'first written, second in flight');

      final c = containerOf(t);
      expect(c.read(authUserProvider).valueOrNull?.uid, _userA.uid);
      c.read(accountBeingDeletedUidProvider.notifier).state = _userA.uid;
      await _flush(t);
      // Precondition of the scenario: auth was NOT touched.
      expect(c.read(authUserProvider).valueOrNull?.uid, _userA.uid);
      pa.holds[2]!.complete();
      await _flush(t);

      expect(pa.saves, 2, reason: 'the third photo is never written');
      expect(sa.saveCalls, 0, reason: 'no sidecar is written');
      expect(sa.saved, isEmpty);
      expect(pa.deleted.toSet(), {'A_p1', 'A_p2'});
      expect(pa.deleted, hasLength(2));
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets(
        'deletion flag set while the sidecar write is pending: the sidecar '
        'and all three photos are removed', (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      sa.hold = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      await _flush(t);
      expect(sa.saveCalls, 1, reason: 'the sidecar write is in flight');

      containerOf(t).read(accountBeingDeletedUidProvider.notifier).state =
          _userA.uid;
      sa.hold!.complete();
      await _flush(t);

      expect(sa.saved, isEmpty);
      expect(sa.deleted, hasLength(1));
      expect(pa.deleted.toSet(), {'A_p1', 'A_p2', 'A_p3'});
      _expectNothingThroughOther(po, so);
      await _expectSilent(t, r);
    });

    testWidgets(
        'control: the deletion flag names ANOTHER uid -> this save is not '
        'aborted', (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[2] = Completer<void>();
      final r = _Rig();
      await r.pump(t,
          photosA: pa, scansA: sa, photosOther: po, scansOther: so);
      await r.reachReview(t);

      await r.tapSave(t);
      containerOf(t).read(accountBeingDeletedUidProvider.notifier).state =
          _userB.uid;
      pa.holds[2]!.complete();
      await _flush(t);
      await t.pumpAndSettle();

      expect(sa.saved, hasLength(1), reason: 'the save committed normally');
      expect(pa.deleted, isEmpty);
      expect(find.text('Scan saved on this phone.'), findsOneWidget);
      _expectNothingThroughOther(po, so);
    });

    testWidgets(
        'F2: after an abort the screen state is cleared (no photos, no '
        'review page, nothing to save or reuse)', (t) async {
      final pa = _Photos('A'), po = _Photos('B');
      final sa = _Scans('A'), so = _Scans('B');
      pa.holds[2] = Completer<void>();
      final r = _Rig();
      // The route vetoes the pop, so the screen survives the abort and its
      // state can be inspected.
      await r.pump(t,
          photosA: pa,
          scansA: sa,
          photosOther: po,
          scansOther: so,
          vetoPop: true);
      await r.reachReview(t);
      expect(find.byKey(const Key('scan.save')), findsOneWidget);

      await r.tapSave(t);
      containerOf(t).read(accountBeingDeletedUidProvider.notifier).state =
          _userA.uid;
      pa.holds[2]!.complete();
      await _flush(t);
      await t.pumpAndSettle();

      expect(pa.deleted.toSet(), {'A_p1', 'A_p2'});
      expect(find.byType(ScanCaptureScreen), findsOneWidget,
          reason: 'precondition: the pop was vetoed, the screen is alive');
      expect(find.byKey(const Key('scan.review')), findsNothing,
          reason: 'no review page of the old account\'s shots');
      expect(find.byKey(const Key('scan.save')), findsNothing,
          reason: 'nothing left to save or retry with the old ids');
      expect(find.byKey(const Key('scan.saveError')), findsNothing);
      expect(find.byType(SnackBar), findsNothing);
      expect(sa.saveCalls, 0);
      _expectNothingThroughOther(po, so);
    });
  });

  group('account wiped mid-save on REAL encrypted stores', () {
    testWidgets(
        'local wipe of A + switch to B while the second put is held: nothing '
        'of A is recreated, nothing of B is created', (t) async {
      final root = Directory.systemTemp.createTempSync('scan_switch_disk');
      addTearDown(() {
        if (root.existsSync()) root.deleteSync(recursive: true);
      });
      final docs = root;
      final photosRoot = Directory('${docs.path}/progress_photos');
      final dirA = Directory('${photosRoot.path}/${_userA.uid}');
      final dirB = Directory('${photosRoot.path}/${_userB.uid}');
      dirA.createSync(recursive: true); // as resolvePhotoDir would have

      final cipher = AesPhotoCipher(AesPhotoCipher.newKey());
      final secondPutGate = Completer<void>();

      final realA = _GatedDiskPhotos(
        t,
        LocalProgressPhotosRepository(
            store: PhotoStore(dir: dirA, cipher: cipher),
            source: _NoSource()),
        gates: {2: secondPutGate},
      );
      final scansA = _DiskScans(
          t,
          LocalScanRepository(
              () async => ScanStore(dir: dirA, cipher: cipher)));
      // B-owned stores point at B's folder: any write routed to the live
      // account after the switch would create it.
      final realB = _GatedDiskPhotos(
        t,
        LocalProgressPhotosRepository(
            store: PhotoStore(dir: dirB, cipher: cipher),
            source: _NoSource()),
        gates: const {},
      );
      final scansB = _DiskScans(
          t,
          LocalScanRepository(
              () async => ScanStore(dir: dirB, cipher: cipher)));

      final r = _Rig();
      await r.pump(t,
          photosA: realA,
          scansA: scansA,
          photosOther: realB,
          scansOther: scansB);
      await r.reachReview(t);

      await r.tapSave(t);
      // First put really completes on disk; the second is held.
      await _settleUntil(t, () => realA.entered >= 2);
      expect(realA.entered, 2);
      expect(_files(dirA, '.bin'), hasLength(1),
          reason: 'precondition: the first encrypted blob is on disk');

      // The account is deleted: the real device wipe runs, then the app moves
      // on to another account.
      SharedPreferences.setMockInitialValues(<String, Object>{});
      final prefs = await t.runAsync(SharedPreferences.getInstance);
      await t.runAsync(() => DeviceLocalDataWipe(
            prefs: prefs,
            documentsDir: docs,
            forgetPhotoKey: (_) async {},
          ).wipe(_userA.uid));
      expect(dirA.existsSync(), isFalse,
          reason: 'precondition: the wipe removed the whole account folder');
      r.auth.add(_userB);
      await _flush(t);

      // The held write now lands (recreating A's folder: that is the hazard),
      // and the save must clean up after itself.
      secondPutGate.complete();
      await _settleUntil(t, () => realA.deletes >= 2 && !_busy);
      await _drain(t);

      expect(realA.entered, 2, reason: 'no third photo write');
      expect(_files(dirA, '.bin'), isEmpty,
          reason: 'no encrypted blob survives for the deleted account');
      expect(_files(dirA, '.scan'), isEmpty, reason: 'no scan sidecar');
      final indexFile = File('${dirA.path}/index.json');
      if (indexFile.existsSync()) {
        expect(jsonDecode(indexFile.readAsStringSync()), isEmpty,
            reason: 'any index left behind references no photo');
      }
      expect(dirB.existsSync(), isFalse,
          reason: 'the new account\'s folder was never created');
      expect(realB.entered, 0);
      expect(realB.deletes, 0);
      expect(photosRoot.listSync().map((e) => e.uri.pathSegments
              .where((s) => s.isNotEmpty)
              .last),
          isNot(contains(_userB.uid)));
      await _expectSilent(t, r);
    });
  });
}

// ---- real-I/O helpers for the disk journey -------------------------------

class _NoSource implements PhotoSource {
  @override
  Future<Uint8List?> take() async => null;
}

final List<Future<Object?>> _pending = [];
bool get _busy => _pending.isNotEmpty;

/// Real I/O must run through `runAsync`; started futures are tracked so the
/// test can wait for them instead of re-entering runAsync.
Future<T?> _io<T>(WidgetTester t, Future<T> Function() fn) {
  final f = t.runAsync<T>(fn);
  _pending.add(f);
  return f;
}

Future<void> _settleUntil(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    if (_pending.isNotEmpty) {
      try {
        await _pending.removeAt(0);
      } catch (_) {}
    }
    await t.pump();
    await t.pump();
  }
}

Future<void> _drain(WidgetTester t) async {
  for (var i = 0; i < 50; i++) {
    while (_pending.isNotEmpty) {
      try {
        await _pending.removeAt(0);
      } catch (_) {}
      await t.pump();
      await t.pump();
    }
    await t.pump();
    if (_pending.isEmpty) break;
  }
}

List<File> _files(Directory d, String ext) => d.existsSync()
    ? d
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith(ext))
        .toList()
    : <File>[];

/// Real repository behind `runAsync`; the Nth `save` call waits on a gate
/// BEFORE touching the disk (the write is "held").
class _GatedDiskPhotos implements ProgressPhotosRepository {
  _GatedDiskPhotos(this.t, this.inner, {required this.gates});
  final WidgetTester t;
  final ProgressPhotosRepository inner;
  final Map<int, Completer<void>> gates;
  int entered = 0;
  int deletes = 0;

  @override
  Future<ProgressPhoto> save(Uint8List bytes,
      {required ProgressPhotoAngle angle,
      double? weightKg,
      String? note}) async {
    final n = ++entered;
    final gate = gates[n];
    if (gate != null) await gate.future;
    final v = await _io(
        t, () => inner.save(bytes, angle: angle, weightKg: weightKg, note: note));
    return v!;
  }

  @override
  Future<void> delete(String id) async {
    deletes++;
    await _io(t, () => inner.delete(id));
  }

  @override
  Stream<List<ProgressPhoto>> watch() => Stream.value(const []);
  @override
  Future<Uint8List?> takeShot() async => null;
  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) =>
      throw UnimplementedError();
}

class _DiskScans implements ScanRepository {
  _DiskScans(this.t, this.inner);
  final WidgetTester t;
  final ScanRepository inner;
  @override
  Future<List<ScanRecord>> list() async => (await _io(t, inner.list))!;
  @override
  Future<void> save(ScanRecord r) async {
    await _io(t, () => inner.save(r));
  }

  @override
  Future<void> delete(String id) async {
    await _io(t, () => inner.delete(id));
  }
}
