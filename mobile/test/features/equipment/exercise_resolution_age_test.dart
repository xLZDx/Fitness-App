import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/features/equipment/data/asset_equipment_repository.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';

/// F3 (site 2): `_resolveExercise` carries the age band and gentle-selection
/// switch, so a minor or senior is shown a max-effort exercise as `withheld`.
/// Equipment is deliberately not carried: a mismatch is still `found`.
///
/// Both public entry points are covered: the "may this person do THIS, now"
/// resolution and the display-only preview resolution.

int get _year => DateTime.now().year;

final _cleared = <ParQQuestion, bool>{
  for (final q in ParQQuestion.values) q: false,
};

const _rack = EquipmentItem(
  id: 'rack',
  name: 'Rack',
  manufacturer: 'Any',
  category: 'strength',
  description: 'd',
);

const _powerlifting = ExerciseItem(
  id: 'pl',
  title: 'Max deadlift',
  equipmentId: 'rack',
  muscles: ['back'],
  difficulty: ExerciseDifficulty.intermediate,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
  vendorGroup: 'Powerlifting',
);

const _advanced = ExerciseItem(
  id: 'adv',
  title: 'Handstand',
  equipmentId: 'rack',
  muscles: ['shoulders'],
  difficulty: ExerciseDifficulty.advanced,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
);

const _ordinary = ExerciseItem(
  id: 'row',
  title: 'Seated row',
  equipmentId: 'rack',
  muscles: ['back'],
  difficulty: ExerciseDifficulty.beginner,
  durationMinutes: 10,
  summary: 's',
  steps: ['a'],
);

UserProfile _profile({
  int? birthYear,
  FitnessGoals goals = FitnessGoals.empty,
  EquipmentAccess equipment = EquipmentAccess.empty,
}) =>
    UserProfile(
      uid: 'u1',
      personal: PersonalInfo(birthYear: birthYear),
      health: HealthHistory(screening: _cleared),
      goals: goals,
      equipment: equipment,
    );

ProviderContainer _container(UserProfile profile) {
  final container = ProviderContainer(overrides: [
    effectiveLanguageCodeProvider.overrideWithValue('en'),
    equipmentRepositoryProvider.overrideWithValue(
      AssetEquipmentRepository()
        ..seedForTests(
          equipment: const [_rack],
          exercises: const [_powerlifting, _advanced, _ordinary],
        ),
    ),
    screeningProfileProvider.overrideWith((ref) async => profile),
  ]);
  addTearDown(container.dispose);
  return container;
}

void main() {
  final entries = <String, FutureProvider<ExerciseResolution> Function(String)>{
    'exerciseResolutionProvider': (id) => exerciseResolutionProvider(id),
    'exercisePreviewResolutionProvider': (id) =>
        exercisePreviewResolutionProvider(id),
  };
  for (final entry in entries.entries) {
    group('F3 ${entry.key}', () {
      Future<ExerciseResolution> resolve(UserProfile p, String id) =>
          _container(p).read(entry.value(id).future);

      test('a minor (15) gets a Powerlifting exercise withheld', () async {
        final r = await resolve(_profile(birthYear: _year - 15), 'pl');
        expect(r.visible, isNull);
        expect(r.exercise?.id, 'pl', reason: 'withheld, not "not found"');
        expect(r.withheldFor, isNotEmpty);
      });

      test('a minor (15) gets an advanced exercise withheld', () async {
        final r = await resolve(_profile(birthYear: _year - 15), 'adv');
        expect(r.visible, isNull);
        expect(r.withheldFor, isNotEmpty);
      });

      test('a senior (70) gets a Powerlifting exercise withheld', () async {
        final r = await resolve(_profile(birthYear: _year - 70), 'pl');
        expect(r.visible, isNull);
        expect(r.exercise?.id, 'pl');
        expect(r.withheldFor, isNotEmpty);
      });

      test('an adult (30) still sees both max-effort exercises', () async {
        final p = _profile(birthYear: _year - 30);
        expect((await resolve(p, 'pl')).visible?.id, 'pl');
        expect((await resolve(p, 'adv')).visible?.id, 'adv');
      });

      test('a minor still sees an ordinary beginner exercise', () async {
        final r = await resolve(_profile(birthYear: _year - 15), 'row');
        expect(r.visible?.id, 'row');
      });

      test('gentle selection (flexibility goal) withholds a max-effort '
          'exercise from an adult', () async {
        final r = await resolve(
          _profile(
              birthYear: _year - 30,
              goals: const FitnessGoals(flexibility: true)),
          'pl',
        );
        expect(r.visible, isNull);
        expect(r.withheldFor, isNotEmpty);
      });

      test('an equipment mismatch is still NOT withheld (equipment is not '
          'carried)', () async {
        const home = EquipmentAccess(
          location: TrainingLocation.home,
          available: [EquipmentKind.bodyweight],
        );
        for (final birthYear in [_year - 30, _year - 15]) {
          final r = await resolve(
              _profile(birthYear: birthYear, equipment: home), 'row');
          expect(r.visible?.id, 'row',
              reason: 'home user, rack exercise, birthYear $birthYear');
        }
      });
    });
  }
}
