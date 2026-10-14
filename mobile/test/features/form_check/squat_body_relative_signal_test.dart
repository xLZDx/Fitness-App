import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/rep_signals.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Operator, 2026-10-14: squat depth and rep detection were wrong and flaky on a
/// real phone. The old signal was a raw hip-minus-knee difference in frame
/// fractions, so the same squat read differently at different phone heights and
/// distances. The live squat now counts on `squatBodyRelativeSignal` (torso
/// lengths). These tests pin: scale and height independence, the near-side-only
/// view, the two depth levels (counted vs shallow), and the spoken result.

const _torso = 0.28; // shoulder-to-hip length at scale 1
const _thigh = 0.25; // hip-to-knee length at scale 1

PoseLandmark _lm(LandmarkType t, double x, double y, double likelihood) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: likelihood);

/// A side-on body. [elevDeg] is how far the hip sits above the knee measured as
/// the thigh's angle off horizontal (85 standing, 0 parallel, negative below);
/// [leanDeg] the trunk off vertical. [scale] resizes the whole body about the
/// hip (the phone being further away) and [dy] shifts it (the phone being
/// higher or lower).
PoseFrame squatBody(
  int ts, {
  required double elevDeg,
  double leanDeg = 10,
  double scale = 1.0,
  double dy = 0.0,
  double nearLikelihood = 0.95,
  double? farLikelihood,
}) {
  const hx = 0.4, hy = 0.5;
  final e = elevDeg * math.pi / 180;
  final l = leanDeg * math.pi / 180;
  final kx = hx + scale * _thigh * math.cos(e);
  // Image y grows downward. Hip above knee (elev > 0) means knee.y > hip.y.
  final kneeY = hy + scale * _thigh * math.sin(e);
  final sx = hx + scale * _torso * math.sin(l);
  final sy = hy - scale * _torso * math.cos(l);
  final far = farLikelihood ?? nearLikelihood;
  return PoseFrame(timestampMs: ts, landmarks: {
    LandmarkType.leftShoulder:
        _lm(LandmarkType.leftShoulder, sx, sy + dy, nearLikelihood),
    LandmarkType.leftHip: _lm(LandmarkType.leftHip, hx, hy + dy, nearLikelihood),
    LandmarkType.leftKnee: _lm(LandmarkType.leftKnee, kx, kneeY + dy, nearLikelihood),
    LandmarkType.leftAnkle: _lm(LandmarkType.leftAnkle, kx,
        kneeY + scale * 0.25 + dy, nearLikelihood),
    LandmarkType.rightShoulder:
        _lm(LandmarkType.rightShoulder, sx, sy + dy, far),
    LandmarkType.rightHip: _lm(LandmarkType.rightHip, hx, hy + dy, far),
    LandmarkType.rightKnee: _lm(LandmarkType.rightKnee, kx, kneeY + dy, far),
  });
}

/// One repetition down to [bottomElev] and back, with the trunk at
/// [bottomLean] at the bottom.
List<PoseFrame> squatRep(
  int startMs, {
  required double bottomElev,
  double bottomLean = 20,
  double scale = 1.0,
  double dy = 0.0,
  double nearLikelihood = 0.95,
  double? farLikelihood,
}) {
  final out = <PoseFrame>[];
  var ts = startMs;
  void add(double elev, double lean) {
    out.add(squatBody(ts,
        elevDeg: elev,
        leanDeg: lean,
        scale: scale,
        dy: dy,
        nearLikelihood: nearLikelihood,
        farLikelihood: farLikelihood));
    ts += 100;
  }

  for (var i = 0; i < 4; i++) {
    add(85, 5);
  }
  const steps = 10;
  for (var i = 1; i <= steps; i++) {
    final t = i / steps;
    add(85 + (bottomElev - 85) * t, 5 + (bottomLean - 5) * t);
  }
  for (var i = 0; i < 6; i++) {
    add(bottomElev, bottomLean);
  }
  for (var i = steps - 1; i >= 0; i--) {
    final t = i / steps;
    add(85 + (bottomElev - 85) * t, 5 + (bottomLean - 5) * t);
  }
  for (var i = 0; i < 4; i++) {
    add(85, 5);
  }
  return out;
}

RepCounter _counter() => RepCounter(
    config: squatBodyRelativeConfig, signal: squatBodyRelativeSignal);

RepCounter _count(List<PoseFrame> frames) {
  final c = _counter();
  for (final f in frames) {
    c.update(f);
  }
  return c;
}

Future<(RepSessionState, MockVoiceCoach)> _session(List<PoseFrame> frames,
    {bool withTarget = false}) async {
  final svc = MockPoseDetectorService(frames);
  // Identity resolver: the spoken text is the cue key name.
  final coach = MockVoiceCoach();
  final container = ProviderContainer(overrides: [
    poseDetectorServiceProvider.overrideWithValue(svc),
    voiceCoachProvider.overrideWithValue(coach),
    if (!withTarget) poseTargetProvider.overrideWithValue(null),
    avatarModeProvider.overrideWith((_) => false),
  ]);
  addTearDown(container.dispose);
  container.read(repSessionControllerProvider);
  await svc.start();
  await pumpEventQueue();
  final state = container.read(repSessionControllerProvider);
  await svc.dispose();
  return (state, coach);
}

void main() {
  group('body-relative squat signal', () {
    test('the same squat counts and peaks identically at two camera '
        'distances and heights', () {
      final near = _count([
        for (var i = 0; i < 3; i++)
          ...squatRep(i * 10000, bottomElev: -5),
      ]);
      final far = _count([
        for (var i = 0; i < 3; i++)
          ...squatRep(i * 10000, bottomElev: -5, scale: 0.55, dy: 0.18),
      ]);
      expect(near.repCount, 3);
      expect(far.repCount, 3, reason: 'a smaller, lower body is the same squat');
      expect(far.reps.first.peakSignal,
          closeTo(near.reps.first.peakSignal, 0.02));
    });

    test('CONTRAST: the old raw signal changes with the same two views', () {
      final a = squatDepthSignal(squatBody(0, elevDeg: 85), 0.5)!;
      final b = squatDepthSignal(
          squatBody(0, elevDeg: 85, scale: 0.55, dy: 0.18), 0.5)!;
      expect((a - b).abs(), greaterThan(0.05),
          reason: 'this is the flakiness the new signal removes');
      final c = squatBodyRelativeSignal(squatBody(0, elevDeg: 85), 0.5)!;
      final d = squatBodyRelativeSignal(
          squatBody(0, elevDeg: 85, scale: 0.55, dy: 0.18), 0.5)!;
      expect(c, closeTo(d, 1e-9));
    });

    test('standing, parallel and below-parallel read in the documented range',
        () {
      final standing = squatBodyRelativeSignal(squatBody(0, elevDeg: 85), 0.5)!;
      final parallel = squatBodyRelativeSignal(squatBody(0, elevDeg: 0), 0.5)!;
      final below = squatBodyRelativeSignal(squatBody(0, elevDeg: -10), 0.5)!;
      expect(standing, lessThan(squatBodyRelativeConfig.topEnter));
      expect(parallel, closeTo(0, 1e-9));
      expect(below, greaterThan(0));
    });

    test('a side-on view with only the near side visible still counts', () {
      final c = _count(squatRep(0,
          bottomElev: -5, nearLikelihood: 0.95, farLikelihood: 0.1));
      expect(c.repCount, 1);
    });

    test('nothing is read when no side has shoulder, hip and knee', () {
      final f = squatBody(0,
          elevDeg: 85, nearLikelihood: 0.2, farLikelihood: 0.2);
      expect(squatBodyRelativeSignal(f, 0.5), isNull);
    });

    test('a shallow squat is still counted, but flagged below full depth', () {
      final shallow = _count(squatRep(0, bottomElev: 17));
      expect(shallow.repCount, 1, reason: 'thigh 17 deg off horizontal counts');
      expect(shallow.reps.single.peakSignal,
          lessThan(kSquatFullDepthSignal));
      expect(shallow.reps.single.severityByRule['squat.depth'], 1);

      final deep = _count(squatRep(0, bottomElev: -5));
      expect(deep.repCount, 1);
      expect(deep.reps.single.severityByRule['squat.depth'] ?? 0, 0);
    });

    test('a quarter squat is not a repetition at all', () {
      final c = _count(squatRep(0, bottomElev: 25));
      expect(c.repCount, 0);
    });
  });

  group('spoken result on the live controller', () {
    test('a shallow rep says shallow; a deep rep says nothing', () async {
      final (shallowState, shallowCoach) =
          await _session(squatRep(0, bottomElev: 17));
      expect(shallowState.repCount, 1);
      expect(shallowCoach.spoken, [FormCueKey.squatDepthShallow.name]);
      expect(shallowState.lastRepCue?.cueKey, FormCueKey.squatDepthShallow);

      final (deepState, deepCoach) = await _session(squatRep(0, bottomElev: -5));
      expect(deepState.repCount, 1);
      expect(deepCoach.spoken, isEmpty);
    });

    test('a deep rep with the trunk folded says round back', () async {
      final (state, coach) =
          await _session(squatRep(0, bottomElev: -5, bottomLean: 75));
      expect(state.repCount, 1);
      expect(coach.spoken, [FormCueKey.squatBackRounding.name]);
    });

    test('a deep, upright rep from a small far-away body says nothing',
        () async {
      final (state, coach) = await _session(
          squatRep(0, bottomElev: -5, scale: 0.55, dy: 0.18));
      expect(state.repCount, 1);
      expect(coach.spoken, isEmpty);
    });

    test('a half squat that returns up speaks the shallow cue, not a miss',
        () async {
      // Reaches -0.38 torso lengths: the lap starts, never reaches the
      // counting depth and is rejected as incomplete. With the silhouette
      // target on, the voice says "shallow", not the generic shape miss.
      final (state, coach) =
          await _session(squatRep(0, bottomElev: 25), withTarget: true);
      expect(state.repCount, 0);
      expect(state.lastReject, RepRejectReason.incomplete);
      expect(coach.spoken, [FormCueKey.squatDepthShallow.name]);
    });
  });
}
