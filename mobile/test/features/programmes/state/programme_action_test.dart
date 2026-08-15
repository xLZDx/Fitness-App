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
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// [ProgrammeAction] is where enrolment actually happens -- it writes the
/// [Programme] row, then every [ScheduledSession] `buildProgrammeSchedule`
/// generates for it. `programme_schedule_test.dart` already pins the pure
/// generation logic; this is what proves the two repository writes actually
/// land together, for the current user, using the real (overridden) catalogue.

ExerciseItem _ex(String id,
        {List<String> muscles = const [], String? title, String? label}) =>
    ExerciseItem(
      id: id,
      title: title ?? id,
      equipmentId: null,
      equipmentLabel: label,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 20,
      summary: '',
      steps: const [],
    );

/// A catalogue with one candidate for every movement role `strength_base`
/// declares.
///
/// Gate P. Enrolment now builds `strength_base` through `buildProgramme`, which
/// fills MOVEMENT ROLES and refuses rather than fabricating a plan when it
/// cannot. A two-row fixture of `_ex('a')` and `_ex('b')` satisfies no role at
/// all, so every case in this file — all of them about the two repository
/// writes landing together, not about programme structure — started coming
/// back as `ProgrammeNotViable`.
///
/// Titles, not ids, because that is what `movementRoleOf` reads.
List<ExerciseItem> _roleCatalogue(
        {List<ExerciseItem> extra = const [], String? label}) =>
    [
      _ex('sq', title: 'Bodyweight Squat', muscles: const ['quads'], label: label),
      _ex('sq2', title: 'Goblet Squat', muscles: const ['quads'], label: label),
      _ex('hi', title: 'Romanian Deadlift', muscles: const ['hamstrings'], label: label),
      _ex('hi2', title: 'Glute Bridge', muscles: const ['glutes'], label: label),
      _ex('hp', title: 'Push Up', muscles: const ['chest'], label: label),
      _ex('hp2', title: 'Bench Press', muscles: const ['chest'], label: label),
      _ex('vp', title: 'Overhead Press', muscles: const ['shoulders'], label: label),
      _ex('vp2', title: 'Push Press', muscles: const ['shoulders'], label: label),
      _ex('hl', title: 'Bent Over Row', muscles: const ['back'], label: label),
      _ex('hl2', title: 'Seated Row', muscles: const ['back'], label: label),
      _ex('vl', title: 'Pull Up', muscles: const ['back'], label: label),
      _ex('vl2', title: 'Lat Pulldown', muscles: const ['back'], label: label),
      _ex('sl', title: 'Walking Lunge', muscles: const ['quads'], label: label),
      _ex('sl2', title: 'Bulgarian Split Squat', muscles: const ['quads'], label: label),
      _ex('ce', title: 'Front Plank', muscles: const ['core'], label: label),
      _ex('ce2', title: 'Hollow Hold', muscles: const ['core'], label: label),
      _ex('cr', title: 'Russian Twist', muscles: const ['core'], label: label),
      _ex('cr2', title: 'Cable Woodchop', muscles: const ['core'], label: label),
      ...extra,
    ];

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
    // Gate P/N. Enrolment runs through the eligibility layer, and an
    // unscreened profile blocks all training — correctly, and it is what every
    // case here started returning. The screening is cleared so these cases
    // keep testing what they name (the two repository writes, the weekday
    // placement, the equipment answer), while the EQUIPMENT half of the
    // context is still read from the seeded profile so
    // `a home, bodyweight-only answer never schedules a barbell` still tests
    // the thing it is about.
    safetyContextProvider.overrideWith((ref) async {
      final profile = await ref.watch(screeningProfileProvider.future);
      return SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        injuries: profile?.health.injuries ?? const [],
        health: profile?.health.flags ?? HealthFlags.empty,
        equipment: profile?.equipment,
      );
    }),
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
        catalogue: _roleCatalogue(),
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
        catalogue: _roleCatalogue(),
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
        catalogue: _roleCatalogue(),
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
        // A role-complete bodyweight catalogue plus one barbell row. The
        // programme now needs candidates for every declared movement role, and
        // the assertion below is still the one that matters: the barbell must
        // not be scheduled for someone who owns none.
        catalogue: _roleCatalogue(
          label: 'None (Bodyweight)',
          extra: [_kit('press', label: 'Barbell')],
        ),
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
      final scheduledIds = {
        for (final r in rows) ...[
          r.exerciseId,
          ...r.extraExercises.map((e) => e.exerciseId),
        ],
      };
      expect(scheduledIds, isNot(contains('press')),
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
        catalogue: _roleCatalogue(label: 'None (Bodyweight)'),
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

    // B5d. `preferredWeekdays` was written by the questionnaire
    // (`step_schedule.dart`) and read by nothing in the scheduling path: the
    // generator spread days evenly, so someone who ticked Monday, Wednesday
    // and Friday got three days measured from whichever weekday they happened
    // to enrol on.
    test('the schedule lands on the weekdays the user ticked', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final template = programmeTemplates.first; // 4 days a week
      final container = await containerWithProfile(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: _roleCatalogue(label: 'None (Bodyweight)'),
        profile: const UserProfile(
          uid: 'alice',
          schedule: TrainingSchedule(
            daysPerWeek: 3,
            preferredWeekdays: [
              DateTime.monday,
              DateTime.wednesday,
              DateTime.friday,
            ],
          ),
        ),
      );

      await container.read(programmeActionProvider.notifier).enroll(template);

      final rows = sessionRepo.cached('alice');
      expect(rows, isNotEmpty);
      expect(
        rows.map((r) => r.scheduledFor.weekday).toSet(),
        {DateTime.monday, DateTime.wednesday, DateTime.friday},
        reason: 'no session may land on a weekday the user did not tick',
      );
    });

    test('ticking fewer weekdays than days-per-week shortens the programme row '
        'too, not just the schedule', () async {
      // The two must agree: `deriveProgrammeProgress` measures completions
      // against `Programme.daysPerWeek`, so a row claiming four days over a
      // two-day schedule would show progress the user can never finish.
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final template = programmeTemplates.first; // 4 days a week
      final container = await containerWithProfile(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: _roleCatalogue(label: 'None (Bodyweight)'),
        profile: const UserProfile(
          uid: 'alice',
          schedule: TrainingSchedule(
            daysPerWeek: 4,
            preferredWeekdays: [DateTime.tuesday, DateTime.saturday],
          ),
        ),
      );

      await container.read(programmeActionProvider.notifier).enroll(template);

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
        // Two candidates for one role, one of them tagged with the focus
        // zone. Gate P changed what a focus zone DOES: it used to pick the
        // pool, which a role structure cannot support — someone who asks for
        // core work still needs a squat in the squat slot. It now orders the
        // candidates within each role, so the assertion below is that the
        // focus-tagged one comes first, not that it is the only one.
        catalogue: _roleCatalogue(extra: [
          _ex('core_squat', title: 'Wall Sit', muscles: const ['core']),
        ]),
        profile: const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(focusZones: [FocusZone.core]),
        ),
      );

      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.first);

      expect(programmeRepo.cached('alice').single.muscles, ['core']);
      final scheduled = {
        for (final r in sessionRepo.cached('alice')) ...[
          r.exerciseId,
          ...r.extraExercises.map((e) => e.exerciseId),
        ],
      };
      expect(scheduled, contains('core_squat'),
          reason: 'the focus zone must reach the selection, not merely the row');
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
        catalogue: _roleCatalogue(),
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
        catalogue: _roleCatalogue(),
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
