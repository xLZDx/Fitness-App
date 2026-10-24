import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/personalisation/data/recommendation_hints.dart';
import 'package:fitness_app/features/personalisation/data/volume_ledger.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';

/// Plan ("Plan for today") ordering: deficit stays the primary key; on equal
/// deficit (or with no history at all) the training context decides, then the
/// pool index. Null context must be exactly the old order.

ExerciseItem _ex(
  String id,
  String title,
  String? label,
  String muscle, {
  String? equipmentId,
  int minutes = 10,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  List<String> contra = const [],
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
      contraindications: contra,
    );

const _noDeload = DeloadVerdict(
    shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);

SafetyContext _safe({
  EquipmentAccess? equipment,
  List<Injury> injuries = const [],
  ExerciseDifficulty? maxDifficulty,
}) =>
    SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
      equipment: equipment,
      injuries: injuries,
      maxDifficulty: maxDifficulty,
    );

const _homeKit = EquipmentAccess(
  location: TrainingLocation.home,
  available: [EquipmentKind.bodyweight, EquipmentKind.dumbbells],
);

/// Mirrors generatedPlanProvider: narrow, then plan under the context.
List<ExerciseItem> _planFor(
  List<ExerciseItem> pool,
  TrainingContext? tc, {
  Map<String, double> deficit = const {},
  SafetyContext? safety,
  int target = 45,
  bool narrow = true,
}) {
  final s = safety ?? _safe();
  final out = buildPlan(
    candidatePool: narrow ? narrowToTrainingContext(pool, s, tc) : pool,
    deficit: deficit,
    deload: _noDeload,
    safety: narrow ? safetyContextForTrainingContext(s, tc) : s,
    trainingContext: tc,
    targetMinutes: target,
  );
  expect(out, isA<PlanReady>());
  return (out as PlanReady).plan.exercises;
}

List<String> _ids(List<ExerciseItem> l) => [for (final e in l) e.id];

/// The OLD ordering rule (priority desc, unattributed last, pool index) PLUS
/// the one-per-first-primary-muscle diversity pass, written out independently
/// of the implementation. [reserved] ids are taken first (goal mix) and count
/// as used groups.
List<String> _refPlan(List<ExerciseItem> pool, Map<String, double> deficit,
    {int target = 45, List<String> reserved = const []}) {
  final rows = [
    for (var i = 0; i < pool.length; i++)
      (
        e: pool[i],
        i: i,
        p: exercisePriority(
            (primary: pool[i].primaryMuscles, secondary: pool[i].muscles),
            deficit)
      )
  ]..sort((a, b) {
      if (a.p == null || b.p == null) {
        if (a.p == null && b.p == null) return a.i.compareTo(b.i);
        return a.p == null ? 1 : -1;
      }
      final c = b.p!.compareTo(a.p!);
      return c != 0 ? c : a.i.compareTo(b.i);
    });
  String group(ExerciseItem e) =>
      e.primaryMuscles.isEmpty ? 'id:${e.id}' : e.primaryMuscles.first;
  final chosen = <int>[];
  var minutes = 0;
  for (final id in reserved) {
    final k = rows.indexWhere((r) => r.e.id == id);
    chosen.add(k);
    minutes += rows[k].e.durationMinutes;
  }
  final used = {for (final k in chosen) group(rows[k].e)};
  for (var k = 0; k < rows.length && chosen.length < 6; k++) {
    if (chosen.contains(k)) continue;
    if (minutes + rows[k].e.durationMinutes > target) continue;
    if (!used.add(group(rows[k].e))) continue;
    chosen.add(k);
    minutes += rows[k].e.durationMinutes;
  }
  for (var k = 0; k < rows.length && chosen.length < 6; k++) {
    if (chosen.contains(k)) continue;
    if (minutes + rows[k].e.durationMinutes > target) continue;
    chosen.add(k);
    minutes += rows[k].e.durationMinutes;
  }
  chosen.sort();
  return [for (final k in chosen) rows[k].e.id];
}

final _pool = <ExerciseItem>[
  _ex('bw1', 'Glute Bridge', 'None (Bodyweight)', 'glutes'),
  _ex('bw2', 'Front Plank', 'None (Bodyweight)', 'core'),
  _ex('band', 'Band Pull Apart', 'Resistance Band', 'back'),
  _ex('db', 'Dumbbell Curl', 'Dumbbells', 'biceps'),
  _ex('rope', 'Rope Double Unders', 'Jump Rope', 'calves'),
  _ex('lp', 'Leg Press', null, 'quads', equipmentId: 'leg_press'),
  _ex('cable', 'Cable Pushdown', 'Cable', 'triceps'),
  _ex('bb', 'Barbell Bench Press', 'Barbell', 'chest'),
];

void main() {
  group('null context: old order plus the same diversity pass (independent reference)', () {
    test('no history: pool order', () {
      expect(_ids(_planFor(_pool, null)), _refPlan(_pool, const {}));
      expect(_ids(_planFor(_pool, null)), ['bw1', 'bw2', 'band', 'db']);
    });

    test('with deficits (ties, nulls, mixed) matches the old rule', () {
      final deficit = {
        'glutes': 2.0,
        'core': 5.0,
        'back': 5.0, // tie with core
        'biceps': 1.0,
        'quads': 5.0, // tie
        'chest': 0.0,
        // calves/triceps have no entry -> unattributed (null priority)
      };
      expect(_ids(_planFor(_pool, null, deficit: deficit)),
          _refPlan(_pool, deficit));
      // and the tie among core/back/quads keeps pool order
      expect(_ids(_planFor(_pool, null, deficit: deficit)).take(3),
          ['bw2', 'band', 'lp']);
    });

    test('a pool of unattributed items keeps catalogue order', () {
      final p = [
        for (var i = 0; i < 8; i++)
          ExerciseItem(
            id: 'u$i',
            title: 'U$i',
            equipmentId: i.isEven ? 'leg_press' : null,
            muscles: const [],
            difficulty: ExerciseDifficulty.beginner,
            durationMinutes: 10,
            summary: '',
            steps: const [],
          )
      ];
      expect(_ids(_planFor(p, null)), _refPlan(p, const {}));
    });
  });

  group('equal deficit / no history: the context decides', () {
    test('gym prefers machines and barbell', () {
      final ids = _ids(_planFor(_pool, TrainingContext.gymMachines));
      expect(ids, ['lp', 'cable', 'bb', 'db']);
    });

    test('outdoors prefers jump rope, bodyweight, bands', () {
      final ids = _ids(_planFor(_pool, TrainingContext.outdoorMinimal));
      expect(ids, ['rope', 'bw1', 'bw2', 'band']);
      expect(ids, isNot(contains('lp')));
    });

    test('home prefers the owned kit, then bodyweight', () {
      final ids = _ids(_planFor(_pool, TrainingContext.home,
          safety: _safe(equipment: _homeKit)));
      expect(ids, ['db', 'bw1', 'bw2']);
    });

    test('the three contexts give three different plans', () {
      final s = _safe(equipment: _homeKit);
      final plans = {
        for (final c in [
          TrainingContext.gymMachines,
          TrainingContext.home,
          TrainingContext.outdoorMinimal
        ])
          c: _ids(_planFor(_pool, c, safety: s)).join(',')
      };
      expect(plans.values.toSet(), hasLength(3), reason: '$plans');
    });

    test('equal numeric deficit also orders by context (attributed items)', () {
      final deficit = {
        for (final m in ['glutes', 'core', 'back', 'biceps', 'calves', 'quads',
            'triceps', 'chest'])
          m: 3.0
      };
      final gym =
          _ids(_planFor(_pool, TrainingContext.gymMachines, deficit: deficit));
      final out = _ids(
          _planFor(_pool, TrainingContext.outdoorMinimal, deficit: deficit));
      expect(gym, ['lp', 'cable', 'bb', 'db']);
      expect(out, ['rope', 'bw1', 'bw2', 'band']);
    });

    test('yoga context adds no preference (affinity 0)', () {
      // yoga narrows to yoga rows; with none, the plan is empty, not an error
      final out = buildPlan(
        candidatePool: _pool,
        deficit: const {},
        deload: _noDeload,
        safety: _safe(),
        trainingContext: TrainingContext.yoga,
      );
      expect(_ids((out as PlanReady).plan.exercises), _refPlan(_pool, const {}));
    });
  });

  group('deficit stays the primary key', () {
    test('a larger deficit beats a better context fit (gym)', () {
      final deficit = {'glutes': 9.0, 'chest': 1.0, 'quads': 1.0};
      final ids = _ids(_planFor(_pool, TrainingContext.gymMachines,
          deficit: deficit, target: 10));
      expect(ids, ['bw1'], reason: 'bodyweight (-3) still wins on deficit 9');
    });

    test('a larger deficit beats a better context fit (outdoors)', () {
      final deficit = {'chest': 9.0, 'calves': 1.0};
      final ids = _ids(_planFor(_pool, TrainingContext.outdoorMinimal,
          deficit: deficit, target: 10, narrow: false));
      expect(ids, ['bb'], reason: 'barbell (-3) wins on deficit 9');
    });

    test('attributed items still come before unattributed ones', () {
      final deficit = {'glutes': 0.5};
      final ids = _ids(_planFor(_pool, TrainingContext.gymMachines,
          deficit: deficit, target: 10));
      expect(ids, ['bw1'], reason: 'the only attributed item leads');
    });
  });

  group('determinism and permutation', () {
    test('repeated builds are identical in every context', () {
      for (final c in [null, ...TrainingContext.values]) {
        final s = _safe(equipment: _homeKit);
        expect(_ids(_planFor(_pool, c, safety: s)),
            _ids(_planFor(_pool, c, safety: s)),
            reason: '$c');
      }
    });

    test('picks come from the pool, with no duplicates', () {
      for (final c in [null, ...TrainingContext.values]) {
        final out = _planFor(_pool, c, safety: _safe(equipment: _homeKit));
        expect(out.toSet().length, out.length);
        for (final e in out) {
          expect(_pool.any((p) => identical(p, e)), isTrue);
        }
      }
    });

    test('tied items keep pool order (index tie-break)', () {
      final tied = [
        for (var i = 0; i < 8; i++)
          _ex('t$i', 'Barbell Row $i', 'Barbell', 'm$i'),
      ];
      expect(_ids(_planFor(tied, TrainingContext.gymMachines)),
          ['t0', 't1', 't2', 't3']);
    });
  });

  group('filters are never bypassed by the affinity', () {
    test('a contraindicated barbell is excluded in the gym', () {
      final p = [
        ..._pool.where((e) => e.id != 'bb'),
        _ex('bb', 'Overhead Barbell Press', 'Barbell', 'shoulders',
            contra: ['shoulder']),
      ];
      final ids = _ids(_planFor(p, TrainingContext.gymMachines,
          safety: _safe(
              injuries: const [
                Injury(bodyPart: 'shoulder', type: 'impingement')
              ]),
          target: 80));
      expect(ids, isNot(contains('bb')));
      expect(ids, isNotEmpty);
    });

    test('the beginner ceiling still removes advanced gym items', () {
      final p = [
        ..._pool,
        _ex('adv', 'Barbell Snatch', 'Barbell', 'traps',
            difficulty: ExerciseDifficulty.advanced),
      ];
      final capped = _ids(_planFor(p, TrainingContext.gymMachines,
          safety: _safe(maxDifficulty: ExerciseDifficulty.beginner),
          target: 100));
      expect(capped, isNot(contains('adv')));
      final free = _ids(_planFor(p, TrainingContext.gymMachines, target: 100));
      expect(free, contains('adv'), reason: 'sanity: it is reachable uncapped');
    });

    test('equipment: outdoors never plans the barbell or machines', () {
      final ids = _ids(_planFor(_pool, TrainingContext.outdoorMinimal,
          target: 200));
      expect(ids, isNot(contains('bb')));
      expect(ids, isNot(contains('lp')));
      expect(ids, isNot(contains('cable')));
    });

    test('equipment: the profile access is still enforced when the pool is not '
        'pre-narrowed', () {
      final ids = _ids(_planFor(
          _pool,
          TrainingContext.gymMachines,
          safety: _safe(
              equipment: const EquipmentAccess(
                  location: TrainingLocation.home,
                  available: [EquipmentKind.bodyweight])),
          narrow: false,
          target: 200));
      expect(ids, isNot(contains('bb')));
      expect(ids, isNot(contains('lp')));
      expect(ids.toSet(), {'bw1', 'bw2'});
    });

    test('the context reason is still reported', () {
      final out = buildPlan(
        candidatePool: _pool,
        deficit: const {},
        deload: _noDeload,
        safety: _safe(),
        trainingContext: TrainingContext.gymMachines,
      ) as PlanReady;
      expect(out.plan.reasons.whereType<TrainingContextReason>(), isNotEmpty);
    });
  });

  group('diversity pass: one exercise per first primary muscle', () {
    final same = <ExerciseItem>[
      _ex('c1', 'Barbell Bench Press', 'Barbell', 'chest'),
      _ex('c2', 'Barbell Incline Press', 'Barbell', 'chest'),
      _ex('c3', 'Barbell Decline Press', 'Barbell', 'chest'),
      _ex('b1', 'Barbell Row', 'Barbell', 'back'),
      _ex('b2', 'Cable Row', 'Cable', 'back'),
      _ex('q1', 'Back Squat', 'Barbell', 'quads'),
      _ex('s1', 'Barbell Shoulder Press', 'Barbell', 'shoulders'),
    ];

    test('distinct muscles are used when available, not three chest presses',
        () {
      for (final c in [null, ...TrainingContext.values]) {
        if (c == TrainingContext.yoga) continue;
        final plan = _planFor(same, c, narrow: false);
        final groups = [for (final e in plan) e.primaryMuscles.first];
        expect(groups.toSet().length, groups.length, reason: '$c $groups');
        expect(plan, hasLength(4));
      }
      expect(_ids(_planFor(same, null, narrow: false)), ['c1', 'b1', 'q1', 's1']);
    });

    test('a second pass fills the slots when muscles run out', () {
      final few = same.take(5).toList();
      final ids = _ids(_planFor(few, null));
      // pass 1: c1, b1; pass 2 fills two more slots from the sorted rest
      expect(ids, ['c1', 'c2', 'c3', 'b1']);
      expect(ids, _refPlan(few, const {}));
    });

    test('deficit still decides which muscle goes first and which row', () {
      final deficit = {'quads': 9.0, 'back': 5.0, 'chest': 1.0, 'shoulders': 0.0};
      final plan = _planFor(same, TrainingContext.gymMachines, deficit: deficit);
      expect(_ids(plan), ['q1', 'b1', 'c1', 's1']);
      expect(_ids(plan), _refPlan(same, deficit));
      expect(_ids(_planFor(same, null, deficit: deficit)),
          _refPlan(same, deficit));
    });

    test('context picks the representative of a muscle on equal deficit', () {
      final bwBack = _ex('b_bw', 'Inverted Row', 'None (Bodyweight)', 'back');
      final pool = [bwBack, ...same];
      final gym = _ids(_planFor(pool, TrainingContext.gymMachines));
      final out = _ids(_planFor(pool, TrainingContext.outdoorMinimal));
      expect(gym, isNot(contains('b_bw')));
      expect(out, contains('b_bw'));
    });

    test('deterministic in every context', () {
      for (final c in [null, ...TrainingContext.values]) {
        final s = _safe(equipment: _homeKit);
        expect(_ids(_planFor(same, c, safety: s)),
            _ids(_planFor(same, c, safety: s)));
      }
    });

    test('untagged items are their own groups (never collapse together)', () {
      final untagged = [
        for (var i = 0; i < 5; i++)
          ExerciseItem(
            id: 'n$i',
            title: 'N$i',
            equipmentId: null,
            muscles: const [],
            difficulty: ExerciseDifficulty.beginner,
            durationMinutes: 10,
            summary: '',
            steps: const [],
          )
      ];
      expect(_ids(_planFor(untagged, null)), ['n0', 'n1', 'n2', 'n3']);
      final mixed = [...untagged, _ex('t1', 'Squat', null, 'quads')];
      expect(_ids(_planFor(mixed, null)), _refPlan(mixed, const {}));
    });

    test('reserved goal items count as used groups', () {
      final mob = ExerciseItem(
        id: 'mob',
        title: 'Hamstring Stretch',
        equipmentId: null,
        equipmentLabel: 'None (Bodyweight)',
        muscles: const ['hamstrings'],
        primaryMuscles: const ['hamstrings'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 10,
        summary: '',
        steps: const [],
        isStretch: true,
      );
      final other = _ex('ham', 'Leg Curl', 'Cable', 'hamstrings');
      final pool = [
        other,
        _ex('c1', 'Bench', 'Barbell', 'chest'),
        _ex('b1', 'Row', 'Barbell', 'back'),
        _ex('q1', 'Squat', 'Barbell', 'quads'),
        mob,
      ];
      final out = buildPlan(
        candidatePool: pool,
        deficit: const {},
        deload: _noDeload,
        safety: _safe(),
        hints: const RecommendationHints(wantsMobility: true),
      ) as PlanReady;
      final ids = _ids(out.plan.exercises);
      expect(ids, contains('mob'));
      expect(ids, isNot(contains('ham')),
          reason: 'hamstrings already covered by the reserved stretch');
      expect(ids, _refPlan(pool, const {}, reserved: ['mob']));
    });
  });

  group('real catalogue, no history ("Plan for today" evidence)', () {
    late List<ExerciseItem> catalogue;
    setUpAll(() {
      final rows = <ExerciseItem>[];
      void walk(Object? n) {
        if (n is Map) {
          if (n.containsKey('id') && n.containsKey('steps')) {
            rows.add(ExerciseItem.fromJson(Map<String, dynamic>.from(n)));
          }
          n.values.forEach(walk);
        } else if (n is List) {
          n.forEach(walk);
        }
      }

      walk(jsonDecode(
          File('assets/data/exercises_vendor.json').readAsStringSync()));
      catalogue = rows;
    });

    test('plans differ between gym, home and outdoors', () {
      final s = _safe(equipment: _homeKit);
      final plans = {
        'gym': _planFor(catalogue, TrainingContext.gymMachines, safety: s),
        'home': _planFor(catalogue, TrainingContext.home, safety: s),
        'outdoors': _planFor(catalogue, TrainingContext.outdoorMinimal, safety: s),
      };
      final unranked = _planFor(catalogue, null, safety: s);
      int diff(String a, String b) =>
          plans[a]!.length -
          _ids(plans[a]!).toSet().intersection(_ids(plans[b]!).toSet()).length;
      for (final e in plans.entries) {
        // ignore: avoid_print
        print('EVIDENCE plan ${e.key} (${e.value.length}): ${e.value.map((x) => '${x.title} [${x.equipmentLabel ?? x.equipmentId ?? 'bodyweight'}; muscle=${x.primaryMuscles.isEmpty ? 'NONE' : x.primaryMuscles.first}]').join(' | ')}');
      }
      // ignore: avoid_print
      print('EVIDENCE plan null-context: ${unranked.map((x) => x.title).join(' | ')}');
      // ignore: avoid_print
      print('EVIDENCE plan differing exercises: '
          'gym-vs-home=${diff('gym', 'home')} '
          'gym-vs-outdoors=${diff('gym', 'outdoors')} '
          'home-vs-outdoors=${diff('home', 'outdoors')} '
          '(of ${plans['gym']!.length})');
      expect(diff('gym', 'outdoors'), greaterThan(0));
      expect(diff('gym', 'home'), greaterThan(0));
      expect(diff('home', 'outdoors'), greaterThan(0));
    });

    test('real null context equals the old rule', () {
      final s = _safe(equipment: _homeKit);
      final eligible = recommendableAtLevel(
          eligibleExercises(catalogue, s), s);
      expect(_ids(_planFor(catalogue, null, safety: s)),
          _refPlan(eligible, const {}));
    });
  });
}
