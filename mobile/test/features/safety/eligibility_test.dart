import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// Gate N. The seven health fields stop being dead data, without becoming
/// guessed medical meaning.
///
/// The decision table below is the whole gate. Everything else in this file
/// guards one property each: that an unenforceable restriction is stated rather
/// than silently ignored, that the whole-person gate is separate from the
/// candidate filter, and that no path reads the free text.

ExerciseItem _ex(
  String id, {
  List<String> contra = const [],
  String? equipmentId,
  String? equipmentLabel,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: equipmentLabel,
      muscles: const ['chest'],
      primaryMuscles: const ['chest'],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 10,
      summary: '',
      steps: const [],
      contraindications: contra,
    );

SafetyVerdict _cleared() =>
    screen({for (final q in ParQQuestion.values) q: false});

SafetyContext _ctx({
  SafetyVerdict? screening,
  HealthFlags health = HealthFlags.empty,
  List<Injury> injuries = const [],
  EquipmentAccess? equipment,
}) =>
    SafetyContext(
      screening: screening ?? _cleared(),
      health: health,
      injuries: injuries,
      equipment: equipment,
    );

void main() {
  group('the decision table', () {
    // (what the user said, what the exercise loads) -> allowed?
    //
    // Written as a table rather than as a dozen prose tests because the thing
    // being asserted IS a table: nine restrictions crossed with nine region
    // tags. Prose cases would have covered four of them and read as though
    // they covered all.
    const cases = <(MovementRestriction, String, bool)>[
      (MovementRestriction.overhead, 'shoulder', false),
      (MovementRestriction.overhead, 'neck', false),
      (MovementRestriction.overhead, 'knee', true),
      (MovementRestriction.deepKneeFlexion, 'knee', false),
      (MovementRestriction.deepKneeFlexion, 'ankle', true),
      (MovementRestriction.loadedSpinalFlexion, 'lower_back', false),
      (MovementRestriction.loadedSpinalFlexion, 'upper_back', true),
      (MovementRestriction.spinalExtension, 'lower_back', false),
      (MovementRestriction.spinalExtension, 'upper_back', false),
      (MovementRestriction.wristLoading, 'wrist', false),
      (MovementRestriction.wristLoading, 'elbow', false),
      (MovementRestriction.wristLoading, 'hip', true),
      // The three the catalogue cannot express. They must NOT filter — there
      // is no tag to filter by — and the advisory covers the honesty.
      (MovementRestriction.impact, 'knee', true),
      (MovementRestriction.balance, 'ankle', true),
      (MovementRestriction.prolongedStanding, 'hip', true),
      (MovementRestriction.other, 'shoulder', true),
    ];

    for (final (restriction, tag, allowed) in cases) {
      test('${restriction.name} vs $tag -> ${allowed ? 'allowed' : 'blocked'}',
          () {
        final verdict = evaluateExercise(
          _ex('e', contra: [tag]),
          _ctx(health: HealthFlags(restrictions: {restriction})),
        );
        expect(verdict.isAllowed || verdict is Degraded, allowed);
      });
    }

    test('every restriction appears in the table above', () {
      // The table is only as good as its coverage. A restriction added to the
      // enum and not to the table would be untested, and the omission would be
      // invisible.
      expect(
        cases.map((c) => c.$1).toSet(),
        MovementRestriction.values.toSet(),
      );
    });
  });

  group('an unenforceable restriction is stated, not ignored', () {
    test('it produces an advisory rather than a filter', () {
      final context =
          _ctx(health: const HealthFlags(restrictions: {MovementRestriction.impact}));

      expect(context.advisories, [
        const EligibilityReason(BlockReason.unscreenableRestriction,
            restriction: MovementRestriction.impact),
      ]);
      expect(eligibleExercises([_ex('a'), _ex('b')], context), hasLength(2),
          reason: 'nothing to filter by means nothing filtered, and hiding the '
              'catalogue would be a different lie');
    });

    test('the candidate comes back Degraded, not Allowed', () {
      // The distinction that lets a surface attach the caveat. Collapsing it
      // into Allowed is how "we could not check this" becomes silence.
      final verdict = evaluateExercise(
        _ex('a'),
        _ctx(health: const HealthFlags(
            restrictions: {MovementRestriction.balance})),
      );
      expect(verdict, isA<Degraded>());
      expect(verdict.reasons.single.reason,
          BlockReason.unscreenableRestriction);
    });

    test('an enforceable restriction produces no advisory', () {
      final context = _ctx(
          health: const HealthFlags(
              restrictions: {MovementRestriction.deepKneeFlexion}));
      expect(context.advisories, isEmpty);
    });
  });

  group('the whole-person gate', () {
    test('post-operative restrictions stop everything', () {
      final c = _ctx(
          health: const HealthFlags(surgery: SurgeryStatus.underRestrictions));
      expect(c.allowsAnyTraining, isFalse);
      expect(c.wholePersonBlocks.map((r) => r.reason),
          contains(BlockReason.postSurgical));
    });

    test('being cleared after surgery does not', () {
      final c = _ctx(
          health: const HealthFlags(
              surgery: SurgeryStatus.clearedForNormalExercise));
      expect(c.allowsAnyTraining, isTrue);
    });

    test('"not sure" after surgery caps the dose without refusing', () {
      // Uncertainty is not a clean bill and not a diagnosis. Refusing would
      // punish honesty; ignoring it would waste the answer.
      final c = _ctx(health: const HealthFlags(surgery: SurgeryStatus.unsure));
      expect(c.allowsAnyTraining, isTrue);
      expect(c.intensityCeiling, 0.8);
    });

    test('a clinician advising against exercise stops everything', () {
      final c = _ctx(
          health: const HealthFlags(
              clinicianAdvice: ClinicianExerciseAdvice.advisedAgainstExercise));
      expect(c.allowsAnyTraining, isFalse);
    });

    test('it is NOT applied by the list filter', () {
      // The bug this split exists to prevent. The first version returned an
      // empty list from `eligibleExercises` when the gate was closed, which
      // rendered the Train tab as a catalogue with nothing in it — no
      // exercises, no reason, nothing to act on.
      final blocked = _ctx(screening: kUnscreened);
      expect(blocked.allowsAnyTraining, isFalse);
      expect(eligibleExercises([_ex('a')], blocked), hasLength(1),
          reason: 'the filter answers "which of these suit them", not '
              '"may they train" — the surface answers the second, out loud');
    });

    test('but it IS applied when a specific exercise is asked about', () {
      // A tap from the catalogue is a different question, and the one that
      // used to walk straight past the screening.
      final blocked = _ctx(screening: kUnscreened);
      final verdict = evaluateExercise(_ex('a'), blocked);
      expect(verdict, isA<Blocked>());
      expect(verdict.reasons.map((r) => r.reason),
          contains(BlockReason.screening));
    });
  });

  group('the intensity ceiling takes the lowest opinion', () {
    test('nothing to say -> no ceiling', () {
      expect(_ctx().intensityCeiling, isNull);
    });

    test('never asked a clinician is a margin, not a penalty', () {
      expect(
          _ctx(health: const HealthFlags(
                  clinicianAdvice: ClinicianExerciseAdvice.notAsked))
              .intensityCeiling,
          0.95);
    });

    test('a managed diagnosis sits between the two', () {
      expect(
          _ctx(health: const HealthFlags(
                  bloodPressure: BloodPressureStatus.managedWithClinician))
              .intensityCeiling,
          0.9);
    });

    test('two opinions resolve to the lower one', () {
      final c = _ctx(
        screening: screen({
          for (final q in ParQQuestion.values) q: false,
          ParQQuestion.otherChronicCondition: true,
        }),
        health: const HealthFlags(
            clinicianAdvice: ClinicianExerciseAdvice.notAsked),
      );
      expect(c.intensityCeiling, 0.8,
          reason: 'the screening cap, not the softer health one');
    });

    test('"I do not know" about blood pressure is not a clean bill', () {
      expect(
          _ctx(health: const HealthFlags(
                  bloodPressure: BloodPressureStatus.unsure))
              .intensityCeiling,
          0.8);
      expect(
          _ctx(health: const HealthFlags(
                  bloodPressure: BloodPressureStatus.noKnownIssue))
              .intensityCeiling,
          isNull);
    });
  });

  group('equipment runs through the one implementation', () {
    test('a home user with no chips gets no barbell work', () {
      final verdict = evaluateExercise(
        _ex('bench', equipmentId: 'bar', equipmentLabel: 'Barbell'),
        _ctx(equipment: const EquipmentAccess(location: TrainingLocation.home)),
      );
      expect(verdict, isA<Blocked>());
      expect(verdict.reasons.map((r) => r.reason),
          contains(BlockReason.equipment));
    });

    test('a surface with no equipment context does not filter', () {
      // Browsing is not being prescribed. Passing null is how a catalogue says
      // so, and it must not be confused with "owns nothing".
      final verdict = evaluateExercise(
        _ex('bench', equipmentId: 'bar', equipmentLabel: 'Barbell'),
        _ctx(),
      );
      expect(verdict.isAllowed, isTrue);
    });
  });

  group('the free text is out of reach', () {
    test('SafetyContext cannot see it', () {
      // Structural, not a comment. `SafetyContext` takes `HealthFlags`, which
      // has no conditions, medications, allergies or otherConcerns on it — so
      // a rule in this layer cannot read them however tempting it becomes.
      const flags = HealthFlags(restrictions: {MovementRestriction.overhead});
      expect(flags.toJson().keys, [
        'restrictions',
        'bloodPressure',
        'surgery',
        'clinicianAdvice',
        // F014. Added deliberately, and it belongs on this list rather than
        // beside it: the fence's whole job is that every key here is a CLOSED
        // answer set with no free text and no medical detail behind it, and
        // `ProfessionalGuidanceNeed` is two values plus null. If a future
        // change adds `trimester` or a due date, this assertion is where it
        // has to be argued for.
        'professionalGuidance',
      ]);
    });

    test('free text alone changes no decision', () {
      final withText = HealthHistory(
        conditions: const ['type 2 diabetes', 'hypertension'],
        medications: const ['metformin', 'ramipril'],
        otherConcerns: 'my shoulder hurts overhead',
        screening: {for (final q in ParQQuestion.values) q: false},
      );
      final context = SafetyContext(
        screening: screen(withText.screening),
        health: withText.flags,
      );

      expect(context.allowsAnyTraining, isTrue);
      expect(context.intensityCeiling, isNull);
      expect(
          evaluateExercise(_ex('press', contra: ['shoulder']), context)
              .isAllowed,
          isTrue,
          reason: 'the text names a shoulder problem and NOTHING may read it. '
              'The normalised chip is how that becomes a restriction.');
    });

    test('and the same user, having answered, is screened', () {
      final answered = HealthHistory(
        conditions: const ['type 2 diabetes'],
        screening: {for (final q in ParQQuestion.values) q: false},
        flags: const HealthFlags(
            restrictions: {MovementRestriction.overhead}),
      );
      final context = SafetyContext(
        screening: screen(answered.screening),
        health: answered.flags,
      );
      expect(
          evaluateExercise(_ex('press', contra: ['shoulder']), context),
          isA<Blocked>());
    });
  });

  group('normalisation state', () {
    test('nothing entered at all', () {
      expect(HealthHistory.empty.normalisation,
          HealthNormalisationState.notProvided);
    });

    test('free text from an older build, and no normalised answers', () {
      const legacy = HealthHistory(medications: ['ramipril']);
      expect(legacy.normalisation, HealthNormalisationState.legacyUnreviewed);
    });

    test('answered', () {
      const answered = HealthHistory(
        medications: ['ramipril'],
        flags: HealthFlags(surgery: SurgeryStatus.none),
      );
      expect(answered.normalisation, HealthNormalisationState.normalised);
    });

    test('an empty restriction set is not an answer', () {
      // "I have no movement restrictions" and "nobody asked me" produce the
      // same empty set, and only the three enums can tell them apart. Reading
      // the set as an answer would mark every untouched profile normalised.
      const noneTicked = HealthHistory(
        medications: ['ramipril'],
        flags: HealthFlags(restrictions: {}),
      );
      expect(noneTicked.normalisation,
          HealthNormalisationState.legacyUnreviewed);
    });
  });

  group('persistence', () {
    test('flags survive a round trip', () {
      const h = HealthHistory(
        flags: HealthFlags(
          restrictions: {
            MovementRestriction.overhead,
            MovementRestriction.impact,
          },
          bloodPressure: BloodPressureStatus.managedWithClinician,
          surgery: SurgeryStatus.clearedForNormalExercise,
          clinicianAdvice: ClinicianExerciseAdvice.limitsGiven,
        ),
      );
      expect(HealthHistory.fromJson(h.toJson()).flags, h.flags);
    });

    test('an unknown restriction name is dropped, not defaulted', () {
      final back = HealthFlags.fromJson(const {
        'restrictions': ['overhead', 'pregnancy', 42],
        'surgery': 'nope',
      });
      expect(back.restrictions, {MovementRestriction.overhead});
      expect(back.surgery, isNull,
          reason: 'every available default here is a claim about someone health');
    });

    test('a malformed block reads as unanswered', () {
      expect(HealthFlags.fromJson('nope'), HealthFlags.empty);
      expect(HealthFlags.fromJson(null), HealthFlags.empty);
    });

    test('a profile carrying only flags is not empty', () {
      // `isEmpty` decides whether the device-local block wins over the server
      // copy. A profile whose only content is the normalised answers would
      // have lost that and been overwritten by an unanswered one.
      const h = HealthHistory(flags: HealthFlags(surgery: SurgeryStatus.none));
      expect(h.isEmpty, isFalse);
    });
  });
}
