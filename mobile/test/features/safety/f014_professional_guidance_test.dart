import 'dart:convert';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/programmes/data/mock_programme_repository.dart';
import 'package:fitness_app/features/programmes/data/programme_builder.dart';
import 'package:fitness_app/features/programmes/data/programme_specs.dart';
import 'package:fitness_app/features/programmes/data/programme_templates.dart';
import 'package:fitness_app/features/programmes/state/programme_providers.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/safety/widgets/eligibility_notice.dart';
import 'package:fitness_app/features/workouts/data/mock_scheduled_session_repository.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';

/// F014 — the app stops prescribing for a state it has never had a policy for.
///
/// ## What the finding was, and what it was not
///
/// Pregnancy and postpartum were never asked, never inferred, never filtered
/// and never warned about, so SPTR generated personalised prescriptions for a
/// state it had not enquired into. Two tests elsewhere used pregnancy
/// specifically as an INVALID value, which is the tell: the concept existed in
/// the codebase only as something that could not be represented.
///
/// The fix deliberately adds no clinical content. There is no trimester, no
/// due date, no postpartum week, no allowlist, no denylist and no risk score,
/// because every one of those is a clinical judgement and this repository has
/// no clinical authority (D1). What it adds is a refusal.
///
/// ## The three states, which is the whole design
///
/// ```text
/// null              not asked                 -> UNKNOWN semantics, unchanged
/// none              asked, nothing reported   -> normal product behaviour
/// reported          asked, state reported     -> whole-person block
/// ```
///
/// The first two must not collapse into each other. "Nobody asked me" is not
/// "I am not pregnant", and a build that treats the first as the second has
/// quietly issued the prescription the finding is about.
void main() {
  // ------------------------------------------------------------- fixtures

  ExerciseItem ex(String id, {String? title}) => ExerciseItem(
        id: id,
        title: title ?? id,
        equipmentId: null,
        primaryMuscles: const [],
        muscles: const [],
        difficulty: ExerciseDifficulty.beginner,
        durationMinutes: 20,
        summary: '',
        steps: const [],
        contraindications: const [],
      );

  /// Real movement titles, in pairs, because `movementRoleOf` reads the TITLE
  /// and the programme builder needs every primary role fillable. A fixture of
  /// meaningless ids makes an enrolment fail for `roleUnfillable` and the
  /// F014 assertion below then passes for the wrong reason.
  List<ExerciseItem> catalogue() => [
        ex('sq', title: 'Bodyweight Squat'),
        ex('sq2', title: 'Goblet Squat'),
        ex('hi', title: 'Romanian Deadlift'),
        ex('hi2', title: 'Glute Bridge'),
        ex('hp', title: 'Push Up'),
        ex('hp2', title: 'Bench Press'),
        ex('vp', title: 'Overhead Press'),
        ex('vp2', title: 'Push Press'),
        ex('hl', title: 'Bent Over Row'),
        ex('hl2', title: 'Seated Row'),
        ex('vl', title: 'Pull Up'),
        ex('vl2', title: 'Lat Pulldown'),
        ex('sl', title: 'Walking Lunge'),
        ex('sl2', title: 'Bulgarian Split Squat'),
        ex('ce', title: 'Front Plank'),
        ex('ce2', title: 'Hollow Hold'),
      ];

  /// Every PAR-Q+ question answered safely, so nothing but F014 can refuse.
  Map<ParQQuestion, bool> clearScreening() =>
      {for (final q in ParQQuestion.values) q: false};

  SafetyContext contextFor(ProfessionalGuidanceNeed? need) => SafetyContext(
        screening: screen(clearScreening()),
        health: HealthFlags(professionalGuidance: need),
      );

  UserProfile profileFor(ProfessionalGuidanceNeed? need) => UserProfile(
        uid: 'u1',
        health: HealthHistory(
          screening: clearScreening(),
          flags: HealthFlags(professionalGuidance: need),
        ),
      );

  const noDeload = DeloadVerdict(
    shouldDeload: false,
    reasons: [],
    suggestedVolumeFactor: 1.0,
  );

  // ------------------------------------------------------- the three states

  group('the three states stay three states', () {
    test('unanswered preserves UNKNOWN semantics and is not a clean answer',
        () {
      final unanswered = contextFor(null);

      // The screening cleared this person, so nothing else refuses them. What
      // must NOT have happened is F014 silently deciding, on their behalf,
      // that an unasked question means "no".
      expect(
        unanswered.wholePersonBlocks
            .where((r) => r.reason == BlockReason.professionalGuidance),
        isEmpty,
        reason: 'an unasked question may not manufacture a block either — '
            'fail-closed on THIS question would refuse every existing user '
            'who onboarded before it was added',
      );

      // And the state is still legible as unanswered downstream. This is the
      // half a boolean cannot express, and the reason the field is a nullable
      // enum rather than `bool isPregnant`.
      expect(unanswered.health.professionalGuidance, isNull);
      expect(HealthFlags(professionalGuidance: null).isUnanswered, isTrue);
      expect(
        HealthFlags(professionalGuidance: ProfessionalGuidanceNeed.none)
            .isUnanswered,
        isFalse,
        reason: '"I am not in any of those situations" is an answer, and a '
            'model that cannot tell it from silence has lost the distinction '
            'this whole audit is about',
      );
    });

    test('an explicit no behaves exactly as before', () {
      final answered = contextFor(ProfessionalGuidanceNeed.none);
      expect(answered.allowsAnyTraining, isTrue);
      expect(answered.blockedByAStatedAnswer, isFalse);
      expect(answered.wholePersonBlocks, isEmpty);
    });

    test('a reported state blocks, and names itself', () {
      final blocked = contextFor(ProfessionalGuidanceNeed.reported);
      expect(blocked.allowsAnyTraining, isFalse);
      expect(
        blocked.blockedByAStatedAnswer,
        isTrue,
        reason: 'this is something the user TOLD us, so the surfaces that '
            'distinguish a stated refusal from an unfinished questionnaire '
            'must see it as stated — otherwise the AI coach keeps prescribing',
      );
      expect(
        blocked.wholePersonBlocks.map((r) => r.reason),
        contains(BlockReason.professionalGuidance),
      );
    });

    test('the block is the only thing this state changes', () {
      // A conservative refusal that also quietly narrowed the catalogue would
      // be inventing clinical content — deciding which exercises are
      // unsuitable, which is exactly what is not authorised here.
      final blocked = contextFor(ProfessionalGuidanceNeed.reported);
      final rows = catalogue();
      expect(
        eligibleExercises(rows, blocked).map((e) => e.id),
        rows.map((e) => e.id),
        reason: 'F014 must not filter a single exercise. It has no clinical '
            'basis on which to prefer one movement over another, and '
            'pretending otherwise would be worse than the gap it closes',
      );
      expect(blocked.intensityCeiling, isNull,
          reason: 'nor may it invent a dose — a ceiling is a prescription');
    });
  });

  // ------------------------------------------------------------- surfaces

  group('no prescribing surface can bypass the block', () {
    test('the planner refuses and states the reason', () {
      final out = buildPlan(
        candidatePool: catalogue(),
        deficit: const {},
        deload: noDeload,
        safety: contextFor(ProfessionalGuidanceNeed.reported),
      );
      expect(out, isA<PlanRefused>());
      expect(
        (out as PlanRefused).reasons.map((r) => r.reason),
        contains(BlockReason.professionalGuidance),
      );
    });

    test('the planner still builds for an explicit no', () {
      // The control. Without it, a planner that refused everybody would pass
      // the case above.
      final out = buildPlan(
        candidatePool: catalogue(),
        deficit: const {},
        deload: noDeload,
        safety: contextFor(ProfessionalGuidanceNeed.none),
      );
      expect(out, isA<PlanReady>());
    });

    test('the programme builder refuses before it composes anything', () {
      final refused = buildProgramme(ProgrammeBuildRequest(
        spec: programmeSpecFor('gym_start', daysPerWeek: 3)!,
        daysPerWeek: 3,
        catalogue: catalogue(),
        safety: contextFor(ProfessionalGuidanceNeed.reported),
        weeks: 4,
      ));
      expect(refused, isA<ProgrammeRefused>());
      expect(
        (refused as ProgrammeRefused).findings.map((f) => f.fault),
        contains(ProgrammeFault.blockedBySafety),
      );
    });
  });

  // ----------------------------------------------------- enrolment + cache

  group('enrolment, deep links and cached state', () {
    Future<ProviderContainer> harness(
      ProfessionalGuidanceNeed? need, {
      MockProgrammeRepository? programmes,
      MockScheduledSessionRepository? sessions,
    }) async {
      final programmeRepo =
          programmes ?? MockProgrammeRepository(latency: Duration.zero);
      final sessionRepo =
          sessions ?? MockScheduledSessionRepository(latency: Duration.zero);
      if (programmes == null) addTearDown(programmeRepo.dispose);
      if (sessions == null) addTearDown(sessionRepo.dispose);

      final container = ProviderContainer(overrides: [
        authUserProvider.overrideWith(
            (_) => Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
        screeningProfileProvider.overrideWith((_) async => profileFor(need)),
        safeCatalogProvider.overrideWith((_) async => catalogue()),
        safetyContextProvider.overrideWith((_) async => contextFor(need)),
        equipmentRepositoryProvider.overrideWithValue(_FakeRepo(catalogue())),
        programmeRepositoryProvider.overrideWithValue(programmeRepo),
        scheduledSessionRepositoryProvider.overrideWithValue(sessionRepo),
      ]);
      addTearDown(container.dispose);
      await container.read(authUserProvider.future);
      return container;
    }

    test('a reported state cannot enrol, and nothing is written', () async {
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final c = await harness(ProfessionalGuidanceNeed.reported,
          programmes: programmeRepo, sessions: sessionRepo);
      await c.read(programmeActionProvider.notifier).enroll(
          programmeTemplates.firstWhere((t) => t.id == 'gym_start'));

      expect(c.read(programmeActionProvider).error, isA<ProgrammeNotViable>());
      expect(programmeRepo.cached('u1'), isEmpty,
          reason: 'a partial write is how a refusal becomes a programme');
      expect(sessionRepo.cached('u1'), isEmpty);
    });

    test('a deep link to an exercise cannot bypass the block', () async {
      // The deep link is the surface with no list in front of it: nothing
      // filtered the id, so whatever refuses it has to refuse at resolution.
      final c = await harness(ProfessionalGuidanceNeed.reported);
      final res = await c.read(exerciseResolutionProvider('sq').future);

      expect(res.exercise, isNotNull,
          reason: 'the exercise exists; saying otherwise is a lie the user '
              'cannot act on');
      expect(res.withheldFor.map((r) => r.reason),
          contains(BlockReason.professionalGuidance));
    });

    test('a deep link resolves normally for an explicit no', () async {
      final c = await harness(ProfessionalGuidanceNeed.none);
      final res = await c.read(exerciseResolutionProvider('sq').future);
      expect(res.withheldFor, isEmpty);
      expect(res.exercise, isNotNull);
    });

    test('a programme cached while eligible does not survive the block',
        () async {
      // The case that matters most, and the one a naive implementation gets
      // wrong: enrol while clear, then report the state. The stored programme
      // is still sitting in the repository, and every surface that renders it
      // must consult the CURRENT context rather than the one that authorised
      // the write.
      final programmeRepo = MockProgrammeRepository(latency: Duration.zero);
      addTearDown(programmeRepo.dispose);
      final sessionRepo = MockScheduledSessionRepository(latency: Duration.zero);
      addTearDown(sessionRepo.dispose);

      final before = await harness(ProfessionalGuidanceNeed.none,
          programmes: programmeRepo, sessions: sessionRepo);
      await before.read(programmeActionProvider.notifier).enroll(
          programmeTemplates.firstWhere((t) => t.id == 'gym_start'));
      expect(before.read(programmeActionProvider).error, isNull);
      expect(programmeRepo.cached('u1'), isNotEmpty,
          reason: 'the premise: there IS a cached programme to resume');

      // Same repositories, new state.
      final after = await harness(ProfessionalGuidanceNeed.reported,
          programmes: programmeRepo, sessions: sessionRepo);

      expect(
        (await after.read(safetyContextProvider.future)).allowsAnyTraining,
        isFalse,
        reason: 'the current context is what any resume path must read',
      );

      // The exercises of that cached programme are refused on tap, which is
      // the terminal action a resume leads to.
      final res = await after.read(exerciseResolutionProvider('sq').future);
      expect(res.withheldFor.map((r) => r.reason),
          contains(BlockReason.professionalGuidance),
          reason: 'a programme authorised last week does not carry authority '
              'into this week');

      // And re-enrolling on top of it is refused too.
      await after.read(programmeActionProvider.notifier).enroll(
          programmeTemplates.firstWhere((t) => t.id == 'gym_start'));
      expect(after.read(programmeActionProvider).error, isA<ProgrammeNotViable>());
    });
  });

  // --------------------------------------------------------------- wording

  group('the wording, rendered, in both languages', () {
    late AppLocalizations en;
    late AppLocalizations ru;

    setUpAll(() async {
      en = await AppLocalizations.delegate.load(const Locale('en'));
      ru = await AppLocalizations.delegate.load(const Locale('ru'));
    });

    const reason = EligibilityReason(BlockReason.professionalGuidance);

    test('it renders, and in the right language', () {
      expect(eligibilityReasonText(en, reason).trim(), isNotEmpty);
      expect(eligibilityReasonText(ru, reason), matches(RegExp(r'[Ѐ-ӿ]')),
          reason: 'a safety refusal shown in the wrong language is the F027 '
              'defect, and this is the most consequential string to lose it on');
      expect(eligibilityReasonText(en, reason),
          isNot(eligibilityReasonText(ru, reason)));
    });

    test('it never says the user is unsafe, or that exercise is prohibited',
        () {
      // The constraint that makes this a product boundary rather than medical
      // advice. Asserted as absence because that is what the instruction
      // actually is: SPTR may say what SPTR will not do, and may not say
      // anything about whether this person should exercise.
      final e = eligibilityReasonText(en, reason).toLowerCase();
      for (final banned in const [
        'unsafe',
        'dangerous',
        'risk',
        'do not exercise',
        'should not exercise',
        'avoid exercise',
        'prohibited',
        'forbidden',
        'not allowed to train',
      ]) {
        expect(e, isNot(contains(banned)), reason: 'en: "$banned"');
      }

      final r = eligibilityReasonText(ru, reason).toLowerCase();
      for (final banned in const [
        'опасно',
        'нельзя',
        'запрещ',
        'риск',
      ]) {
        expect(r, isNot(contains(banned)), reason: 'ru: "$banned"');
      }
    });

    test('it states that training can be appropriate, and refers', () {
      // The positive half. Absence-only assertions would be satisfied by an
      // empty string, and by a refusal that simply stonewalls.
      final e = eligibilityReasonText(en, reason).toLowerCase();
      expect(e, contains('can be appropriate'),
          reason: 'the refusal must not read as "exercise is off limits"');
      expect(e, anyOf(contains('midwife'), contains('doctor')),
          reason: 'a refusal with no route forward is a dead end');

      final r = eligibilityReasonText(ru, reason).toLowerCase();
      expect(r, contains('могут быть уместны'));
      expect(r, anyOf(contains('врач'), contains('акушерк')));
    });

    test('the question asks for no clinical detail', () {
      // The data-minimisation claim, asserted against the shipped copy rather
      // than against the intention. A question that asks for a due date has
      // collected a medical record whatever the enum says.
      for (final (name, l10n) in [('en', en), ('ru', ru)]) {
        final q = l10n.healthStepProfessionalGuidance.toLowerCase();
        for (final banned in const [
          'trimester',
          'триместр',
          'due date',
          'срок',
          'week',
          'недел',
        ]) {
          expect(q, isNot(contains(banned)), reason: '$name: "$banned"');
        }
      }
    });

    test('the answer options are a plain yes and no', () {
      expect(en.guidanceNeedNone, isNotEmpty);
      expect(en.guidanceNeedReported, isNotEmpty);
      expect(ru.guidanceNeedNone, matches(RegExp(r'[Ѐ-ӿ]')));
      expect(ru.guidanceNeedReported, matches(RegExp(r'[Ѐ-ӿ]')));
    });
  });

  // --------------------------------------------------------------- privacy

  group('what actually gets persisted', () {
    test('the stored document carries no medical detail', () {
      // The privacy argument, made against the JSON that really lands in
      // Firestore, in a backup and in a data export — not against the doc
      // comment that claims it.
      final json = const HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      ).toJson();

      expect(json['professionalGuidance'], 'reported');

      final serialised = jsonEncode(json).toLowerCase();
      for (final banned in const [
        'pregnan',
        'postpartum',
        'perinatal',
        'trimester',
        'birth',
        'maternal',
        'due',
      ]) {
        expect(serialised, isNot(contains(banned)),
            reason: 'the persisted state named "$banned". A profile document '
                'that discloses a pregnancy is a medical record; this app '
                'needs to know what it will DO, which is all the generic '
                'value says: $serialised');
      }
    });

    test('a round trip preserves all three states distinctly', () {
      for (final need in [null, ...ProfessionalGuidanceNeed.values]) {
        final restored =
            HealthFlags.fromJson(HealthFlags(professionalGuidance: need).toJson());
        expect(restored.professionalGuidance, need,
            reason: 'losing a state on reload turns a block into a clean bill');
      }
    });

    test('an unknown stored value is dropped, not defaulted', () {
      // The file's existing rule, which matters more for this field than for
      // any other: defaulting a value this build cannot name would be making
      // up a health answer, in whichever direction the default points.
      final restored = HealthFlags.fromJson({
        'professionalGuidance': 'somethingAFutureBuildAdded',
      });
      expect(restored.professionalGuidance, isNull);
    });

    test('no source file stores a pregnancy-specific field', () {
      // A fence, because the cheap next change is somebody adding
      // `trimester` to `HealthFlags` "while we are here".
      final src = File('lib/features/safety/data/health_flags.dart')
          .readAsStringSync()
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('///'))
          .join('\n')
          .toLowerCase();
      for (final banned in const [
        'trimester',
        'duedate',
        'postpartumweek',
        'gestation',
      ]) {
        expect(src, isNot(contains(banned)),
            reason: 'F014 authorises a refusal, not a medical record: '
                '"$banned"');
      }
    });
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
