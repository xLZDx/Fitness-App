import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_coach/generated_exercise_repository.dart';
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
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// The consolidated A–D adversarial matrix.
///
/// ## Why this file exists when every gate already has its own tests
///
/// G-A, G-B, G-C, G-D and G-E were each proven in isolation, and each proof
/// looked at the surface that gate touched. That is exactly the shape of
/// coverage that let F020 ship half-fixed: a shared rule applied on one screen
/// and not the next, with each screen's own test passing.
///
/// So this asserts ONE SAFETY STATE AGAINST EVERY SURFACE AT ONCE, in a table.
/// A surface added later that forgets the eligibility layer fails here even if
/// its own test file is green, and a state that behaves differently on two
/// screens shows up as two cells of one row disagreeing.
///
/// ## The three states that must never be conflated
///
/// The matrix's rows are chosen to hold the distinction G-B's
/// `blockedByAStatedAnswer` exists for:
///
/// * `unscreened`  — nothing is known. Ordinary browsing content STAYS VISIBLE;
///   terminal training authority is withheld.
/// * `blocked`     — the user stated something that refuses them. Actionable
///   paths are denied.
/// * `cleared`     — authorised for terminal action.
///
/// Collapsing the first two is the failure mode this programme hit twice, and
/// both times it hid the whole app from every un-onboarded user.
void main() {
  ExerciseItem ex(
    String id, {
    String? title,
    List<String> contraindications = const [],
  }) =>
      ExerciseItem(
        id: id,
        title: title ?? id,
        equipmentId: null,
        equipmentLabel: null,
        muscles: const [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 20,
        summary: '',
        steps: const [],
        contraindications: contraindications,
      );

  /// One catalogue used by every cell, so a difference between two cells is a
  /// difference in the SURFACE, never in the fixture.
  List<ExerciseItem> catalogue() => [
        ex('sq', title: 'Bodyweight Squat'),
        ex('sq2', title: 'Goblet Squat'),
        ex('hi', title: 'Romanian Deadlift'),
        ex('hi2', title: 'Glute Bridge'),
        ex('hp', title: 'Push Up'),
        ex('hp2', title: 'Bench Press'),
        ex('vp', title: 'Overhead Press', contraindications: ['shoulder']),
        ex('vp2', title: 'Push Press'),
        ex('hl', title: 'Bent Over Row'),
        ex('hl2', title: 'Seated Row'),
        ex('vl', title: 'Pull Up'),
        ex('vl2', title: 'Lat Pulldown'),
        ex('sl', title: 'Walking Lunge'),
        ex('sl2', title: 'Bulgarian Split Squat'),
        ex('ce', title: 'Front Plank'),
        ex('ce2', title: 'Hollow Hold'),
        ex('cr', title: 'Russian Twist'),
        ex('cr2', title: 'Cable Woodchop'),
      ];

  /// `vp` is contraindicated for a shoulder injury and is an overhead press,
  /// so it is also the row a shoulder RESTRICTION should remove. One exercise
  /// answering to both is deliberate: it is what makes the injury row and the
  /// restriction row comparable.
  const attacked = 'vp';

  /// The states under attack.
  ///
  /// `profile` is what the app actually stores and what
  /// `exerciseResolutionProvider` and `cannotScreenGeneratedFor` read;
  /// `safety` is the derived context the display surfaces read. Both are built
  /// from one description so a row cannot accidentally describe two different
  /// people.
  final states = <String, ({UserProfile? profile, SafetyContext safety})>{
    'cleared': (
      profile: UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: {for (final q in ParQQuestion.values) q: false},
        ),
      ),
      safety: SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
      ),
    ),
    'injury': (
      profile: UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: {for (final q in ParQQuestion.values) q: false},
          injuries: const [
            Injury(bodyPart: 'shoulder', type: 'strain'),
          ],
        ),
      ),
      safety: SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        injuries: const [Injury(bodyPart: 'shoulder', type: 'strain')],
      ),
    ),
    'restriction': (
      profile: UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: {for (final q in ParQQuestion.values) q: false},
          flags: HealthFlags(restrictions: {MovementRestriction.overhead}),
        ),
      ),
      safety: SafetyContext(
        screening: screen({for (final q in ParQQuestion.values) q: false}),
        health: HealthFlags(restrictions: {MovementRestriction.overhead}),
      ),
    ),
    'blocked': (
      profile: UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: {
            for (final q in ParQQuestion.values) q: q == ParQQuestion.chestPain,
          },
        ),
      ),
      safety: SafetyContext(
        screening: screen({
          for (final q in ParQQuestion.values) q: q == ParQQuestion.chestPain,
        }),
      ),
    ),
    'unscreened': (
      profile: null,
      safety: SafetyContext(screening: kUnscreened),
    ),
  };

  ProviderContainer harness(String state, {List<ExerciseItem>? rows}) {
    final s = states[state]!;
    final container = ProviderContainer(overrides: [
      authUserProvider.overrideWith(
          (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
      screeningProfileProvider.overrideWith((_) async => s.profile),
      safeCatalogProvider.overrideWith((_) async => rows ?? catalogue()),
      safetyContextProvider.overrideWith((_) async => s.safety),
      // `exerciseResolutionProvider` walks the REPOSITORY, not the safe
      // catalogue -- a difference worth stating, because it is why a surface
      // can be fixed in one place and still be wrong in the other.
      equipmentRepositoryProvider
          .overrideWithValue(_FakeRepo(rows ?? catalogue())),
      // A REAL generated row, seeded.
      //
      // Without it every `ai::` lookup returns not-found because the cache is
      // empty, and cell C passes for the wrong reason — which is exactly what
      // it did: reverting `cannotScreenGeneratedFor`'s restriction half left
      // this file green. A cell that cannot tell the fix from its absence is
      // not evidence, so the generated row has to exist for the gate to be
      // observable.
      generatedExerciseRepositoryProvider.overrideWithValue(_SeededGenerated()),
    ]);
    addTearDown(container.dispose);
    return container;
  }

  // ---------------------------------------------------------------- states

  group('the three states stay three states', () {
    test('unscreened is not the same as blocked', () {
      final unscreened = states['unscreened']!.safety;
      final blocked = states['blocked']!.safety;

      // Both refuse terminal authority...
      expect(unscreened.allowsAnyTraining, isFalse);
      expect(blocked.allowsAnyTraining, isFalse);

      // ...and only one of them refuses ordinary display.
      expect(unscreened.blockedByAStatedAnswer, isFalse,
          reason: 'nothing was stated, so nothing may be hidden on that basis');
      expect(blocked.blockedByAStatedAnswer, isTrue);
    });

    test('cleared is authorised for terminal action, the other two are not', () {
      expect(states['cleared']!.safety.allowsAnyTraining, isTrue);
      expect(states['injury']!.safety.allowsAnyTraining, isTrue,
          reason: 'an injury narrows the catalogue; it does not refuse the '
              'person');
      expect(states['restriction']!.safety.allowsAnyTraining, isTrue);
    });
  });

  // ------------------------------------------------- catalogue eligibility

  group('A: the eligibility layer, every state', () {
    // `blocked` is TRUE here on purpose, and it is the invariant rather than
    // an oversight. `eligibleExercises` passes `includeWholePerson: false`: it
    // is a DISPLAY filter, narrowing by what the user's injuries and
    // restrictions rule out, never by the whole-person gate. A person the
    // screen refuses still gets a library to read; what they do not get is a
    // terminal action, which groups B and D below assert.
    //
    // My first version of this table expected `false` and was wrong. Writing
    // it down rather than quietly correcting it: the expectation that a
    // blocked user should see an empty library is precisely the
    // over-suppression this programme shipped twice.
    for (final entry in {
      'cleared': true,
      'injury': false,
      'restriction': false,
      'blocked': true,
      'unscreened': true,
    }.entries) {
      test('${entry.key}: overhead press present == ${entry.value}', () async {
        final c = harness(entry.key);
        final all = await c.read(safeCatalogProvider.future);
        final safety = await c.read(safetyContextProvider.future);
        final ids = eligibleExercises(all, safety).map((e) => e.id).toSet();

        expect(ids.contains(attacked), entry.value,
            reason: '${entry.key} saw ${ids.length} of ${all.length} rows');

        // The other half of every row, and the one that matters most: a state
        // that removes the attacked exercise must NOT empty the catalogue.
        // Both times this programme over-suppressed, the tell was here.
        expect(ids, contains('sq'),
            reason: 'an unrelated exercise must survive every state');
      });
    }
  });

  // -------------------------------------------------- exercise resolution

  group('B: tapping the exercise itself, every state', () {
    for (final entry in {
      'cleared': 'found',
      'injury': 'withheld',
      'restriction': 'withheld',
      'blocked': 'withheld',
      'unscreened': 'withheld',
    }.entries) {
      test('${entry.key}: resolving the overhead press is ${entry.value}',
          () async {
        // A tap is "may this person do THIS, now", so unlike the feed above
        // this one IS refused for an unscreened user -- and that difference
        // between the two groups is the invariant, not an inconsistency.
        final c = harness(entry.key);
        final res = await c.read(exerciseResolutionProvider(attacked).future);
        expect(_kind(res), entry.value);
      });
    }

    test('an unscreened refusal is explained, not disguised as not-found',
        () async {
      // The guard for THIS surface, which is a different guard from the feed's.
      //
      // I first wrote this expecting `found`, and that was wrong: a tap is a
      // terminal question, so the whole-person gate applies and an unscreened
      // user is correctly withheld even for a harmless exercise. The property
      // actually worth holding is the one the deep-link fix established --
      // that the refusal names itself. Collapsing it into `notFound` tells a
      // user the exercise does not exist, which is both false and unactionable.
      final c = harness('unscreened');
      final res = await c.read(exerciseResolutionProvider('sq').future);
      expect(_kind(res), 'withheld');
      expect(res.exercise, isNotNull,
          reason: 'the exercise exists and the user must be able to see that '
              'it is being withheld rather than missing');
      expect(res.withheldFor, isNotEmpty,
          reason: 'a refusal with no stated reason cannot be acted on');
    });
  });

  // ------------------------------------------- generated (ai::) exercises

  group('C: an ai:: id can never reach a user who cannot be screened', () {
    for (final state in ['injury', 'restriction']) {
      test('$state: the generated row is not found', () async {
        final c = harness(state);
        final res = await c.read(
            exerciseResolutionProvider(_generatedId).future);
        expect(_kind(res), 'notFound',
            reason: 'a generated row carries no contraindications and never '
                'will at read time, so it cannot be screened for $state');
      });
    }

    test('the control: a cleared user DOES reach the generated row', () async {
      // Without this the group above proves nothing — an empty cache would
      // satisfy every `notFound` assertion. This is the cell that makes the
      // other two mean something.
      final c = harness('cleared');
      final res = await c.read(exerciseResolutionProvider(_generatedId).future);
      expect(_kind(res), 'found',
          reason: 'the seeded generated row must be reachable for a user the '
              'app can screen, or the refusals above are vacuous');
    });

    test('a malformed ai:: id is not found rather than parsed', () async {
      final c = harness('cleared');
      expect(_kind(await c.read(exerciseResolutionProvider('ai::garbage').future)),
          'notFound');
      expect(
          _kind(await c.read(
              exerciseResolutionProvider('ai::a::b::c::d').future)),
          'notFound');
    });

    test('an invented catalogue-looking id is not found, not fabricated',
        () async {
      final c = harness('cleared');
      expect(
          _kind(await c.read(
              exerciseResolutionProvider('ea_this_never_existed').future)),
          'notFound');
    });
  });

  // ------------------------------------------------------ programme gate

  group('D: programme enrolment, every state', () {
    Future<Object?> enrol(String state) async {
      final s = states[state]!;
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);
      final container = ProviderContainer(overrides: [
        authUserProvider
            .overrideWith((_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
        screeningProfileProvider.overrideWith((_) async => s.profile),
        safeCatalogProvider.overrideWith((_) async => catalogue()),
        safetyContextProvider.overrideWith((_) async => s.safety),
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
        scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
      ]);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      await container
          .read(programmeActionProvider.notifier)
          .enroll(programmeTemplates.firstWhere((t) => t.id == 'gym_start'));
      final error = container.read(programmeActionProvider).error;
      if (error == null) {
        // A successful enrolment must have written BOTH halves. A programme
        // row with no sessions is the shape a half-applied refusal takes.
        expect(programmeRepo.cached('u1'), isNotEmpty);
        expect(sessionRepo.cached('u1'), isNotEmpty);
      } else {
        expect(programmeRepo.cached('u1'), isEmpty,
            reason: 'a refusal must write nothing at all ($state)');
        expect(sessionRepo.cached('u1'), isEmpty, reason: state);
      }
      return error;
    }

    test('cleared enrols', () async {
      expect(await enrol('cleared'), isNull);
    });

    for (final state in ['blocked', 'unscreened']) {
      test('$state is refused, and nothing is written', () async {
        final error = await enrol(state);
        expect(error, isA<ProgrammeNotViable>(), reason: state);
        expect(
          (error as ProgrammeNotViable).findings.map((f) => f.fault),
          contains(ProgrammeFault.blockedBySafety),
          reason: 'enrolment prescribes work, so it takes the STRICTER gate: '
              'an unscreened person is refused here even though their library '
              'stays visible ($state)',
        );
      });
    }

    for (final state in ['injury', 'restriction']) {
      test('$state still enrols, on a narrowed catalogue', () async {
        // The over-suppression guard for the programme surface: narrowing is
        // not refusing, and a user with a shoulder problem still gets a
        // programme.
        expect(await enrol(state), isNull, reason: state);
      });
    }
  });

  // ---------------------------------------------------- the cross-gate row

  test('E: one state, every surface, no surface disagreeing', () async {
    // The point of the whole file, stated once. For a movement restriction:
    // the feed hides the attacked row, the tap withholds it, the generated
    // path refuses entirely, and the programme still builds. Four surfaces,
    // one state, asserted together -- which is what a per-gate test file
    // cannot do.
    final c = harness('restriction');
    final all = await c.read(safeCatalogProvider.future);
    final safety = await c.read(safetyContextProvider.future);

    expect(eligibleExercises(all, safety).map((e) => e.id), isNot(contains(attacked)));
    expect(_kind(await c.read(exerciseResolutionProvider(attacked).future)),
        'withheld');
    expect(_kind(await c.read(exerciseResolutionProvider(_generatedId).future)),
        'notFound');
    expect(safety.allowsAnyTraining, isTrue);
    expect(safety.blockedByAStatedAnswer, isFalse,
        reason: 'a restriction narrows; it is not a refusal of the person');
  });
}

/// `ExerciseResolution` is one class with three named constructors, not a
/// sealed hierarchy, so the three outcomes are read off its fields.
String _kind(ExerciseResolution r) {
  if (r.exercise == null) return 'notFound';
  return r.withheldFor.isEmpty ? 'found' : 'withheld';
}

/// Serves the matrix catalogue as bodyweight exercises.
///
/// `exerciseResolutionProvider` reads `EquipmentRepository`, so overriding
/// `safeCatalogProvider` alone leaves it resolving against the real asset
/// repository -- which is how the first run of this file reported
/// `notFound` for every state and looked like a safety pass.
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

/// The id of the seeded generated exercise. Shape matters: the provider parses
/// `ai::<equipmentId>::<index>` and refuses anything else.
const _generatedId = 'ai::machine-1::0';

/// A generated-exercise cache holding one row.
///
/// It carries NO `contraindications`, which is the whole reason the gate
/// exists: the generator emits none, so the eligibility layer would clear this
/// row for every injury and every restriction if it were allowed through.
class _SeededGenerated implements GeneratedExerciseRepository {
  @override
  Future<List<ExerciseItem>?> get(String equipmentId, String languageCode) async {
    if (equipmentId != 'machine-1') return null;
    return const [
      ExerciseItem(
        id: _generatedId,
        title: 'Machine Overhead Press',
        equipmentId: 'machine-1',
        muscles: ['shoulders'],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 20,
        summary: '',
        steps: [],
      ),
    ];
  }

  @override
  Future<void> save(
      String equipmentId, String languageCode, List<ExerciseItem> items) async {}
}
