import 'dart:async';
import 'dart:convert';
import 'dart:io';

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
import 'package:fitness_app/features/programmes/data/movement_role.dart';
import 'package:fitness_app/features/programmes/data/programme.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
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
  // F015/B1: replaces the cleared context below outright, so a case can
  // enrol as a person the safety layer refuses.
  SafetyContext? safety,
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
      if (safety != null) return safety;
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
  /// F015 (G-B/B1) — the whole-person gate applies to BOTH enrolment arms.
  ///
  /// `programme_providers.dart` reads a `ProgrammeSpec` for the template and
  /// builds through `buildProgramme` when there is one; `buildProgramme`
  /// refuses a blocked person itself. The `else` arm — templates with no
  /// declared role structure, `shred_endurance` and `shoulders_arms` — called
  /// `buildProgrammeSchedule` with an injury-filtered, equipment-sliced
  /// catalogue and no safety context at all. So which of two templates a
  /// person happened to tap decided whether their screening was honoured.
  group('F015/B1: a refused person is refused whichever template they tap',
      () {
    SafetyContext chestPain() => SafetyContext(
          screening: screen({
            for (final q in ParQQuestion.values)
              q: q == ParQQuestion.chestPain,
          }),
        );

    // G-E note. This group used to split the templates into a spec-BEARING
    // and a spec-LESS arm, because only the first ran the safety gate. G-E
    // gave every shipped template a spec and deleted the second arm outright,
    // so `firstWhere((t) => programmeSpecFor(t.id) == null)` — what this file
    // used to select the defective case with — now throws `StateError`.
    //
    // The finding is not obsolete, only its old shape: it was about ONE
    // template escaping the gate, so the proof that survives is every shipped
    // template being subject to it, checked by name rather than by whichever
    // two the list happened to hold.
    test('every shipped template refuses a blocked person, and writes nothing',
        () async {
      for (final template in programmeTemplates) {
        final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
        addTearDown(programmeRepo.dispose);
        final sessionRepo =
            MockScheduledSessionRepository(latency: Duration.zero);
        addTearDown(sessionRepo.dispose);
        final container = _container(
          programmeRepo: programmeRepo,
          sessionRepo: sessionRepo,
          catalogue: _roleCatalogue(),
          user: const AuthUser(uid: 'u1', displayName: 'T'),
          safety: chestPain(),
        );
        addTearDown(container.dispose);
        await container.read(authUserProvider.future);

        await container.read(programmeActionProvider.notifier).enroll(template);

        final state = container.read(programmeActionProvider);
        expect(state.hasError, isTrue, reason: template.id);
        expect(state.error, isA<ProgrammeNotViable>(), reason: template.id);
        expect(
          (state.error as ProgrammeNotViable).findings.map((f) => f.fault),
          contains(ProgrammeFault.blockedBySafety),
          reason: 'N01 renders the stated refusal off exactly this fault '
              '(${template.id})',
        );
        expect(programmeRepo.cached('u1'), isEmpty,
            reason: 'nothing may be written for a person who was refused '
                '(${template.id})');
        expect(sessionRepo.cached('u1'), isEmpty, reason: template.id);
      }
    });

    test('a template id with no declared structure refuses instead of filling',
        () async {
      // The arm that replaced `_fillDay`. Unreachable from the shipped list by
      // construction — which is the point of the loop above — but reachable
      // from a stored enrolment written by an older build, and THAT is the
      // path that used to reach the alphabetical filler.
      const unshipped = ProgrammeTemplate(
        id: 'retired_v1_programme',
        goal: ProgrammeGoal.strength,
        level: ExerciseDifficulty.beginner,
        weeks: 4,
        daysPerWeek: 3,
        muscles: ['chest'],
      );
      expect(programmeSpecFor(unshipped.id), isNull,
          reason: 'the fixture is only meaningful while this stays true');

      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: _roleCatalogue(),
        user: const AuthUser(uid: 'u1', displayName: 'T'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container.read(programmeActionProvider.notifier).enroll(unshipped);

      final state = container.read(programmeActionProvider);
      expect(state.error, isA<ProgrammeNotViable>());
      expect(
        (state.error as ProgrammeNotViable).findings.map((f) => f.fault),
        contains(ProgrammeFault.noDeclaredStructure),
      );
      expect(programmeRepo.cached('u1'), isEmpty);
      expect(sessionRepo.cached('u1'), isEmpty,
          reason: 'NO_SAFE_VIABLE_PROGRAMME is a result, not a half-written one',
      );
    });
  });

  /// G-E — F021 and F022, measured where the defect actually was.
  ///
  /// `programme_builder_test.dart` asserts both criteria against
  /// `buildProgramme` directly, and that is not a proof of these findings:
  /// `buildProgramme` already satisfied them before G-E. The defect was that
  /// `shred_endurance` and `shoulders_arms` never REACHED it — enrolment sent
  /// them to `buildProgrammeSchedule`/`_fillDay`, which walked the catalogue
  /// alphabetically. So the proof has to run through `enroll` and read what
  /// was written to the session repository, which is what the user gets.
  ///
  /// Both cases below fail against the pre-G-E implementation. The mutation
  /// run is recorded in the decision log.
  group('G-E: the templates that used the filler now build from a spec', () {
    /// Four candidates per role, so rotation has somewhere to go.
    ///
    /// `_roleCatalogue` carries two, which is enough to FILL every slot and
    /// therefore enough for every case above, but not enough to distinguish a
    /// rotating builder from a repeating one — with two candidates a role must
    /// reuse one every other session. F022 is about that distinction, so it
    /// needs a pool that could have repeated and did not.
    ///
    /// Titles, not ids: `movementRoleOf` classifies on the title.
    List<ExerciseItem> deepRoleCatalogue() {
      const byRole = <String, List<String>>{
        'sq': ['Bodyweight Squat', 'Goblet Squat', 'Front Squat', 'Box Squat'],
        'hi': [
          'Romanian Deadlift',
          'Glute Bridge',
          'Kettlebell Swing',
          'Good Morning',
        ],
        'hp': ['Push Up', 'Bench Press', 'Chest Press', 'Ring Dip'],
        'vp': [
          'Overhead Press',
          'Push Press',
          'Arnold Press',
          'Military Press',
        ],
        'hl': ['Bent Over Row', 'Seated Row', 'Face Pull', 'Cable Row'],
        'vl': ['Pull Up', 'Lat Pulldown', 'Chin Up', 'Wide Pulldown'],
        'sl': [
          'Walking Lunge',
          'Bulgarian Split Squat',
          'Step Up',
          'Reverse Lunge',
        ],
        'ce': ['Front Plank', 'Hollow Hold', 'Ab Wheel', 'Side Plank'],
        'cr': [
          'Russian Twist',
          'Cable Woodchop',
          'Pallof Press',
          'Oblique Crunch',
        ],
      };
      return [
        for (final entry in byRole.entries)
          for (var i = 0; i < entry.value.length; i++)
            _ex('${entry.key}$i', title: entry.value[i]),
      ];
    }

    /// The scheduled rows, in the order they were written, as exercise-id sets.
    List<Set<String>> writtenSessions(MockScheduledSessionRepository repo) => [
          for (final r in repo.cached('u1'))
            {r.exerciseId, ...r.extraExercises.map((e) => e.exerciseId)},
        ];

    Future<MockScheduledSessionRepository> enrolInto(
        ProgrammeTemplate template) async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: deepRoleCatalogue(),
        user: const AuthUser(uid: 'u1', displayName: 'T'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      await container.read(programmeActionProvider.notifier).enroll(template);
      expect(container.read(programmeActionProvider).hasError, isFalse,
          reason: '${template.id}: ${container.read(programmeActionProvider).error}');
      return sessionRepo;
    }

    ProgrammeTemplate byId(String id) =>
        programmeTemplates.firstWhere((t) => t.id == id);

    for (final id in const ['shred_endurance', 'shoulders_arms']) {
      test('F021: an enrolled $id week covers four primary strength roles',
          () async {
        final repo = await enrolInto(byId(id));
        final byTitle = {for (final e in deepRoleCatalogue()) e.id: e};
        final template = byId(id);
        final firstWeek =
            writtenSessions(repo).take(template.daysPerWeek).expand((s) => s);
        final roles = <MovementRole>{
          for (final exerciseId in firstWeek)
            if (kPrimaryStrengthRoles.contains(movementRoleOf(byTitle[exerciseId]!)))
              movementRoleOf(byTitle[exerciseId]!)!,
        };
        expect(roles.length, greaterThanOrEqualTo(4),
            reason: 'covered ${roles.map((r) => r.name)}');
      });

      test('F022: consecutive $id sessions share at most one exercise',
          () async {
        final repo = await enrolInto(byId(id));
        final sessions = writtenSessions(repo);
        expect(sessions.length, greaterThan(1));
        for (var i = 1; i < sessions.length; i++) {
          final shared = sessions[i - 1].intersection(sessions[i]);
          expect(shared.length, lessThanOrEqualTo(1),
              reason: 'sessions ${i - 1} and $i share $shared');
        }
      });
    }

    /// The shipped catalogue, read the same way `programme_builder_test.dart`
    /// reads it.
    ///
    /// F021 and F022 were both MEASURED against these 1,887 rows, so the
    /// end-to-end proof has to run on them too. The fixtures above cannot
    /// reproduce F022: the filler walked the pool alphabetically, and a
    /// 36-row fixture is small enough that the walk does not come back around
    /// to a previous day's exercises the way it does on the real catalogue.
    List<ExerciseItem> shippedCatalogue() {
      final file = File('assets/data/exercises_vendor.json');
      expect(file.existsSync(), isTrue,
          reason: 'F021/F022 were measured against the shipped catalogue');
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
      return rows;
    }

    /// Enrols into `shred_endurance` on the shipped catalogue and returns the
    /// written sessions with the rows needed to classify them.
    ///
    /// F021 and F022 get a case each rather than sharing one, so that each
    /// carries its own mutation evidence: a single case stops at the first
    /// failed expectation, and F021 fails first against the old
    /// implementation, which would leave F022 unproven.
    Future<(List<Set<String>>, Map<String, ExerciseItem>, ProgrammeTemplate)>
        enrolOnShippedCatalogue() async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final catalogue = shippedCatalogue();
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: catalogue,
        user: const AuthUser(uid: 'u1', displayName: 'T'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      final template = byId('shred_endurance');
      await container.read(programmeActionProvider.notifier).enroll(template);
      expect(container.read(programmeActionProvider).hasError, isFalse,
          reason: '${container.read(programmeActionProvider).error}');

      final sessions = writtenSessions(sessionRepo);
      expect(sessions, hasLength(template.weeks * template.daysPerWeek));
      return (sessions, {for (final e in catalogue) e.id: e}, template);
    }

    test('F021: a shipped-catalogue week is a strength week, not whatever '
        'sorts first', () async {
      // The finding as it was originally measured, at the surface that
      // produced it. `shred_endurance` is the template whose enrolment used to
      // reach `_fillDay`, and against that implementation this reports
      // `covered ()` — not one primary strength pattern in the whole week.
      final (sessions, rows, template) = await enrolOnShippedCatalogue();
      final roles = <MovementRole>{
        for (final id in sessions.take(template.daysPerWeek).expand((s) => s))
          if (rows[id] != null &&
              kPrimaryStrengthRoles.contains(movementRoleOf(rows[id]!)))
            movementRoleOf(rows[id]!)!,
      };
      expect(roles.length, greaterThanOrEqualTo(4),
          reason: 'covered ${roles.map((r) => r.name)}');
    });

    test('F022: shipped-catalogue sessions do not repeat each other', () async {
      // Measured pairwise across the whole 8-week enrolment rather than on one
      // pair, so a rotation that only drifts apart later still has to hold at
      // week 1.
      final (sessions, _, _) = await enrolOnShippedCatalogue();
      for (var i = 1; i < sessions.length; i++) {
        final shared = sessions[i - 1].intersection(sessions[i]);
        expect(shared.length, lessThanOrEqualTo(1),
            reason: 'sessions ${i - 1} and $i share $shared');
      }
    });

    test('a catalogue that satisfies no role refuses instead of force-filling',
        () async {
      // NO_SAFE_VIABLE_PROGRAMME as a result rather than an error condition.
      // `_fillDay` took whatever the pool held and wrote a full multi-week
      // schedule regardless; these rows classify as nothing at all, so the
      // spec pipeline has no candidate for any slot.
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: [
          _ex('m1', title: 'Hamstring Stretch'),
          _ex('m2', title: 'Pigeon Pose'),
          _ex('m3', title: 'Cat Cow Stretch'),
        ],
        user: const AuthUser(uid: 'u1', displayName: 'T'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .enroll(byId('shred_endurance'));

      expect(container.read(programmeActionProvider).error,
          isA<ProgrammeNotViable>());
      expect(programmeRepo.cached('u1'), isEmpty);
      expect(sessionRepo.cached('u1'), isEmpty,
          reason: 'a refusal must not leave a half-written programme behind');
    });

    test('an empty catalogue refuses deterministically', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: const [],
        user: const AuthUser(uid: 'u1', displayName: 'T'),
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .enroll(byId('shred_endurance'));

      expect(container.read(programmeActionProvider).error,
          isA<ProgrammeNotViable>());
      expect(sessionRepo.cached('u1'), isEmpty);
    });
  });

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

  /// R-03 — the terminal mutation refuses on its own authority.
  ///
  /// `addExerciseToActiveProgramme` schedules training. Until R-03 it carried
  /// no safety check at all and was safe only because its single caller sits
  /// behind an `EligibilityNotice`. A review can confirm that no bypass exists
  /// TODAY; it cannot confirm that none appears the next time somebody adds a
  /// second "add to programme" entry point.
  ///
  /// So these cases do exactly what a second caller would: they invoke the
  /// domain operation directly, with no UI in the way, and require it to
  /// refuse by itself. The mutation run (deleting the gate from
  /// `programme_providers.dart`) is recorded in the decision log — the three
  /// refusal cases fail and the [Degraded] case stays green, which is what
  /// makes the last one worth having.
  group('R-03: addExerciseToActiveProgramme is gated at the mutation', () {
    /// An active programme already on file, so a refusal cannot be mistaken
    /// for "there was nothing to add to". Seeded through the repository rather
    /// than by enrolling, because a refused person cannot enrol.
    Programme activeProgramme() => Programme(
          id: 'p1',
          templateId: 'strength_base',
          title: 'strength_base',
          goal: ProgrammeGoal.strength,
          level: ExerciseDifficulty.beginner,
          weeks: 4,
          daysPerWeek: 3,
          startedAt: DateTime(2026, 1, 1),
        );

    /// Invokes the domain operation directly and returns what it left behind.
    Future<(Object?, MockScheduledSessionRepository)> addDirectly(
      ExerciseItem exercise,
      SafetyContext safety,
    ) async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      await programmeRepo.save('alice', activeProgramme());

      final container = _container(
        programmeRepo: programmeRepo,
        sessionRepo: sessionRepo,
        catalogue: _roleCatalogue(),
        user: const AuthUser(uid: 'alice', displayName: 'Alice'),
        safety: safety,
      );
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      await container.read(programmesProvider.future);
      expect(container.read(activeProgrammeProvider), isNotNull,
          reason: 'the fixture is only meaningful with a programme to add to');

      await container
          .read(programmeActionProvider.notifier)
          .addExerciseToActiveProgramme(exercise);

      return (container.read(programmeActionProvider).error, sessionRepo);
    }

    SafetyContext cleared({HealthFlags? health}) => SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          health: health ?? HealthFlags.empty,
        );

    test('a whole-person block refuses, and schedules nothing', () async {
      final (error, sessionRepo) = await addDirectly(
        _ex('bonus', muscles: ['chest']),
        SafetyContext(
          screening: screen({
            for (final q in ParQQuestion.values) q: q == ParQQuestion.chestPain,
          }),
        ),
      );

      expect(error, isA<ProgrammeNotViable>());
      expect(
        (error as ProgrammeNotViable).findings.map((f) => f.fault),
        contains(ProgrammeFault.blockedBySafety),
        reason: 'the refusal must carry the fault the UI renders the stated '
            'reason off, not a bare StateError',
      );
      expect(sessionRepo.cached('alice'), isEmpty);
    });

    test('an exercise-specific block refuses a person who may otherwise train',
        () async {
      // Not the whole-person gate: this person is cleared for training and is
      // refused only THIS exercise. A gate that checked `allowsAnyTraining`
      // alone would let it through, so this is what separates the two.
      final (error, sessionRepo) = await addDirectly(
        ExerciseItem(
          id: 'bonus',
          title: 'Deep Squat',
          equipmentId: null,
          equipmentLabel: null,
          muscles: const ['quads'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 20,
          summary: '',
          steps: const [],
          contraindications: const ['knee'],
        ),
        cleared(
          health: const HealthFlags(
            restrictions: {MovementRestriction.deepKneeFlexion},
          ),
        ),
      );

      expect(error, isA<ProgrammeNotViable>());
      expect(sessionRepo.cached('alice'), isEmpty);
    });

    test('a safety context that cannot be resolved refuses rather than '
        'proceeding', () async {
      // Fail-closed. "We could not tell" must not read as "go ahead" on a path
      // that schedules training. The failure travels out as the error it is,
      // rather than being caught and treated as "no restrictions known".
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      await programmeRepo.save('alice', activeProgramme());

      final container = ProviderContainer(overrides: [
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
        scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'alice', displayName: 'A'))),
        safeCatalogProvider.overrideWith((ref) async => _roleCatalogue()),
        safetyContextProvider.overrideWith(
            (ref) async => throw StateError('profile unreachable')),
      ]);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      await container.read(programmesProvider.future);

      await container
          .read(programmeActionProvider.notifier)
          .addExerciseToActiveProgramme(_ex('bonus'));

      expect(container.read(programmeActionProvider).error, isA<StateError>());
      expect(sessionRepo.cached('alice'), isEmpty);
    });

    test('an exercise the user lacks the equipment for is still addable',
        () async {
      // R4-A's finding, followed to its cause. The player shows an exercise
      // through `exerciseResolutionProvider`, which deliberately builds its
      // context WITHOUT equipment: tapping a leg press you do not own is an
      // explicit statement about what you want to look at, and refusing it
      // would turn a browse into a prescription (that provider's own doc says
      // exactly this).
      //
      // The R-03 gate read `safetyContextProvider`, which DOES carry
      // equipment. So the two disagreed, and the disagreement was reachable in
      // the most ordinary case there is: a home user taps a barbell exercise,
      // the page shows it, and "add to programme" refuses -- with the raw
      // `ProgrammeNotViable([...])` in a snackbar, because the caller has no
      // branch for a refusal it was never supposed to receive.
      //
      // Equipment is not a safety rule and this gate is a safety gate.
      final (error, sessionRepo) = await addDirectly(
        ExerciseItem(
          id: 'bonus',
          title: 'Barbell Bench Press',
          equipmentId: 'barbell',
          equipmentLabel: 'Barbell',
          muscles: const ['chest'],
          difficulty: ExerciseDifficulty.beginner,
          durationMinutes: 20,
          summary: '',
          steps: const [],
        ),
        SafetyContext(
          screening: screen({for (final q in ParQQuestion.values) q: false}),
          equipment: const EquipmentAccess(
            location: TrainingLocation.home,
            available: [EquipmentKind.bodyweight],
          ),
        ),
      );

      expect(error, isNull,
          reason: 'equipment is not a safety rule. The user chose this '
              'exercise on a page that showed it to them');
      expect(sessionRepo.cached('alice').where((r) => r.exerciseId == 'bonus'),
          hasLength(1));
    });

    test('a caveat the catalogue cannot screen does NOT refuse', () async {
      // The other direction, and the reason the gate reads `isAllowed` rather
      // than `is Allowed`. `impact` carries no region tag, so it produces a
      // [Degraded] advisory — an honest "we could not check this for you". If
      // that refused, every user carrying an unscreenable restriction would
      // lose the button entirely, which is the same defect that once emptied
      // the catalogue.
      final (error, sessionRepo) = await addDirectly(
        _ex('bonus', muscles: ['chest']),
        cleared(
          health: const HealthFlags(
            restrictions: {MovementRestriction.impact},
          ),
        ),
      );

      expect(error, isNull, reason: 'a caveat is not a refusal');
      expect(sessionRepo.cached('alice').where((r) => r.exerciseId == 'bonus'),
          hasLength(1));
    });
  });
}
