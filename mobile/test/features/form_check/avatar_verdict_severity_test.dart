import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// A double standing in for [SquatDepthClassifier] / [DeadliftHipHingeClassifier]:
/// `canFault == false`, and its feedback carries a non-zero severity anyway.
/// No shipped rule does this today (both severity-0-only rules also happen to
/// always emit severity 0), which is exactly why a gate that read severity
/// alone would still pass every existing test while being wrong — this double
/// exists so the gate is provably reading `canFault`, not inferring it from
/// the number.
class _UnentitledButLoud implements FormClassifier {
  @override
  bool get canFault => false;

  @override
  String get rule => 'test.unentitled';

  @override
  Set<LandmarkType> get requiredLandmarks => const {};

  @override
  FormFeedback? evaluate(PoseFrame frame) => null;
}

FormFeedback _feedback(int severity, {String rule = 'pushup.alignment'}) =>
    FormFeedback(
      rule: rule,
      severity: severity,
      cueKey: FormCueKey.pushupAlignSagging,
    );

void main() {
  group('avatarVerdictSeverity', () {
    test('no active classifier: no verdict', () {
      expect(avatarVerdictSeverity(const [], _feedback(2)), isNull);
    });

    test('active classifier cannot fault: no verdict, even at severity 2', () {
      expect(
        avatarVerdictSeverity([SquatDepthClassifier()], _feedback(2)),
        isNull,
        reason: 'SquatDepthClassifier.canFault is false by design '
            '(camera-angle confound) -- a real severity value from it must '
            'never be painted as a verdict',
      );
      expect(
        avatarVerdictSeverity([DeadliftHipHingeClassifier()], _feedback(2)),
        isNull,
      );
    });

    test(
        'the gate reads canFault, not the severity number -- an unentitled '
        'classifier stays ungated even when its feedback is loud', () {
      expect(
        avatarVerdictSeverity([_UnentitledButLoud()], _feedback(2)),
        isNull,
        reason: 'a naive `feedback?.severity` gate with no canFault check '
            'would return 2 here, coloring the avatar red for a rule that is '
            'not entitled to raise an alarm at all',
      );
    });

    test('entitled classifier, no feedback yet: no verdict', () {
      expect(
        avatarVerdictSeverity([PushupAlignmentClassifier()], null),
        isNull,
      );
    });

    test(
        'stale feedback from a different rule is rejected, not painted as a '
        'verdict', () {
      // FormFeedbackController does not clear its state on an exercise
      // switch -- only on the next scorable frame. Squat is inactive here
      // (its feedback would be severity 0 anyway), so this reproduces the
      // real defect: pushup active, but the feedback in hand still belongs
      // to whatever ran before it.
      expect(
        avatarVerdictSeverity(
          [PushupAlignmentClassifier()],
          _feedback(0, rule: 'squat.depth'),
        ),
        isNull,
        reason: 'a naive `feedback?.severity` gate with no rule-identity '
            'check would paint the avatar green here off a stale squat '
            'reading, on an exercise switch with no fresh pushup frame yet',
      );
      expect(
        avatarVerdictSeverity(
          [PushupAlignmentClassifier()],
          _feedback(2, rule: 'deadlift.hip_hinge'),
        ),
        isNull,
      );
    });

    test('entitled classifier: severity passes through unchanged', () {
      expect(
        avatarVerdictSeverity([PushupAlignmentClassifier()], _feedback(0)),
        0,
      );
      expect(
        avatarVerdictSeverity([PushupAlignmentClassifier()], _feedback(1)),
        1,
      );
      expect(
        avatarVerdictSeverity([PushupAlignmentClassifier()], _feedback(2)),
        2,
      );
    });
  });
}
