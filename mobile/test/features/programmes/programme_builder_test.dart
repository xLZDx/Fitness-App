import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/movement_role.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// Gate P. A programme is constructed and validated as a programme.
///
/// The tests assert INVARIANTS, never an expected list of exercise ids: the
/// catalogue is a purchased library that changes with every vendor update, and
/// a test pinned to today's ids would go red for a reason that has nothing to
/// do with programming.
///
/// The real catalogue is loaded from the shipped asset. That is deliberate and
/// it is the only way the central claim can be checked at all — "Strength Base
/// contains 14 distinct exercises, all of them yoga and sit-ups" is a fact
/// about 1,887 real rows, and a fixture of six invented ones cannot confirm or
/// refute it.

List<ExerciseItem> _catalogue() {
  final file = File('assets/data/exercises_vendor.json');
  expect(file.existsSync(), isTrue,
      reason: 'the shipped catalogue is the subject of this file');
  final raw = jsonDecode(file.readAsStringSync());
  final rows = <ExerciseItem>[];
  void walk(Object? node) {
    if (node is Map) {
      if (node.containsKey('id') && node.containsKey('steps')) {
        rows.add(ExerciseItem.fromJson(Map<String, dynamic>.from(node)));
      }
      node.values.forEach(walk);
    } else if (node is List) {
      node.forEach(walk);
    }
  }

  walk(raw);
  return rows;
}

SafetyContext _cleared({
  HealthFlags health = HealthFlags.empty,
  List<Injury> injuries = const [],
  EquipmentAccess? equipment,
}) =>
    SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
      health: health,
      injuries: injuries,
      equipment: equipment,
    );

ProgrammeBuildRequest _request({
  String templateId = 'strength_base',
  SafetyContext? safety,
  List<ExerciseItem>? catalogue,
  int weeks = 8,
  int daysPerWeek = 4,
  List<ExerciseItem> Function(MovementRole, List<ExerciseItem>)? rank,
}) =>
    ProgrammeBuildRequest(
      spec: programmeSpecFor(templateId)!,
      catalogue: catalogue ?? _catalogue(),
      safety: safety ?? _cleared(),
      weeks: weeks,
      daysPerWeek: daysPerWeek,
      rank: rank,
    );

void main() {
  late List<ExerciseItem> catalogue;

  setUpAll(() => catalogue = _catalogue());

  group('the catalogue supports role-based construction', () {
    test('the derivation classifies most of the shipped catalogue', () {
      // Measured, not assumed. If a vendor update drops coverage below what the
      // specs need, this is where it shows — before a programme quietly loses
      // a slot.
      final classified =
          catalogue.where((e) => movementRoleOf(e) != null).length;
      expect(catalogue, hasLength(1887),
          reason: 'the catalogue changed; re-measure before trusting the rest');
      expect(classified / catalogue.length, greaterThan(0.85),
          reason: 'measured at 89.7% when the rules were written');
    });

    test('every primary strength role has candidates', () {
      final pools = byMovementRole(catalogue);
      for (final role in kPrimaryStrengthRoles) {
        expect(pools[role], isNotNull, reason: role.name);
        expect(pools[role]!.length, greaterThan(10), reason: role.name);
      }
    });

    test('a split squat is single-leg, not a squat', () {
      // The rule-order case. "Split squat" contains "squat", and a programme
      // that counts it as one has no unilateral work at all while reporting
      // that it does.
      final splits = catalogue.where((e) =>
          e.title.toLowerCase().contains('split squat') &&
          // Excluding the stretches, which are mobility first by rule order —
          // "Bulgarian Split Squat Stretch" is a hip opener, not unilateral
          // strength work, and the rule that catches it is doing its job.
          !e.title.toLowerCase().contains('stretch') &&
          !e.isStretch);
      expect(splits, isNotEmpty);
      for (final e in splits) {
        expect(movementRoleOf(e), MovementRole.singleLeg, reason: e.title);
      }
    });

    test('a yoga pose is mobility, whatever its name contains', () {
      final poses =
          catalogue.where((e) => e.vendorGroup == 'Yoga').toList();
      expect(poses, isNotEmpty);
      for (final e in poses) {
        expect(movementRoleOf(e), MovementRole.mobility, reason: e.title);
      }
    });
  });

  group('Strength Base, before and after', () {
    test('it is now built from movement roles', () {
      final result = buildProgramme(_request());
      expect(result, isA<ProgrammeBuilt>());
      final report = reportOn((result as ProgrammeBuilt).sessions);

      // The shipped programme: 32 sessions, 14 distinct exercises, all of them
      // yoga poses, sit-ups and bicycle twists.
      expect(report.sessions, 32);
      expect(report.uniqueExercises, greaterThan(14),
          reason: 'the number the sequential filler managed across 32 sessions');
      expect(report.roles, containsAll(kPrimaryStrengthRoles),
          reason: 'a strength programme that trains no strength pattern is the '
              'defect this gate exists to remove');
    });

    test('no session is made only of mobility and core work', () {
      final built = buildProgramme(_request()) as ProgrammeBuilt;
      for (final s in built.sessions) {
        final primary =
            s.exercises.where((e) => kPrimaryStrengthRoles.contains(e.role));
        expect(primary, isNotEmpty,
            reason: 'week ${s.week} day ${s.dayIndex} is not a strength '
                'session');
      }
    });

    test('every declared role is trained at least twice a week', () {
      final built = buildProgramme(_request()) as ProgrammeBuilt;
      final spec = programmeSpecFor('strength_base')!;
      final report = reportOn(built.sessions);
      for (final role
          in spec.declaredRoles.intersection(spec.frequencyRoles)) {
        expect(report.weeklyFrequency[role] ?? 0,
            greaterThanOrEqualTo(spec.minWeeklyFrequencyPerRole),
            reason: role.name);
      }
    });

    test('weekly volume is counted in sets, not in cards', () {
      final built = buildProgramme(_request()) as ProgrammeBuilt;
      final report = reportOn(built.sessions);
      final spec = programmeSpecFor('strength_base')!;
      for (final entry in report.weeklySets.entries) {
        expect(entry.value, greaterThanOrEqualTo(spec.minWeeklySetsPerRole),
            reason: entry.key.name);
        expect(entry.value, lessThanOrEqualTo(spec.maxWeeklySetsPerRole),
            reason: entry.key.name);
      }
      // Sets, not sessions: four slots at four sets is sixteen, not four.
      expect(built.sessions.first.totalSets, 16);
    });

    test('the same exercise never appears twice in one session', () {
      final built = buildProgramme(_request()) as ProgrammeBuilt;
      for (final s in built.sessions) {
        final ids = s.exercises.map((e) => e.exercise.id).toList();
        expect(ids.toSet(), hasLength(ids.length),
            reason: 'week ${s.week} day ${s.dayIndex}');
      }
    });

    test('and the build is reproducible', () {
      // `List.sort` on the pools before any ranking. Without it the programme
      // would depend on catalogue iteration order and could not be reproduced
      // from a bug report.
      final a = buildProgramme(_request()) as ProgrammeBuilt;
      final b = buildProgramme(_request()) as ProgrammeBuilt;
      expect(
        a.sessions.map((s) => s.exercises.map((e) => e.exercise.id).toList()),
        b.sessions.map((s) => s.exercises.map((e) => e.exercise.id).toList()),
      );
    });
  });

  group('safety is inside the builder, not upstream of it', () {
    test('a blocked person gets a refusal, not a programme', () {
      final result = buildProgramme(_request(
          safety: SafetyContext(screening: kUnscreened)));
      expect(result, isA<ProgrammeRefused>());
      expect((result as ProgrammeRefused).findings.single.fault,
          ProgrammeFault.blockedBySafety);
    });

    test('an injury removes its exercises from every slot', () {
      final built = buildProgramme(_request(
        safety: _cleared(
            injuries: const [Injury(bodyPart: 'knee', type: 'strain')]),
      ));
      expect(built, isA<ProgrammeBuilt>());
      for (final s in (built as ProgrammeBuilt).sessions) {
        for (final e in s.exercises) {
          expect(e.exercise.contraindications, isNot(contains('knee')),
              reason: e.exercise.title);
        }
      }
    });

    test('a movement restriction does the same', () {
      final built = buildProgramme(_request(
        safety: _cleared(
            health: const HealthFlags(
                restrictions: {MovementRestriction.overhead})),
      ));
      if (built is ProgrammeBuilt) {
        for (final s in built.sessions) {
          for (final e in s.exercises) {
            expect(e.exercise.contraindications, isNot(contains('shoulder')),
                reason: e.exercise.title);
          }
        }
      } else {
        // Also acceptable: refusing because a slot became unfillable. What is
        // NOT acceptable is a programme containing overhead work.
        expect((built as ProgrammeRefused).findings.map((f) => f.fault),
            contains(ProgrammeFault.roleUnfillable));
      }
    });
  });

  group('personalisation may order, and may not decide', () {
    test('a ranker that reorders is obeyed', () {
      final built = buildProgramme(_request(
        rank: (role, pool) => pool.reversed.toList(),
      ));
      final plain = buildProgramme(_request());
      expect(built, isA<ProgrammeBuilt>());
      expect(
        (built as ProgrammeBuilt)
            .sessions
            .first
            .exercises
            .map((e) => e.exercise.id),
        isNot((plain as ProgrammeBuilt)
            .sessions
            .first
            .exercises
            .map((e) => e.exercise.id)),
      );
    });

    test('a ranker that INSERTS an exercise is ignored', () {
      // The invariant the ML/AI stage exists inside. A ranker is a permutation;
      // anything else is the safety boundary moving, and the deterministic list
      // is what gets built from.
      final smuggled = ExerciseItem(
        id: 'smuggled',
        title: 'Barbell Back Squat',
        equipmentId: 'rack',
        muscles: const ['quads'],
        primaryMuscles: const ['quads'],
        difficulty: ExerciseDifficulty.advanced,
        durationMinutes: 10,
        summary: '',
        steps: const [],
        contraindications: const ['knee'],
      );
      final built = buildProgramme(_request(
        safety: _cleared(
            injuries: const [Injury(bodyPart: 'knee', type: 'strain')]),
        rank: (role, pool) => [smuggled, ...pool],
      ));

      expect(built, isA<ProgrammeBuilt>());
      final ids = [
        for (final s in (built as ProgrammeBuilt).sessions)
          for (final e in s.exercises) e.exercise.id,
      ];
      expect(ids, isNot(contains('smuggled')));
    });

    test('a ranker that FORGES a row with the right id is ignored', () {
      // The hole an id-set check leaves. A ranker returns the same number of
      // rows carrying the same ids, so length and id set both match — and
      // every field on them is its own invention. Those objects are what the
      // rest of the builder would plan, validate and schedule, so
      // `validateProgramme` would be re-checking the ranker's forged
      // `contraindications` instead of the catalogue row.
      var forgedSeen = false;
      final built = buildProgramme(_request(
        // The same list the identity assertion below compares against — the
        // helper builds a fresh one per call otherwise.
        catalogue: catalogue,
        safety: _cleared(
            injuries: const [Injury(bodyPart: 'knee', type: 'strain')]),
        rank: (role, pool) => [
          for (final e in pool)
            () {
              forgedSeen = true;
              return ExerciseItem(
                id: e.id,
                title: e.title,
                equipmentId: e.equipmentId,
                muscles: e.muscles,
                primaryMuscles: e.primaryMuscles,
                difficulty: e.difficulty,
                durationMinutes: e.durationMinutes,
                summary: e.summary,
                steps: e.steps,
                // The forgery: a row the knee injury should have removed,
                // wearing the id of one that survived it.
                contraindications: const ['knee'],
              );
            }(),
        ],
      ));

      expect(forgedSeen, isTrue, reason: 'the ranker must actually have run');
      expect(built, isA<ProgrammeBuilt>());
      for (final session in (built as ProgrammeBuilt).sessions) {
        for (final e in session.exercises) {
          expect(e.exercise.contraindications, isNot(contains('knee')),
              reason: '${e.exercise.id}: a forged row reached the programme');
          expect(catalogue.any((c) => identical(c, e.exercise)), isTrue,
              reason: '${e.exercise.id} is not the catalogue object');
        }
      }
    });

    test('a ranker that DROPS the pool is ignored', () {
      final built = buildProgramme(_request(rank: (role, pool) => const []));
      expect(built, isA<ProgrammeBuilt>(),
          reason: 'an empty ranking must not empty the programme');
    });
  });

  group('the validator can say no', () {
    test('weekly sets are bounded for a role outside frequencyRoles too', () {
      // `volumeOutOfBand` is documented as "weekly programmed sets for a role
      // fall outside the configured band". It used to iterate the same set as
      // the frequency check — `declaredRoles ∩ frequencyRoles ∩ trainable` —
      // so with the default `kPrimaryStrengthRoles` neither core role's volume
      // was bounded at all, whatever was programmed.
      const spec = ProgrammeSpec(
        id: 'test',
        sessions: [
          SessionSpec(name: 'A', slots: [MovementRole.coreAntiExtension]),
        ],
        setsPerSlot: 99,
        minWeeklySetsPerRole: 1,
        maxWeeklySetsPerRole: 10,
        minSurvivingPrimaryRoles: 0,
      );
      final request = ProgrammeBuildRequest(
        spec: spec,
        catalogue: catalogue,
        safety: _cleared(),
        weeks: 1,
        daysPerWeek: 1,
      );
      final built = buildProgramme(request);
      final findings = built is ProgrammeBuilt
          ? built.adaptations
          : (built as ProgrammeRefused).findings;
      // 99 sets of core in one week, against a band of 1..10.
      expect(findings.map((f) => f.fault),
          contains(ProgrammeFault.volumeOutOfBand));
      expect(
          findings.where((f) => f.fault == ProgrammeFault.volumeOutOfBand).map(
              (f) => f.role),
          contains(MovementRole.coreAntiExtension));
    });

    test('an ineligible exercise inserted after construction is caught', () {
      // The check that must never fire in production, proved to fire when the
      // thing it guards against happens. This is how an AI review that edits a
      // finished plan gets caught rather than trusted.
      final request = _request(
        safety: _cleared(
            injuries: const [Injury(bodyPart: 'knee', type: 'strain')]),
      );
      final tampered = [
        PlannedSession(
          week: 0,
          dayIndex: 0,
          specName: 'A',
          exercises: [
            PlannedExercise(
              exercise: ExerciseItem(
                id: 'x',
                title: 'Back Squat',
                equipmentId: null,
                muscles: const ['quads'],
                primaryMuscles: const ['quads'],
                difficulty: ExerciseDifficulty.beginner,
                durationMinutes: 10,
                summary: '',
                steps: const [],
                contraindications: const ['knee'],
              ),
              role: MovementRole.squat,
              sets: 4,
            ),
          ],
        ),
      ];

      final findings =
          validateProgramme(tampered, request.spec, request);
      expect(findings.map((f) => f.fault),
          contains(ProgrammeFault.ineligibleExerciseIncluded));
    });

    test('an empty session is caught', () {
      final request = _request();
      final findings = validateProgramme(
        const [PlannedSession(
            week: 0, dayIndex: 0, specName: 'A', exercises: [])],
        request.spec,
        request,
      );
      expect(findings.map((f) => f.fault),
          contains(ProgrammeFault.emptySession));
    });

    test('a role mislabelled on a placed exercise is caught', () {
      final request = _request();
      final squat = catalogue
          .firstWhere((e) => movementRoleOf(e) == MovementRole.squat);
      final findings = validateProgramme(
        [
          PlannedSession(week: 0, dayIndex: 0, specName: 'A', exercises: [
            PlannedExercise(
                exercise: squat, role: MovementRole.verticalPull, sets: 3),
          ]),
        ],
        request.spec,
        request,
      );
      expect(findings.map((f) => f.fault),
          contains(ProgrammeFault.roleUnfillable));
    });
  });

  group('adversarial profiles', () {
    test('A: beginner, bodyweight only, knee limitation', () {
      final result = buildProgramme(_request(
        templateId: 'gym_start',
        weeks: 6,
        daysPerWeek: 3,
        safety: _cleared(
          equipment: const EquipmentAccess(location: TrainingLocation.home),
          health: const HealthFlags(
              restrictions: {MovementRestriction.deepKneeFlexion}),
        ),
      ));

      // Either outcome is acceptable; a fabricated plan is not.
      if (result is ProgrammeBuilt) {
        for (final s in result.sessions) {
          for (final e in s.exercises) {
            expect(e.exercise.contraindications, isNot(contains('knee')));
            expect(e.exercise.needsEquipment, isFalse,
                reason: '${e.exercise.title} needs kit this user has not got');
          }
        }
      } else {
        expect((result as ProgrammeRefused).findings, isNotEmpty);
      }
    });

    test('B: intermediate, full gym, shoulder restriction', () {
      final result = buildProgramme(_request(
        safety: _cleared(
          equipment: const EquipmentAccess(location: TrainingLocation.gym),
          health: const HealthFlags(
              restrictions: {MovementRestriction.overhead}),
        ),
      ));
      if (result is ProgrammeBuilt) {
        for (final s in result.sessions) {
          for (final e in s.exercises) {
            expect(e.exercise.contraindications, isNot(contains('shoulder')));
          }
        }
      } else {
        expect((result as ProgrammeRefused).findings, isNotEmpty);
      }
    });

    test('C: advanced, limited equipment, no health restrictions', () {
      final result = buildProgramme(_request(
        safety: _cleared(
          equipment: const EquipmentAccess(
            location: TrainingLocation.home,
            available: [EquipmentKind.dumbbells],
          ),
        ),
      ));
      expect(result, isNotNull);
      if (result is ProgrammeBuilt) {
        expect(result.sessions, isNotEmpty);
      }
    });

    test('D: the screening blocks vigorous exercise', () {
      final result = buildProgramme(_request(
        safety: SafetyContext(
          screening: screen({
            for (final q in ParQQuestion.values) q: false,
            ParQQuestion.chestPain: true,
          }),
        ),
      ));
      expect(result, isA<ProgrammeRefused>());
    });

    test('E: too few eligible exercises to satisfy the constraints', () {
      // Fails EXPLICITLY. The old builder would have produced a programme of
      // one exercise repeated, and reported success.
      final result = buildProgramme(_request(
        catalogue: [
          catalogue.firstWhere((e) => movementRoleOf(e) == MovementRole.squat),
        ],
      ));
      expect(result, isA<ProgrammeRefused>());
      expect((result as ProgrammeRefused).findings.map((f) => f.fault),
          contains(ProgrammeFault.roleUnfillable));
    });

    test('F: an empty catalogue does not crash', () {
      final result = buildProgramme(_request(catalogue: const []));
      expect(result, isA<ProgrammeRefused>());
    });

    test('G: zero weeks does not crash', () {
      final result = buildProgramme(_request(weeks: 0));
      expect(result, isA<ProgrammeRefused>());
    });
  });

  /// G-E — every shipped template has a declared structure, and the
  /// alphabetical fallback is gone.
  ///
  /// `programmeSpecFor` returning null was the ONLY thing that routed an
  /// enrolment to `buildProgrammeSchedule`, whose `_fillDay` walked the
  /// catalogue in alphabetical order (F021) and repeated three of four
  /// exercises between consecutive days (F022). Specs for the last three
  /// templates remove the branch rather than patching the filler.
  group('G-E: every shipped template builds from a spec', () {
    test('no shipped template falls through to a null spec', () {
      // The guard on the whole gate. A template added later without a spec
      // fails here rather than silently reaching a filler that no longer
      // exists.
      for (final t in programmeTemplates) {
        expect(programmeSpecFor(t.id, daysPerWeek: t.daysPerWeek), isNotNull,
            reason: '${t.id} has no declared role structure');
      }
    });

    test('the questionnaire-built programme has one for every day count it '
        'can be given', () {
      // `from_answers` is minted by `programmeFromProfile`, not listed in
      // `programmeTemplates`, so the loop above cannot see it. Its day count
      // is whatever the user ticked: the questionnaire offers 2..6
      // (`step_schedule.dart`) and `programmeDaysPerWeek` floors at 1, so 1..6
      // is the reachable range.
      for (final days in const [1, 2, 3, 4, 5, 6]) {
        expect(programmeSpecFor(kProfileProgrammeId, daysPerWeek: days),
            isNotNull,
            reason: '$days days a week');
      }
    });

    test('a week longer than any declared structure refuses rather than '
        'repeating a session', () {
      // 7 is not reachable from the product. It is null on purpose and not by
      // omission: enrolment turns it into `noDeclaredStructure`, which is a
      // true statement, where stretching the six-day shape over seven days
      // would repeat a session every week — the exact defect that shipped in
      // G-E's own first draft for `shred_endurance`.
      expect(programmeSpecFor(kProfileProgrammeId, daysPerWeek: 7), isNull);
      expect(programmeSpecFor('strength_base', daysPerWeek: 0), isNull);
    });

    test('a structure has exactly as many sessions as the week has days', () {
      // The invariant behind both of the above, stated once. A shape with
      // fewer sessions than days makes `buildProgramme`'s rolling cursor
      // repeat one every week, and `duplicateSession` then refuses the
      // enrolment for anyone whose eligible pool is too narrow to disguise it.
      for (final days in const [1, 2, 3, 4, 5, 6]) {
        for (final id in programmeSpecIds) {
          expect(programmeSpecFor(id, daysPerWeek: days)!.sessions, hasLength(days),
              reason: '$id at $days days a week');
        }
      }
    });

    test('every id builds at every day count it can be asked for', () {
      // Having a structure is not the same as being buildable. A five-day
      // `shred_endurance` returned a spec and then refused every enrolment,
      // and only a build proved it.
      for (final days in const [1, 2, 3, 4, 5, 6]) {
        for (final id in programmeSpecIds) {
          final result = buildProgramme(ProgrammeBuildRequest(
            spec: programmeSpecFor(id, daysPerWeek: days)!,
            catalogue: catalogue,
            safety: _cleared(),
            weeks: 4,
            daysPerWeek: days,
          ));
          expect(result, isA<ProgrammeBuilt>(),
              reason: '$id at $days days a week: '
                  '${result is ProgrammeRefused ? result.findings : ''}');
        }
      }
    });

    test('every shipped template actually builds against the real catalogue',
        () {
      // Having a spec is not the same as being buildable. This is what would
      // catch a spec whose frequency rules the shipped catalogue cannot meet
      // -- which would turn a working enrolment into a refusal for every user.
      for (final t in programmeTemplates) {
        final result = buildProgramme(ProgrammeBuildRequest(
          spec: programmeSpecFor(t.id, daysPerWeek: t.daysPerWeek)!,
          catalogue: catalogue,
          safety: _cleared(),
          weeks: t.weeks,
          daysPerWeek: t.daysPerWeek,
        ));
        expect(result, isA<ProgrammeBuilt>(), reason: t.id);
      }
    });

    test('F021: a week of strength covers at least four primary roles', () {
      // The plan's own acceptance criterion. The filler this replaces walked
      // the catalogue alphabetically, so a "strength" week could be yoga
      // poses and sit-ups.
      final result = buildProgramme(_request(daysPerWeek: 4, weeks: 1));
      final built = result as ProgrammeBuilt;
      final roles = <MovementRole>{
        for (final s in built.sessions)
          for (final e in s.exercises)
            if (kPrimaryStrengthRoles.contains(e.role)) e.role,
      };
      expect(roles.length, greaterThanOrEqualTo(4),
          reason: 'covered ${roles.map((r) => r.name)}');
    });

    test('F022: consecutive sessions overlap by at most one exercise', () {
      // The three-of-four repetition, stated as the plan states it. Measured
      // pairwise across a whole 8-week enrolment rather than on one pair, so
      // a rotation that only drifts apart later still has to hold at week 1.
      final built = buildProgramme(_request(daysPerWeek: 4, weeks: 8))
          as ProgrammeBuilt;
      for (var i = 1; i < built.sessions.length; i++) {
        final a = built.sessions[i - 1].exercises.map((e) => e.exercise.id).toSet();
        final b = built.sessions[i].exercises.map((e) => e.exercise.id).toSet();
        expect(a.intersection(b).length, lessThanOrEqualTo(1),
            reason: 'sessions ${i - 1} and $i share ${a.intersection(b)}');
      }
    });
  });
}
