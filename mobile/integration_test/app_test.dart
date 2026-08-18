import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show AssetManifest, rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:fitness_app/core/assets/asset_bootstrap.dart';
import 'package:fitness_app/core/router/app_router.dart';
import 'package:fitness_app/core/settings/app_settings.dart';
import 'package:fitness_app/core/settings/state/settings_providers.dart';
import 'package:fitness_app/core/theme/app_theme.dart';
import 'package:fitness_app/features/auth/data/auth_user.dart';
import 'package:fitness_app/features/auth/data/auth_repository.dart';
import 'package:fitness_app/features/auth/state/auth_providers.dart';
import 'package:fitness_app/features/data_export/backup_envelope.dart';
import 'package:fitness_app/features/equipment/widgets/muscle_map.dart';
import 'package:fitness_app/features/form_check/state/form_check_providers.dart';
import 'package:fitness_app/features/profile/data/profile_models.dart';
import 'package:fitness_app/features/profile/data/profile_repository.dart';
import 'package:fitness_app/features/profile/state/profile_providers.dart';
import 'package:fitness_app/core/camera/camera_session.dart';
import 'package:fitness_app/features/visual_equipment/data/mlkit_live_equipment_service.dart';
import 'package:fitness_app/features/visual_equipment/state/live_equipment_providers.dart';
import 'package:fitness_app/shared/widgets/aurora_background.dart';
import 'package:fitness_app/features/auth/data/sign_in_outcome.dart';

/// Real-device workflow tests.
///
/// These exist because the 574-test unit and widget suite was green while two
/// shipped features could not work on a phone at all. Neither of those failures
/// is visible off-device:
///
///   * the native ML Kit bridge rejects frames a Dart-side fake accepts, and
///   * `Image.asset` resolves through the built asset manifest, not the
///     filesystem the tests can see.
///
/// So this file drives the REAL widget tree, the REAL camera and the REAL
/// bundle. Auth and the profile are the only things faked — a sign-in would
/// need network and a Firebase provider toggle, and it is not what is under
/// test here.

/// A stream that replays [value] to EVERY listener and stays open.
///
/// `Stream.value` is single-subscription, and the router listens to
/// `authStateChanges()` twice (once directly, once inside its multi-source
/// listenable) — that threw "Stream has already been listened to" and took the
/// whole suite down.
Stream<T> _replay<T>(T value) => Stream<T>.multi((c) => c.add(value));

/// Signed-in auth, synchronously.
///
/// The router reads `authRepo.currentUser` and `profileRepo.cached(uid)`
/// DIRECTLY (app_router.dart:173-174), not the derived providers — overriding
/// `authUserProvider` alone left the app sitting on /login, which is what the
/// first run of this suite actually proved.
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

/// A profile that is already complete, so the router does not divert to
/// onboarding.
class _CompletedProfile implements ProfileRepository {
  _CompletedProfile(this.profile);
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
    uid: 'e2e-user',
    displayName: 'E2E',
    email: 'e2e@example.com',
  );

  final profile = UserProfile.empty('e2e-user').copyWith(
    personal: const PersonalInfo(
      age: 32,
      heightCm: 180,
      activityLevel: ActivityLevel.moderatelyActive,
    ),
    goals: const FitnessGoals(strength: true, muscleGain: true),
    completedAt: DateTime(2026, 1, 1),
  );

  Widget app({AppSettings settings = const AppSettings()}) {
    return ProviderScope(
      overrides: [
        // Override the REPOSITORIES, not the derived providers: the router's
        // redirect reads them synchronously.
        authRepositoryProvider.overrideWith((_) => _SignedInAuth(signedIn)),
        profileRepositoryProvider
            .overrideWith((_) => _CompletedProfile(profile)),
        initialSettingsProvider.overrideWithValue(settings),
        // The real recogniser: this is the whole point of running on a device.
        liveEquipmentServiceProvider.overrideWith((ref) {
          final svc = MlKitLiveEquipmentService(session: CameraSession());
          ref.onDispose(svc.dispose);
          return svc;
        }),
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

  /// Splash animates for ~1.5s before the redirect settles, and several tabs
  /// start streams. pumpAndSettle alone times out against a live camera, so
  /// pump in slices instead.
  Future<void> boot(WidgetTester tester, {AppSettings? settings}) async {
    await tester.pumpWidget(
      settings == null ? app() : app(settings: settings),
    );
    for (var i = 0; i < 24; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }

  /// Taps a bottom-nav tab by its visible label.
  ///
  /// Reports what IS on screen when the label is not, because the bare
  /// framework message — `Found 0 widgets with text "..."` — is the same
  /// whether the tab was renamed, the app never booted, or navigation landed
  /// somewhere else entirely. Two of this file's four stale failures were the
  /// first of those and read like the second.
  Future<void> tapTab(WidgetTester tester, String label) async {
    final tab = find.text(label);
    if (tab.evaluate().isEmpty) {
      final visible = tester
          .widgetList<Text>(find.byType(Text))
          .map((w) => w.data ?? '')
          .where((s) => s.trim().isNotEmpty)
          .toList();
      fail('no tab labelled "$label". On screen now: $visible');
    }
    await tester.tap(tab);
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }


  /// Prints every Text on screen. Kept because "found 0 widgets" tells you
  /// nothing about which screen you are actually looking at.
  void dumpTexts(WidgetTester tester, String where) {
    final texts = tester
        .widgetList<Text>(find.byType(Text))
        .map((w) => w.data ?? w.textSpan?.toPlainText() ?? '')
        .where((s) => s.trim().isNotEmpty)
        .toList();
    debugPrint('VISIBLE[$where] ${texts.length}: $texts');
  }

  setUpAll(() async {
    // Unpacks the bundled tflite model into the docs dir, exactly as main()
    // does — the live recogniser reads it by absolute path.
    await AssetBootstrap().ensureBundledAssets();
  });

  testWidgets('boots into Russian and lands on Home', (tester) async {
    await boot(tester);
    dumpTexts(tester, 'after boot');

    expect(find.text('Главная'), findsWidgets,
        reason: 'nav labels must be translated, not just body copy');

    // Was `find.text('Готовы тренироваться?')`. That string is `homeReadyToTrain`,
    // and grepping `lib/` for it returns the two .arb files and NOTHING else —
    // the home header now greets by time of day (`home_page.dart:183-186`). The
    // test was asserting a sentence the product had removed, which is why it
    // reported a boot failure for a home screen that boots fine.
    //
    // Any of the three, not one: which greeting shows depends on the clock, and
    // a test that passes only in the afternoon is a test that fails at night.
    final greeting = find.byWidgetPredicate((w) =>
        w is Text &&
        const ['Доброе утро', 'Добрый день', 'Добрый вечер'].contains(w.data));
    expect(greeting, findsWidgets,
        reason: 'the home header greets in Russian');
    // The English default would mean the locale pin regressed.
    expect(find.text('Good morning'), findsNothing);
    expect(find.text('Good afternoon'), findsNothing);
    expect(find.text('Good evening'), findsNothing);
  });

  testWidgets('every tab opens without an error widget', (tester) async {
    await boot(tester);

    // Labels come from `navScan` and friends in `app_ru.arb`. The scan tab was
    // "Распознавание" when this was written and is "Скан" now — a rename that
    // took this test and the one below down together, and looked like a boot
    // failure in the log.
    //
    // It happened again: `navWorkouts` is "Тренировки", and this list said
    // "Тренировка". The tab was there the whole time. Hard-coding a display
    // string is what keeps costing this test — the strings live in
    // `app_ru.arb:708-709` and nothing binds them to this list.
    for (final tab in ['Скан', 'Тренировки', 'Прогресс', 'Профиль']) {
      await tapTab(tester, tab);
      expect(find.byType(ErrorWidget), findsNothing, reason: 'on $tab');
      expect(tester.takeException(), isNull, reason: 'on $tab');
    }
  });

  // Device proof for the NV21 fix. On the operator's phone this surfaced as
  // "Recognition engine failed: ImageFormat is not supported." because CameraX
  // delivers YUV_420_888 and ML Kit only accepts NV21/YV12.
  testWidgets('live recognition starts without a format error', (tester) async {
    await boot(tester);
    await tapTab(tester, 'Скан');

    await tester.tap(find.byType(Switch).first);
    // Give the camera and the labeler real time to run frames.
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.textContaining('ImageFormat'), findsNothing,
        reason: 'the exact error the operator photographed');
    expect(find.textContaining('Recognition engine failed'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  // Device proof for the asset fix. Every exercise rendered "Demo unavailable"
  // because a pubspec directory entry does not recurse into subdirectories, so
  // none of the frames were packaged.
  //
  // Asserted against the bundle rather than by tapping through the UI: here
  // `rootBundle` reads the REAL installed APK, which is the thing that was
  // broken. Navigating by "tap the first InkWell" was both fragile and a weaker
  // claim.
  //
  // What it guards moved. The 132 demo photographs in `assets/exercises/` and
  // the `exercises.json` that referenced them were both deleted on 2026-08-04
  // when the clip-only rule landed, so this asserted on an asset that no longer
  // exists and failed for the most misleading possible reason: the removal was
  // deliberate. The bug class did NOT go away — `assets/posters/girl/` and
  // `assets/posters/men/` are two separate pubspec entries precisely because
  // one entry would not recurse — so the test now points at the posters.
  testWidgets('every poster the catalog names is inside the installed APK',
      (tester) async {
    final raw = await rootBundle.loadString('assets/data/exercises_vendor.json');
    final items =
        (json.decode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final paths = <String>{
      for (final e in items)
        ...((e['poster'] as Map<String, dynamic>?) ?? const {})
            .values
            .whereType<String>(),
    };
    // Not a magic number to keep in sync by hand: what matters is that the
    // catalog names posters at all. A catalog that lost the field would
    // otherwise make an empty loop below pass.
    expect(paths.length, greaterThan(2000),
        reason: 'the catalog stopped naming posters');

    // The manifest, not 2,539 individual loads. It is generated from what was
    // actually bundled, so an unrecursed directory shows up here as absence —
    // the exact failure — and it costs one read instead of one per file.
    final manifest = await AssetManifest.loadFromAssetBundle(rootBundle);
    final packaged = manifest.listAssets().toSet();
    final missing = paths.difference(packaged).toList()..sort();
    expect(missing, isEmpty, reason: 'named by the catalog, absent from the APK');

    // The manifest can only prove declaration. Load a spread of real files to
    // prove bytes arrived too — both bodies, because they are separate entries
    // and a broken one would be invisible in a same-directory sample.
    final sample = [
      ...paths.where((p) => p.contains('/girl/')).take(10),
      ...paths.where((p) => p.contains('/men/')).take(10),
    ];
    expect(sample, hasLength(20), reason: 'both bodies must be represented');
    for (final path in sample) {
      final bytes = await rootBundle.load(path);
      expect(bytes.lengthInBytes, greaterThan(0), reason: '$path is empty');
    }
  });

  testWidgets('the recognition model is inside the installed APK',
      (tester) async {
    final bytes = await rootBundle.load('assets/models/equipment_v1.tflite');
    expect(bytes.lengthInBytes, greaterThan(1000000));
  });

  // Painted directly rather than reached by navigation: the point is that the
  // CustomPainter and its Path.combine clipping survive a real Skia/Impeller
  // backend, which is not something the host-side suite exercises.
  testWidgets('the muscle map paints on a real device', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.light(),
      // The widget gained a legend, and `AppLocalizations.of(context)` returns
      // null when no delegate is installed — so this threw a null-check error
      // inside build and read as "Skia cannot paint the map", which is what the
      // test claims to be about. A bare MaterialApp is not the app.
      locale: const Locale('ru'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: const Scaffold(
        body: Center(
          child: SizedBox(
            width: 340,
            child: MuscleMap(
              primary: ['quads', 'lats'],
              secondary: ['glutes', 'core', 'calves', 'traps'],
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.byType(MuscleMap), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the settings language switch retranslates live', (tester) async {
    await boot(tester);
    // Reached directly: tab-hopping is covered above, and this test is about
    // the locale actually changing under a real engine.
    //
    // The comment here used to say the context must come from INSIDE a routed
    // page, because `AuroraBackground` sits above the Router's inherited widget
    // and `GoRouter.of()` there throws. That diagnosis was right and the remedy
    // was fragile: it anchored on a home-screen sentence, and when that sentence
    // was removed this test started failing with `Bad state: No element` — a
    // message about a missing widget, for a test about translation.
    //
    // The provider holds the same router and does not care where it is read.
    final router = ProviderScope.containerOf(
      tester.element(find.byType(AuroraBackground).first),
    ).read(appRouterProvider);
    router.push('/settings');
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.text('Оформление'), findsOneWidget);

    await tester.tap(find.byKey(const Key('settings-language-en')));
    for (var i = 0; i < 10; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }

    expect(find.text('Appearance'), findsOneWidget,
        reason: 'the switch must retranslate the live UI');
  });

  testWidgets('dark theme applies from settings', (tester) async {
    await boot(tester,
        settings: const AppSettings(themeMode: AppThemeMode.dark));

    final ctx = tester.element(find.byType(AuroraBackground).first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
  });

  /// H2b, on a device.
  ///
  /// The unit tests call `encryptBackup` directly. This one goes through the
  /// notifier, which hands the work to `compute` — a real background isolate,
  /// on real ARM/x86 silicon, at the shipped 210,000 PBKDF2 rounds. None of
  /// that exists in `flutter test`: the isolate, the cost, and whether a
  /// second of work blocks the frame are device facts.
  testWidgets('the transfer backup seals and opens on the device',
      (tester) async {
    await boot(tester);

    final sealed = await compute(
      _sealForTest,
      (payload: '{"kind":"sensitive-profile","version":1,"data":{}}',
       passphrase: 'a phrase i will remember'),
    );
    expect(sealed, isNot(contains('sensitive-profile')));
    final opened = await compute(
      _openForTest,
      (envelope: sealed, passphrase: 'a phrase i will remember'),
    );
    expect(opened, contains('sensitive-profile'));
  });

  /// Every route the app can reach, opened on the device, in one pass.
  ///
  /// The four-tab walk above covers the shell and nothing else: 28 of the 33
  /// routes in `app_router.dart` are reachable only by a deep link or a tap
  /// several screens in, and none of them had ever been opened by a test on a
  /// device. A screen that throws on a real bundle — a missing asset, a plugin
  /// that only exists on Android, a provider that reads a platform channel —
  /// looks identical to a passing widget test until someone opens it.
  ///
  /// Navigated with `go` rather than by tapping through, deliberately: the
  /// question here is "does this screen render on a phone", not "can it be
  /// reached", and a tap path would make one broken button hide every screen
  /// behind it.
  ///
  /// A screen that renders an empty state or a "not found" is a PASS. The bar
  /// is an `ErrorWidget` (Flutter's red screen) or an escaped exception —
  /// the two things a user cannot do anything about.
  testWidgets('every route in the router opens on the device', (tester) async {
    await boot(tester);
    // From the provider, NOT `GoRouter.of(context)`. `AuroraBackground` is
    // installed by `MaterialApp.router`'s `builder`, which sits ABOVE the
    // Navigator the router injects `InheritedGoRouter` into — so the lookup
    // asserts "No GoRouter found in context". The provider holds the same
    // instance and does not care where in the tree it is read from.
    final router = ProviderScope.containerOf(
      tester.element(find.byType(AuroraBackground).first),
    ).read(appRouterProvider);

    // Parameterised routes get an id that does not exist on purpose: the
    // not-found path is the one a deep link from a stale notification actually
    // hits, and it is the half nobody opens by hand.
    const routes = <String>[
      '/home', '/scan', '/workouts', '/progress', '/profile',
      '/onboarding', '/settings', '/about', '/licences', '/terms', '/privacy',
      '/injuries', '/subscription', '/donors', '/plan', '/celebrity-plans',
      '/photos', '/backup', '/community', '/contribute', '/moderate',
      '/coaches', '/posture', '/form-check', '/workout-summary',
      '/delete-account',
      '/equipment/does-not-exist',
      '/exercise/does-not-exist',
      '/workout/does-not-exist',
      '/team/does-not-exist',
    ];

    final broken = <String>[];
    for (final route in routes) {
      router.go(route);
      // Sliced rather than pumpAndSettle: several of these open a camera or a
      // stream, and settle never returns against a live one.
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      final err = tester.takeException();
      if (err != null) broken.add('$route -> $err');
      if (find.byType(ErrorWidget).evaluate().isNotEmpty) {
        broken.add('$route -> ErrorWidget on screen');
      }
      // Back to a known screen, so a route that leaves a modal or a camera
      // open cannot make the NEXT one look broken.
      router.go('/home');
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 250));
      }
      tester.takeException();
    }

    expect(broken, isEmpty,
        reason: 'routes that failed to render on the device:\n'
            '${broken.join('\n')}');
  });

  /// T1, on a device, against the catalog inside the installed APK.
  ///
  /// The tags are written by a Python pass into an asset. Whether that asset
  /// is the one the APK actually carries is exactly the class of bug this file
  /// exists for — `Image.asset` resolving through the built manifest rather
  /// than the filesystem took two features down before.
  testWidgets('the shipped catalog carries usable pose tags', (tester) async {
    await boot(tester);

    final raw = await rootBundle.loadString('assets/data/exercises_vendor.json');
    final rows = (jsonDecode(raw) as List).cast<Map<String, dynamic>>();
    final tags = <String>{
      for (final r in rows)
        if (r['poseTargetId'] != null) r['poseTargetId'] as String,
    };

    expect(tags, isNotEmpty, reason: 'the tagging pass never reached the APK');
    // Every pattern the coach offers must have BOTH authored targets and a rep
    // signal — that pairing is what `formCoachSupports` decides, and it is the
    // thing worth pinning. The membership below is not: it grew from one
    // movement to six when `rep_signals.dart` gained body-relative signals for
    // curl, overhead press, sit-up, hinge and lunge (`rep_signals.dart:214-231`),
    // and this expectation was left reading `['squat']` from before that work.
    //
    // It failed on all three targets — emulator, Galaxy S8, S23 Ultra — for
    // three sessions, which is the real cost: a suite with one permanently red
    // test is a suite whose next genuine failure looks like the usual one.
    //
    // Sorted, because a Set's iteration order is not a contract and a test that
    // encodes one fails on an unrelated day.
    final offered = tags.where(formCoachSupports).toList()..sort();
    expect(offered, [
      'curl',
      'hinge',
      'lunge',
      'overhead_press',
      'situp',
      'squat',
    ]);
    // `pushup` and `deadlift` must NOT appear, and for two different reasons —
    // the push-up has both silhouettes authored but no signal that tracks it
    // (hip-versus-knee height barely moves), the deadlift has no shape at all.
    // Both are still offered as chips; the screen says counting is off rather
    // than showing a number that cannot move.
    expect(offered, isNot(contains('pushup')));
    expect(offered, isNot(contains('deadlift')));

    final squats = rows.where((r) => r['poseTargetId'] == 'squat').toList();
    expect(squats.length, greaterThan(20));
    // The pruning that followed reading all 69 first-pass rows: side, curtsy,
    // pistol, kneeling, holds and two-movement combinations are gone.
    final titles = squats.map((r) => (r['title'] as String).toLowerCase());
    for (final bad in const [
      'side squat', 'curtsy', 'pistol', 'kneeling', 'squat hold', 'wall squat',
    ]) {
      expect(titles.where((t) => t.contains(bad)), isEmpty, reason: bad);
    }
  });
}

String _sealForTest(({String payload, String passphrase}) a) =>
    encryptBackup(plaintext: a.payload, passphrase: a.passphrase);

String _openForTest(({String envelope, String passphrase}) a) =>
    decryptBackup(envelopeJson: a.envelope, passphrase: a.passphrase);
