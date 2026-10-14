import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_availability.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/progress_photos/data/progress_photo.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_access.dart';
import 'package:fitness_app/features/progress_photos/scan/scan_repository.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_capture_screen.dart';
import 'package:fitness_app/features/progress_photos/scan/ui/scan_ports.dart';
import 'package:fitness_app/features/progress_photos/state/progress_photos_providers.dart';
import '../../../../helpers/test_app.dart';
import 'scan_fakes.dart';

/// Records every write the capture screen could make.
class _Photos extends MockProgressPhotosRepository {
  int saves = 0;
  @override
  Future<ProgressPhoto> save(Uint8List bytes,
      {required ProgressPhotoAngle angle, double? weightKg, String? note}) {
    saves++;
    return super.save(bytes, angle: angle, weightKg: weightKg, note: note);
  }
}

class _Rig {
  final camera = FakeScanCamera();
  final speaker = FakeSpeaker();
  final haptics = FakeHaptics();
  final scans = FakeScanRepository();
  final photos = _Photos();
  int nowMs = 0;

  Future<void> pump(WidgetTester tester, {bool pushed = false}) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scanAccessProvider.overrideWithValue(ScanAccess.allowed),
        scanCameraProvider.overrideWith((ref) => camera),
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
                    onPressed: () => Navigator.of(ctx).push(
                        MaterialPageRoute<void>(
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

  Future<void> frame(WidgetTester tester, PoseFrame f, {int stepMs = 250}) async {
    nowMs += stepMs;
    camera.ctrl.add(f);
    await tester.pump();
    await tester.pump();
  }

  Future<void> drive(WidgetTester tester, PoseFrame f,
      {required bool Function() until, int limitMs = 20000}) async {
    final end = nowMs + limitMs;
    while (!until() && nowMs < end) {
      await frame(tester, f);
    }
  }
}

final _countdown = find.byKey(const Key('scan.countdown'));

void main() {
  group('camera permission denied', () {
    for (final reason in [
      CameraUnavailableReason.permissionDenied,
      CameraUnavailableReason.permissionPermanentlyDenied,
    ]) {
      testWidgets('${reason.name}: error state, no manual shutter, nothing saved',
          (tester) async {
        final r = _Rig()..camera.startError = CameraUnavailable(reason);
        await r.pump(tester);

        expect(r.camera.starts, 1);
        expect(find.byKey(const Key('scan.cameraError')), findsOneWidget);
        expect(find.textContaining(reason.name), findsOneWidget,
            reason: 'the typed reason must reach the user, not a generic text');
        expect(find.byKey(const Key('fake.preview')), findsNothing);
        expect(_countdown, findsNothing);
        final shutter = tester
            .widget<FilledButton>(find.byKey(const Key('scan.shutter')));
        expect(shutter.onPressed, isNull,
            reason: 'a shot cannot be taken without a camera');
        expect(r.camera.stills, 0);
        expect(r.photos.saves, 0);
        expect(r.scans.saved, isEmpty);
      });
    }
  });

  group('app lifecycle', () {
    testWidgets('pausing the app during the countdown cancels it',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => _countdown.evaluate().isNotEmpty);
      expect(_countdown, findsOneWidget, reason: 'precondition: counting down');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      await tester.pump();

      expect(_countdown, findsNothing,
          reason: 'a countdown must not stay on screen while the app is in the '
              'background');
      expect(r.camera.stills, 0);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
    });

    testWidgets(
        'no shot is taken from a countdown that was running when the app '
        'went to the background and came back later', (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => _countdown.evaluate().isNotEmpty);
      expect(_countdown, findsOneWidget);

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      // No frames arrive while backgrounded; wall time passes well beyond the
      // moment the shutter was due.
      r.nowMs += 30000;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await r.frame(tester, frontFrame());

      expect(r.camera.stills, 0,
          reason: 'the stale countdown must not fire a shot on resume');
      expect(_countdown, findsNothing);
      expect(r.photos.saves, 0);
      expect(r.scans.saved, isEmpty);
    });
  });

  group('partial set', () {
    testWidgets('two of three poses: no review, no save, nothing written',
        (tester) async {
      final r = _Rig();
      await r.pump(tester);
      await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
      await r.drive(tester, sideFrame(), until: () => r.camera.stills == 2);

      expect(r.camera.stills, 2);
      expect(find.byKey(const Key('scan.review')), findsNothing);
      expect(find.byKey(const Key('scan.save')), findsNothing,
          reason: 'saving is only offered once all three poses are shot');
      expect(r.photos.saves, 0);
      expect(r.scans.saved, isEmpty);
    });

    testWidgets('leaving with two poses captured writes and deletes nothing',
        (tester) async {
      final r = _Rig();
      await r.pump(tester, pushed: true);
      await tester.tap(find.byKey(const Key('test.open')));
      await tester.pumpAndSettle();
      await r.drive(tester, frontFrame(), until: () => r.camera.stills == 1);
      await r.drive(tester, sideFrame(), until: () => r.camera.stills == 2);

      await tester.tap(find.byKey(const Key('scan.close')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('scan.shutter')), findsNothing,
          reason: 'the screen is gone');
      expect(r.camera.stops, greaterThan(0), reason: 'camera released');
      expect(r.photos.saves, 0);
      expect(r.scans.saved, isEmpty);
    });
  });
}
