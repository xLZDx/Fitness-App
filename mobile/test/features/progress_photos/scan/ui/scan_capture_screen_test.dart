import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_models.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_pose.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_capture_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

/// Camera that counts previews (= screen rebuilds) and can fail a still.
class _TestCamera extends FakeScanCamera {
  int previews = 0;
  bool failStill = false;

  @override
  Widget buildPreview(BuildContext context) {
    previews++;
    return super.buildPreview(context);
  }

  @override
  Future<Uint8List?> captureStill() async {
    if (failStill) throw StateError('still failed');
    return super.captureStill();
  }
}

class _ThrowingShutterHaptics extends FakeHaptics {
  @override
  void shutter() => throw StateError('haptics broke');
}

class _FailingScanRepository extends FakeScanRepository {
  @override
  Future<void> save(ScanRecord r) async => throw StateError('sidecar failed');
}

class _TrackingPhotos extends MockProgressPhotosRepository {
  final List<String> savedIds = [];
  final List<String> deletedIds = [];

  @override
  Future<ProgressPhoto> save(Uint8List bytes,
      {required ProgressPhotoAngle angle, double? weightKg, String? note}) async {
    final p = await super
        .save(bytes, angle: angle, weightKg: weightKg, note: note);
    savedIds.add(p.id);
    return p;
  }

  @override
  Future<void> delete(String id) async {
    deletedIds.add(id);
    await super.delete(id);
  }
}

class _Rig {
  _Rig({_TestCamera? camera, FakeHaptics? haptics, FakeScanRepository? scans})
      : camera = camera ?? _TestCamera(),
        haptics = haptics ?? FakeHaptics(),
        scans = scans ?? FakeScanRepository();

  final _TestCamera camera;
  final speaker = FakeSpeaker();
  final FakeHaptics haptics;
  final FakeScanRepository scans;
  final photos = _TrackingPhotos();
  int nowMs = 0;
  int cameraProviderDisposals = 0;

  Future<void> pump(WidgetTester tester,
      {ScanAccess access = ScanAccess.allowed, bool pushed = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scanAccessProvider.overrideWithValue(access),
        // overrideWith keeps the provider auto-dispose, like production.
        scanCameraProvider.overrideWith((ref) {
          ref.onDispose(() => cameraProviderDisposals++);
          return camera;
        }),
        scanSpeakerProvider.overrideWithValue(speaker),
        scanHapticsProvider.overrideWithValue(haptics),
        scanClockProvider.overrideWithValue(() => nowMs),
        scanRepositoryProvider.overrideWithValue(scans),
        progressPhotosRepositoryProvider.overrideWithValue(photos),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: kTestLocale,
        localizationsDelegates: kTestLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: pushed
            ? Builder(
                builder: (ctx) => Scaffold(
                  body: TextButton(
                    key: const Key('test.open'),
                    onPressed: () => Navigator.of(ctx).push(MaterialPageRoute<void>(
                        builder: (_) => const ScanCaptureScreen())),
                    child: const Text('open'),
                  ),
                ),
              )
            : const ScanCaptureScreen(),
      ),
    ));
    await tester.pump();
    await tester.pump();
  }

  /// Feeds [frame] every 250 ms until [until] is true (or the limit).
  Future<void> drive(WidgetTester tester, PoseFrame frame,
      {required bool Function() until, int limitMs = 20000}) async {
    final end = nowMs + limitMs;
    while (!until() && nowMs < end) {
      nowMs += 250;
      camera.ctrl.add(frame);
      await tester.pump();
      await tester.pump();
    }
  }
}

Finder _pill(String text) => find.descendant(
    of: find.byKey(const Key('scan.pose')), matching: find.text(text));

void main() {
  testWidgets('ready -> countdown -> shutter -> next pose', (tester) async {
    final r = _Rig();
    await r.pump(tester);
    expect(r.camera.starts, 1);
    expect(find.byKey(const Key('fake.preview')), findsOneWidget);

    await r.drive(tester, frontFrame(), until: () => r.nowMs >= 1250);
    expect(find.byKey(const Key('scan.countdown')), findsOneWidget);
    expect(r.haptics.ticks, greaterThan(0));
    expect(r.speaker.said, contains('3'));

    await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
    expect(r.camera.stills, 1);
    expect(r.haptics.shutters, 1);
    expect(find.byKey(const Key('scan.countdown')), findsNothing);
    expect(_pill('Side'), findsOneWidget);
  });

  testWidgets('countdown is cancelled when readiness is lost', (tester) async {
    final r = _Rig();
    await r.pump(tester);
    await r.drive(tester, frontFrame(), until: () => r.nowMs >= 1750);
    expect(find.byKey(const Key('scan.countdown')), findsOneWidget);

    await r.drive(tester, emptyFrame(), until: () => r.nowMs >= 2000);
    expect(find.byKey(const Key('scan.countdown')), findsNothing);
    expect(r.camera.stills, 0);
    expect(r.haptics.warns, 1);
  });

  testWidgets('hints are spoken once, not on every frame', (tester) async {
    final r = _Rig();
    await r.pump(tester);
    final small = body(h: 0.45, top: 0.25);
    await r.drive(tester, small, until: () => r.nowMs >= 3000);
    expect(r.speaker.said.where((s) => s.contains('closer')).length, 1);
    expect(find.text('Step a little closer.'), findsWidgets);
  });

  testWidgets('manual shutter works without readiness (after the timer)',
      (tester) async {
    final r = _Rig();
    await r.pump(tester);
    await tester.tap(find.byKey(const Key('scan.shutter')));
    await tester.pump();
    expect(r.camera.stills, 0, reason: 'the manual shutter no longer fires at once');
    for (var i = 0; i < kScanManualTimerDefault; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    expect(r.camera.stills, 1);
  });

  testWidgets('three poses -> review -> retake -> save', (tester) async {
    final r = _Rig();
    await r.pump(tester);
    await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
    await r.drive(tester, sideFrame(), until: () => r.camera.stills == 2);
    // The back step needs the explicit "facing away" confirmation.
    await tester.tap(find.byKey(const Key('scan.facingAway')));
    await tester.pump();
    await r.drive(tester, backFrame(), until: () => r.camera.stills == 3);
    expect(find.byKey(const Key('scan.review')), findsOneWidget);
    expect(r.camera.stops, greaterThan(0));

    await tester.tap(find.byKey(const Key('scan.retake.front')));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('scan.review')), findsNothing);
    expect(_pill('Front'), findsOneWidget);
    await r.drive(tester, frontFrame(), until: () => r.camera.stills == 4);
    expect(find.byKey(const Key('scan.review')), findsOneWidget);

    await tester.tap(find.byKey(const Key('scan.save')));
    await tester.pump();
    await tester.pump();
    expect(r.scans.saved, hasLength(1));
    final rec = r.scans.saved.single;
    expect(rec.shots.keys.toSet(), ScanPose.values.toSet());
    final front = rec.shots[ScanPose.front]!.landmarks;
    expect(front, isNotEmpty);
    expect(front.every((l) => l.x >= 0 && l.x <= 1), isTrue);
    expect(front.any((l) => l.name == LandmarkType.leftShoulder.name), isTrue);
  });

  testWidgets('back step does not fire on a visible face', (tester) async {
    final r = _Rig();
    await r.pump(tester);
    await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
    await r.drive(tester, sideFrame(), until: () => r.camera.stills == 2);
    await r.drive(tester, frontFrame(), until: () => false, limitMs: 6000);
    expect(r.camera.stills, 2);
  });

  testWidgets('camera failure is shown', (tester) async {
    final r = _Rig()..camera.startError = StateError('denied');
    await r.pump(tester);
    expect(find.byKey(const Key('scan.cameraError')), findsOneWidget);
  });

  testWidgets('the camera provider stays alive while mounted and is disposed '
      'after the screen is popped', (tester) async {
    final r = _Rig();
    await r.pump(tester, pushed: true);
    await tester.tap(find.byKey(const Key('test.open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('scan.shutter')), findsOneWidget);

    // Auto-dispose would fire here if nothing but `ref.read` held the camera.
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    expect(r.cameraProviderDisposals, 0,
        reason: 'camera must not be disposed under a mounted screen');

    await tester.tap(find.byKey(const Key('scan.close')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byKey(const Key('scan.shutter')), findsNothing);
    expect(r.cameraProviderDisposals, 1,
        reason: 'camera is released once the screen is gone');
  });

  testWidgets('a pose frame stream error shows the camera error state',
      (tester) async {
    final r = _Rig();
    await r.pump(tester);
    await r.drive(tester, frontFrame(), until: () => r.nowMs >= 1250);
    expect(find.byKey(const Key('scan.countdown')), findsOneWidget);

    r.camera.ctrl.addError(StateError('stream broke'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('scan.cameraError')), findsOneWidget);
    expect(find.byKey(const Key('scan.countdown')), findsNothing);
  });

  testWidgets('a capture that throws resets the busy flag', (tester) async {
    final r = _Rig(haptics: _ThrowingShutterHaptics());
    await r.pump(tester);
    // The shutter fires from the frame loop; haptics throw inside _capture.
    await r.drive(tester, frontFrame(), until: () => r.nowMs >= 6000);
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byKey(const Key('scan.shutter')));
    expect(button.onPressed, isNotNull,
        reason: '_capturing must be reset even when the capture body throws');
    expect(find.byType(SnackBar), findsOneWidget);
    expect(r.camera.stills, 0);
  });

  testWidgets('a failing still capture resets the busy flag', (tester) async {
    final r = _Rig(camera: _TestCamera()..failStill = true);
    await r.pump(tester);
    await tester.tap(find.byKey(const Key('scan.shutter')));
    for (var i = 0; i < kScanManualTimerDefault; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await tester.pump();
    await tester.pump();
    final button = tester.widget<FilledButton>(find.byKey(const Key('scan.shutter')));
    expect(button.onPressed, isNotNull);
    expect(find.byType(SnackBar), findsOneWidget);
  });

  testWidgets('a failed sidecar write removes the photos already written',
      (tester) async {
    final r = _Rig(scans: _FailingScanRepository());
    await r.pump(tester);
    await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
    await r.drive(tester, sideFrame(), until: () => r.camera.stills == 2);
    await tester.tap(find.byKey(const Key('scan.facingAway')));
    await tester.pump();
    await r.drive(tester, backFrame(), until: () => r.camera.stills == 3);

    await tester.tap(find.byKey(const Key('scan.save')));
    await tester.pump();
    await tester.pump();
    expect(r.photos.savedIds, hasLength(3));
    expect(r.photos.deletedIds.toSet(), r.photos.savedIds.toSet(),
        reason: 'no orphan photo may stay in the timeline');
    expect(find.byKey(const Key('scan.saveError')), findsOneWidget);
  });

  testWidgets('unchanged readiness does not rebuild the screen',
      (tester) async {
    final r = _Rig();
    await r.pump(tester);
    // The first cue is throttled until the 2 s live-region gap has passed and
    // then rebuilds ONCE (the stale-cue fix); after that nothing may rebuild.
    await r.drive(tester, emptyFrame(), until: () => r.nowMs >= 2500);
    final before = r.camera.previews;
    await r.drive(tester, emptyFrame(), until: () => r.nowMs >= 6000);
    expect(r.camera.previews, before,
        reason: 'identical evaluations must not call setState');
  });

  group('access gating', () {
    for (final c in {
      ScanAccess.underage: 'only available from age 18',
      ScanAccess.ageUnknown: 'Complete your profile',
      ScanAccess.needsSupporter: 'The guided scan is a Supporter',
      ScanAccess.needsConsent: 'privacy notice',
      ScanAccess.signedOut: 'Sign in',
    }.entries) {
      testWidgets('${c.key.name} shows a message and never opens the camera',
          (tester) async {
        final r = _Rig();
        await r.pump(tester, access: c.key);
        expect(find.byKey(Key('scan.gate.${c.key.name}')), findsOneWidget);
        expect(find.textContaining(c.value), findsOneWidget);
        expect(r.camera.starts, 0);
        expect(find.byKey(const Key('scan.shutter')), findsNothing);
      });
    }
  });
}
