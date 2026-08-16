import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/session_screening_providers.dart';

/// The stale-state attack.
///
/// Every other proof in this repository fixes the user's safety state, then
/// asks a surface what it does. That is not how the hazard arrives. It arrives
/// as a TRANSITION: content is fetched, cached, and rendered while the user is
/// cleared, and the answer they gave afterwards has to reach it anyway.
///
/// The invariant under attack:
///
/// > cached UI state is not authority. A terminal action reads the CURRENT
/// > safety state, not the one that was true when the screen was built.
///
/// So each case here holds ONE container across the change, exactly as a
/// running app does, rather than building a fresh one per state — a fresh
/// container would prove nothing, because it never held the stale value.
void main() {
  const squat = ExerciseItem(
    id: 'squat',
    title: 'Back Squat',
    equipmentId: null,
    muscles: ['quads'],
    difficulty: ExerciseDifficulty.beginner,
    durationMinutes: 20,
    summary: '',
    steps: [],
    contraindications: ['knee'],
  );

  ExerciseItem ex(String id, String title) => ExerciseItem(
        id: id,
        title: title,
        equipmentId: null,
        muscles: const [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 20,
        summary: '',
        steps: const [],
      );

  final catalogue = <ExerciseItem>[
    squat,
    ex('sq2', 'Goblet Squat'),
    ex('hi', 'Romanian Deadlift'),
    ex('hi2', 'Glute Bridge'),
    ex('hp', 'Push Up'),
    ex('hp2', 'Bench Press'),
    ex('vp', 'Overhead Press'),
    ex('vp2', 'Push Press'),
    ex('hl', 'Bent Over Row'),
    ex('hl2', 'Seated Row'),
    ex('vl', 'Pull Up'),
    ex('vl2', 'Lat Pulldown'),
    ex('sl', 'Walking Lunge'),
    ex('sl2', 'Bulgarian Split Squat'),
    ex('ce', 'Front Plank'),
    ex('ce2', 'Hollow Hold'),
    ex('cr', 'Russian Twist'),
    ex('cr2', 'Cable Woodchop'),
  ];

  UserProfile profileWith({
    List<Injury> injuries = const [],
    bool chestPain = false,
  }) =>
      UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: {
            for (final q in ParQQuestion.values)
              q: chestPain && q == ParQQuestion.chestPain,
          },
          injuries: injuries,
        ),
      );

  SafetyContext contextFor(UserProfile p) => SafetyContext(
        screening: screen(p.health.screening),
        injuries: p.health.injuries,
        health: p.health.flags,
      );

  /// A container whose profile can CHANGE while it is alive.
  ///
  /// `_MutableProfile` is a notifier rather than an override swap because an
  /// override swap disposes and rebuilds the container's providers, which is
  /// the one thing that would make this file vacuous: it would test a fresh
  /// read, not an invalidated stale one.
  ({ProviderContainer container, void Function(UserProfile) change}) live(
      UserProfile initial) {
    final source = StateProvider<UserProfile>((_) => initial);
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      screeningProfileProvider
          .overrideWith((ref) async => ref.watch(source)),
      safetyContextProvider
          .overrideWith((ref) async => contextFor(ref.watch(source))),
      safeCatalogProvider.overrideWith((ref) async {
        final safety = await ref.watch(safetyContextProvider.future);
        return eligibleExercises(catalogue, safety);
      }),
      equipmentRepositoryProvider.overrideWithValue(_FakeRepo(catalogue)),
    ]);
    addTearDown(container.dispose);
    return (
      container: container,
      change: (p) => container.read(source.notifier).state = p,
    );
  }

  test('allowed, resolved, then injured: the SAME container re-answers',
      () async {
    final app = live(profileWith());

    // The user is cleared and the squat resolves. This value is now cached.
    final before = await app.container.read(exerciseResolutionProvider('squat').future);
    expect(before.withheldFor, isEmpty, reason: 'precondition: it was allowed');

    // They log a knee injury.
    app.change(profileWith(injuries: const [Injury(bodyPart: 'knee', type: 'strain')]));

    final after = await app.container.read(exerciseResolutionProvider('squat').future);
    expect(after.withheldFor, isNotEmpty,
        reason: 'the cached "allowed" must not survive the answer that '
            'contradicts it');
    expect(after.exercise, isNotNull,
        reason: 'withheld, not vanished — the user must be able to see why');
  });

  test('a scheduled session written while cleared is struck after the injury',
      () async {
    // The cached-workout case: the row is already in the repository, written
    // when the exercise was fine. Nothing rewrites it — the session carries no
    // safety verdict by design — so the only thing standing between the user
    // and a contraindicated workout is re-resolution at read time.
    final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
    addTearDown(sessionRepo.dispose);

    final source = StateProvider<UserProfile>((_) => profileWith());
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      screeningProfileProvider.overrideWith((ref) async => ref.watch(source)),
      safetyContextProvider
          .overrideWith((ref) async => contextFor(ref.watch(source))),
      equipmentRepositoryProvider.overrideWithValue(_FakeRepo(catalogue)),
      scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
      upcomingSessionsProvider.overrideWith((ref) => [
            ScheduledSession(
              id: 's1',
              exerciseId: 'squat',
              exerciseTitle: 'Back Squat',
              scheduledFor: DateTime(2026, 9, 1),
              durationMinutes: 20,
            ),
          ]),
    ]);
    addTearDown(container.dispose);

    final before =
        await container.read(screenedUpcomingSessionsProvider.future);
    expect(before.single.withheldExerciseIds, isEmpty);

    container.read(source.notifier).state =
        profileWith(injuries: const [Injury(bodyPart: 'knee', type: 'strain')]);

    final after = await container.read(screenedUpcomingSessionsProvider.future);
    expect(after.single.withheldExerciseIds, contains('squat'),
        reason: 'a session scheduled before the injury must be struck after '
            'it, because nothing rewrites the stored row');
  });

  test('unscreened, catalogue cached, then a stated block: the feed still '
      'shows, the terminal action does not', () async {
    // The three-state distinction under a transition. Going from "nothing
    // stated" to "something stated that refuses you" must change the TERMINAL
    // answer and must not empty the library.
    final app = live(profileWith());
    final firstFeed = await app.container.read(safeCatalogProvider.future);
    expect(firstFeed, isNotEmpty);

    app.change(profileWith(chestPain: true));

    final safety = await app.container.read(safetyContextProvider.future);
    expect(safety.blockedByAStatedAnswer, isTrue);
    expect(safety.allowsAnyTraining, isFalse);

    final feed = await app.container.read(safeCatalogProvider.future);
    expect(feed, isNotEmpty,
        reason: 'a whole-person block is not a reason to empty the library');

    final tapped =
        await app.container.read(exerciseResolutionProvider('sq2').future);
    expect(tapped.withheldFor, isNotEmpty,
        reason: 'the terminal question must take the new answer');
  });

  test('enrolled while cleared, then blocked: a second enrolment is refused',
      () async {
    // The programme half. G-E reads the safety context at enrolment time, so
    // this proves the read is CURRENT rather than a value captured when the
    // page was built.
    final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
    addTearDown(programmeRepo.dispose);
    final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
    addTearDown(sessionRepo.dispose);

    final source = StateProvider<UserProfile>((_) => profileWith());
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      screeningProfileProvider.overrideWith((ref) async => ref.watch(source)),
      safetyContextProvider
          .overrideWith((ref) async => contextFor(ref.watch(source))),
      safeCatalogProvider.overrideWith((_) async => catalogue),
      equipmentRepositoryProvider.overrideWithValue(_FakeRepo(catalogue)),
      programmeRepositoryProvider.overrideWithValue(programmeRepo),
      scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
    ]);
    addTearDown(container.dispose);
    await container.read(authUserProvider.future);

    final template = programmeTemplates.firstWhere((t) => t.id == 'gym_start');
    await container.read(programmeActionProvider.notifier).enroll(template);
    expect(container.read(programmeActionProvider).hasError, isFalse,
        reason: 'precondition: a cleared user enrols');
    final writtenWhileCleared = sessionRepo.cached('u1').length;
    expect(writtenWhileCleared, greaterThan(0));

    container.read(source.notifier).state = profileWith(chestPain: true);

    await container.read(programmeActionProvider.notifier).enroll(template);
    final error = container.read(programmeActionProvider).error;
    expect(error, isA<ProgrammeNotViable>());
    expect((error as ProgrammeNotViable).findings.map((f) => f.fault),
        contains(ProgrammeFault.blockedBySafety));
    expect(sessionRepo.cached('u1'), hasLength(writtenWhileCleared),
        reason: 'the refused second enrolment wrote nothing further');
  });

  test('the answer being REMOVED reopens what it closed', () async {
    // The direction nobody tests, and the one that produces a silent
    // permanent lockout if the invalidation is one-way. A user who corrects a
    // mistaken injury entry must get their exercise back.
    final app = live(
        profileWith(injuries: const [Injury(bodyPart: 'knee', type: 'strain')]));

    final blocked =
        await app.container.read(exerciseResolutionProvider('squat').future);
    expect(blocked.withheldFor, isNotEmpty);

    app.change(profileWith());

    final reopened =
        await app.container.read(exerciseResolutionProvider('squat').future);
    expect(reopened.withheldFor, isEmpty,
        reason: 'removing the answer must reopen the exercise, or a mistyped '
            'injury is permanent');
  });
}

class _FakeRepo implements EquipmentRepository {
  _FakeRepo(this.rows);
  final List<ExerciseItem> rows;

  @override
  Future<List<EquipmentItem>> listEquipment() async => const [];

  @override
  Future<EquipmentItem?> findEquipment(String id) async => null;

  @override
  Future<List<ExerciseItem>> exercisesFor(String equipmentId) async => const [];

  @override
  Future<List<ExerciseItem>> bodyweightExercises() async => rows;
}
