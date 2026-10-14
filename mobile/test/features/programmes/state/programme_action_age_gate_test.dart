import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// F3 (site 1): the add-to-programme gate carries the person's age band and
/// gentle-selection switch, so a minor or senior cannot add a max-effort
/// exercise the plan itself would refuse. Equipment is deliberately NOT carried
/// (see the R-03 case in `programme_action_test.dart`).
///
/// The REAL `safetyContextProvider` is used (only the profile is overridden),
/// so the age band is derived by production code from the birth year.

int get _year => DateTime.now().year;

final _cleared = <ParQQuestion, bool>{
  for (final q in ParQQuestion.values) q: false,
};

// `UserProfile` is not const-constructed here (the screening map is final).
UserProfile _profile({
  int? birthYear,
  FitnessGoals goals = FitnessGoals.empty,
  EquipmentAccess equipment = EquipmentAccess.empty,
}) =>
    UserProfile(
      uid: 'alice',
      personal: PersonalInfo(birthYear: birthYear),
      health: HealthHistory(screening: _cleared),
      goals: goals,
      equipment: equipment,
    );

ExerciseItem _exercise({
  String id = 'x',
  String? vendorGroup,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
  String? equipmentId,
  String? equipmentLabel,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: equipmentLabel,
      muscles: const ['back'],
      difficulty: difficulty,
      durationMinutes: 20,
      summary: '',
      steps: const [],
      vendorGroup: vendorGroup,
    );

final _powerlifting =
    _exercise(id: 'deadlift_max', vendorGroup: 'Powerlifting');
final _advanced =
    _exercise(id: 'handstand', difficulty: ExerciseDifficulty.advanced);

Future<(Object?, MockScheduledSessionRepository)> _add(
  UserProfile profile,
  ExerciseItem exercise,
) async {
  final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
  addTearDown(programmeRepo.dispose);
  final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
  addTearDown(sessionRepo.dispose);
  await programmeRepo.save(
    'alice',
    Programme(
      id: 'p1',
      templateId: 'strength_base',
      title: 'strength_base',
      goal: ProgrammeGoal.strength,
      level: ExerciseDifficulty.beginner,
      weeks: 4,
      daysPerWeek: 3,
      startedAt: DateTime(2026, 1, 1),
    ),
  );
  final container = ProviderContainer(overrides: [
    programmeRepositoryProvider.overrideWithValue(programmeRepo),
    scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
    authUserProvider.overrideWith(
        (_) => Stream.value(const AuthUser(uid: 'alice', displayName: 'A'))),
    screeningProfileProvider.overrideWith((ref) async => profile),
  ]);
  addTearDown(container.dispose);
  await container.read(authUserProvider.future);
  await container.read(programmesProvider.future);
  expect(container.read(activeProgrammeProvider), isNotNull,
      reason: 'the fixture needs an active programme to add to');

  await container
      .read(programmeActionProvider.notifier)
      .addExerciseToActiveProgramme(exercise);
  return (container.read(programmeActionProvider).error, sessionRepo);
}

void _expectRefused(Object? error, MockScheduledSessionRepository repo) {
  expect(error, isA<ProgrammeNotViable>());
  expect(
    (error as ProgrammeNotViable).findings.map((f) => f.fault),
    contains(ProgrammeFault.blockedBySafety),
  );
  expect(repo.cached('alice'), isEmpty, reason: 'nothing may be scheduled');
}

void _expectAdded(Object? error, MockScheduledSessionRepository repo, String id) {
  expect(error, isNull);
  expect(repo.cached('alice').where((r) => r.exerciseId == id), hasLength(1));
}

void main() {
  group('F3: addExerciseToActiveProgramme carries age band and gentle switch',
      () {
    test('a minor (15) is refused a Powerlifting exercise', () async {
      final (error, repo) =
          await _add(_profile(birthYear: _year - 15), _powerlifting);
      _expectRefused(error, repo);
    });

    test('a minor (15) is refused an advanced exercise', () async {
      final (error, repo) =
          await _add(_profile(birthYear: _year - 15), _advanced);
      _expectRefused(error, repo);
    });

    test('a senior (70) is refused a Powerlifting exercise', () async {
      final (error, repo) =
          await _add(_profile(birthYear: _year - 70), _powerlifting);
      _expectRefused(error, repo);
    });

    test('an adult (30) may add a Powerlifting exercise', () async {
      final (error, repo) =
          await _add(_profile(birthYear: _year - 30), _powerlifting);
      _expectAdded(error, repo, 'deadlift_max');
    });

    test('a minor may still add an ordinary beginner exercise', () async {
      final (error, repo) = await _add(
          _profile(birthYear: _year - 15), _exercise(id: 'row_easy'));
      _expectAdded(error, repo, 'row_easy');
    });

    test('an adult with the gentle-selection switch (flexibility goal) is '
        'refused a Powerlifting exercise', () async {
      final (error, repo) = await _add(
        _profile(
            birthYear: _year - 30,
            goals: const FitnessGoals(flexibility: true)),
        _powerlifting,
      );
      _expectRefused(error, repo);
    });

    test('equipment is still NOT carried: a home bodyweight minor/adult '
        'adding a barbell exercise is not refused', () async {
      const home = EquipmentAccess(
        location: TrainingLocation.home,
        available: [EquipmentKind.bodyweight],
      );
      final barbell = _exercise(
          id: 'barbell_row', equipmentId: 'barbell', equipmentLabel: 'Barbell');
      for (final birthYear in [_year - 30, _year - 15]) {
        final (error, repo) = await _add(
            _profile(birthYear: birthYear, equipment: home), barbell);
        _expectAdded(error, repo, 'barbell_row');
      }
    });
  });
}
