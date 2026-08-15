import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/safety/data/par_q.dart';

/// The screen, and the state this app did not have.
///
/// Before Gate M every path that could produce a session produced one. There
/// was no verdict, no refusal type, and therefore no test that could have
/// failed. The assertions here are ordered by how much they matter: the
/// fail-closed property first, because every other property is decoration if
/// silence reads as clearance.

Map<ParQQuestion, bool> _allNo() => {
      for (final q in ParQQuestion.values) q: false,
    };

void main() {
  group('fail-closed', () {
    test('an unanswered screen blocks', () {
      final v = screen(const {});
      expect(v.decision, SafetyDecision.blocked);
      expect(v.allowsTraining, isFalse);
      expect(v.reasons, hasLength(ParQQuestion.values.length));
      expect(v.reasons.every((r) => r.incomplete), isTrue);
    });

    test('ONE unanswered question blocks, however good the rest are', () {
      // The case a permissive default gets wrong. Six clean answers look like
      // a clear screen from any angle except this one.
      for (final missing in ParQQuestion.values) {
        final answers = _allNo()..remove(missing);
        final v = screen(answers);
        expect(v.decision, SafetyDecision.blocked,
            reason: 'leaving ${missing.name} unanswered must not pass');
        expect(v.reasons, [SafetyReason.incomplete(missing)]);
      }
    });

    test('unanswered and answered-yes are told apart', () {
      // Same decision, different thing to say to a person: one is a referral,
      // the other is a form to finish.
      final unanswered = screen(const {}).reasons.first;
      final answered = screen(_allNo()..[ParQQuestion.chestPain] = true)
          .reasons
          .first;

      expect(unanswered.incomplete, isTrue);
      expect(answered.incomplete, isFalse);
      expect(unanswered, isNot(answered));
    });

    test('kUnscreened is blocked', () {
      // Named constant used at every provider that has no profile yet. If this
      // ever became permissive, every signed-out and still-loading path would
      // silently start producing plans.
      expect(kUnscreened.decision, SafetyDecision.blocked);
    });
  });

  group('the decision rule', () {
    test('no to all seven clears', () {
      final v = screen(_allNo());
      expect(v.decision, SafetyDecision.clear);
      expect(v.reasons, isEmpty);
      expect(v.intensityCeiling, isNull,
          reason: 'a clear screen has no opinion about intensity. Returning '
              '1.0 here capped the user below the planner own 1.10 ceiling, '
              'so a clean bill of health made the app more cautious.');
    });

    test('a blocking answer refuses outright', () {
      for (final q in kBlockingQuestions) {
        final v = screen(_allNo()..[q] = true);
        expect(v.decision, SafetyDecision.blocked, reason: q.name);
        expect(v.allowsTraining, isFalse);
        expect(v.reasons, [SafetyReason.question(q)]);
      }
    });

    test('a non-blocking yes restricts rather than refusing', () {
      final nonBlocking =
          ParQQuestion.values.where((q) => !kBlockingQuestions.contains(q));
      expect(nonBlocking, isNotEmpty);

      for (final q in nonBlocking) {
        final v = screen(_allNo()..[q] = true);
        expect(v.decision, SafetyDecision.restricted, reason: q.name);
        expect(v.allowsTraining, isTrue);
        expect(v.intensityCeiling, isNotNull, reason: q.name);
        expect(v.intensityCeiling!, lessThan(1.0));
      }
    });

    test('blocking wins over restricting, and both are reported', () {
      final v = screen(_allNo()
        ..[ParQQuestion.otherChronicCondition] = true
        ..[ParQQuestion.medicallySupervisedOnly] = true);

      expect(v.decision, SafetyDecision.blocked);
      expect(
          v.reasons,
          containsAll([
            SafetyReason.question(ParQQuestion.medicallySupervisedOnly),
            SafetyReason.question(ParQQuestion.otherChronicCondition),
          ]),
          reason: 'the user is owed the whole picture, not the first stop');
    });

    test('the blocking set is short, and deliberately so', () {
      // A screen that blocks on everything is one users learn to lie to, and
      // one lie makes every other answer worthless. If this number grows, the
      // reasoning above it has to grow with it.
      expect(kBlockingQuestions, hasLength(2));
      expect(kBlockingQuestions,
          containsAll([
            ParQQuestion.chestPain,
            ParQQuestion.medicallySupervisedOnly,
          ]));
    });
  });

  group('output stability', () {
    test('reasons come back in question order, not in map order', () {
      // `answers` is whatever the caller built. A message whose bullet order
      // depends on the insertion order of a map cannot be reproduced from a
      // screenshot.
      final forward = <ParQQuestion, bool>{
        ParQQuestion.heartConditionOrHighBloodPressure: true,
        ParQQuestion.musculoskeletalProblem: true,
      };
      final backward = <ParQQuestion, bool>{
        ParQQuestion.musculoskeletalProblem: true,
        ParQQuestion.heartConditionOrHighBloodPressure: true,
      };
      for (final q in ParQQuestion.values) {
        forward.putIfAbsent(q, () => false);
        backward.putIfAbsent(q, () => false);
      }

      expect(screen(forward).reasons, screen(backward).reasons);
      expect(screen(forward).reasons.map((r) => r.question), [
        ParQQuestion.heartConditionOrHighBloodPressure,
        ParQQuestion.musculoskeletalProblem,
      ]);
    });

    test('every question is reachable by the screen', () {
      // Guards the one failure that has no symptom: a question added to the
      // enum, read by `screen`, and never rendered — every user blocked by a
      // question nobody was asked. The widget side of this is enforced by the
      // exhaustive switch in `parQQuestionText`; this side pins that no
      // question is silently ignored here.
      for (final q in ParQQuestion.values) {
        final v = screen(_allNo()..[q] = true);
        expect(v.reasons.map((r) => r.question), contains(q),
            reason: '${q.name} answered yes produced no reason at all');
      }
    });
  });
}
