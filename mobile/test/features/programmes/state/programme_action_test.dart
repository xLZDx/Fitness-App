import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
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

ProviderContainer _container({
  required MockProgrammeRepository programmeRepo,
  required MockScheduledSessionRepository sessionRepo,
  required List<ExerciseItem> catalogue,
  AuthUser? user,
}) {
  return ProviderContainer(overrides: [
    programmeRepositoryProvider.overrideWithValue(programmeRepo),
    scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
    authUserProvider.overrideWith((_) => Stream.value(user)),
    safeCatalogProvider.overrideWith((ref) async => catalogue),
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
