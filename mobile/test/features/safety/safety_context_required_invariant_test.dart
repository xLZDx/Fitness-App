import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// MVP1.G3 OBS-1 item 3 (CI: safety-invariant regression guard).
///
/// `buildPlan` and `ProgrammeBuildRequest` already make `SafetyContext`
/// `required` -- Dart's own type system makes an actual runtime bypass
/// uncompilable, which is why F014/F015 (pregnancy path, B5d bypass) could be
/// fixed this way in the first place. What is NOT guarded today is the
/// *invariant itself* regressing silently: someone drops `required` (or adds
/// a default), and every existing call site keeps compiling with a caller
/// that never has to think about safety again -- exactly the bug class this
/// item exists to catch before it ships.
///
/// The regex checks below read the actual source text at test time, so a
/// future edit that removes `required` fails HERE, with a message naming the
/// exact invariant, instead of failing silently (nothing else would notice --
/// the type still checks, it is just permissive again).
void main() {
  group('SafetyContext required-parameter invariant (source guard)', () {
    test('buildPlan still declares safety as a required parameter', () {
      final source =
          File('lib/features/ai_planner/data/plan_builder.dart')
              .readAsStringSync();
      expect(
        RegExp(r'required\s+SafetyContext\s+safety\s*,').hasMatch(source),
        isTrue,
        reason:
            'plan_builder.dart no longer declares `safety` as a required '
            'SafetyContext parameter on buildPlan(). This is the exact '
            'invariant that made F014/F015 fixable by construction -- a '
            'caller that forgets to screen must fail to compile, not fall '
            'through to an unscreened plan.',
      );
    });

    test(
        'ProgrammeBuildRequest still declares safety as a required '
        'constructor field', () {
      final source =
          File('lib/features/programmes/data/programme_builder.dart')
              .readAsStringSync();
      expect(
        RegExp(r'required\s+this\.safety\s*,').hasMatch(source),
        isTrue,
        reason:
            'programme_builder.dart no longer declares `safety` as a '
            'required field on ProgrammeBuildRequest. Same invariant as '
            'buildPlan(), same consequence: a caller that forgets to screen '
            'must fail to compile.',
      );
    });
  });

  group('SafetyContext required-parameter invariant (construction proof)',
      () {
    final cleared = SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
    );

    test('buildPlan runs to completion when a SafetyContext is supplied', () {
      // The point of this test is not the plan's content (that is
      // plan_builder_test.dart's job) -- it is that a caller which DOES pass
      // safety compiles and runs, proving the positive path this invariant
      // must not break while guarding the negative one above.
      final outcome = buildPlan(
        candidatePool: const [],
        deficit: const {},
        deload: const DeloadVerdict(
          shouldDeload: false,
          reasons: [],
          suggestedVolumeFactor: 1.0,
        ),
        safety: cleared,
      );
      expect(outcome, isA<PlanOutcome>());
    });

    test(
        'ProgrammeBuildRequest constructs when a SafetyContext is supplied',
        () {
      final spec = programmeSpecFor('strength_base');
      expect(spec, isNotNull,
          reason: 'strength_base is the template every other programme '
              'test in this repo relies on existing');
      final request = ProgrammeBuildRequest(
        spec: spec!,
        catalogue: const <ExerciseItem>[],
        safety: cleared,
        weeks: 8,
        daysPerWeek: 4,
      );
      expect(request.safety, same(cleared));
    });
  });
}
