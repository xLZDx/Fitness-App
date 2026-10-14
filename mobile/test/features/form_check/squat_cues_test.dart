import 'dart:math' as math;

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/cue_text.dart';
import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/rep_counter.dart';
import 'package:fitness_app/features/form_check/data/voice_coach.dart';

import 'unscorable_frame_test.dart' show squatFrame;

/// Operator, 2026-10-14, real phone: the squat coach's voice was generic and
/// never said "round back" or "shallow squat". These pin the two specific cues:
/// the back-position rule (trunk fold at depth, with hysteresis) and the
/// shallow-depth fault on a completed repetition.

PoseLandmark _p(LandmarkType t, double x, double y, [double l = 0.95]) =>
    PoseLandmark(type: t, x: x, y: y, likelihood: l);

/// A side-on frame: knee level with the hip (parallel), shoulder placed
/// [leanDeg] off vertical above the hip. [hipKneeDy] > 0 lifts the knee ABOVE
/// the hip line (hip lower than knee); negative puts the hip above the knee.
PoseFrame _side(int ts, double leanDeg,
    {double hipKneeDy = 0.0, bool leftVisible = true}) {
  const torso = 0.25;
  final rad = leanDeg * math.pi / 180;
  const hx = 0.5, hy = 0.6;
  final lv = leftVisible ? 0.95 : 0.1;
  final rv = leftVisible ? 0.1 : 0.95;
  final sx = hx + torso * math.sin(rad);
  final sy = hy - torso * math.cos(rad);
  final ky = hy - hipKneeDy;
  return PoseFrame(timestampMs: ts, landmarks: {
    LandmarkType.leftShoulder: _p(LandmarkType.leftShoulder, sx, sy, lv),
    LandmarkType.leftHip: _p(LandmarkType.leftHip, hx, hy, lv),
    LandmarkType.leftKnee: _p(LandmarkType.leftKnee, hx + 0.2, ky, lv),
    LandmarkType.rightShoulder: _p(LandmarkType.rightShoulder, sx, sy, rv),
    LandmarkType.rightHip: _p(LandmarkType.rightHip, hx, hy, rv),
    LandmarkType.rightKnee: _p(LandmarkType.rightKnee, hx + 0.2, ky, rv),
  });
}

/// Feeds [leans] one frame each and returns what the rule said on each.
List<FormFeedback?> _run(SquatBackClassifier c, List<double> leans,
        {double hipKneeDy = 0.0, bool leftVisible = true}) =>
    [
      for (var i = 0; i < leans.length; i++)
        () {
          final f = _side(i * 40, leans[i],
              hipKneeDy: hipKneeDy, leftVisible: leftVisible);
          final r = evaluateGated([c], f);
          return r.worst;
        }(),
    ];

void main() {
  group('SquatBackClassifier', () {
    test('an upright squat never faults', () {
      final out = _run(SquatBackClassifier(), List.filled(30, 30.0));
      expect(out.every((f) => f == null || f.severity == 0), isTrue);
    });

    test('a rounded (folded) back faults, but only after the minimum frames',
        () {
      final out = _run(SquatBackClassifier(), List.filled(12, 72.0));
      final n = SquatBackClassifier.minFaultFrames;
      for (var i = 0; i < n - 1; i++) {
        expect(out[i], isNull, reason: 'frame $i is below the min-frames bar');
      }
      expect(out[n - 1], isNotNull);
      expect(out[n - 1]!.severity, 2);
      expect(out[n - 1]!.cueKey, FormCueKey.squatBackRounding);
      expect(out[n - 1]!.rule, 'squat.back');
      expect(out[n - 1]!.metric, closeTo(72, 0.5));
    });

    test('one jittery frame does not flicker the cue', () {
      // 4 bad frames, one good, 4 bad: the streak restarts, so it never fires.
      final leans = [
        ...List.filled(4, 72.0),
        30.0,
        ...List.filled(4, 72.0),
      ];
      final out = _run(SquatBackClassifier(), leans);
      expect(out.every((f) => f == null), isTrue);
    });

    test('hysteresis: stays on between the exit and enter thresholds, clears '
        'below the exit', () {
      final c = SquatBackClassifier();
      final out = _run(c, [
        ...List.filled(6, 72.0), // fires
        56.0, // between exit (50) and enter (60): still faulting
        44.0, // below exit: clears
      ]);
      expect(out[5], isNotNull);
      expect(out[6], isNotNull, reason: 'held by hysteresis');
      expect(out[7], isNull, reason: 'cleared below the exit threshold');
    });

    test('a fold while standing (hips high) is not a squat fault', () {
      // Hip well above the knee: hipKneeDy < 0 ... knee BELOW hip by 0.3 of 0.25
      // torso, i.e. a standing stance bending to reach the phone.
      final out = _run(SquatBackClassifier(), List.filled(12, 75.0),
          hipKneeDy: -0.3);
      expect(out.every((f) => f == null), isTrue);
    });

    test('side-on with only the RIGHT side visible still judges the fold', () {
      final out = _run(SquatBackClassifier(), List.filled(12, 72.0),
          leftVisible: false);
      expect(out.last, isNotNull);
      expect(out.last!.cueKey, FormCueKey.squatBackRounding);
    });

    test('it is allowed to fault, and names the hip as the fault vertex', () {
      final c = SquatBackClassifier();
      expect(c.canFault, isTrue);
      expect(c.faultVertex, LandmarkType.leftHip);
    });
  });

  group('words and voice', () {
    for (final locale in const ['en', 'ru']) {
      test('both new cues have text, an explanation and a rule name ($locale)',
          () async {
        TestWidgetsFlutterBinding.ensureInitialized();
        final l10n = await AppLocalizations.delegate.load(Locale(locale));
        for (final key in [
          FormCueKey.squatBackRounding,
          FormCueKey.squatDepthShallow,
        ]) {
          expect(formCueText(l10n, key).trim(), isNotEmpty);
          final fb = FormFeedback(rule: 'x', severity: 1, cueKey: key);
          expect(formFaultExplanation(l10n, fb)?.trim(), isNotEmpty,
              reason: '$key can fault, so it is explained');
        }
        expect(formRuleName(l10n, 'squat.back'), isNot('squat.back'));
      });
    }

    test('the RU cues say what the operator asked for', () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      final ru = await AppLocalizations.delegate.load(const Locale('ru'));
      expect(formCueText(ru, FormCueKey.squatBackRounding),
          contains('Спина'));
      expect(formCueText(ru, FormCueKey.squatDepthShallow),
          contains('Неглубокий'));
    });

    test('the voice gate lets both cues through (severity floor)', () async {
      final coach = MockVoiceCoach(
          resolveText: (k) => k.name); // identity: key name is the text
      await coach.cue(const FormFeedback(
          rule: 'squat.back',
          severity: 2,
          cueKey: FormCueKey.squatBackRounding));
      expect(coach.spoken, ['squatBackRounding']);
      coach.clear();
      await coach.cue(const FormFeedback(
          rule: 'squat.depth',
          severity: 1,
          cueKey: FormCueKey.squatDepthShallow));
      expect(coach.spoken, ['squatDepthShallow']);
    });
  });

  group('shallow depth on a completed repetition', () {
    // Old-unit squat signal (hip minus knee): knee fixed at 0.72, so hip 0.68
    // reaches the counting depth (-0.04) and hip 0.72 is parallel (0.0).
    const config = RepCounterConfig(fullDepthSignal: -0.01);

    List<PoseFrame> rep(double bottomHipY) {
      final out = <PoseFrame>[];
      var ts = 0;
      void add(double y) {
        out.add(squatFrame(ts, y));
        ts += 100;
      }

      for (var i = 0; i < 3; i++) {
        add(0.42);
      }
      for (var y = 0.46; y < bottomHipY; y += 0.04) {
        add(y);
      }
      add(bottomHipY);
      add(bottomHipY);
      for (var y = bottomHipY - 0.04; y > 0.42; y -= 0.04) {
        add(y);
      }
      for (var i = 0; i < 3; i++) {
        add(0.42);
      }
      return out;
    }

    RepCounter run(double bottomHipY, {RepCounterConfig cfg = config}) {
      final counter = RepCounter(config: cfg);
      for (final f in rep(bottomHipY)) {
        counter.update(f);
      }
      return counter;
    }

    test('a rep that is counted but stops above full depth is shallow', () {
      final c = run(0.70); // signal -0.02: counted, short of -0.01
      expect(c.repCount, 1);
      expect(c.reps.single.severityByRule['squat.depth'], 1);
      expect(c.reps.single.offendingRules, contains('squat.depth'));
      expect(c.sloppyReps, 1);
      expect(c.cleanReps, 0);
    });

    test('a rep that reaches full depth is not shallow', () {
      final c = run(0.74);
      expect(c.repCount, 1);
      expect(c.reps.single.severityByRule['squat.depth'] ?? 0, 0);
      expect(c.cleanReps, 1);
    });

    test('with no fullDepthSignal configured nothing changes (other movements)',
        () {
      final c = run(0.70, cfg: const RepCounterConfig());
      expect(c.repCount, 1);
      expect(c.reps.single.severityByRule['squat.depth'] ?? 0, 0);
    });
  });
}
