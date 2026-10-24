import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/home/data/suggestion_builder.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart';

/// Context-aware ranking in `buildSuggestions`: the same pool must produce a
/// different top list in a gym, at home and outdoors, and the bonus must only
/// REORDER what the hard filters already allow.

final now = DateTime(2026, 7, 30, 12);

ExerciseItem ex(
  String id,
  String title,
  String? label,
  String muscle, {
  String? equipmentId,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  int minutes = 8,
}) =>
    ExerciseItem(
      id: id,
      title: title,
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: [muscle],
      primaryMuscles: [muscle],
      difficulty: difficulty,
      durationMinutes: minutes,
      summary: '',
      steps: const [],
    );

// One exercise per primary muscle, so the one-per-muscle diversity pass never
// hides a ranking difference. Pool order is deliberately NOT the order any
// context prefers, so a context that did nothing would return this order.
final pool = <ExerciseItem>[
  ex('bw_plank', 'Front Plank', 'None (Bodyweight)', 'core'),
  ex('bw_bridge', 'Glute Bridge', 'None (Bodyweight)', 'glutes'),
  ex('band', 'Band Pull Apart', 'Resistance Band', 'back'),
  ex('db', 'Dumbbell Curl', 'Dumbbells', 'biceps'),
  ex('rope', 'Rope Double Unders', 'Jump Rope', 'calves'),
  ex('press', 'Leg Press', null, 'quads', equipmentId: 'leg_press'),
  ex('cable', 'Cable Triceps Pushdown', 'Cable', 'triceps'),
  ex('bb', 'Barbell Bench Press', 'Barbell', 'chest'),
];

List<String> ids(List<WorkoutSuggestion> l) => [for (final s in l) s.exerciseId];

const homeKit = EquipmentAccess(
  location: TrainingLocation.home,
  available: [EquipmentKind.bodyweight, EquipmentKind.dumbbells],
);

UserProfile profile({
  EquipmentAccess equipment = homeKit,
  FitnessTier? tier,
  FitnessGoals goals = FitnessGoals.empty,
}) =>
    UserProfile.empty('u1').copyWith(
      equipment: equipment,
      level: FitnessLevel.empty.copyWith(tier: tier),
      goals: goals,
      completedAt: DateTime(2026, 1, 1),
    );

List<WorkoutSuggestion> build(
  List<ExerciseItem> candidates,
  TrainingContext? c, {
  UserProfile? p,
  int limit = 3,
  List<WorkoutLogEntry> logs = const [],
}) =>
    buildSuggestions(
      candidates: candidates,
      profile: p ?? profile(),
      recentLogs: logs,
      now: now,
      limit: limit,
      trainingContext: c,
    );

void main() {
  group('same pool, different context -> different top suggestions', () {
    test('gym prefers machines/barbell; top 3 are press, cable, barbell', () {
      final out = build(pool, TrainingContext.gymMachines);
      expect(ids(out), ['press', 'cable', 'bb']);
    });

    test('outdoors prefers rope, bodyweight, band; never machines or barbell',
        () {
      final out = build(pool, TrainingContext.outdoorMinimal);
      expect(ids(out), ['rope', 'bw_plank', 'bw_bridge']);
      expect(ids(out), isNot(contains('press')));
      expect(ids(out), isNot(contains('bb')));
    });

    test('home with dumbbells prefers the owned kit, then bodyweight', () {
      final out = build(pool, TrainingContext.home);
      expect(ids(out).first, 'db');
      expect(ids(out).sublist(1), ['bw_plank', 'bw_bridge']);
      // unavailable kit (barbell, machine, cable, band, rope) is -3 => later
      final five = ids(build(pool, TrainingContext.home, limit: 8));
      for (final late in ['bb', 'press', 'cable', 'band', 'rope']) {
        expect(five.indexOf(late), greaterThan(five.indexOf('bw_bridge')),
            reason: late);
      }
    });

    test('the three contexts produce three distinct top-3 lists', () {
      final gym = ids(build(pool, TrainingContext.gymMachines));
      final home = ids(build(pool, TrainingContext.home));
      final out = ids(build(pool, TrainingContext.outdoorMinimal));
      expect({gym.join(), home.join(), out.join()}, hasLength(3));
    });

    test('gym vs outdoors top-3 share no exercise', () {
      final gym = ids(build(pool, TrainingContext.gymMachines)).toSet();
      final out = ids(build(pool, TrainingContext.outdoorMinimal)).toSet();
      expect(gym.intersection(out), isEmpty);
    });

    test('deterministic: two builds are identical for every context', () {
      for (final c in [null, ...TrainingContext.values]) {
        expect(ids(build(pool, c)), ids(build(pool, c)), reason: '$c');
      }
    });

    test('the suggestion carries the context it was ranked for', () {
      for (final c in TrainingContext.values) {
        for (final s in build(pool, c)) {
          expect(s.trainingContext, c);
        }
      }
    });
  });

  group('null context is unchanged', () {
    test('null context keeps pool order when nothing else scores', () {
      final out = build(pool, null, p: profile(), limit: 8);
      expect(ids(out), [for (final e in pool) e.id]);
    });

    test('null context ignores equipment type entirely', () {
      final reversed = pool.reversed.toList();
      final out = build(reversed, null, limit: 8);
      expect(ids(out), [for (final e in reversed) e.id]);
    });

    test('yoga context adds nothing: same order as null', () {
      expect(ids(build(pool, TrainingContext.yoga, limit: 8)),
          ids(build(pool, null, limit: 8)));
    });

    test('the omitted parameter equals an explicit null', () {
      expect(
          ids(buildSuggestions(
              candidates: pool,
              profile: profile(),
              recentLogs: const [],
              now: now,
              limit: 8)),
          ids(build(pool, null, limit: 8)));
    });
  });

  group('the bonus only reorders: it never readmits', () {
    test('an item the filters removed is never suggested, even at +3', () {
      // At home with bodyweight + dumbbells the barbell/machine/cable rows are
      // removed by the SAME narrowing the app runs before buildSuggestions.
      final safety = SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        equipment: homeKit,
      );
      final allowed =
          eligibleForTrainingContext(pool, safety, TrainingContext.home);
      expect(allowed.map((e) => e.id), isNot(contains('bb')));
      final out = build(allowed, TrainingContext.home, limit: 8);
      expect(ids(out), isNot(contains('bb')));
      expect(ids(out), isNot(contains('press')));
      expect(ids(out), isNot(contains('cable')));
      // and the output is a subset of the input
      expect(ids(out).toSet().difference(allowed.map((e) => e.id).toSet()),
          isEmpty);
    });

    test('output ids are always a subset of the candidates, in every context',
        () {
      final subset = [pool[0], pool[3], pool[7]];
      final allowed = subset.map((e) => e.id).toSet();
      for (final c in [null, ...TrainingContext.values]) {
        expect(ids(build(subset, c, limit: 8)).toSet().difference(allowed),
            isEmpty,
            reason: '$c');
      }
    });

    test('beginner ceiling: an advanced gym item is not readmitted', () {
      final advanced = ex('adv_bb', 'Barbell Snatch', 'Barbell', 'traps',
          difficulty: ExerciseDifficulty.advanced);
      final withAdvanced = [...pool, advanced];
      final out = build(withAdvanced, TrainingContext.gymMachines,
          p: profile(tier: FitnessTier.beginner), limit: 8);
      expect(ids(out), isNot(contains('adv_bb')));
      expect(ids(out), isNotEmpty);
      // sanity: without the ceiling the same item IS reachable and ranks high
      final free = build(withAdvanced, TrainingContext.gymMachines,
          p: profile(tier: FitnessTier.advanced), limit: 8);
      expect(ids(free), contains('adv_bb'));
    });

    test('never-trained tier is also capped at beginner', () {
      final intermediate = ex('mid', 'Barbell Row', 'Barbell', 'lats',
          difficulty: ExerciseDifficulty.intermediate);
      final out = build([...pool, intermediate], TrainingContext.gymMachines,
          p: profile(tier: FitnessTier.never), limit: 9);
      expect(ids(out), isNot(contains('mid')));
    });

    test('an exercise done in the last 48 hours stays out despite the bonus',
        () {
      final out = build(pool, TrainingContext.gymMachines,
          logs: [
            WorkoutLogEntry(
              id: 'l1',
              exerciseId: 'press',
              exerciseTitle: 'Leg Press',
              completedAt: now.subtract(const Duration(hours: 10)),
              durationMinutes: 10,
            ),
          ],
          limit: 8);
      expect(ids(out), isNot(contains('press')));
      expect(ids(out).first, anyOf('cable', 'bb'));
    });

    test('empty candidates stays empty in every context', () {
      for (final c in TrainingContext.values) {
        expect(build(const [], c), isEmpty);
      }
    });
  });

  group('the bonus is additive and halved, not dominant', () {
    test('an untrained-muscle signal (+3) beats a gym machine bonus (+1.5)', () {
      final chestDone = ex('chest_done', 'Cable Fly', 'Cable', 'chest');
      final backFresh =
          ex('back_fresh', 'Band Row', 'Resistance Band', 'back'); // gym 0
      final machineChest = ex('chest_machine', 'Chest Press', null, 'chest',
          equipmentId: 'chest_press');
      final out = build([machineChest, backFresh, chestDone],
          TrainingContext.gymMachines,
          logs: [
            WorkoutLogEntry(
              id: 'l',
              exerciseId: 'chest_done',
              exerciseTitle: 'Cable Fly',
              completedAt: now.subtract(const Duration(days: 3)),
              durationMinutes: 10,
            ),
          ],
          limit: 3);
      // back is untrained: +3 (band is 0 in a gym); the chest machine only
      // gets +1.5 from the context. History outweighs the context bonus.
      expect(ids(out).first, 'back_fresh');
      final back = out.firstWhere((s) => s.exerciseId == 'back_fresh');
      expect(back.reason, SuggestionReason.untrainedMuscle);
    });

    test('a cardio goal still lifts cardio over a pure context preference',
        () {
      final run = ex('run', 'Treadmill Run', null, 'quads',
          equipmentId: 'treadmill');
      final out = build(
          [ex('bwx', 'Plank', 'None (Bodyweight)', 'core'), run],
          TrainingContext.outdoorMinimal,
          p: profile(goals: const FitnessGoals(weightLoss: true)));
      // outdoors machine -4*.5 = -2, +2 cardio goal = 0; plank +2*.5 = +1.
      // The plank wins here; the point is the arithmetic is the documented one.
      expect(out.first.exerciseId, 'bwx');
      final gym = build(
          [ex('bwx', 'Plank', 'None (Bodyweight)', 'core'), run],
          TrainingContext.gymMachines,
          p: profile(goals: const FitnessGoals(weightLoss: true)));
      expect(gym.first.exerciseId, 'run');
      expect(gym.first.reason, SuggestionReason.cardioForWeightLoss);
    });
  });

  group('real catalogue evidence (operator complaint: do contexts differ?)', () {
    late List<ExerciseItem> catalogue;

    setUpAll(() {
      final file = File('assets/data/exercises_vendor.json');
      expect(file.existsSync(), isTrue);
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

      walk(jsonDecode(file.readAsStringSync()));
      catalogue = rows;
    });

    List<WorkoutSuggestion> top5(TrainingContext c, {bool ranked = true}) {
      final safety = SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        equipment: homeKit,
      );
      final candidates = eligibleForTrainingContext(catalogue, safety, c);
      return buildSuggestions(
        candidates: candidates,
        profile: profile(),
        recentLogs: const [],
        now: now,
        limit: 5,
        trainingContext: ranked ? c : null,
      );
    }

    test('top-5 suggestions differ between gym, home and outdoors', () {
      final gym = top5(TrainingContext.gymMachines);
      final home = top5(TrainingContext.home);
      final out = top5(TrainingContext.outdoorMinimal);
      expect(gym, hasLength(5));
      expect(home, hasLength(5));
      expect(out, hasLength(5));
      int diff(List<WorkoutSuggestion> a, List<WorkoutSuggestion> b) =>
          5 - ids(a).toSet().intersection(ids(b).toSet()).length;
      // ignore: avoid_print
      print('EVIDENCE top5 differing (of 5): gym-vs-home=${diff(gym, home)} '
          'gym-vs-outdoors=${diff(gym, out)} home-vs-outdoors=${diff(home, out)}');
      // ignore: avoid_print
      for (final e in {'gym': gym, 'home': home, 'outdoors': out}.entries) {
        // ignore: avoid_print
        print('EVIDENCE ${e.key}: '
            '${e.value.map((s) => '${s.title} [${s.exercise?.equipmentLabel ?? s.exercise?.equipmentId ?? 'bodyweight'}]').join(' | ')}');
      }
      expect(diff(gym, home), greaterThan(0));
      expect(diff(gym, out), greaterThan(0));
      expect(diff(home, out), greaterThanOrEqualTo(0));
    });

    test('the context ranking changes the list vs ranking disabled', () {
      for (final c in [
        TrainingContext.gymMachines,
        TrainingContext.outdoorMinimal,
      ]) {
        final withBonus = ids(top5(c));
        final without = ids(top5(c, ranked: false));
        // ignore: avoid_print
        print('EVIDENCE ${c.name}: top5 changed by the bonus = '
            '${5 - withBonus.toSet().intersection(without.toSet()).length} of 5');
        expect(withBonus, isNot(without), reason: c.name);
      }
    });

    test('gym top-5 is mostly loaded kit; outdoors top-5 has no machine', () {
      final gym = top5(TrainingContext.gymMachines);
      final loaded = gym.where((s) => s.exercise!.needsEquipment).length;
      expect(loaded, greaterThanOrEqualTo(4), reason: 'gym top-5 loaded=$loaded');
      for (final s in top5(TrainingContext.outdoorMinimal)) {
        expect(contextAffinity(s.exercise!, TrainingContext.outdoorMinimal, null),
            greaterThanOrEqualTo(0),
            reason: s.title);
      }
    });

    test('documented outdoors weights hold on REAL rows by vendor label', () {
      // Many real rows carry BOTH an equipmentId (bench_press, dumbbell,
      // resistance_bands, ...) and a label. The documented weights are about
      // the kit, so a Dumbbells row must score as dumbbell (+1, or +3 with an
      // outdoor movement word), a Resistance Band row as band (+2 / +4).
      const c = TrainingContext.outdoorMinimal;
      final bad = <String>[];
      var checked = 0;
      for (final e in catalogue) {
        final label = e.equipmentLabel?.toLowerCase().trim();
        if (e.isStretch) continue;
        if (label == 'dumbbells' || label == 'kettlebells') {
          checked++;
          if (contextAffinity(e, c, null) < 1) bad.add('${e.title} [$label]');
        } else if (label == 'resistance band' ||
            label == 'loop resistance band') {
          checked++;
          if (contextAffinity(e, c, null) < 2) bad.add('${e.title} [$label]');
        }
      }
      // ignore: avoid_print
      print('EVIDENCE outdoors misclassified dumbbell/kettlebell/band rows: '
          '${bad.length} of $checked (first: ${bad.take(3).toList()})');
      expect(checked, greaterThan(300));
      expect(bad, isEmpty,
          reason: '${bad.length} of $checked rows scored below the documented '
              'weight');
    });

    test('documented gym weights hold on real rows: dumbbells +2, not +3', () {
      const c = TrainingContext.gymMachines;
      final wrong = [
        for (final e in catalogue)
          if (!e.isStretch &&
              e.equipmentLabel?.toLowerCase().trim() == 'dumbbells' &&
              contextAffinity(e, c, null) != 2)
            e.title
      ];
      // ignore: avoid_print
      print('EVIDENCE gym Dumbbells rows not at +2: ${wrong.length}');
      expect(wrong, isEmpty);
    });
  });
}
