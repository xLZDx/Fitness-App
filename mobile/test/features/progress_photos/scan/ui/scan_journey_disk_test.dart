// Body-scan journeys against the REAL encrypted stores on a temp directory:
// what the user does on screen, and what is (and is not) left on disk.
//
// Disk I/O is real, so every store call is routed through `tester.runAsync`
// by the thin wrappers below; the screens, providers, ports and the auto
// shutter run unchanged.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/notifications/notification_service.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
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
import 'package:fitness_app/features/progress_photos/scan/ui/scan_compare_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_gate_view.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

final _png = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');

/// Real-I/O futures started by the app under test; [settle] waits on them
/// instead of starting a second (re-entrant) runAsync.
final List<Future<Object?>> _pending = [];

int _running = 0;
final List<void Function()> _waiters = [];

/// Serialised: runAsync must never be re-entered, and the app issues
/// overlapping store calls (a delete invalidates the photo list, which reads).
/// Only STARTED calls are in [_pending]; queued ones start after a pump.
Future<T?> _io<T>(WidgetTester t, Future<T> Function() fn) async {
  while (_running > 0) {
    final c = Completer<void>();
    _waiters.add(c.complete);
    await c.future;
  }
  _running++;
  final f = t.runAsync<T>(fn);
  _pending.add(f);
  try {
    return await f;
  } finally {
    _running--;
    if (_waiters.isNotEmpty) _waiters.removeAt(0)();
  }
}

class _NoSource implements PhotoSource {
  @override
  Future<Uint8List?> take() async => null;
}

class _IoPhotos implements ProgressPhotosRepository {
  _IoPhotos(this.t, this.inner);
  final WidgetTester t;
  final ProgressPhotosRepository inner;
  @override
  Stream<List<ProgressPhoto>> watch() => Stream.fromFuture(
      _io(t, () => inner.watch().first).then((v) => v!));
  @override
  Future<Uint8List?> takeShot() => inner.takeShot();
  @override
  Future<ProgressPhoto> save(Uint8List bytes,
          {required ProgressPhotoAngle angle,
          double? weightKg,
          String? note}) =>
      _io(
              t,
              () => inner.save(bytes,
                  angle: angle, weightKg: weightKg, note: note))
          .then((v) => v!);
  @override
  Future<void> delete(String id) => _io(t, () => inner.delete(id));
  @override
  Future<Uint8List> bytesOf(ProgressPhoto photo) =>
      _io(t, () => inner.bytesOf(photo)).then((v) => v!);
}

class _IoScans implements ScanRepository {
  _IoScans(this.t, this.inner);
  final WidgetTester t;
  final ScanRepository inner;
  @override
  Future<List<ScanRecord>> list() => _io(t, inner.list).then((v) => v!);
  @override
  Future<void> save(ScanRecord r) => _io(t, () => inner.save(r));
  @override
  Future<void> delete(String id) => _io(t, () => inner.delete(id));
}

class _NoopReminder extends ScanReminderNotifier {
  @override
  bool build() => false;
  @override
  Future<ReminderOutcome?> sync({int? weekday, int? minutes}) async => null;
}

class _Disk {
  _Disk(this.t) {
    dir = Directory.systemTemp.createTempSync('scan_journey');
    addTearDown(() {
      if (dir.existsSync()) dir.deleteSync(recursive: true);
    });
    cipher = AesPhotoCipher(AesPhotoCipher.newKey());
    photoStore = PhotoStore(dir: dir, cipher: cipher);
    scanStore = ScanStore(dir: dir, cipher: cipher);
    photos = _IoPhotos(
        t,
        LocalProgressPhotosRepository(
            store: photoStore, source: _NoSource()));
    scans = _IoScans(
        t, LocalScanRepository(() async => ScanStore(dir: dir, cipher: cipher)));
  }
  final WidgetTester t;
  late final Directory dir;
  late final AesPhotoCipher cipher;
  late final PhotoStore photoStore;
  late final ScanStore scanStore;
  late final _IoPhotos photos;
  late final _IoScans scans;

  List<File> files(String ext) => dir.existsSync()
      ? dir
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith(ext))
          .toList()
      : <File>[];

  /// Anything at all on disk (photos, index, scans folder).
  List<FileSystemEntity> everything() =>
      dir.existsSync() ? dir.listSync(recursive: true) : <FileSystemEntity>[];

  Future<void> seed(String id, int day) => t.runAsync(() async {
        for (final p in ScanPose.ordered) {
          await photoStore.put(Uint8List.fromList([day, p.index, 7, 7]),
              takenAt: DateTime(2026, 9, day),
              id: '${id}_${p.name}',
              angle: ProgressPhotoAngle.values.byName(p.name));
        }
        await scanStore.save(ScanRecord(
          id: id,
          createdAt: DateTime(2026, 9, day),
          shots: {
            for (final p in ScanPose.ordered)
              p: ScanShot(photoId: '${id}_${p.name}', landmarks: const []),
          },
        ));
      });

  List<Override> overrides() => [
        progressPhotosRepositoryProvider.overrideWithValue(photos),
        scanRepositoryProvider.overrideWithValue(scans),
        scanReminderEnabledProvider.overrideWith(_NoopReminder.new),
      ];
}

/// Pumps while real I/O completes, until [done] holds (bounded).
Future<void> settle(WidgetTester t, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    if (_pending.isNotEmpty) {
      final f = _pending.removeAt(0);
      try {
        await f;
      } catch (_) {}
    }
    await t.pump();
    await t.pump();
  }
  await t.pump();
  await t.pump();
}

/// Lets in-flight store calls and the UI work that follows them finish.
Future<void> drain(WidgetTester t) async {
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

Widget _app(List<Override> o, Widget home) => ProviderScope(
      overrides: o,
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: home,
      ),
    );

final _countdown = find.byKey(const Key('scan.countdown'));
Finder _pill(String text) => find.descendant(
    of: find.byKey(const Key('scan.pose')), matching: find.text(text));

class _Capture {
  _Capture(this.disk);
  final _Disk disk;
  final camera = FakeScanCamera();
  final haptics = FakeHaptics();
  int nowMs = 0;

  List<Override> overrides() => [
        ...disk.overrides(),
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanCameraProvider.overrideWith((ref) => camera),
        scanSpeakerProvider.overrideWithValue(FakeSpeaker()),
        scanHapticsProvider.overrideWithValue(haptics),
        scanClockProvider.overrideWithValue(() => nowMs),
      ];

  Future<void> drive(WidgetTester t, PoseFrame f,
      {required bool Function() until, int limitMs = 20000}) async {
    final end = nowMs + limitMs;
    while (!until() && nowMs < end) {
      nowMs += 250;
      camera.ctrl.add(f);
      await t.pump();
      await t.pump();
    }
  }
}

void main() {
  setUp(() {
    // A previous test may have ended with store calls still queued.
    _pending.clear();
    _waiters.clear();
    _running = 0;
  });

  group('allowed user: capture journey on real encrypted storage', () {
    testWidgets(
        'not-ready frames never count down; ready starts; interruption resets; '
        'three poses in order; save writes 3 encrypted photos + 1 scan record',
        (t) async {
      final c = _Capture(_Disk(t));
      await t.pumpWidget(_app(c.overrides(), const ScanCaptureScreen()));
      await t.pump();
      await t.pump();

      // 1. Not-ready frames (nobody in view, then a body that is too small)
      //    never start the countdown or the shutter.
      await c.drive(t, emptyFrame(), until: () => c.nowMs >= 5000);
      await c.drive(t, body(h: 0.45, top: 0.25), until: () => c.nowMs >= 10000);
      expect(_countdown, findsNothing);
      expect(c.camera.stills, 0);
      expect(c.haptics.ticks, 0);
      expect(_pill('Front'), findsOneWidget);

      // 2. A ready, steady frame starts the countdown.
      await c.drive(t, frontFrame(),
          until: () => _countdown.evaluate().isNotEmpty);
      expect(_countdown, findsOneWidget);
      expect(c.camera.stills, 0);

      // 3. A not-ready frame in the middle resets it; the hold restarts from
      //    zero and the shot comes a full hold later, not immediately.
      c.nowMs += 250;
      c.camera.ctrl.add(emptyFrame());
      await t.pump();
      await t.pump();
      expect(_countdown, findsNothing);
      expect(c.camera.stills, 0);
      final interruptedAt = c.nowMs;
      c.nowMs += 250;
      c.camera.ctrl.add(frontFrame());
      await t.pump();
      await t.pump();
      expect(_countdown, findsNothing,
          reason: 'the countdown must not resume where it stopped');
      await c.drive(t, frontFrame(), until: () => c.camera.stills == 1);
      expect(c.camera.stills, 1);
      expect(c.nowMs - interruptedAt, greaterThanOrEqualTo(4000));

      // 4. Poses come in order: front, side, back (back needs confirmation).
      expect(_pill('Side'), findsOneWidget);
      await c.drive(t, sideFrame(), until: () => c.camera.stills == 2);
      expect(_pill('Back'), findsOneWidget);
      await t.tap(find.byKey(const Key('scan.facingAway')));
      await t.pump();
      await c.drive(t, backFrame(), until: () => c.camera.stills == 3);
      expect(find.byKey(const Key('scan.review')), findsOneWidget);

      // 5. Nothing is on disk until the review is confirmed.
      expect(c.disk.everything(), isEmpty,
          reason: 'photos stay in memory until Save');

      await t.tap(find.byKey(const Key('scan.save')));
      await settle(t, () => c.disk.files('.scan').isNotEmpty);
      await drain(t); // let the save finish

      // 6. Exactly 3 encrypted photos and one scan record.
      final bins = c.disk.files('.bin');
      expect(bins, hasLength(3));
      expect(c.disk.files('.scan'), hasLength(1));
      final index = await t.runAsync(c.disk.photoStore.index);
      expect(index!.map((p) => p.angle).toSet(), {
        ProgressPhotoAngle.front,
        ProgressPhotoAngle.side,
        ProgressPhotoAngle.back,
      });
      final byAngle = {for (final p in index) p.angle: p};
      for (final entry in {
        ProgressPhotoAngle.front: 1,
        ProgressPhotoAngle.side: 2,
        ProgressPhotoAngle.back: 3,
      }.entries) {
        final photo = byAngle[entry.key]!;
        final raw = File(photo.storagePath).readAsBytesSync();
        final plain = Uint8List.fromList([entry.value, 1, 2, 3]);
        expect(raw, isNot(plain), reason: 'blob must be an envelope');
        expect(raw.length, greaterThan(plain.length));
        final back = await t.runAsync(() => c.disk.photoStore.read(photo));
        expect(back, plain, reason: '${entry.key.name} shot decrypts intact');
      }
      final indexText = File('${c.disk.dir.path}/index.json').readAsStringSync();
      expect(indexText.toLowerCase().contains('landmark'), isFalse);

      final records = await t.runAsync(c.disk.scanStore.list);
      expect(records, hasLength(1));
      final rec = records!.single;
      expect(rec.shots.keys.toSet(), ScanPose.values.toSet());
      expect(rec.shots.values.map((s) => s.photoId).toSet(),
          index.map((p) => p.id).toSet(),
          reason: 'the record points at exactly the three saved photos');
      expect(rec.shots[ScanPose.front]!.landmarks, isNotEmpty);
      final sidecar =
          latin1.decode(c.disk.files('.scan').single.readAsBytesSync());
      expect(sidecar.contains(LandmarkType.leftShoulder.name), isFalse,
          reason: 'landmarks are encrypted inside the sidecar');
    });

    testWidgets('leaving mid-set writes nothing to disk', (t) async {
      final c = _Capture(_Disk(t));
      await t.pumpWidget(_app(
        c.overrides(),
        Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const Key('test.open'),
              onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                  builder: (_) => const ScanCaptureScreen())),
              child: const Text('open'),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('test.open')));
      await t.pumpAndSettle();
      await c.drive(t, frontFrame(), until: () => c.camera.stills == 1);
      await c.drive(t, sideFrame(), until: () => c.camera.stills == 2);
      expect(c.camera.stills, 2);

      await t.tap(find.byKey(const Key('scan.close')));
      await t.pumpAndSettle();
      await drain(t);

      expect(find.byKey(const Key('scan.shutter')), findsNothing);
      expect(c.disk.everything(), isEmpty,
          reason: 'no photo, index, or scan record from a half-finished set');
    });
  });

  group('gate refusals and deletion of saved scans', () {
    final refusals = {
      ScanAccess.signedOut: 'Sign in',
      ScanAccess.underage: 'only available from age 18',
      ScanAccess.ageUnknown: 'Complete your profile',
      ScanAccess.needsSupporter: 'Supporter benefit',
      ScanAccess.needsConsent: 'privacy notice',
    };

    testWidgets('each refusal shows its own, distinct message', (t) async {
      final texts = <String>{};
      for (final e in refusals.entries) {
        await t.pumpWidget(_app([
          scanRepositoryProvider.overrideWithValue(_IoScans(t, _MemScans())),
          scanReminderEnabledProvider.overrideWith(_NoopReminder.new),
        ], Scaffold(body: ScanGateView(access: e.key))));
        await t.pump();
        final msg = find.byKey(Key('scan.gate.${e.key.name}'));
        expect(msg, findsOneWidget, reason: e.key.name);
        final text = tester(t, msg);
        expect(text, contains(e.value), reason: e.key.name);
        texts.add(text);
        expect(find.byKey(const Key('scan.gate.deleteAll')), findsNothing,
            reason: 'no saved scans: no delete action');
      }
      expect(texts, hasLength(refusals.length));
    });

    for (final access in refusals.keys) {
      testWidgets(
          '${access.name}: "Delete my scans" removes every encrypted file',
          (t) async {
        final disk = _Disk(t);
        await disk.seed('scan_a', 1);
        await disk.seed('scan_b', 15);
        expect(disk.files('.bin'), hasLength(6));
        expect(disk.files('.scan'), hasLength(2));

        await t.pumpWidget(
            _app(disk.overrides(), Scaffold(body: ScanGateView(access: access))));
        await settle(t,
            () => find.byKey(const Key('scan.gate.deleteAll')).evaluate().isNotEmpty);
        expect(find.text('Delete my scans'), findsOneWidget);

        await t.tap(find.byKey(const Key('scan.gate.deleteAll')));
        await t.pumpAndSettle();
        await t.tap(find.byKey(const Key('scan.delete.confirm')));
        await settle(t, () => disk.files('.bin').isEmpty && disk.files('.scan').isEmpty);
        await drain(t);

        expect(disk.files('.bin'), isEmpty);
        expect(disk.files('.scan'), isEmpty);
        final left = await t.runAsync(disk.photoStore.index);
        expect(left, isEmpty, reason: 'the photo index is emptied too');
        expect(find.byKey(const Key('scan.gate.deleteAll')), findsNothing);
      });
    }
  });

  group('compare screen on saved scans', () {
    testWidgets(
        'side-by-side, slider and ghost modes; deleting one scan removes only '
        'its files', (t) async {
      t.view.physicalSize = const Size(800, 2400);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final disk = _Disk(t);
      await disk.seed('scan_old', 1);
      await disk.seed('scan_new', 20);

      await t.pumpWidget(_app([
        ...disk.overrides(),
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanShotBytesProvider.overrideWith((ref, id) async => _png),
      ], const ScanCompareScreen()));
      await settle(t,
          () => find.byKey(const Key('scan.compare.modes')).evaluate().isNotEmpty);

      expect(find.byKey(const Key('scan.compare.sideBySide')), findsOneWidget);
      await t.tap(find.text('Slider'));
      await t.pump();
      expect(find.byKey(const Key('scan.compare.slider')), findsOneWidget);
      await t.tap(find.text('Overlay'));
      await t.pump();
      expect(find.byKey(const Key('scan.compare.ghost')), findsOneWidget);

      // Delete the earlier (oldest) scan.
      await t.tap(find.byKey(const Key('scan.compare.delete.earlier')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('scan.delete.confirm')));
      await settle(t, () => disk.files('.scan').length == 1);
      await drain(t);

      final bins = disk.files('.bin').map((f) => f.uri.pathSegments.last).toSet();
      expect(bins, {for (final p in ScanPose.ordered) 'scan_new_${p.name}.bin'});
      expect(disk.files('.scan').single.uri.pathSegments.last, 'scan_new.scan');
      final records = await t.runAsync(disk.scanStore.list);
      expect(records!.map((r) => r.id), ['scan_new']);
    });
  });
}

String tester(WidgetTester t, Finder f) => t.widget<Text>(f).data ?? '';

class _MemScans implements ScanRepository {
  @override
  Future<List<ScanRecord>> list() async => const [];
  @override
  Future<void> save(ScanRecord r) async {}
  @override
  Future<void> delete(String id) async {}
}
