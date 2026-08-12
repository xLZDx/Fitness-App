import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart'
    show poseDetectorServiceProvider;
import 'package:fitness_app/features/posture/posture_page.dart';
import 'package:fitness_app/features/posture/state/posture_providers.dart';

/// `start()`/`stop()` resolve immediately -- that lifecycle is byte-for-byte
/// what `start_lifecycle_test.dart` already covers for Form Check (the two
/// screens share the exact same start/stop/retry code). This file is about
/// what R10 actually adds: the capture window and its per-metric results.
class _ImmediateService with NoCameraControls implements PoseDetectorService {
  final _frames = StreamController<PoseFrame>.broadcast();

  @override
  Stream<PoseFrame> frames() => _frames.stream;

  @override
  Future<void> ensurePermission() async {}

  @override
  Future<void> start() async {}

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async => _frames.close();

  void push(PoseFrame f) => _frames.add(f);
}

PoseLandmark _lm(LandmarkType type, double x, double y) =>
    PoseLandmark(type: type, x: x, y: y, likelihood: 0.95);

/// Shoulder height difference lands inside the typical band, hip height
/// difference lands in the mild band, and the ears sit far enough forward to
/// read as notable -- three different verdicts from one frame shape, so a
/// test that finds the right label in the right card is not just matching
/// on one lucky coincidence.
PoseFrame _frame(int t) => PoseFrame(timestampMs: t, landmarks: {
      LandmarkType.leftShoulder: _lm(LandmarkType.leftShoulder, 0.4, 0.314),
      LandmarkType.rightShoulder: _lm(LandmarkType.rightShoulder, 0.6, 0.3),
      LandmarkType.leftHip: _lm(LandmarkType.leftHip, 0.42, 0.5),
      LandmarkType.rightHip: _lm(LandmarkType.rightHip, 0.58, 0.5),
      LandmarkType.leftEar: _lm(LandmarkType.leftEar, 0.78, 0.15),
      LandmarkType.rightEar: _lm(LandmarkType.rightEar, 0.82, 0.15),
    });

void _phoneSized(WidgetTester t) {
  t.view.physicalSize = const Size(400, 1600);
  t.view.devicePixelRatio = 1.0;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
}

Widget _page(
  _ImmediateService svc, {
  Duration captureDuration = const Duration(milliseconds: 100),
}) =>
    ProviderScope(
      overrides: [
        poseDetectorServiceProvider.overrideWithValue(svc),
        postureCaptureDurationProvider.overrideWithValue(captureDuration),
      ],
      child: MaterialApp(
        theme: AppTheme.dark(),
        locale: const Locale('en'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: const PosturePage(),
      ),
    );

void main() {
  testWidgets('shows the start prompt before any capture, and the disclaimer',
      (t) async {
    _phoneSized(t);
    await t.pumpWidget(_page(_ImmediateService()));
    await t.pump();
    await t.pump();

    expect(find.byKey(const Key('posture.start')), findsOneWidget);
    expect(find.byKey(const Key('posture.capturing')), findsNothing);
    expect(find.byKey(const Key('posture.disclaimer')), findsOneWidget);
  });

  testWidgets('capturing shows the hold-still band, then a verdict per metric',
      (t) async {
    _phoneSized(t);
    final svc = _ImmediateService();
    await t.pumpWidget(_page(svc));
    await t.pump();
    await t.pump();

    await t.tap(find.byKey(const Key('posture.start')));
    await t.pump();
    expect(find.byKey(const Key('posture.capturing')), findsOneWidget);

    for (var i = 0; i < 6; i++) {
      svc.push(_frame(i));
      await t.pump(const Duration(milliseconds: 10));
    }
    await t.pump(const Duration(milliseconds: 150));
    await t.pump();

    expect(find.byKey(const Key('posture.capturing')), findsNothing);
    expect(find.byKey(const Key('posture.metric.shoulder_asymmetry.verdict')),
        findsOneWidget);
    expect(find.text('Typical range'), findsOneWidget);
    expect(find.byKey(const Key('posture.metric.pelvis_tilt.verdict')),
        findsOneWidget);
    expect(find.text('Mild variation'), findsOneWidget);
    expect(find.byKey(const Key('posture.metric.forward_head.verdict')),
        findsOneWidget);
    expect(find.text('Notable variation'), findsOneWidget);
    expect(find.byKey(const Key('posture.start')), findsOneWidget,
        reason: 'the button stays, relabelled to check again');
  });

  testWidgets('no frames in the window reports the honest empty state',
      (t) async {
    _phoneSized(t);
    final svc = _ImmediateService();
    await t.pumpWidget(_page(svc));
    await t.pump();
    await t.pump();

    await t.tap(find.byKey(const Key('posture.start')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 150));
    await t.pump();

    expect(find.byKey(const Key('posture.no_body')), findsOneWidget);
  });
}
