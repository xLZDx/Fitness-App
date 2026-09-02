import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/form_check/data/form_classifier.dart';
import 'package:fitness_app/features/form_check/data/pose_landmark.dart';
import 'package:fitness_app/features/form_check/data/pose_target.dart' show kPoseMatchPassing;
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';

/// A double standing in for [SquatDepthClassifier] / [DeadliftHipHingeClassifier]:
/// `canFault == false`, and its feedback carries a non-zero severity anyway.
/// No shipped rule does this today (both severity-0-only rules also happen to
/// always emit severity 0), which is exactly why a gate that read severity
/// alone would still pass every existing test while being wrong — this double
/// exists so the gate is provably reading `canFault`, not inferring it from
/// the number.
class _UnentitledButLoud implements FormClassifier {

  /// No vertex: a test double has no angle to turn on, and a ring drawn on a
  /// joint no rule measured would point at nothing.
  @override
  LandmarkType? get faultVertex => null;
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

    // FORMCOACH_COORDINATE_UNIFICATION_2026-08-31: `matchScore` is the
    // fallback for exactly the classifiers the tests above show stay
    // ungated -- squat depth and hip hinge -- now that the target is drawn
    // at the avatar's own scale and scoring against it is legitimate there.
    group('matchScore fallback, for classifiers that cannot fault', () {
      test('no matchScore: unchanged, still no verdict', () {
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null),
          isNull,
        );
      });

      test('matchScore below the passing threshold: still no verdict', () {
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: kPoseMatchPassing - 0.01),
          isNull,
          reason: 'falling short of the target mid-rep is not a fault -- only '
              'a COMPLETED rep judged against it is (lastRepMissedTarget), so '
              'this must never paint red',
        );
      });

      test('matchScore at or above the passing threshold: severity 0 '
          '(correct)', () {
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: kPoseMatchPassing),
          0,
        );
        expect(
          avatarVerdictSeverity([DeadliftHipHingeClassifier()], null,
              matchScore: 1.0),
          0,
        );
      });

      test('an entitled classifier ignores matchScore entirely -- its own '
          'feedback always wins', () {
        expect(
          avatarVerdictSeverity(
            [PushupAlignmentClassifier()],
            _feedback(2),
            matchScore: 1.0,
          ),
          2,
          reason: 'a fault-capable classifier never falls back to the match '
              'score, even when one happens to be available',
        );
      });

      test('no active classifier at all: matchScore still cannot paint a '
          'verdict on its own', () {
        expect(
          avatarVerdictSeverity(const [], null, matchScore: 1.0),
          isNull,
        );
      });
    });

    group('the error half of the two overlay states', () {
      // Found by standing in front of the camera rather than by reading the
      // code. Thirteen squats on an S23: the skeleton was white on every
      // frame. Green needs a live match at or above the pass mark, and a body
      // descending into a squat is nowhere near the bottom target's shape for
      // most of the movement — while red had no source wired to it at all. So
      // the one shipped movement with a target and a rep counter could say
      // "correct" and "no opinion", never "wrong", with the cue card two
      // centimetres below it reading «Вы не дошли до силуэта».
      //
      // The doc comment had described this colour coming from the completed
      // rep since the gate was written. Only the argument was missing.

      test('a completed rep that missed the target paints the error colour',
          () {
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: 0.4, lastRepMissedTarget: true),
          2,
        );
      });

      test('and reaching the shape live overrules it, without waiting for the '
          'rep to end', () {
        // The interaction that makes this usable: miss a rep, get red, then
        // actually arrive in the shape and go green immediately rather than
        // standing in a correct position under a red body until the next rep
        // boundary.
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: 1.0, lastRepMissedTarget: true),
          0,
        );
      });

      test('a completed rep that reached it paints nothing on its own', () {
        // `false` is a real answer — the rep was judged and it passed — but the
        // live match is what says so, and mid-descent after a good rep there is
        // no claim to make. Not 0: that would paint the body green while the
        // user is standing at the top of the next rep, which is the
        // false-safety-signal this file exists to prevent.
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: 0.4, lastRepMissedTarget: false),
          isNull,
        );
      });

      test('no rep has completed yet, so there is nothing to report', () {
        expect(
          avatarVerdictSeverity([SquatDepthClassifier()], null,
              matchScore: 0.4, lastRepMissedTarget: null),
          isNull,
        );
      });

      test('a fault-capable classifier is untouched by it', () {
        // The push-up has its own verdict and must not be second-guessed by a
        // silhouette result belonging to a different rule.
        expect(
          avatarVerdictSeverity([PushupAlignmentClassifier()], null,
              matchScore: 0.4, lastRepMissedTarget: true),
          isNull,
          reason: 'no feedback from its own rule means no verdict, and a '
              'missed silhouette is not that rule speaking',
        );
      });

      test('and no classifier at all still paints nothing', () {
        expect(
          avatarVerdictSeverity(const [], null,
              matchScore: 0.4, lastRepMissedTarget: true),
          isNull,
        );
      });
    });
  });
}
