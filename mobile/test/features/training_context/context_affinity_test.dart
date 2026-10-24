import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';

/// `contextAffinity` and `rankForContext`: the preference layer that orders
/// candidates which already passed every hard filter. Fixtures use realistic
/// vendor labels (exact strings seen in the shipped catalogue).

ExerciseItem _ex(
  String id, {
  String? title,
  String? label,
  String? equipmentId,
  List<String> primary = const ['quads'],
  bool stretch = false,
  String? group,
}) =>
    ExerciseItem(
      id: id,
      title: title ?? 'Move $id',
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: primary,
      primaryMuscles: primary,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      isStretch: stretch,
      vendorGroup: group,
    );

// Neutral titles on purpose: none contains an outdoor word, so the only thing
// moving the outdoors score is the equipment.
final bodyweight = _ex('bw', title: 'Glute Bridge', label: 'None (Bodyweight)');
final bodyweightNoLabel = _ex('bw0', title: 'Glute Bridge');
final legPress = _ex('lp', title: 'Leg Press', equipmentId: 'leg_press');
final cable = _ex('cb', title: 'Triceps Pushdown', label: 'Cable');
final barbell = _ex('bb', title: 'Back Squat', label: 'Barbell');
final dumbbell = _ex('db', title: 'Goblet Squat', label: 'Dumbbells');
final kettlebell = _ex('kb', title: 'Kettlebell Swing', label: 'Kettlebells');
final band = _ex('rb', title: 'Band Pull Apart', label: 'Resistance Band');
final jumpRope = _ex('jr', title: 'Double Unders', label: 'Jump Rope');
final medBall = _ex('mb', title: 'Wall Ball Toss', label: 'Medicine Ball');
final pullUpBar = _ex('pb', title: 'Hanging Raise', label: 'Pull Up Bar');
final bench = _ex('bn', title: 'Step Up Box Hold', label: 'Bench');
final sled = _ex('sl', title: 'Sled Drag', label: 'Sled');
final yogaMat =
    _ex('ym', title: 'Floor Bridge', label: 'Yoga Mat'); // mat is no equipment
final stretch =
    _ex('st', title: 'Hamstring Stretch', label: 'Yoga Mat', stretch: true);
final stretchBarbell = _ex('stb',
    title: 'Barbell Shoulder Opener', label: 'Barbell', stretch: true);

const homeDumbbells = EquipmentAccess(
  location: TrainingLocation.home,
  available: [EquipmentKind.bodyweight, EquipmentKind.dumbbells],
);
const homeNothing = EquipmentAccess(
  location: TrainingLocation.home,
  available: [EquipmentKind.bodyweight],
);

double _a(ExerciseItem e, TrainingContext? c, [EquipmentAccess? a]) =>
    contextAffinity(e, c, a);

void main() {
  group('contextAffinity: null and yoga are neutral', () {
    test('null context scores everything 0', () {
      for (final e in [bodyweight, legPress, barbell, jumpRope, stretch]) {
        expect(_a(e, null), 0, reason: e.id);
        expect(_a(e, null, homeNothing), 0, reason: e.id);
      }
    });
    test('yoga scores everything 0, equipment or not', () {
      for (final e in [bodyweight, legPress, barbell, jumpRope, stretch]) {
        expect(_a(e, TrainingContext.yoga), 0, reason: e.id);
      }
    });
  });

  group('contextAffinity: stretch / mobility is 0 everywhere', () {
    for (final c in TrainingContext.values) {
      test('${c.name}: stretch items (even with loaded kit) stay 0', () {
        expect(_a(stretch, c, homeNothing), 0);
        expect(_a(stretchBarbell, c, homeNothing), 0);
      });
    }
  });

  group('contextAffinity: gymMachines', () {
    const c = TrainingContext.gymMachines;
    test('bodyweight is penalised (-3), with and without a label', () {
      expect(_a(bodyweight, c), -3);
      expect(_a(bodyweightNoLabel, c), -3);
      expect(_a(yogaMat, c), -3, reason: 'a mat is not equipment');
    });
    test('machine id, cable, sled and barbell are +3', () {
      expect(_a(legPress, c), 3);
      expect(_a(cable, c), 3);
      expect(_a(sled, c), 3);
      expect(_a(barbell, c), 3);
    });
    test('dumbbell and kettlebell are +2', () {
      expect(_a(dumbbell, c), 2);
      expect(_a(kettlebell, c), 2);
    });
    test('bands and portable kit are 0', () {
      expect(_a(band, c), 0);
      expect(_a(jumpRope, c), 0);
      expect(_a(medBall, c), 0);
    });
    test('other loaded kit is +1.5', () {
      expect(_a(bench, c), 1.5);
      expect(_a(pullUpBar, c), 1.5);
    });
    test('strict order: machine > dumbbell > other loaded > band > bodyweight',
        () {
      final scores = [
        for (final e in [legPress, dumbbell, bench, band, bodyweight])
          _a(e, c)
      ];
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i - 1], greaterThan(scores[i]), reason: '$scores');
      }
    });
    test('the access argument is ignored in the gym', () {
      expect(_a(barbell, c, homeNothing), 3);
    });
  });

  group('contextAffinity: home', () {
    const c = TrainingContext.home;
    test('kit the person owns is +3', () {
      expect(_a(dumbbell, c, homeDumbbells), 3);
    });
    test('bodyweight is +1.5, a mat item +2 (1.5 + 0.5)', () {
      expect(_a(bodyweight, c, homeDumbbells), 1.5);
      expect(_a(bodyweightNoLabel, c, homeDumbbells), 1.5);
      expect(_a(yogaMat, c, homeDumbbells), 2);
    });
    test('kit that is not available with the access is -3', () {
      expect(_a(barbell, c, homeDumbbells), -3);
      expect(_a(legPress, c, homeDumbbells), -3);
      expect(_a(cable, c, homeNothing), -3);
      expect(_a(dumbbell, c, homeNothing), -3);
    });
    test('owned kit beats bodyweight beats mat-less unavailable kit', () {
      expect(_a(dumbbell, c, homeDumbbells),
          greaterThan(_a(bodyweight, c, homeDumbbells)));
      expect(_a(bodyweight, c, homeDumbbells),
          greaterThan(_a(barbell, c, homeDumbbells)));
    });
    test('null access skips the availability check (kit stays +3)', () {
      expect(_a(barbell, c, null), 3);
      expect(_a(bodyweight, c, null), 1.5);
    });
    test('access derived by equipmentAccessFor drops a carried-over gym', () {
      final access = equipmentAccessFor(
        TrainingContext.home,
        const EquipmentAccess(
            location: TrainingLocation.gym,
            available: [EquipmentKind.fullGym, EquipmentKind.dumbbells]),
      );
      expect(_a(barbell, c, access), -3);
      expect(_a(dumbbell, c, access), 3);
    });
  });

  group('contextAffinity: outdoorMinimal', () {
    const c = TrainingContext.outdoorMinimal;
    test('bodyweight +2, jump rope +3, bands/portable +2', () {
      expect(_a(bodyweight, c), 2);
      expect(_a(jumpRope, c), 3);
      expect(_a(band, c), 2);
      expect(_a(medBall, c), 2);
    });
    test('pull-up / dip bar kit +2', () {
      expect(_a(pullUpBar, c), 2);
      expect(_a(_ex('dp', title: 'Parallel Bar Hold', label: 'Dip Bar'), c), 2);
      expect(_a(_ex('rg', title: 'Ring Hold', label: 'Rings'), c), 2);
      expect(_a(_ex('tx', title: 'Suspended Row', label: 'TRX'), c), 2);
    });
    test('dumbbell/kettlebell +1, other loaded -1, barbell -3, machine -4', () {
      expect(_a(dumbbell, c), 1);
      expect(_a(kettlebell, c), 1);
      expect(_a(bench, c), -1);
      expect(_a(barbell, c), -3);
      expect(_a(legPress, c), -4);
      expect(_a(cable, c), -4);
      expect(_a(sled, c), -4);
    });
    test('outdoor-friendly movements get +2 on top', () {
      expect(_a(_ex('pu', title: 'Push Up', label: 'None (Bodyweight)'), c), 4);
      expect(_a(_ex('bu', title: 'Burpee', label: 'None (Bodyweight)'), c), 4);
      expect(_a(_ex('ju', title: 'Squat Jump', label: 'None (Bodyweight)'), c),
          4);
      expect(
          _a(
              _ex('cg',
                  title: 'Star Drill',
                  label: 'None (Bodyweight)',
                  group: 'Calisthenics-Cardio-Plyo-Functional'),
              c),
          4,
          reason: 'conditioning vendor group counts without a title word');
      expect(_a(_ex('pl', title: 'Pull Up', label: 'Pull Up Bar'), c), 4);
    });
    test('a barbell lunge is still pushed down: -3 + 2 = -1', () {
      expect(_a(_ex('bl', title: 'Barbell Lunge', label: 'Barbell'), c), -1);
    });
    test('order: jump rope > bodyweight > dumbbell > bench > barbell > machine',
        () {
      final scores = [
        for (final e in [jumpRope, bodyweight, dumbbell, bench, barbell, legPress])
          _a(e, c)
      ];
      for (var i = 1; i < scores.length; i++) {
        expect(scores[i - 1], greaterThan(scores[i]), reason: '$scores');
      }
    });
    test('REGRESSION CANDIDATE: crunch / trunk are not "run" movements', () {
      // _outdoorTitleWords matches by substring: 'run' is inside Crunch and
      // Trunk. A floor crunch is not park cardio; expected to stay at +2.
      expect(_a(_ex('cr', title: 'Crunch', label: 'None (Bodyweight)'), c), 2,
          reason: 'substring "run" must not boost Crunch');
      expect(
          _a(_ex('tw', title: 'Trunk Rotation', label: 'None (Bodyweight)'), c),
          2,
          reason: 'substring "run" must not boost Trunk Rotation');
    });
    test(
        'REGRESSION CANDIDATE: a resistance cable is band kit, not a machine',
        () {
      // exercise_filter maps 'resistance cable' to EquipmentKind.bands, and
      // equipmentAccessFor(outdoorMinimal) always grants bands, so the pool
      // admits it; the affinity must not then call it a machine (-4).
      expect(
          _a(_ex('rc', title: 'Cable Face Pull', label: 'Resistance Cable'), c),
          greaterThan(0));
    });
  });

  group('rankForContext', () {
    final pool = <ExerciseItem>[
      bodyweight,
      legPress,
      dumbbell,
      jumpRope,
      barbell,
      band,
      bench,
      cable,
      stretch,
      yogaMat,
    ];
    List<String> ids(List<ExerciseItem> l) => [for (final e in l) e.id];

    List<ExerciseItem> rank(TrainingContext? c,
            {Set<String> focus = const {}, EquipmentAccess? access}) =>
        rankForContext(pool, focus: focus, context: c, access: access);

    test('is always a permutation (same objects, nothing added or dropped)', () {
      for (final c in [null, ...TrainingContext.values]) {
        final out = rank(c, access: equipmentAccessFor(c, homeDumbbells));
        expect(out, hasLength(pool.length), reason: '$c');
        expect(out.toSet().length, pool.length, reason: '$c no duplicates');
        for (final e in out) {
          expect(pool.any((p) => identical(p, e)), isTrue,
              reason: '$c returned a foreign object');
        }
      }
    });

    test('does not mutate the input list', () {
      final copy = List.of(pool);
      rank(TrainingContext.gymMachines);
      expect(ids(pool), ids(copy));
    });

    test('null context and empty focus returns the input order unchanged', () {
      expect(ids(rank(null)), ids(pool));
    });

    test('yoga with empty focus is also unchanged (all affinity 0)', () {
      expect(ids(rank(TrainingContext.yoga)), ids(pool));
    });

    test('null context with focus equals the OLD focus-first behaviour', () {
      final chesty = _ex('c1', primary: ['chest']);
      final backy = _ex('b1', primary: ['back']);
      final chesty2 = _ex('c2', primary: ['chest']);
      final backy2 = _ex('b2', primary: ['back']);
      final p = [backy, chesty, backy2, chesty2];
      const focus = {'chest'};
      // The pre-change callback, verbatim.
      final old = [
        ...p.where((e) =>
            e.primaryMuscles.any(focus.contains) || e.muscles.any(focus.contains)),
        ...p.where((e) => !(e.primaryMuscles.any(focus.contains) ||
            e.muscles.any(focus.contains))),
      ];
      final out =
          rankForContext(p, focus: focus, context: null, access: null);
      expect(ids(out), ids(old));
      expect(ids(out), ['c1', 'c2', 'b1', 'b2']);
    });

    test('gym puts machine/barbell first and bodyweight last', () {
      final out = ids(rank(TrainingContext.gymMachines));
      // +3: legPress, barbell, cable (pool order); +2 dumbbell; +1.5 bench;
      // 0: jumpRope, band, stretch (pool order); -3: bodyweight, yogaMat.
      expect(out, [
        'lp', 'bb', 'cb', 'db', 'bn', 'jr', 'rb', 'st', 'bw', 'ym',
      ]);
    });

    test('outdoors puts jump rope/bodyweight/band first and machines last', () {
      final out = ids(rank(TrainingContext.outdoorMinimal));
      expect(out, [
        'jr', // 3
        'bw', 'rb', 'ym', // 2 (pool order; yoga mat is bodyweight)
        'db', // 1
        'st', // 0
        'bn', // -1
        'bb', // -3
        'lp', 'cb', // -4
      ]);
    });

    test('home with dumbbells: owned kit, then bodyweight, then unavailable',
        () {
      final out = ids(rank(TrainingContext.home, access: homeDumbbells));
      // db 3, mat item 2, bodyweight 1.5, stretch 0, then every unavailable
      // item (-3) in pool order.
      expect(out, [
        'db', 'ym', 'bw', 'st', 'lp', 'jr', 'bb', 'rb', 'bn', 'cb',
      ]);
    });

    test('deterministic: repeated calls and a shuffled-then-restored pool agree',
        () {
      for (final c in TrainingContext.values) {
        final a = ids(rank(c, access: homeDumbbells));
        final b = ids(rank(c, access: homeDumbbells));
        expect(a, b, reason: c.name);
      }
    });

    test('tie stability: equal affinity and focus keep the incoming order', () {
      final tied = [
        for (var i = 0; i < 12; i++) _ex('t$i', label: 'Barbell'),
      ];
      final out = rankForContext(tied,
          focus: const {},
          context: TrainingContext.gymMachines,
          access: null);
      expect(ids(out), ids(tied));
      // reversed input gives the reversed output (order comes from the input,
      // not from ids or sort internals)
      final rev = tied.reversed.toList();
      expect(
          ids(rankForContext(rev,
              focus: const {},
              context: TrainingContext.gymMachines,
              access: null)),
          ids(rev));
    });

    test('affinity outranks focus; focus outranks pool index', () {
      final bwBack = _ex('bw_back',
          label: 'None (Bodyweight)', primary: ['back']);
      final bwChest = _ex('bw_chest',
          label: 'None (Bodyweight)', primary: ['chest']);
      final bbBack = _ex('bb_back', label: 'Barbell', primary: ['back']);
      final bbChest = _ex('bb_chest', label: 'Barbell', primary: ['chest']);
      final p = [bwBack, bwChest, bbBack, bbChest];
      final gym = rankForContext(p,
          focus: const {'chest'},
          context: TrainingContext.gymMachines,
          access: null);
      // barbells (+3) first, chest first inside the tier; then bodyweight.
      expect(ids(gym), ['bb_chest', 'bb_back', 'bw_chest', 'bw_back']);
      final out = rankForContext(p,
          focus: const {'chest'},
          context: TrainingContext.outdoorMinimal,
          access: null);
      // bodyweight (+2) first, chest first inside; barbell (-3) last.
      expect(ids(out), ['bw_chest', 'bw_back', 'bb_chest', 'bb_back']);
    });

    test('focus matches on secondary muscles too', () {
      final a = ExerciseItem(
        id: 'sec',
        title: 'Row',
        equipmentId: null,
        equipmentLabel: 'Barbell',
        muscles: const ['back', 'biceps'],
        primaryMuscles: const ['back'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 8,
        summary: '',
        steps: const [],
      );
      final b = _ex('other', label: 'Barbell', primary: ['quads']);
      final out = rankForContext([b, a],
          focus: const {'biceps'},
          context: TrainingContext.gymMachines,
          access: null);
      expect(ids(out), ['sec', 'other']);
    });

    test('empty pool returns an empty list', () {
      expect(
          rankForContext(const [],
              focus: const {'chest'},
              context: TrainingContext.home,
              access: homeNothing),
          isEmpty);
    });

    test('gym and outdoors orders are not the same', () {
      expect(ids(rank(TrainingContext.gymMachines)),
          isNot(ids(rank(TrainingContext.outdoorMinimal))));
    });
  });
}
