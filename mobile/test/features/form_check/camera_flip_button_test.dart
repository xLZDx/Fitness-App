import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/widgets/camera_flip_button.dart';
import '../../helpers/test_app.dart';

/// The coach and the posture screen both open the FRONT camera, and both want
/// the whole body in frame. At arm's length a selfie camera sees a torso; the
/// distance needed for head-to-heel means putting the phone down, at which
/// point the screen is unreadable. A mirror plus the back lens is the way out
/// of that, which is what this control is for.

class _FakeService implements PoseDetectorService {
  final ValueNotifier<SessionFacing> _facing =
      ValueNotifier<SessionFacing>(SessionFacing.front);
  int flips = 0;

  @override
  ValueListenable<SessionFacing> get facing => _facing;

  @override
  Future<void> flipCamera() async {
    flips++;
    _facing.value = _facing.value == SessionFacing.front
        ? SessionFacing.back
        : SessionFacing.front;
  }

  /// Deliberately never opens: the button must be readable and pressable
  /// before any camera exists.
  @override
  Stream<PoseFrame> frames() => const Stream.empty();
  @override
  Future<void> ensurePermission() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

Future<void> _pump(WidgetTester tester, _FakeService svc) {
  return tester.pumpWidget(MaterialApp(
    theme: AppTheme.dark(),
    locale: kTestLocale,
    localizationsDelegates: kTestLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: Scaffold(appBar: AppBar(actions: [CameraFlipButton(svc: svc)])),
  ));
}

void main() {
  testWidgets('tapping it flips the lens', (tester) async {
    final svc = _FakeService();
    await _pump(tester, svc);

    await tester.tap(find.byKey(const Key('camera.flip')));
    await tester.pump();

    expect(svc.flips, 1);
    expect(svc.facing.value, SessionFacing.back);
  });

  testWidgets('the label names where it will take you, not where you are',
      (tester) async {
    // A control that reports the current state is unreadable at a glance
    // mid-set; one that names its destination is.
    final svc = _FakeService();
    await _pump(tester, svc);
    final l10n = await AppLocalizations.delegate.load(kTestLocale);

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      l10n.cameraUseBackLens,
      reason: 'the front camera is open, so the offer is the back one',
    );

    await tester.tap(find.byKey(const Key('camera.flip')));
    await tester.pump();

    expect(
      tester.widget<Tooltip>(find.byType(Tooltip)).message,
      l10n.cameraUseFrontLens,
    );
  });

  testWidgets('it follows the camera that OPENED, not a tap', (tester) async {
    // A phone with one camera answers every request with the same lens.
    // `CameraSession` publishes what really opened for exactly this reason: a
    // label that flipped on the tap would claim a change the hardware never
    // made.
    final svc = _FakeService();
    await _pump(tester, svc);
    final l10n = await AppLocalizations.delegate.load(kTestLocale);

    svc._facing.value = SessionFacing.back;
    await tester.pump();

    expect(tester.widget<Tooltip>(find.byType(Tooltip)).message,
        l10n.cameraUseFrontLens);
    expect(svc.flips, 0, reason: 'nothing was tapped');
  });

  testWidgets('a detector with no camera still satisfies the interface',
      (tester) async {
    // The mixin exists because every implementation here uses `implements`,
    // which inherits no bodies. Concrete defaults on the abstract class
    // compiled and then failed at all five call sites.
    final replay = MockPoseDetectorService(const []);
    expect(replay.facing.value, SessionFacing.front);
    await expectLater(replay.flipCamera(), completes);
  });
}
