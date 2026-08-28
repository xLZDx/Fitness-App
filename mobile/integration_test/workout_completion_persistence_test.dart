import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/features/safety/data/par_q.dart';
import 'package:fitness_app/features/workouts/data/mock_workout_session_repository.dart';
import 'package:fitness_app/features/workouts/data/workout_log.dart' show DifficultyRating;
import 'package:fitness_app/features/workouts/data/workout_session.dart';
import 'package:fitness_app/features/workouts/state/workout_session_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';

/// Device proof for "workout results aren't saving" (operator report,
/// 2026-08-27/28).
///
/// A live on-device investigation (S8, `core/DECISION_LOG.md` 2026-08-28)
/// found the save mechanism itself intact -- three real exercises marked
/// complete through the actual app produced three real Firestore documents,
/// timestamped within seconds of the taps. The account used for the report
/// had simply never cleared the PAR-Q+ health screen, which blocks starting
/// ANY workout with no on-screen hint that "results aren't saving" and
/// "the workout never started" are different problems.
///
/// This file locks in the wiring that live check exercised by hand, so a
/// future regression in it (a button's onTap, `LogSessionAction`,
/// `upsertExerciseById`, the session-key derivation) fails a test instead of
/// waiting for another manual report. Building it also caught a second, real
/// bug: `_MarkCompleteButton.onTap` could silently drop the difficulty
/// rating when the rest timer's insertion disposed the button's own list
/// item mid-flow (fixed in `workout_player_page.dart`, same commit; this
/// file's `difficulty` assertion below is what proves the fix and would
/// catch the regression if it came back).
///
/// Runs against the app's own default in-memory repository
/// (`MockWorkoutSessionRepository`, the same class the pure unit suite
/// already covers) rather than live Firestore -- deliberately: this proves
/// the button-to-repository CONTRACT on every run, phone or emulator,
/// without needing network or credentials. The claim that a save reaches
/// the real backend is a network fact, already proven once on the device
/// and not re-provable by a hermetic test; see the decision log entry above
/// for that evidence. The "remembered for next time" half of the operator's
/// request IS provable hermetically, though -- see the second half of the
/// test below, which tears the widget tree down and rebuilds a fresh
/// `ProviderScope` against the SAME repository instance to prove a cold
/// screen re-reads what a previous screen wrote, rather than only reading
/// back what it just wrote itself in the same scope.
Stream<T> _replay<T>(T value) => Stream<T>.multi((c) => c.add(value));

class _SignedInAuth implements AuthRepository {
  _SignedInAuth(this.user);
  final AuthUser user;

  @override
  AuthUser? get currentUser => user;

  @override
  Stream<AuthUser?> authStateChanges() => _replay<AuthUser?>(user);

  @override
  Future<AuthUser> signInAnonymously() async => user;

  @override
  Future<SignInResult> signInWithGoogle() async =>
      SignInResult(user, GuestUpgrade.notAGuest);

  @override
  Future<void> signOut() async {}
}

/// A profile that has cleared onboarding AND the PAR-Q+ screen.
///
/// The second half is the point of this fixture. `app_test.dart`'s own
/// `_CompletedProfile` leaves `health.screening` empty, which
/// `exerciseResolutionProvider` (whole-person gate ON for a direct
/// `/workout/:id` open) reads as an unanswered screen and blocks every
/// exercise -- exactly the state the operator's real account was in. Reusing
/// that fixture here would test the eligibility block, not the save path.
class _ScreenedProfile implements ProfileRepository {
  _ScreenedProfile(this.profile);
  UserProfile profile;

  @override
  UserProfile? cached(String uid) => profile;

  @override
  Stream<UserProfile?> watch(String uid) => _replay<UserProfile?>(profile);

  @override
  Future<UserProfile?> load(String uid) async => profile;

  @override
  Future<void> save(UserProfile p) async => profile = p;

  @override
  Future<void> delete(String uid) async {}
}

Future<void> main() async {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  const signedIn = AuthUser(
    uid: 'workout-save-e2e',
    displayName: 'E2E',
    email: 'workout-save-e2e@example.com',
  );

  final profile = UserProfile.empty('workout-save-e2e').copyWith(
    personal: const PersonalInfo(
      age: 30,
      heightCm: 175,
      activityLevel: ActivityLevel.moderatelyActive,
    ),
    goals: const FitnessGoals(strength: true),
    completedAt: DateTime(2026, 1, 1),
    health: HealthHistory(
      // Every PAR-Q+ question answered "No" -- SafetyDecision.clear. See the
      // file doc: an incomplete screen here is the actual bug this test
      // exists to distinguish from a broken save.
      screening: {for (final q in ParQQuestion.values) q: false},
    ),
  );

  // Built fresh per `boot()` call, but the REPOSITORY passed in is not --
  // that is what lets the second `boot()` below model "a cold app start"
  // rather than "the same screen re-reading its own write".
  Widget app(MockWorkoutSessionRepository repo) {
    return ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => _SignedInAuth(signedIn)),
        profileRepositoryProvider
            .overrideWith((_) => _ScreenedProfile(profile)),
        initialSettingsProvider.overrideWithValue(const AppSettings()),
        // Overridden to a SPECIFIC instance (`overrideWithValue`, not the
        // provider's own default `create`) so the same in-memory store
        // survives a `ProviderScope` teardown -- the fixture equivalent of
        // "still on the device after the app restarts". main.dart is the
        // only place that swaps this repository for Firestore.
        workoutSessionRepositoryProvider.overrideWithValue(repo),
      ],
      child: Consumer(
        builder: (context, ref, _) {
          final live = ref.watch(settingsControllerProvider);
          final code = live.language.localeCode;
          return MaterialApp.router(
            title: 'Fitness App',
            locale: code == null ? null : Locale(code),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: const [Locale('ru'), Locale('en')],
            theme: AppTheme.light(),
            darkTheme: AppTheme.dark(),
            themeMode: live.themeMode.material,
            routerConfig: ref.watch(appRouterProvider),
            debugShowCheckedModeBanner: false,
            builder: (context, child) =>
                AuroraBackground(child: child ?? const SizedBox.shrink()),
          );
        },
      ),
    );
  }

  Future<void> boot(WidgetTester tester, MockWorkoutSessionRepository repo) async {
    await tester.pumpWidget(app(repo));
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Tears the current widget tree down (disposing its `ProviderScope` and
  /// every provider inside it -- `workoutSessionsProvider`'s stream
  /// subscription included) and boots a genuinely new one against [repo].
  /// Nothing from the old scope is reused: this is as close to "the app was
  /// closed and reopened" as a single `testWidgets` body can get without
  /// actually restarting the OS process.
  Future<void> restart(WidgetTester tester, MockWorkoutSessionRepository repo) async {
    await tester.pumpWidget(const SizedBox.shrink());
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    await boot(tester, repo);
  }

  ProviderContainer containerOf(WidgetTester tester) =>
      ProviderScope.containerOf(
        tester.element(find.byType(AuroraBackground).first),
      );

  GoRouter routerOf(WidgetTester tester) =>
      containerOf(tester).read(appRouterProvider);

  /// Opens exercise [id] directly (no `day` query -- separate single-exercise
  /// sessions is the shape that matches what "2-3 exercises, mark them done"
  /// actually needs, and it is the shape the on-device check used), taps the
  /// real "Mark complete" button (`Key('player.markComplete')`,
  /// `workout_player_page.dart`), and answers the real post-set difficulty
  /// sheet with "Just right" -- MANDATORY here, not best-effort: this is the
  /// exact step whose silent failure the fixed bug produced, so a run where
  /// the sheet never appears must fail the test rather than quietly skip the
  /// one assertion that would catch a regression of it.
  Future<void> completeExercise(WidgetTester tester, String id) async {
    routerOf(tester).go('/workout/$id');
    for (var i = 0; i < 12; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // `SmoothScrollList` is a virtualized `ListView.builder`
    // (`shared/widgets/smooth_scroll_list.dart`) -- exactly what the manual
    // on-device check also had to swipe past: the button sits below the
    // video, muscle map and steps card and is not built until scrolled into
    // view. It is also the reshuffle that disposed `_MarkCompleteButton`'s
    // element in the bug this test guards -- the rest timer this tap starts
    // inserts a row above the button while the sheet below is still open.
    final button = find.byKey(const Key('player.markComplete'));
    await tester.scrollUntilVisible(button, 400, maxScrolls: 20);
    for (var i = 0; i < 2; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(button, findsOneWidget,
        reason: 'no Mark-complete button for $id -- likely still blocked by '
            'eligibility, which would mean the fixture profile regressed');
    await tester.tap(button);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    // Matched by the emoji rather than the localized label so a copy change
    // does not make this test fragile for an unrelated reason. Mandatory:
    // see the doc comment above.
    final rightPill = find.text('👍');
    expect(rightPill, findsOneWidget,
        reason: 'the difficulty sheet did not appear for $id -- the '
            'exercise-completion path itself changed, or the sheet regressed');
    await tester.tap(rightPill);
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  void expectSavedSessions(
    MockWorkoutSessionRepository repo,
    List<String> exerciseIds, {
    required String stage,
  }) {
    final saved = repo.cached(signedIn.uid);
    expect(saved.length, exerciseIds.length,
        reason: '[$stage] every marked exercise must produce its own saved, '
            'completed session -- fewer means a tap silently failed to save, '
            'more means a session key collided');
    for (final session in saved) {
      expect(session.status, WorkoutSessionStatus.completed, reason: stage);
      expect(session.completedAt, isNotNull, reason: stage);
      expect(session.exercises, hasLength(1), reason: stage);
      // The exact defect this file was written to catch: the difficulty
      // rating the user picked must actually be persisted, not silently
      // dropped by a disposed-element early return.
      expect(session.exercises.single.difficulty, DifficultyRating.justRight,
          reason: '[$stage] the difficulty rating did not persist for '
              '${session.exercises.single.exerciseId}');
    }
    final savedIds =
        saved.expand((s) => s.exercises).map((e) => e.exerciseId).toSet();
    expect(savedIds, exerciseIds.toSet(), reason: stage);
  }

  testWidgets(
    '2-3 exercises marked complete persist with their rating, survive a '
    'ProviderScope restart, and more can be added afterward',
    (tester) async {
      final repo = MockWorkoutSessionRepository();
      await boot(tester, repo);

      // Real, shipped, bodyweight, no-equipment exercise ids -- the exact
      // three the adaptive plan handed the operator's own test account
      // on-device (core/DECISION_LOG.md, 2026-08-28), reused here so a
      // catalog edit that removed them fails this test for the right reason
      // rather than picking arbitrary ids that happen to compile today.
      const firstBatch = [
        'ea_3_leg_chatarunga_pose',
        'ea_3_leg_dog_pose',
        'ea_3_4_sit_up',
      ];
      for (final id in firstBatch) {
        await completeExercise(tester, id);
      }
      expectSavedSessions(repo, firstBatch, stage: 'first session, live');

      final totals = await containerOf(tester)
          .read(workoutSessionTotalsProvider.future);
      expect(totals.total, firstBatch.length,
          reason: 'the totals a Progress-tab reopen would show, same scope');
      final history = containerOf(tester).read(workoutSessionHistoryProvider);
      expect(history.length, firstBatch.length);

      // "remembered ... to recalculate next time" (the operator's own ask),
      // proven properly rather than by re-reading the same live scope: tear
      // the whole widget tree down (disposing this ProviderScope and every
      // provider in it) and boot a genuinely NEW one against the SAME
      // repository instance. Nothing here re-runs the three taps above --
      // if this fresh scope shows anything other than exactly what was
      // already saved, the recovery path (not the write path) is what
      // broke.
      await restart(tester, repo);

      final totalsAfterRestart = await containerOf(tester)
          .read(workoutSessionTotalsProvider.future);
      expect(totalsAfterRestart.total, firstBatch.length,
          reason: 'a fresh ProviderScope must recover sessions a PRIOR one '
              'saved, without redoing any of the taps above');
      final historyAfterRestart =
          containerOf(tester).read(workoutSessionHistoryProvider);
      expect(historyAfterRestart.length, firstBatch.length);
      expectSavedSessions(repo, firstBatch, stage: 'after restart');

      // "add ... more workouts" (the operator's own ask): against the FRESH
      // scope, not the original one, prove totals grow from what was
      // recovered rather than resetting to zero and rebuilding from
      // scratch.
      const secondBatch = [
        'ea_4_corners_curtsy',
        'ea_4_corners_side_step',
      ];
      for (final id in secondBatch) {
        await completeExercise(tester, id);
      }
      final allIds = [...firstBatch, ...secondBatch];
      expectSavedSessions(repo, allIds, stage: 'after adding more');

      final finalTotals = await containerOf(tester)
          .read(workoutSessionTotalsProvider.future);
      expect(finalTotals.total, allIds.length,
          reason: 'totals must grow from the recovered 3, not reset to 2');
    },
  );
}
