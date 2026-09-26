import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/pose_detector_service.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_roll_diagnostics.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';
import 'package:fitness_app/features/form_check/state/coach_phase_providers.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// Gate F1 phase 1: the camera-roll diagnosis must measure angles with a pinned
/// sign, decide by the rule written before the device run, and log exactly the
/// stance that preceded each completed rep.

PoseLandmark _lm(LandmarkType t, double x, double y, [double p = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: p);

/// A side-on body from named midline points, both sides on the same spot as in
/// a true profile.
PoseFrame _body(int ts, Map<String, (double, double)> pts) {
  final out = <LandmarkType, PoseLandmark>{};
  void pair(String k, LandmarkType l, LandmarkType r) {
    final v = pts[k]!;
    out[l] = _lm(l, v.$1, v.$2);
    out[r] = _lm(r, v.$1, v.$2);
  }

  pair('shoulder', LandmarkType.leftShoulder, LandmarkType.rightShoulder);
  pair('hip', LandmarkType.leftHip, LandmarkType.rightHip);
  pair('knee', LandmarkType.leftKnee, LandmarkType.rightKnee);
  pair('ankle', LandmarkType.leftAnkle, LandmarkType.rightAnkle);
  return PoseFrame(timestampMs: ts, landmarks: out);
}

const _centre = (0.33, 0.6);

/// Rotate a point about [_centre] so every vector's pinned angle grows by
/// [deg] — the definition of a camera roll under the convention.
(double, double) _rot((double, double) p, double deg) {
  final dx = p.$1 - _centre.$1, dy = p.$2 - _centre.$2;
  final r = math.sqrt(dx * dx + dy * dy);
  final a = math.atan2(dx, dy) + deg * math.pi / 180;
  return (_centre.$1 + r * math.sin(a), _centre.$2 + r * math.cos(a));
}

(double, double) _mirror((double, double) p) => (2 * _centre.$1 - p.$1, p.$2);

Map<String, (double, double)> _map(Map<String, (double, double)> pose,
        (double, double) Function((double, double)) f) =>
    {for (final e in pose.entries) e.key: f(e.value)};

/// A squat at the bottom, facing image-left, with a slight forward lean.
const _bottomLeft = <String, (double, double)>{
  'shoulder': (0.26, 0.45),
  'hip': (0.42, 0.70),
  'knee': (0.22, 0.68),
  'ankle': (0.25, 0.88),
};

/// Standing, facing image-left, leaning 3 degrees forward.
final _standLeft = <String, (double, double)>{
  'shoulder': (0.30 - 0.63 * math.sin(3 * math.pi / 180), 0.25),
  'hip': (0.30, 0.55),
  'knee': (0.30, 0.72),
  'ankle': (0.30, 0.88),
};

RollRep _repFrom(Map<String, (double, double)> stand,
    Map<String, (double, double)> bottom) {
  final seg = segmentAnglesOf(_body(0, bottom))!;
  return RollRep(
    facing: seg.facing,
    standingMedian: standingAxisAngle(_body(0, stand)),
    thigh: seg.thigh,
    shank: seg.shank,
  );
}

List<RollRep> _session(double rollDeg,
    {Map<String, (double, double)>? rightBottom}) {
  (double, double) roll((double, double) p) => _rot(p, rollDeg);
  final left = _repFrom(_map(_standLeft, roll), _map(_bottomLeft, roll));
  final right = _repFrom(
    _map(_map(_standLeft, _mirror), roll),
    _map(rightBottom ?? _map(_bottomLeft, _mirror), roll),
  );
  return [left, left, right, right];
}

void main() {
  group('segmentAngle: pinned sign', () {
    test('straight down is 0, toward +x positive, toward -x negative', () {
      expect(segmentAngle((0, 0), (0, 1)), closeTo(0, 1e-9));
      expect(segmentAngle((0, 0), (1, 0)), closeTo(90, 1e-9));
      expect(segmentAngle((0, 0), (-1, 0)), closeTo(-90, 1e-9));
      expect(segmentAngle((0, 0), (1, 1)), closeTo(45, 1e-9));
    });

    test('mirror negates, roll adds the same angle to every vector', () {
      const a = (0.3, 0.4), b = (0.1, 0.9);
      final base = segmentAngle(a, b);
      expect(segmentAngle(_mirror(a), _mirror(b)), closeTo(-base, 1e-9));
      expect(segmentAngle(_rot(a, 15), _rot(b, 15)), closeTo(base + 15, 1e-9));
      const c = (0.5, 0.5), d = (0.2, 0.55);
      expect(segmentAngle(_rot(c, 15), _rot(d, 15)),
          closeTo(segmentAngle(c, d) + 15, 1e-9));
    });

    test('facing follows which side of the hip the knee is on', () {
      expect(segmentAnglesOf(_body(0, _bottomLeft))!.facing, -1);
      expect(
          segmentAnglesOf(_body(0, _map(_bottomLeft, _mirror)))!.facing, 1);
    });
  });

  group('classifyRoll: the pre-registered rule', () {
    test('one pose mirrored across facings plus a +15 degree roll: CONFIRMED',
        () {
      final c = classifyRoll(_session(15));
      expect(c.verdict, RollVerdict.confirmed, reason: '$c');
      expect(c.delta, closeTo(15, 0.01));
      expect(c.thighDiff, lessThan(0.01));
      expect(c.shankDiff, lessThan(0.01));
    });

    test('the same pose with no roll: REFUTED, nothing to explain', () {
      final c = classifyRoll(_session(0));
      expect(c.verdict, RollVerdict.refuted, reason: '$c');
      expect(c.delta, closeTo(0, 0.01));
    });

    test('two different poses plus a roll: REFUTED', () {
      final deeper = Map.of(_map(_bottomLeft, _mirror))
        ..['knee'] = (0.48, 0.62);
      final c = classifyRoll(_session(15, rightBottom: deeper));
      expect(c.verdict, RollVerdict.refuted, reason: '$c');
    });

    test('fewer than 2 usable reps in a facing: INCONCLUSIVE', () {
      final s = _session(15);
      final unusable = RollRep(
          facing: s[3].facing,
          standingMedian: null,
          thigh: s[3].thigh,
          shank: s[3].shank);
      expect(classifyRoll([s[0], s[1], s[2], unusable]).verdict,
          RollVerdict.inconclusive);
      expect(classifyRoll(const []).verdict, RollVerdict.inconclusive);
    });
  });

  group('robustSummary', () {
    test('median of odd and even samples', () {
      expect(robustSummary([3, 1, 2])!.median, 2);
      expect(robustSummary([4, 1, 3, 2])!.median, 2.5);
      expect(robustSummary(const []), isNull);
    });

    test('one 40 degree outlier among 25 samples near 14 barely moves it', () {
      final s = robustSummary([...List.filled(24, 14.0), 40.0])!;
      expect((s.median - 14).abs(), lessThan(1),
          reason: 'a mean would move to 15.04');
      expect(s.n, 25);
      expect(s.max, 40);
    });
  });

  group('StandingWindow', () {
    PoseFrame still(int i) => _body(i, _standLeft);

    test('the first settle frames at the top never count', () {
      final w = StandingWindow();
      for (var i = 0; i < kStandingSettleFrames; i++) {
        w.onTopFrame(still(i));
      }
      expect(w.liveSamples, isEmpty);
      w.onTopFrame(still(99));
      expect(w.liveSamples, hasLength(1));
    });

    test('a moving hip does not count as standing', () {
      final w = StandingWindow();
      for (var i = 0; i < 40; i++) {
        final p = Map.of(_standLeft)..['hip'] = (0.30 + 0.02 * i, 0.55);
        w.onTopFrame(_body(i, p));
      }
      expect(w.liveSamples, isEmpty);
    });

    test('bounded to the latest samples', () {
      final w = StandingWindow();
      for (var i = 0; i < 200; i++) {
        w.onTopFrame(still(i));
      }
      expect(w.liveSamples, hasLength(kStandingWindowCapacity));
    });

    test('19 samples are insufficient, 20 are usable', () {
      expect(StandingSnapshot(List.filled(19, 1.0)).usable, isFalse);
      expect(StandingSnapshot(List.filled(20, 1.0)).usable, isTrue);
    });

    test('descent freezes the stance and clears the live window', () {
      final w = StandingWindow();
      for (var i = 0; i < 40; i++) {
        w.onTopFrame(still(i));
      }
      w.onDescentStarted();
      expect(w.liveSamples, isEmpty);
      final s = w.takeSnapshot()!;
      expect(s.samples, hasLength(40 - kStandingSettleFrames));
      expect(s.usable, isTrue);
      expect(w.takeSnapshot(), isNull, reason: 'handed over once');
    });

    test('reset discards a frozen snapshot', () {
      final w = StandingWindow();
      for (var i = 0; i < 40; i++) {
        w.onTopFrame(still(i));
      }
      w.onDescentStarted();
      w.reset();
      expect(w.takeSnapshot(), isNull);
    });
  });

  group('lifecycle through RepSessionController', () {
    late List<String> lines;
    late DebugPrintCallback saved;

    setUp(() {
      lines = [];
      saved = debugPrint;
      debugPrint = (String? m, {int? wrapWidth}) {
        if (m != null) lines.add(m);
      };
    });
    tearDown(() => debugPrint = saved);

    /// Standing at [hipY] with the shoulders shifted by [lean] — the lean sets
    /// a distinguishable standing axis per stance.
    PoseFrame stand(int ts, double hipY, {double lean = 0}) =>
        _body(ts, {
          'shoulder': (0.45 + lean, hipY - 0.28),
          'hip': (0.45, hipY),
          'knee': (0.45, 0.72),
          'ankle': (0.45, 0.90),
        });

    Future<(ProviderContainer, StreamController<PoseFrame>)> start() async {
      final frames = StreamController<PoseFrame>.broadcast();
      final c = ProviderContainer(overrides: [
        poseDetectorServiceProvider
            .overrideWith((_) => _Service(frames.stream)),
        voiceCoachProvider.overrideWith((_) => MockVoiceCoach()),
      ]);
      addTearDown(c.dispose);
      addTearDown(frames.close);
      c.read(repSessionControllerProvider);
      c.read(formFeedbackControllerProvider);
      c.read(coachPhaseControllerProvider.notifier).start();
      return (c, frames);
    }

    var ts = 0;
    Future<void> push(StreamController<PoseFrame> s, PoseFrame f) async {
      s.add(f);
      await Future<void>.delayed(Duration.zero);
    }

    Future<void> holdStand(StreamController<PoseFrame> s, int n,
        {double lean = 0}) async {
      for (var i = 0; i < n; i++) {
        await push(s, stand(ts += 100, 0.42, lean: lean));
      }
    }

    Future<void> squat(StreamController<PoseFrame> s,
        {double lean = 0, bool complete = true}) async {
      final bottom = complete ? 0.71 : 0.64;
      for (var h = 0.46; h < bottom; h += 0.04) {
        await push(s, stand(ts += 100, h, lean: lean));
      }
      for (var i = 0; i < 4; i++) {
        await push(s, stand(ts += 100, bottom, lean: lean));
      }
      for (var h = bottom - 0.03; h > 0.42; h -= 0.04) {
        await push(s, stand(ts += 100, h, lean: lean));
      }
    }

    List<String> segments() =>
        [for (final l in lines) if (l.contains('[rep]   segments')) l];

    test(
        'a completed rep logs the stance frozen at its descent; a rejected '
        'attempt never leaks into the next rep', () async {
      ts = 0;
      final (c, s) = await start();

      // Rep 1: a long, still stance, then a full squat.
      await holdStand(s, 35, lean: 0.02);
      await squat(s, lean: 0.02);
      await holdStand(s, 3, lean: 0.02);
      expect(c.read(repSessionControllerProvider).repCount, 1);
      expect(segments(), hasLength(1));
      expect(segments().single, contains('usable'));
      expect(segments().single, contains('n=${35 - kStandingSettleFrames}'),
          reason: 'exactly the pre-descent stance, not the bottom or ascent');

      // An attempt with a different stance that never reaches the bottom.
      await holdStand(s, 35, lean: -0.06);
      await squat(s, lean: -0.06, complete: false);
      await holdStand(s, 3);
      expect(c.read(repSessionControllerProvider).repCount, 1,
          reason: 'positive control: the attempt was rejected');
      expect(segments(), hasLength(1), reason: 'a rejection logs nothing');

      // Rep 2 with almost no stance: its line must not carry the rejected
      // attempt's samples.
      await squat(s);
      await holdStand(s, 3);
      expect(c.read(repSessionControllerProvider).repCount, 2);
      expect(segments(), hasLength(2));
      expect(segments().last, contains('insufficient'));
      expect(segments().last, isNot(contains('usable')));

      // A new set clears everything.
      await holdStand(s, 35, lean: 0.02);
      c.read(repSessionControllerProvider.notifier).resetSet();
      await squat(s);
      await holdStand(s, 3);
      expect(segments().last, contains('raw=[]'));
    });
  });
}

class _Service with NoCameraControls implements PoseDetectorService {
  _Service(this._stream);
  final Stream<PoseFrame> _stream;

  @override
  Stream<PoseFrame> frames() => _stream;
  @override
  Future<void> ensurePermission() async {}
  @override
  Future<void> start() async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
