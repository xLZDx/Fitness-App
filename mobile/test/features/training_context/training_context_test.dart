import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:fitness_app/features/account_deletion/data/local_data_wipe.dart';
import 'package:fitness_app/features/ai_planner/data/plan_builder.dart';
import 'package:fitness_app/features/ai_planner/data/workout_plan.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/recovery/data/deload_detector.dart';
import 'package:fitness_app/features/safety/data/age_policy.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/training_context/data/training_context.dart';
import 'package:fitness_app/features/training_context/state/training_context_providers.dart';
import 'package:fitness_app/features/training_context/widgets/training_context_selector.dart';

ExerciseItem _ex(
  String id, {
  String? equipmentId,
  String? label,
  String? group,
  bool stretch = false,
  ExerciseDifficulty difficulty = ExerciseDifficulty.beginner,
}) =>
    ExerciseItem(
      id: id,
      title: id,
      equipmentId: equipmentId,
      equipmentLabel: label,
      muscles: const ['quads'],
      primaryMuscles: const ['quads'],
      difficulty: difficulty,
      durationMinutes: 8,
      summary: '',
      steps: const [],
      isStretch: stretch,
      vendorGroup: group,
    );

final _pool = <ExerciseItem>[
  _ex('pushup', label: 'None (Bodyweight)'),
  _ex('db_curl', label: 'Dumbbells'),
  _ex('kb_swing', label: 'Kettlebells'),
  _ex('bb_squat', label: 'Barbell'),
  _ex('leg_press', equipmentId: 'leg_press', label: 'Leg Press Machine'),
  _ex('band_row', label: 'Resistance Band'),
  _ex('rope', label: 'Jump rope'),
  _ex('ball_slam', label: 'Medicine Ball'),
  _ex('contradiction', equipmentId: 'bench_press', label: 'None'),
  _ex('cobra', label: 'Yoga Mat', group: 'Yoga', stretch: true),
  _ex('strap_stretch',
      label: 'Resistance Band', group: 'Stretching - Mobility'),
  _ex('headstand',
      label: 'None',
      group: 'Yoga',
      stretch: true,
      difficulty: ExerciseDifficulty.advanced),
];

Set<String> _ids(List<ExerciseItem> l) => {for (final e in l) e.id};

SafetyContext _safety({
  EquipmentAccess? equipment,
  AgeBand band = AgeBand.adult,
}) =>
    SafetyContext(
      screening: screen({for (final q in ParQQuestion.values) q: false}),
      equipment: equipment,
      ageBand: band,
    );

const _gymAndDumbbells = EquipmentAccess(
  location: TrainingLocation.mixed,
  available: [EquipmentKind.fullGym, EquipmentKind.dumbbells],
);

void main() {
  group('equipment per context', () {
    test('gym allows machines and free weights, whatever the profile says', () {
      final got = _ids(eligibleForTrainingContext(
          _pool,
          _safety(
              equipment:
                  const EquipmentAccess(location: TrainingLocation.home)),
          TrainingContext.gymMachines));
      expect(got, containsAll(['leg_press', 'bb_squat', 'db_curl', 'pushup']));
    });

    test('home = bodyweight + owned kit; a gym profile is not carried over',
        () {
      final got = _ids(eligibleForTrainingContext(
          _pool, _safety(equipment: _gymAndDumbbells), TrainingContext.home));
      expect(got, containsAll(['pushup', 'db_curl', 'cobra']));
      expect(got, isNot(contains('leg_press')));
      expect(got, isNot(contains('bb_squat')));
      expect(got, isNot(contains('kb_swing')));
      expect(got, isNot(contains('band_row')));
      expect(got, isNot(contains('contradiction')));
    });

    test('home with no equipment answers is bodyweight only, not everything',
        () {
      final got = _ids(
          eligibleForTrainingContext(_pool, _safety(), TrainingContext.home));
      expect(got, {'pushup', 'cobra', 'headstand'});
    });

    test('outdoors = bodyweight + portable kit + owned dumbbells/kettlebells',
        () {
      final got = _ids(eligibleForTrainingContext(
          _pool,
          _safety(equipment: _gymAndDumbbells),
          TrainingContext.outdoorMinimal));
      expect(got,
          containsAll(['pushup', 'band_row', 'rope', 'ball_slam', 'db_curl']));
      expect(got, isNot(contains('kb_swing')));
      expect(got, isNot(contains('bb_squat')));
      expect(got, isNot(contains('leg_press')));
      expect(got, isNot(contains('contradiction')));
    });

    test('skipped (null context) is exactly the pre-existing filter', () {
      final s = _safety(equipment: _gymAndDumbbells);
      expect(_ids(eligibleForTrainingContext(_pool, s, null)),
          _ids(eligibleExercises(_pool, s)));
    });
  });

  group('yoga', () {
    test('yields only yoga / stretch / mobility, ignoring equipment', () {
      for (final access in [
        null,
        const EquipmentAccess(location: TrainingLocation.home),
        _gymAndDumbbells,
      ]) {
        final got = eligibleForTrainingContext(
            _pool, _safety(equipment: access), TrainingContext.yoga);
        expect(_ids(got), {'cobra', 'strap_stretch', 'headstand'});
        expect(got.every(isYogaExercise), isTrue);
      }
    });
  });

  group('age policy applies in every context', () {
    for (final c in TrainingContext.values) {
      test('senior: advanced pose / max-effort work withheld in ${c.name}', () {
        final pool = [
          ..._pool,
          _ex('deadlift', group: 'Powerlifting', label: 'None'),
        ];
        final got = _ids(eligibleForTrainingContext(
            pool,
            _safety(equipment: _gymAndDumbbells, band: AgeBand.senior),
            c));
        expect(got, isNot(contains('headstand')));
        expect(got, isNot(contains('deadlift')));
        expect(got, isNotEmpty);
      });
    }
  });

  test('plan: context reason is stated and pool is narrowed', () {
    const noDeload = DeloadVerdict(
        shouldDeload: false, reasons: [], suggestedVolumeFactor: 1.0);
    final s = _safety(equipment: _gymAndDumbbells);
    final out = buildPlan(
      candidatePool: narrowToTrainingContext(_pool, s, TrainingContext.yoga),
      deficit: const {},
      deload: noDeload,
      safety: safetyContextForTrainingContext(s, TrainingContext.yoga),
      trainingContext: TrainingContext.yoga,
    ) as PlanReady;
    expect(_ids(out.plan.exercises),
        everyElement(isIn(['cobra', 'strap_stretch', 'headstand'])));
    expect(out.plan.reasons.whereType<TrainingContextReason>().single.context,
        TrainingContext.yoga);
  });

  group('persistence', () {
    ProviderContainer container(String uid) => ProviderContainer(overrides: [
          authUserProvider.overrideWith((_) =>
              Stream.value(AuthUser(uid: uid, displayName: 'T'))),
        ]);

    test('unanswered by default; choice persists per uid; skip is distinct',
        () async {
      SharedPreferences.setMockInitialValues({});
      var c = container('alice');
      expect(await c.read(trainingContextProvider.future),
          TrainingContextAnswer.unanswered);
      await c
          .read(trainingContextProvider.notifier)
          .choose(TrainingContext.home);
      c.dispose();

      c = container('alice');
      expect(await c.read(trainingContextProvider.future),
          const TrainingContextAnswer.chosen(TrainingContext.home));
      c.dispose();

      c = container('bob');
      expect(await c.read(trainingContextProvider.future),
          TrainingContextAnswer.unanswered);
      await c.read(trainingContextProvider.notifier).skip();
      c.dispose();

      c = container('bob');
      final bob = await c.read(trainingContextProvider.future);
      expect(bob, TrainingContextAnswer.skipped);
      expect(bob.answered, isTrue);
      expect(bob.context, isNull);
      c.dispose();
    });

    test('an unreadable stored value reads as unanswered, never a default',
        () {
      expect(
          decodeTrainingContext('garbage'), TrainingContextAnswer.unanswered);
    });

    test("account deletion wipe removes only that uid's answer", () async {
      SharedPreferences.setMockInitialValues({
        trainingContextKeyFor('alice'): 'yoga',
        trainingContextKeyFor('bob'): 'home',
      });
      final prefs = await SharedPreferences.getInstance();
      final docs = Directory.systemTemp.createTempSync('tc_wipe');
      addTearDown(() => docs.deleteSync(recursive: true));
      await DeviceLocalDataWipe(prefs: prefs, documentsDir: docs).wipe('alice');
      expect(prefs.getString(trainingContextKeyFor('alice')), isNull);
      expect(prefs.getString(trainingContextKeyFor('bob')), 'home');
    });
  });

  testWidgets('selector: unanswered shows prompt, four choices and skip; tap stores',
      (t) async {
    SharedPreferences.setMockInitialValues({});
    await t.pumpWidget(ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) =>
            Stream.value(const AuthUser(uid: 'alice', displayName: 'T'))),
      ],
      child: const MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(body: TrainingContextSelector()),
      ),
    ));
    await t.pumpAndSettle();
    for (final c in TrainingContext.values) {
      expect(find.byKey(Key('training-context.${c.name}')), findsOneWidget);
    }
    expect(find.byKey(const Key('training-context.skip')), findsOneWidget);
    await t.tap(find.byKey(const Key('training-context.yoga')));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('training-context.skip')), findsNothing);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString(trainingContextKeyFor('alice')), 'yoga');
  });
}
