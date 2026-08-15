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
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// B5d-2 — the programme built from the questionnaire, with no template picked.
///
/// Two layers, deliberately separate. [programmeFromProfile] is pure and can be
/// pinned field by field; going through `enroll` is what proves the thing it
/// produces actually survives the enrolment path — the days-per-week
/// reconciliation, the focus-zone resolution and the schedule generator all sit
/// between the builder and what the user ends up with, and the builder can be
/// perfectly right while any of them drops its answer on the floor.

ExerciseItem _ex(String id, {List<String> muscles = const [], String? title}) =>
    ExerciseItem(
      id: id,
      title: title ?? id,
      equipmentId: null,
      muscles: muscles,
      difficulty: ExerciseDifficulty.beginner,
      durationMinutes: 20,
      summary: '',
      steps: const [],
    );

/// One candidate for every movement role a template programme declares.
///
/// Gate P: enrolling in a template builds by role and refuses rather than
/// fabricating, so a two-row fixture produces no programme at all.
List<ExerciseItem> _roleCatalogue() => [
      _ex('sq', title: 'Bodyweight Squat', muscles: const ['quads']),
      _ex('sq2', title: 'Goblet Squat', muscles: const ['quads']),
      _ex('hi', title: 'Romanian Deadlift', muscles: const ['hamstrings']),
      _ex('hi2', title: 'Glute Bridge', muscles: const ['glutes']),
      _ex('hp', title: 'Push Up', muscles: const ['chest']),
      _ex('hp2', title: 'Bench Press', muscles: const ['chest']),
      _ex('vp', title: 'Overhead Press', muscles: const ['shoulders']),
      _ex('vp2', title: 'Push Press', muscles: const ['shoulders']),
      _ex('hl', title: 'Bent Over Row', muscles: const ['back']),
      _ex('hl2', title: 'Seated Row', muscles: const ['back']),
      _ex('vl', title: 'Pull Up', muscles: const ['back']),
      _ex('vl2', title: 'Lat Pulldown', muscles: const ['back']),
      _ex('sl', title: 'Walking Lunge', muscles: const ['quads']),
      _ex('sl2', title: 'Bulgarian Split Squat', muscles: const ['quads']),
      _ex('ce', title: 'Front Plank', muscles: const ['core']),
      _ex('ce2', title: 'Hollow Hold', muscles: const ['core']),
      _ex('cr', title: 'Russian Twist', muscles: const ['core']),
      _ex('cr2', title: 'Cable Woodchop', muscles: const ['core']),
    ];

void main() {
  group('programmeFromProfile', () {
    test('reads goal, level and days from the answers', () {
      final template = programmeFromProfile(const UserProfile(
        uid: 'alice',
        goals: FitnessGoals(primary: ProgrammeGoal.muscle),
        level: FitnessLevel(tier: FitnessTier.advanced),
        schedule: TrainingSchedule(daysPerWeek: 5),
      ));

      expect(template.id, kProfileProgrammeId);
      expect(template.goal, ProgrammeGoal.muscle);
      expect(template.level, ExerciseDifficulty.advanced);
      expect(template.daysPerWeek, 5);
    });

    test('an unanswered questionnaire lands on the documented defaults', () {
      final template = programmeFromProfile(const UserProfile(uid: 'alice'));

      expect(template.goal, ProgrammeGoal.form);
      expect(template.level, ExerciseDifficulty.beginner);
      expect(template.daysPerWeek, kProfileProgrammeDaysPerWeek);
      expect(template.weeks, kProfileProgrammeWeeks);
    });

    test('a null profile is total, not a crash', () {
      final template = programmeFromProfile(null);
      expect(template.id, kProfileProgrammeId);
      expect(template.goal, ProgrammeGoal.form);
    });

    test('"never trained" is a beginner, not its own tier', () {
      // The catalogue has three difficulties and `FitnessTier` has four. The
      // extra one has to land somewhere, and the gentlest tier is the only
      // direction that is safe to be wrong in.
      final template = programmeFromProfile(const UserProfile(
        uid: 'alice',
        level: FitnessLevel(tier: FitnessTier.never),
      ));
      expect(template.level, ExerciseDifficulty.beginner);
    });

    test('names no muscles, so focus zones are what fills them in', () {
      // The empty list is `ProgrammeTemplate`'s full-body sentinel and the
      // exact condition `programmeMuscles` resolves focus zones under. If this
      // ever starts naming muscles, the user's focus zones stop being read and
      // nothing else in the code would say so.
      final profile = const UserProfile(
        uid: 'alice',
        goals: FitnessGoals(focusZones: [FocusZone.chest, FocusZone.arms]),
      );
      final template = programmeFromProfile(profile);

      expect(template.muscles, isEmpty);
      expect(programmeMuscles(template, profile), isNotEmpty);
    });

    test('the weeks default is a constant, not derived from the goal', () {
      // Pins the decision itself: the questionnaire never asks for a duration,
      // so every goal gets the same one until it does. A future change that
      // makes this goal-dependent has to break this test and say why.
      for (final goal in ProgrammeGoal.values) {
        final template = programmeFromProfile(
            UserProfile(uid: 'alice', goals: FitnessGoals(primary: goal)));
        expect(template.weeks, kProfileProgrammeWeeks, reason: '$goal');
      }
    });
  });

  group('canBuildProgrammeFromProfile', () {
    test('false with no profile at all', () {
      expect(canBuildProgrammeFromProfile(null), isFalse);
    });

    test('false when the questionnaire holds nothing this reads', () {
      // The builder would still produce a programme — it is total — but it
      // would be a generic one wearing a label that claims it came from
      // answers the user never gave.
      expect(
        canBuildProgrammeFromProfile(const UserProfile(uid: 'alice')),
        isFalse,
      );
    });

    test('any single answer is enough', () {
      const cases = <String, UserProfile>{
        'goal': UserProfile(
            uid: 'a', goals: FitnessGoals(primary: ProgrammeGoal.strength)),
        'focus zones': UserProfile(
            uid: 'a', goals: FitnessGoals(focusZones: [FocusZone.back])),
        'tier': UserProfile(
            uid: 'a', level: FitnessLevel(tier: FitnessTier.beginner)),
        'days per week':
            UserProfile(uid: 'a', schedule: TrainingSchedule(daysPerWeek: 3)),
        'named weekdays': UserProfile(
            uid: 'a', schedule: TrainingSchedule(preferredWeekdays: [1, 3, 5])),
      };
      cases.forEach((name, profile) {
        expect(canBuildProgrammeFromProfile(profile), isTrue, reason: name);
      });
    });
  });

  group('enrolling in a questionnaire-built programme', () {
    Future<ProviderContainer> containerWith({
      required UserProfile profile,
      required MockProgrammeRepository programmeRepo,
      required MockScheduledSessionRepository sessionRepo,
      List<ExerciseItem>? catalogue,
    }) async {
      final profileRepo = MockProfileRepository(latency: Duration.zero);
      addTearDown(profileRepo.dispose);
      await profileRepo.save(profile);

      final container = ProviderContainer(overrides: [
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
        scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'alice', displayName: 'A'))),
        safeCatalogProvider.overrideWith((ref) async =>
            catalogue ??
            _roleCatalogue()),
        profileRepositoryProvider.overrideWithValue(profileRepo),
        // Gate P/N. Enrolling in a TEMPLATE now runs the eligibility layer and
        // the role builder; an unscreened profile blocks all training. These
        // cases are about `programmeFromProfile`, so the screening is cleared
        // and the rest of the context still comes from the seeded profile.
        safetyContextProvider.overrideWith((ref) async {
          final p = await ref.watch(screeningProfileProvider.future);
          return SafetyContext(
            screening: screen({for (final q in ParQQuestion.values) q: false}),
            injuries: p?.health.injuries ?? const [],
            health: p?.health.flags ?? HealthFlags.empty,
            equipment: p?.equipment,
          );
        }),
      ]);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      return container;
    }

    test('the whole answer sheet reaches the stored programme', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = await containerWith(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        profile: const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(
            primary: ProgrammeGoal.muscle,
            focusZones: [FocusZone.chest],
          ),
          level: FitnessLevel(tier: FitnessTier.intermediate),
          schedule: TrainingSchedule(daysPerWeek: 3, preferredWeekdays: [1, 3, 5]),
        ),
      );

      final profile = await container.read(screeningProfileProvider.future);
      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeFromProfile(profile));

      final saved = programmeRepo.cached('alice').single;
      expect(saved.templateId, kProfileProgrammeId);
      expect(saved.goal, ProgrammeGoal.muscle);
      expect(saved.level, ExerciseDifficulty.intermediate);
      expect(saved.weeks, kProfileProgrammeWeeks);
      expect(saved.daysPerWeek, 3);
      // The focus zone had somewhere to go precisely because the built
      // template names no muscles of its own.
      expect(saved.muscles, contains('chest'));

      final rows = sessionRepo.cached('alice');
      expect(rows, hasLength(kProfileProgrammeWeeks * 3));
      expect(rows.every((r) => r.programmeId == saved.id), isTrue);
      // B5d-1's promise still holds on this path: every session lands on one
      // of the three weekdays that were actually ticked.
      expect(rows.every((r) => const [1, 3, 5].contains(r.scheduledFor.weekday)),
          isTrue,
          reason: 'a session landed on a weekday the user did not tick');
    });

    test('naming fewer weekdays than days-a-week shortens the programme rather '
        'than scheduling an unticked day', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = await containerWith(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        profile: const UserProfile(
          uid: 'alice',
          schedule: TrainingSchedule(daysPerWeek: 5, preferredWeekdays: [2, 6]),
        ),
      );

      final profile = await container.read(screeningProfileProvider.future);
      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeFromProfile(profile));

      final saved = programmeRepo.cached('alice').single;
      expect(saved.daysPerWeek, 2);
      expect(sessionRepo.cached('alice'),
          hasLength(kProfileProgrammeWeeks * 2));
    });

    test('replaces an active template programme instead of running both',
        () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final container = await containerWith(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        profile: const UserProfile(
          uid: 'alice',
          goals: FitnessGoals(primary: ProgrammeGoal.strength),
        ),
      );

      final action = container.read(programmeActionProvider.notifier);
      await action.enroll(programmeTemplates.first);
      final profile = await container.read(screeningProfileProvider.future);
      await action.enroll(programmeFromProfile(profile));

      final saved = programmeRepo.cached('alice');
      expect(saved, hasLength(2));
      expect(
        saved.firstWhere((p) => p.templateId == programmeTemplates.first.id).status,
        ProgrammeStatus.abandoned,
      );
      expect(
        saved.firstWhere((p) => p.templateId == kProfileProgrammeId).status,
        ProgrammeStatus.active,
      );
    });
  });
}
