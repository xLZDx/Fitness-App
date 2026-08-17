import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/equipment/data/equipment_models.dart';
import 'package:fitness_app/features/equipment/data/equipment_repository.dart';
import 'package:fitness_app/features/equipment/state/equipment_providers.dart';
import 'package:fitness_app/features/equipment/workout_player_page.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/safety/data/eligibility.dart';
import 'package:fitness_app/features/safety/data/health_flags.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/safety/state/eligibility_providers.dart';
import 'package:fitness_app/features/workouts/data/scheduled_session.dart';
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/scheduled_session_providers.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';

/// The substitution surface, across a change in the user's answers.
///
/// ## What this is for
///
/// `_AddExerciseButton` opens a picker whose result is written straight into
/// the logged session. That write is terminal: nothing downstream re-evaluates
/// it, and there is no refusal card that could catch it afterwards. The picker
/// itself filters with `eligibleExercises`, which deliberately does NOT apply
/// the whole-person gate — the page's own doc says so, and gives the reason:
/// the gate is answered upstream by `exerciseResolutionProvider`, which
/// withholds the entry exercise for a blocked user, so the button is never
/// reached.
///
/// That reasoning is correct and it is a claim about COMPOSITION: two
/// mechanisms in different files, each proven separately, relied on to add up.
/// `stale_state_attack_test.dart` proves the provider re-answers when the user
/// answers F014; nothing proved that the SCREEN followed. A `ref.read` in
/// place of the `ref.watch` at `workout_player_page.dart:165` would break the
/// composition without either existing proof going red.
///
/// So this holds one widget tree across the change, exactly as a running app
/// does — a fresh pump would prove nothing, because it never held the stale
/// value — and asserts the picker leaves with it.
void main() {
  const squat = ExerciseItem(
    id: 'squat',
    title: 'Back Squat',
    equipmentId: null,
    muscles: ['quads'],
    difficulty: ExerciseDifficulty.beginner,
    durationMinutes: 20,
    summary: 's',
    steps: ['Stand', 'Sit', 'Drive'],
  );
  const row = ExerciseItem(
    id: 'row',
    title: 'Bent-over Row',
    equipmentId: null,
    muscles: ['back'],
    difficulty: ExerciseDifficulty.beginner,
    durationMinutes: 20,
    summary: 's',
    steps: ['Hinge', 'Pull'],
  );

  UserProfile profile({HealthFlags flags = HealthFlags.empty}) => UserProfile(
        uid: 'u1',
        health: HealthHistory(
          // Fully cleared, so the health answer below is the only thing that
          // can change the verdict.
          screening: {for (final q in ParQQuestion.values) q: false},
          flags: flags,
        ),
      );

  /// One tree, one container, a profile that can change under it.
  ({Widget widget, void Function(UserProfile) change}) app() {
    final source = StateProvider<UserProfile>((_) => profile());
    late ProviderContainer container;
    final widget = ProviderScope(
      overrides: [
        authUserProvider.overrideWith((_) =>
            Stream.value(const AuthUser(uid: 'u1', displayName: 'T'))),
        equipmentRepositoryProvider
            .overrideWithValue(_FakeRepo(const [squat, row])),
        // NOT overridden: `exerciseResolutionProvider` is the mechanism under
        // test, so it has to be the real one. Its inputs are what move.
        screeningProfileProvider.overrideWith((ref) async => ref.watch(source)),
        safetyContextProvider.overrideWith((ref) async {
          final p = ref.watch(source);
          return SafetyContext(
            screening: screen(p.health.screening),
            injuries: p.health.injuries,
            health: p.health.flags,
          );
        }),
        safeCatalogProvider.overrideWith((_) async => const [squat, row]),
        // The picker is hidden until the day's first exercise has been
        // logged -- there is no session to append to before one exists -- so
        // the fixture is a day with a logged entry rather than a bare
        // exercise. Without this the control below finds nothing and every
        // assertion after the change passes for the wrong reason.
        scheduledSessionsProvider.overrideWith((_) => Stream.value([
              ScheduledSession(
                id: 'day_1',
                exerciseId: 'squat',
                exerciseTitle: 'Back Squat',
                scheduledFor: DateTime.utc(2026, 8, 14, 9),
                durationMinutes: 40,
                extraExercises: const [
                  WorkoutSessionExercise(
                      exerciseId: 'row', exerciseTitle: 'Bent-over Row'),
                ],
              ),
            ])),
        workoutSessionsProvider.overrideWith((_) => Stream.value([
              WorkoutSession(
                id: daySessionId('day_1'),
                title: 'Back Squat',
                exercises: const [
                  WorkoutSessionExercise(
                      exerciseId: 'squat', exerciseTitle: 'Back Squat'),
                ],
                startedAt: DateTime.utc(2026, 8, 14, 9),
                completedAt: DateTime.utc(2026, 8, 14, 9, 12),
                status: WorkoutSessionStatus.completed,
              ),
            ])),
      ],
      child: Consumer(builder: (context, ref, _) {
        container = ProviderScope.containerOf(context);
        return MaterialApp(
          theme: AppTheme.dark(),
          locale: const Locale('en'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: const WorkoutPlayerPage(exerciseId: 'squat', dayId: 'day_1'),
        );
      }),
    );
    return (
      widget: widget,
      change: (p) => container.read(source.notifier).state = p,
    );
  }

  Future<void> tall(WidgetTester t) async {
    t.view.physicalSize = const Size(400, 3000);
    t.view.devicePixelRatio = 1.0;
    addTearDown(t.view.reset);
  }

  testWidgets('the picker leaves with the answer that refuses training',
      (t) async {
    await tall(t);
    final a = app();
    await t.pumpWidget(a.widget);
    await t.pumpAndSettle();

    // The control, and it is load-bearing: without it every assertion after
    // the change would pass against a page that never rendered the button.
    expect(find.byKey(const Key('player.addExercise')), findsOneWidget,
        reason: 'precondition: a cleared user is offered the substitution');
    expect(find.byKey(const Key('player.withheld')), findsNothing);

    a.change(profile(
      flags: const HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      ),
    ));
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.addExercise')), findsNothing,
        reason: 'the picker writes straight into the logged session and has no '
            'whole-person gate of its own. It relies on this page having gone '
            'away first, which is only true while the page WATCHES the '
            'resolution rather than reading it once');
    expect(find.byKey(const Key('player.withheld')), findsOneWidget,
        reason: 'withheld with its reason, not a blank screen');
  });

  testWidgets('and comes back when the answer is corrected', (t) async {
    // The direction nobody tests, and the one that produces a silent permanent
    // lockout if the invalidation is one-way.
    await tall(t);
    final a = app();
    await t.pumpWidget(a.widget);
    await t.pumpAndSettle();

    a.change(profile(
      flags: const HealthFlags(
        professionalGuidance: ProfessionalGuidanceNeed.reported,
      ),
    ));
    await t.pumpAndSettle();
    expect(find.byKey(const Key('player.withheld')), findsOneWidget);

    a.change(profile());
    await t.pumpAndSettle();

    expect(find.byKey(const Key('player.addExercise')), findsOneWidget);
    expect(find.byKey(const Key('player.withheld')), findsNothing);
  });
}

class _FakeRepo implements EquipmentRepository {
  const _FakeRepo(this.rows);
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
