import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_fit.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';

/// B5d-3 — the six templates ordered by how well they answer the questionnaire.
///
/// What is worth pinning is not that a sort runs. It is the three ways this
/// could quietly lie to a user: claiming a match against a question they never
/// answered, reordering a catalogue on the strength of nothing, and reshuffling
/// between builds so the "best" programme is whichever one was drawn last.

ProgrammeTemplate _t(
  String id, {
  ProgrammeGoal goal = ProgrammeGoal.form,
  ExerciseDifficulty level = ExerciseDifficulty.beginner,
  int daysPerWeek = 3,
  List<String> muscles = const [],
}) =>
    ProgrammeTemplate(
      id: id,
      goal: goal,
      level: level,
      weeks: 8,
      daysPerWeek: daysPerWeek,
      muscles: muscles,
    );

ExerciseItem _ex(String id, List<String> muscles) => ExerciseItem.fromJson({
      'id': id,
      'title': id,
      'durationMinutes': 10,
      'difficulty': 'beginner',
      'muscles': muscles,
      'steps': const ['a'],
    });

void main() {
  group('programmeFit', () {
    test('an unanswered question is never a match', () {
      // The failure this rules out: a card claiming "matches your goal" to
      // someone who never named one.
      final fit = programmeFit(_t('a'), const UserProfile(uid: 'alice'));
      expect(fit.goal, isFalse);
      expect(fit.level, isFalse);
      expect(fit.schedule, isFalse);
      expect(fit.zones, isFalse);
      expect(fit.hasAny, isFalse);
    });

    test('a null profile matches nothing', () {
      expect(programmeFit(_t('a'), null).hasAny, isFalse);
    });

    test('goal and level match only on an exact answer', () {
      const profile = UserProfile(
        uid: 'alice',
        goals: FitnessGoals(primary: ProgrammeGoal.strength),
        level: FitnessLevel(tier: FitnessTier.intermediate),
      );

      final exact = programmeFit(
          _t('a',
              goal: ProgrammeGoal.strength,
              level: ExerciseDifficulty.intermediate),
          profile);
      expect(exact.goal, isTrue);
      expect(exact.level, isTrue);

      // Adjacent tiers are NOT a half-match: how far outside their level it is
      // safe to put someone is a training decision, and the wrong direction of
      // that guess puts a beginner into advanced work.
      final adjacent = programmeFit(
          _t('b',
              goal: ProgrammeGoal.muscle, level: ExerciseDifficulty.advanced),
          profile);
      expect(adjacent.goal, isFalse);
      expect(adjacent.level, isFalse);
    });

    test('"never trained" reads as beginner, matching the enrol path', () {
      final fit = programmeFit(
        _t('a', level: ExerciseDifficulty.beginner),
        const UserProfile(
            uid: 'alice', level: FitnessLevel(tier: FitnessTier.never)),
      );
      expect(fit.level, isTrue);
    });

    test(
        'schedule fits when the programme asks for no more days than the user '
        'has', () {
      const profile =
          UserProfile(uid: 'alice', schedule: TrainingSchedule(daysPerWeek: 4));

      expect(programmeFit(_t('a', daysPerWeek: 3), profile).schedule, isTrue);
      expect(programmeFit(_t('b', daysPerWeek: 4), profile).schedule, isTrue);
      // Five days for someone with four schedules a session a week they will
      // not do — the same asymmetry `programmeDaysPerWeek` applies on enrol.
      expect(programmeFit(_t('c', daysPerWeek: 5), profile).schedule, isFalse);
    });

    test('a zone matches only a programme that names muscles', () {
      const profile = UserProfile(
        uid: 'alice',
        goals: FitnessGoals(focusZones: [FocusZone.arms]),
      );

      expect(
        programmeFit(_t('named', muscles: const ['biceps', 'triceps']), profile)
            .zones,
        isTrue,
      );
      // A full-body programme would match every zone trivially, and "matches
      // your focus areas" on a programme targeting nothing in particular is
      // noise dressed as a recommendation.
      expect(programmeFit(_t('fullbody'), profile).zones, isFalse);
      // A zone the programme does not cover is not a match either.
      expect(
        programmeFit(_t('legs', muscles: const ['quads']), profile).zones,
        isFalse,
      );
    });

    test('no catalogue passed in is never an equipment match', () {
      // Same "unanswered = no claim" contract as the other four dimensions —
      // the caller has not resolved a catalogue yet, so there is nothing to
      // check the template against.
      final fit = programmeFit(
        _t('a', muscles: const ['chest']),
        const UserProfile(uid: 'alice'),
      );
      expect(fit.equipment, isFalse);
    });

    test('a full-body template never claims an equipment match', () {
      // Same reasoning as the zones exclusion above: a full-body template
      // draws from the whole catalogue (`buildProgrammeSchedule`'s
      // `fullBodyPool`), so it would find something there almost by
      // construction — a claim every template can trivially earn is noise,
      // not a recommendation.
      final fit = programmeFit(
        _t('a'), // isFullBody
        const UserProfile(uid: 'alice'),
        catalogue: [_ex('e1', const ['chest'])],
      );
      expect(fit.equipment, isFalse);
    });

    test('equipment fits when every named muscle has real support', () {
      final fit = programmeFit(
        _t('a', muscles: const ['chest', 'back']),
        const UserProfile(uid: 'alice'),
        catalogue: [_ex('e1', const ['chest']), _ex('e2', const ['back'])],
      );
      expect(fit.equipment, isTrue);
    });

    test('one unsupported muscle is enough to fail the equipment dimension',
        () {
      // `every`, not `any`: `buildProgrammeSchedule` silently falls back to
      // the whole catalogue for a muscle it cannot fill, which is the right
      // answer for scheduling and the wrong one for claiming a match — the
      // template's own split (chest/back) would quietly become chest/generic.
      final fit = programmeFit(
        _t('a', muscles: const ['chest', 'back']),
        const UserProfile(uid: 'alice'),
        // Only 'chest' has support; nothing trains 'back'.
        catalogue: [_ex('e1', const ['chest'])],
      );
      expect(fit.equipment, isFalse);
    });

    test('score counts matched dimensions and nothing else', () {
      final fit = programmeFit(
        _t('a',
            goal: ProgrammeGoal.muscle,
            level: ExerciseDifficulty.advanced,
            daysPerWeek: 3,
            muscles: const ['chest']),
        const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(
              primary: ProgrammeGoal.muscle, focusZones: [FocusZone.chest]),
          level: FitnessLevel(tier: FitnessTier.advanced),
          schedule: TrainingSchedule(daysPerWeek: 5),
        ),
      );
      expect(fit.score, 4);
    });

    test('a catalogue that covers every named muscle adds a fifth point',
        () {
      final fit = programmeFit(
        _t('a',
            goal: ProgrammeGoal.muscle,
            level: ExerciseDifficulty.advanced,
            daysPerWeek: 3,
            muscles: const ['chest']),
        const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(
              primary: ProgrammeGoal.muscle, focusZones: [FocusZone.chest]),
          level: FitnessLevel(tier: FitnessTier.advanced),
          schedule: TrainingSchedule(daysPerWeek: 5),
        ),
        catalogue: [_ex('e1', const ['chest'])],
      );
      expect(fit.score, 5);
    });
  });

  group('rankTemplates', () {
    test('leaves the catalogue alone when there is nothing to rank by', () {
      // Reordering on the strength of nothing and calling it a recommendation
      // is indistinguishable, from outside, from a real one.
      for (final profile in [null, const UserProfile(uid: 'alice')]) {
        expect(
          rankTemplates(programmeTemplates, profile)
              .map((r) => r.template.id)
              .toList(),
          programmeTemplates.map((t) => t.id).toList(),
          reason: 'profile: $profile',
        );
      }
    });

    test('puts the best-fitting programme first', () {
      // `shoulders_arms` is the only shipped template that is muscle-goal AND
      // 3-day AND names arm muscles; `hypertrophy` shares the goal but asks
      // for four days.
      final ranked = rankTemplates(
        programmeTemplates,
        const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(
              primary: ProgrammeGoal.muscle, focusZones: [FocusZone.arms]),
          level: FitnessLevel(tier: FitnessTier.intermediate),
          schedule: TrainingSchedule(daysPerWeek: 3),
        ),
      );

      expect(ranked.first.template.id, 'shoulders_arms');
      expect(ranked.first.fit.score, 4);
      // Scores must never increase down the list.
      for (var i = 1; i < ranked.length; i++) {
        expect(ranked[i].fit.score, lessThanOrEqualTo(ranked[i - 1].fit.score),
            reason: 'position $i outscores the one above it');
      }
    });

    test('equal scores keep catalogue order', () {
      // `List.sort` is not stable in Dart, so this is the guard against the
      // "best" programme being whichever one the sort happened to leave on top.
      //
      // Deliberately NOT phrased as "the same answer on repeated runs", which
      // is what this test said first: for a fixed input and comparator
      // `List.sort` is deterministic, so an UNSTABLE sort would return the same
      // wrong order every time too. Repeating the call would have looked like
      // proof and been none. What proves it is comparing one score bucket
      // against the catalogue's own order.
      const profile = UserProfile(
        uid: 'alice',
        schedule: TrainingSchedule(daysPerWeek: 3),
      );
      final ranked = rankTemplates(programmeTemplates, profile);

      // Ties have to exist in the fixture, or the claim is untested.
      expect(ranked.map((r) => r.fit.score).toSet().length,
          lessThan(programmeTemplates.length),
          reason: 'no ties in the fixture — the stability claim is untested');

      final threeDay = ranked
          .where((r) => r.fit.score == 1)
          .map((r) => r.template.id)
          .toList();
      expect(threeDay.length, greaterThan(1),
          reason: 'a bucket of one cannot show an ordering');
      final catalogueOrder =
          programmeTemplates.map((t) => t.id).where(threeDay.contains).toList();
      expect(threeDay, catalogueOrder);
    });

    test('an empty list ranks to an empty list', () {
      expect(rankTemplates(const [], const UserProfile(uid: 'a')), isEmpty);
    });

    test('the catalogue reaches every template it ranks, not just the first',
        () {
      // `shoulders_arms` and `hypertrophy` both target `ProgrammeGoal.muscle`
      // (B5d-3's own fixture note above), so a catalogue that only supports
      // one of their muscle sets has to separate them — proves `catalogue`
      // is threaded per-template through `rankTemplates`, not applied once.
      final ranked = rankTemplates(
        programmeTemplates,
        const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(primary: ProgrammeGoal.muscle),
        ),
        catalogue: [
          _ex('e1', const ['shoulders']),
          _ex('e2', const ['biceps']),
          _ex('e3', const ['triceps']),
          // Nothing trains chest/back/quads/hamstrings — `hypertrophy` keeps
          // its goal match but not an equipment one.
        ],
      );
      final byId = {for (final r in ranked) r.template.id: r.fit};
      expect(byId['shoulders_arms']!.equipment, isTrue);
      expect(byId['hypertrophy']!.equipment, isFalse);
      expect(byId['shoulders_arms']!.score, byId['hypertrophy']!.score + 1,
          reason: 'the equipment point is what should separate them');
    });
  });
}
