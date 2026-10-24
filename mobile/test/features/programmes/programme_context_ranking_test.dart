import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/movement_role.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';

/// The programme builder with the context-aware `rank` callback exactly as
/// `ProgrammeAction.enroll` wires it (narrow -> safety-for-context ->
/// rankForContext). The ranker must stay a permutation (the builder ignores a
/// ranker that is not) and must move the generated programme in the intended
/// direction.

ExerciseItem _ex(String id, String title, String label,
        {String muscle = 'quads'}) =>
    ExerciseItem(
      id: id,
      title: title,
      equipmentId: null,
      equipmentLabel: label,
      muscles: [muscle],
      primaryMuscles: [muscle],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 8,
      summary: '',
      steps: const [],
    );

// Titles are what movementRoleOf reads. Neutral, no outdoor words (so only the
// equipment moves the outdoors score).
const _titles = {
  'sq': 'Back Squat',
  'hi': 'Romanian Deadlift',
  'hp': 'Bench Press',
  'vp': 'Overhead Press',
  'hl': 'Bent Over Row',
  'vl': 'Lat Pulldown',
  'sl': 'Bulgarian Split Squat',
  'ce': 'Front Plank',
  'cr': 'Russian Twist',
};

// [copies] variants per role: the builder rotates through each role's pool as
// it fills slots, so a pool of one or two would put the "other" kit into day 1
// whatever the ranking says. Day 1 reads at most the first four positions.
List<ExerciseItem> _kit(String prefix, String label, {int copies = 5}) => [
      for (final e in _titles.entries)
        for (var i = 0; i < copies; i++)
          _ex('$prefix${e.key}$i', e.value, label),
    ];

SafetyContext _cleared({EquipmentAccess? equipment}) => SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
      equipment: equipment,
    );

/// Mirrors `ProgrammeAction.enroll` (programme_providers.dart).
ProgrammeBuildResult _buildFor(
  List<ExerciseItem> catalogue,
  TrainingContext? tc, {
  SafetyContext? safety,
  Set<String> focus = const {},
  bool narrow = true,
  String templateId = 'strength_base',
}) {
  final s = safety ?? _cleared();
  final spec = programmeSpecFor(templateId)!;
  return buildProgramme(ProgrammeBuildRequest(
    spec: spec,
    catalogue: narrow ? narrowToTrainingContext(catalogue, s, tc) : catalogue,
    safety: narrow ? safetyContextForTrainingContext(s, tc) : s,
    weeks: 4,
    daysPerWeek: 4,
    rank: (focus.isEmpty && tc == null)
        ? null
        : (role, pool) => rankForContext(pool,
            focus: focus,
            context: tc,
            access: equipmentAccessFor(tc, s.equipment)),
  ));
}

List<String> _firstDay(ProgrammeBuildResult r) => [
      for (final e in (r as ProgrammeBuilt).sessions.first.exercises)
        e.exercise.id
    ];

Set<String> _allIds(ProgrammeBuildResult r) => {
      for (final s in (r as ProgrammeBuilt).sessions)
        for (final e in s.exercises) e.exercise.id
    };

void main() {
  // Both kits present in ONE catalogue; ranking (not narrowing) decides.
  final mixed = [..._kit('bb_', 'Barbell'), ..._kit('bw_', 'None (Bodyweight)')];

  group('ranking direction (no narrowing: the ranker alone decides)', () {
    test('gym day 1 is all barbell, outdoors day 1 is all bodyweight', () {
      final gym = _buildFor(mixed, TrainingContext.gymMachines, narrow: false);
      final out = _buildFor(mixed, TrainingContext.outdoorMinimal, narrow: false);
      expect(gym, isA<ProgrammeBuilt>());
      expect(out, isA<ProgrammeBuilt>());
      expect(_firstDay(gym), everyElement(startsWith('bb_')));
      expect(_firstDay(out), everyElement(startsWith('bw_')));
    });

    test('the two programmes differ, week after week', () {
      final gym = _buildFor(mixed, TrainingContext.gymMachines, narrow: false)
          as ProgrammeBuilt;
      final out = _buildFor(mixed, TrainingContext.outdoorMinimal, narrow: false)
          as ProgrammeBuilt;
      expect(gym.sessions.length, out.sessions.length);
      var differing = 0;
      for (var i = 0; i < gym.sessions.length; i++) {
        final a = [for (final e in gym.sessions[i].exercises) e.exercise.id];
        final b = [for (final e in out.sessions[i].exercises) e.exercise.id];
        if (a.join() != b.join()) differing++;
      }
      expect(differing, gym.sessions.length,
          reason: 'every session differs when the ranker prefers other kit');
    });

    test('home with only bodyweight avoids the (unavailable) barbell', () {
      final s = _cleared(
          equipment: const EquipmentAccess(
              location: TrainingLocation.home,
              available: [EquipmentKind.bodyweight]));
      final home = _buildFor(mixed, TrainingContext.home,
          safety: s, narrow: false);
      expect(_firstDay(home), everyElement(startsWith('bw_')));
    });

    test('home with ranking only: bodyweight preferred over barbell', () {
      final gym = _buildFor(mixed, TrainingContext.gymMachines, narrow: false);
      final home = _buildFor(mixed, TrainingContext.home,
          safety: _cleared(
              equipment: const EquipmentAccess(
                  location: TrainingLocation.home,
                  available: [EquipmentKind.bodyweight])),
          narrow: false);
      expect(_firstDay(home), isNot(_firstDay(gym)));
    });

    test('a ranker that moves nothing changes nothing: null context = old path',
        () {
      final none = _buildFor(mixed, null, narrow: false) as ProgrammeBuilt;
      final unranked = buildProgramme(ProgrammeBuildRequest(
        spec: programmeSpecFor('strength_base')!,
        catalogue: mixed,
        safety: _cleared(),
        weeks: 4,
        daysPerWeek: 4,
      )) as ProgrammeBuilt;
      expect([
        for (final s in none.sessions)
          [for (final e in s.exercises) e.exercise.id]
      ], [
        for (final s in unranked.sessions)
          [for (final e in s.exercises) e.exercise.id]
      ]);
    });

    test('null context + focus equals the old focus-first ranker', () {
      const focus = {'chest'};
      final catalogue = [
        ..._kit('a_', 'Barbell'),
        for (final e in _titles.entries)
          _ex('c_${e.key}', e.value, 'Barbell', muscle: 'chest'),
      ];
      final newPath = _buildFor(catalogue, null, focus: focus, narrow: false);
      final oldRank = buildProgramme(ProgrammeBuildRequest(
        spec: programmeSpecFor('strength_base')!,
        catalogue: catalogue,
        safety: _cleared(),
        weeks: 4,
        daysPerWeek: 4,
        rank: (role, pool) => [
          ...pool.where((e) =>
              e.primaryMuscles.any(focus.contains) ||
              e.muscles.any(focus.contains)),
          ...pool.where((e) => !(e.primaryMuscles.any(focus.contains) ||
              e.muscles.any(focus.contains))),
        ],
      ));
      expect([
        for (final s in (newPath as ProgrammeBuilt).sessions)
          [for (final e in s.exercises) e.exercise.id]
      ], [
        for (final s in (oldRank as ProgrammeBuilt).sessions)
          [for (final e in s.exercises) e.exercise.id]
      ]);
      expect(_firstDay(newPath).any((i) => i.startsWith('c_')), isTrue);
    });
  });

  group('existing invariants hold under every context', () {
    for (final c in [null, ...TrainingContext.values]) {
      test('${c ?? 'skipped'}: built, no repeats in a session, sets bounded',
          () {
        final catalogue = [
          ..._kit('bb_', 'Barbell'),
          ..._kit('bw_', 'None (Bodyweight)'),
          ..._kit('db_', 'Dumbbells'),
        ];
        final r = _buildFor(catalogue, c);
        if (c == TrainingContext.yoga) {
          // No yoga rows in this catalogue: an explicit refusal, never a
          // fabricated strength plan.
          expect(r, isA<ProgrammeRefused>());
          return;
        }
        expect(r, isA<ProgrammeBuilt>());
        final built = r as ProgrammeBuilt;
        expect(built.sessions, hasLength(16));
        final spec = programmeSpecFor('strength_base')!;
        final report = reportOn(built.sessions);
        for (final s in built.sessions) {
          final ids = [for (final e in s.exercises) e.exercise.id];
          expect(ids.toSet(), hasLength(ids.length));
        }
        for (final entry in report.weeklySets.entries) {
          expect(entry.value, greaterThanOrEqualTo(spec.minWeeklySetsPerRole));
          expect(entry.value, lessThanOrEqualTo(spec.maxWeeklySetsPerRole));
        }
        expect(report.roles, containsAll(kPrimaryStrengthRoles));
      });
    }

    test('only objects from the catalogue are scheduled (permutation guard)',
        () {
      final r = _buildFor(mixed, TrainingContext.gymMachines, narrow: false)
          as ProgrammeBuilt;
      for (final s in r.sessions) {
        for (final e in s.exercises) {
          expect(mixed.any((m) => identical(m, e.exercise)), isTrue,
              reason: e.exercise.id);
        }
      }
    });

    test('a non-permutation ranker is ignored, not obeyed', () {
      final forged = _buildFor(mixed, null, narrow: false);
      final base = buildProgramme(ProgrammeBuildRequest(
        spec: programmeSpecFor('strength_base')!,
        catalogue: mixed,
        safety: _cleared(),
        weeks: 4,
        daysPerWeek: 4,
        rank: (role, pool) => pool.take(1).toList(), // drops items
      ));
      expect(_allIds(base), _allIds(forged));
    });

    test('outdoors narrowing still removes the barbell kit entirely', () {
      final r = _buildFor(mixed, TrainingContext.outdoorMinimal);
      expect(_allIds(r), everyElement(startsWith('bw_')));
    });

    test('building twice gives an identical programme (deterministic)', () {
      for (final c in TrainingContext.values) {
        if (c == TrainingContext.yoga) continue;
        final a = _buildFor(mixed, c) as ProgrammeBuilt;
        final b = _buildFor(mixed, c) as ProgrammeBuilt;
        expect([
          for (final s in a.sessions) [for (final e in s.exercises) e.exercise.id]
        ], [
          for (final s in b.sessions) [for (final e in s.exercises) e.exercise.id]
        ], reason: c.name);
      }
    });
  });

  group('real catalogue evidence: first programme day by context', () {
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

    SafetyContext homeKit() => _cleared(
        equipment: const EquipmentAccess(
            location: TrainingLocation.home,
            available: [EquipmentKind.bodyweight, EquipmentKind.dumbbells]));

    test('first day differs between gym, home and outdoors', () {
      final ctxs = {
        'gym': TrainingContext.gymMachines,
        'home': TrainingContext.home,
        'outdoors': TrainingContext.outdoorMinimal,
      };
      final day = <String, List<ExerciseItem>>{};
      for (final e in ctxs.entries) {
        final r = _buildFor(catalogue, e.value, safety: homeKit());
        expect(r, isA<ProgrammeBuilt>(), reason: e.key);
        day[e.key] = [
          for (final p in (r as ProgrammeBuilt).sessions.first.exercises)
            p.exercise
        ];
        // ignore: avoid_print
        print('EVIDENCE day1 ${e.key}: ${day[e.key]!.map((x) => '${x.title} [${x.equipmentLabel ?? x.equipmentId ?? 'bodyweight'}]').join(' | ')}');
      }
      int diff(String a, String b) {
        final x = day[a]!.map((e) => e.id).toSet();
        final y = day[b]!.map((e) => e.id).toSet();
        return day[a]!.length - x.intersection(y).length;
      }

      // ignore: avoid_print
      print('EVIDENCE day1 size=${day['gym']!.length} differing: '
          'gym-vs-home=${diff('gym', 'home')} '
          'gym-vs-outdoors=${diff('gym', 'outdoors')} '
          'home-vs-outdoors=${diff('home', 'outdoors')}');
      expect(diff('gym', 'outdoors'), greaterThan(0));
      expect(diff('gym', 'home'), greaterThan(0));
    });

    test('ranking moves real programmes: gym day-1 kit is heavier than before',
        () {
      final s = homeKit();
      final ranked = _buildFor(catalogue, TrainingContext.gymMachines,
          safety: s) as ProgrammeBuilt;
      final plain = buildProgramme(ProgrammeBuildRequest(
        spec: programmeSpecFor('strength_base')!,
        catalogue: narrowToTrainingContext(
            catalogue, s, TrainingContext.gymMachines),
        safety: safetyContextForTrainingContext(s, TrainingContext.gymMachines),
        weeks: 4,
        daysPerWeek: 4,
      )) as ProgrammeBuilt;
      double mean(ProgrammeBuilt b) {
        final l = [
          for (final p in b.sessions.first.exercises)
            contextAffinity(p.exercise, TrainingContext.gymMachines, null)
        ];
        return l.reduce((a, b) => a + b) / l.length;
      }

      // ignore: avoid_print
      print('EVIDENCE gym day-1 mean affinity ranked=${mean(ranked)} '
          'unranked=${mean(plain)}');
      expect(mean(ranked), greaterThan(mean(plain)));
    });

    test('outdoors day 1 has no machine / barbell on the real catalogue', () {
      final r = _buildFor(catalogue, TrainingContext.outdoorMinimal,
          safety: homeKit()) as ProgrammeBuilt;
      for (final p in r.sessions.first.exercises) {
        expect(
            contextAffinity(p.exercise, TrainingContext.outdoorMinimal, null),
            greaterThanOrEqualTo(0),
            reason: p.exercise.title);
      }
    });
  });
}
