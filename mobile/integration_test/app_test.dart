import 'dart:convert';

import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
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
  Future<AuthUser> signInWithGoogle() async => user;

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

  Future<void> tapTab(WidgetTester tester, String label) async {
    await tester.tap(find.text(label));
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
    expect(find.text('Готовы тренироваться?'), findsOneWidget);
    // The English default would mean the locale pin regressed.
    expect(find.text('Ready to train?'), findsNothing);
  });

  testWidgets('every tab opens without an error widget', (tester) async {
    await boot(tester);

    for (final tab in ['Распознавание', 'Тренировка', 'Прогресс', 'Профиль']) {
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
    await tapTab(tester, 'Распознавание');

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
  // none of the 132 frames were packaged.
  //
  // Asserted against the bundle rather than by tapping through the UI: here
  // `rootBundle` reads the REAL installed APK, which is the thing that was
  // broken. Navigating by "tap the first InkWell" was both fragile and a weaker
  // claim.
  testWidgets('every declared demo frame is inside the installed APK',
      (tester) async {
    final raw = await rootBundle.loadString('assets/data/exercises.json');
    final items =
        (json.decode(raw) as List<dynamic>).cast<Map<String, dynamic>>();
    final paths = <String>{
      for (final e in items)
        ...(e['frames'] as List<dynamic>? ?? const []).cast<String>(),
    };
    expect(paths, hasLength(132));

    final missing = <String>[];
    for (final path in paths) {
      try {
        final bytes = await rootBundle.load(path);
        if (bytes.lengthInBytes == 0) missing.add('$path (empty)');
      } catch (_) {
        missing.add(path);
      }
    }
    expect(missing, isEmpty, reason: 'not packaged in the APK on the device');
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
    // The context has to come from INSIDE a routed page: AuroraBackground lives
    // in MaterialApp.builder, which sits above the Router's inherited widget,
    // so GoRouter.of() there throws "No GoRouter found in context".
    final ctx = tester.element(find.text('Готовы тренироваться?'));
    GoRouter.of(ctx).push('/settings');
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
    // Exactly one pattern may offer the coach today, and it must be the one
    // with authored targets AND a rep signal.
    final offered = tags.where(formCoachSupports).toList();
    expect(offered, ['squat']);

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
