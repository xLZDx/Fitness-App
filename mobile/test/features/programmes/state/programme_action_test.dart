import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/mock_profile_repository.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// [ProgrammeAction] is where enrolment actually happens -- it writes the
/// [Programme] row, then every [ScheduledSession] `buildProgrammeSchedule`
/// generates for it. `programme_schedule_test.dart` already pins the pure
/// generation logic; this is what proves the two repository writes actually
/// land together, for the current user, using the real (overridden) catalogue.

ExerciseItem _ex(String id, {List<String> muscles = const []}) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 20,
      summary: '',
      steps: const [],
    );

ExerciseItem _kit(String id, {String? label}) => ExerciseItem(
      id: id,
      title: id,
      equipmentId: null,
      equipmentLabel: label,
      muscles: const [],
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 20,
      summary: '',
      steps: const [],
    );

ProviderContainer _container({
  required MockProgrammeRepository programmeRepo,
  required MockScheduledSessionRepository sessionRepo,
  required List<ExerciseItem> catalogue,
  AuthUser? user,
  MockProfileRepository? profileRepo,
}) {
  return ProviderContainer(overrides: [
    programmeRepositoryProvider.overrideWithValue(programmeRepo),
    scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
    authUserProvider.overrideWith((_) => Stream.value(user)),
    safeCatalogProvider.overrideWith((ref) async => catalogue),
    if (profileRepo != null)
      profileRepositoryProvider.overrideWithValue(profileRepo),
  ]);
}

void main() {
  group('ProgrammeAction.enroll', () {
    test('writes the programme and its generated schedule for the current '
        'user', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_ex('a', muscles: ['chest']), _ex('b', muscles: ['back'])],
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final template = programmeTemplates.first;
      await container.read(programmeActionProvider.notifier).enroll(template);

      expect(container.read(programmeActionProvider).hasValue, isTrue);

      final saved = programmeRepo.cached('alice');
      expect(saved, hasLength(1));
      // B2a: the stored title is the template ID, not a display string. Every
      // screen resolves the name from `templateId` through `ProgrammeLabels`,
      // so a programme enrolled in Russian reads correctly after the user
      // switches the app to English. What is stored only surfaces if the
      // template itself disappears.
      expect(saved.single.title, template.id);
      expect(saved.single.templateId, template.id);
      expect(saved.single.status, ProgrammeStatus.active);

      final rows = sessionRepo.cached('alice');
      expect(rows, hasLength(template.weeks * template.daysPerWeek));
      expect(rows.every((r) => r.programmeId == saved.single.id), isTrue);
    });

    test('errors when no user is signed in, and writes nothing', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_ex('a')],
        user: null,
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);

      final state = container.read(programmeActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
      expect(programmeRepo.cached('alice'), isEmpty);
    });

    test('enrolling in a second programme abandons the first rather than '
        'running both', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_ex('a', muscles: ['chest'])],
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final action = container.read(programmeActionProvider.notifier);
      await action.enroll(programmeTemplates[0]);
      await action.enroll(programmeTemplates[1]);

      final saved = programmeRepo.cached('alice');
      expect(saved, hasLength(2));
      final first = saved.firstWhere((p) => p.templateId == programmeTemplates[0].id);
      final second = saved.firstWhere((p) => p.templateId == programmeTemplates[1].id);
      expect(first.status, ProgrammeStatus.abandoned);
      expect(first.endedAt, isNotNull);
      expect(second.status, ProgrammeStatus.active);
    });
  });

  group('ProgrammeAction.enroll reads the questionnaire (B5a)', () {
    /// Builds a container whose signed-in user already has [profile] stored.
    Future<ProviderContainer> containerWithProfile({
      required MockProgrammeRepository programmeRepo,
      required MockScheduledSessionRepository sessionRepo,
      required List<ExerciseItem> catalogue,
      required UserProfile profile,
    }) async {
      final profileRepo = MockProfileRepository(latency: Duration.zero);
      addTearDown(profileRepo.dispose);
      await profileRepo.save(profile);
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: catalogue,
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
        profileRepo: profileRepo,
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      return container;
    }

    test('a home, bodyweight-only answer never schedules a barbell', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = await containerWithProfile(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [
          _kit('pushup', label: 'None (Bodyweight)'),
          _kit('press', label: 'Barbell'),
        ],
        profile: const UserProfile(
          uid: 'alice',
          equipment: EquipmentAccess(
            location: TrainingLocation.home,
            available: [EquipmentKind.bodyweight],
          ),
        ),
      );

      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);

      final rows = sessionRepo.cached('alice');
      expect(rows, isNotEmpty);
      expect(rows.every((r) => r.exerciseId == 'pushup'), isTrue,
          reason: 'a barbell reached a user who owns none');
    });

    test('the schedule follows the days the user said they have', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final template = programmeTemplates.first; // 4 days a week
      final container = await containerWithProfile(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_kit('pushup', label: 'None (Bodyweight)')],
        profile: const UserProfile(
          uid: 'alice',
          schedule: TrainingSchedule(daysPerWeek: 2),
        ),
      );

      await container.read(programmeActionProvider.notifier).enroll(template);

      // The stored row and the generated sessions must agree, which is why the
      // clamp is applied to the Programme rather than inside the generator.
      expect(programmeRepo.cached('alice').single.daysPerWeek, 2);
      expect(sessionRepo.cached('alice'), hasLength(template.weeks * 2));
    });

    test('focus zones fill in a full-body template and show on the row',
        () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      // `strength_base` names no muscles, so the answer to "what do you want
      // worked on" has somewhere to go.
      expect(programmeTemplates.first.muscles, isEmpty);

      final container = await containerWithProfile(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [
          _ex('crunch', muscles: ['core']),
          _ex('curl', muscles: ['biceps']),
        ],
        profile: const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(focusZones: [FocusZone.core]),
        ),
      );

      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);

      expect(programmeRepo.cached('alice').single.muscles, ['core']);
      expect(
        sessionRepo.cached('alice').every((r) => r.exerciseId == 'crunch'),
        isTrue,
      );
    });
  });

  group('programmeDaysPerWeek', () {
    test('an unanswered schedule leaves the template alone', () {
      expect(programmeDaysPerWeek(4, null), 4);
      expect(programmeDaysPerWeek(4, const UserProfile(uid: 'a')), 4);
    });

    test('a lower answer wins', () {
      expect(
        programmeDaysPerWeek(4,
            const UserProfile(uid: 'a', schedule: TrainingSchedule(daysPerWeek: 2))),
        2,
      );
    });

    test('a higher answer does not add days the programme never offered', () {
      expect(
        programmeDaysPerWeek(3,
            const UserProfile(uid: 'a', schedule: TrainingSchedule(daysPerWeek: 6))),
        3,
      );
    });

    test('a zero written by hand still produces a programme, not an empty one',
        () {
      expect(
        programmeDaysPerWeek(4,
            const UserProfile(uid: 'a', schedule: TrainingSchedule(daysPerWeek: 0))),
        1,
      );
    });
  });

  group('programmeMuscles', () {
    test('a template that names muscles keeps them, whatever the user chose',
        () {
      final hypertrophy = findProgrammeTemplate('hypertrophy')!;
      expect(
        programmeMuscles(
          hypertrophy,
          const UserProfile(
            uid: 'a',
            goals: FitnessGoals(focusZones: [FocusZone.arms]),
          ),
        ),
        hypertrophy.muscles,
      );
    });

    test('a full-body template takes the user focus zones', () {
      expect(
        programmeMuscles(
          findProgrammeTemplate('strength_base')!,
          const UserProfile(
            uid: 'a',
            goals: FitnessGoals(focusZones: [FocusZone.arms, FocusZone.core]),
          ),
        ),
        containsAll(['biceps', 'triceps', 'forearms', 'core']),
      );
    });

    test('selecting fullBody leaves a full-body programme full-body', () {
      expect(
        programmeMuscles(
          findProgrammeTemplate('strength_base')!,
          const UserProfile(
            uid: 'a',
            goals: FitnessGoals(focusZones: [FocusZone.fullBody]),
          ),
        ),
        isEmpty,
      );
    });

    test('no profile leaves a full-body template full-body', () {
      expect(programmeMuscles(findProgrammeTemplate('strength_base')!, null),
          isEmpty);
    });
  });

  group('ProgrammeAction.addExerciseToActiveProgramme', () {
    test('schedules the exercise under the active programme', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_ex('a', muscles: ['chest'])],
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);
      // Let the stream-backed activeProgrammeProvider settle on the newly
      // saved row -- same pattern the enroll test above relies on implicitly
      // via `.cached`, but this path reads through the live provider.
      await container.read(programmesProvider.future);

      final extra = _ex('bonus', muscles: ['chest']);
      await container
          .read(programmeActionProvider.notifier)
          .addExerciseToActiveProgramme(extra);

      expect(container.read(programmeActionProvider).hasValue, isTrue);
      final rows = sessionRepo.cached('alice');
      final bonusRow = rows.where((r) => r.exerciseId == 'bonus');
      expect(bonusRow, hasLength(1));
      expect(bonusRow.single.programmeId, isNotNull);
    });

    test('errors when there is no active programme', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [_ex('a')],
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .addExerciseToActiveProgramme(_ex('bonus'));

      final state = container.read(programmeActionProvider);
      expect(state.hasError, isTrue);
      expect(state.error, isA<StateError>());
      expect(sessionRepo.cached('alice'), isEmpty);
    });
  });
}
