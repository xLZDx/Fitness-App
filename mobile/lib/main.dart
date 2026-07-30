import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/assets/asset_bootstrap.dart';
import 'core/health/platform_health_service.dart';
import 'core/health/state/health_providers.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
// Imported for the AppThemeModeX / AppLanguageX extensions used below —
// extension methods are only visible where their library is imported.
import 'core/settings/app_settings.dart';
import 'core/settings/settings_repository.dart';
import 'core/settings/state/settings_providers.dart';
import 'core/theme/app_theme.dart';
import 'core/wear/state/wear_providers.dart';
import 'core/wear/wear_sync_service.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/auth/state/auth_providers.dart';
import 'features/donor_wall/data/cloud_donor_wall_repository.dart';
import 'features/donor_wall/state/donor_wall_providers.dart';
import 'features/equipment/data/cloud_functions_equipment_report_service.dart';
import 'features/equipment/state/equipment_providers.dart';
import 'features/form_check/data/mlkit_pose_detector_service.dart';
import 'features/form_check/data/tts_voice_coach.dart';
import 'features/form_check/state/form_check_providers.dart';
import 'features/marketplace/data/coach_marketplace_service.dart';
import 'features/marketplace/state/marketplace_providers.dart';
import 'features/moments/data/prefs_moment_repository.dart';
import 'features/moments/state/moment_providers.dart';
import 'features/profile/data/firestore_profile_repository.dart';
import 'features/profile/state/profile_providers.dart';
import 'features/subscription/data/cloud_functions_stripe_service.dart';
import 'features/subscription/data/firestore_subscription_repository.dart';
import 'features/subscription/state/subscription_providers.dart';
import 'features/visual_equipment/data/firestore_recognition_history.dart';
import 'features/visual_equipment/data/mlkit_live_equipment_service.dart';
import 'features/visual_equipment/data/mlkit_visual_equipment_service.dart';
import 'features/visual_equipment/state/live_equipment_providers.dart';
import 'features/visual_equipment/state/recognition_history_providers.dart';
import 'features/visual_equipment/state/visual_equipment_providers.dart';
import 'features/workouts/data/firestore_scheduled_session_repository.dart';
import 'features/workouts/data/firestore_workout_log_repository.dart';
import 'features/workouts/data/offline_video_cache.dart';
import 'features/workouts/state/offline_video_providers.dart';
import 'features/workouts/state/scheduled_session_providers.dart';
import 'features/workouts/state/workout_log_providers.dart';
import 'firebase_options.dart';
import 'shared/widgets/aurora_background.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Warm up notifications + request permissions once on launch. We keep a
  // single instance and inject it into Riverpod so reminders are de-duped
  // and cancellable across restarts.
  final NotificationService notifications = LocalNotificationService();
  await notifications.init();

  // Open SharedPreferences-backed nurture-moments repository up-front so
  // the first cold-start launch counts.
  final momentRepo = await PrefsMomentRepository.open();

  // Settings must be resolved BEFORE the first frame: theme and locale are
  // read during the initial build, and loading them asynchronously would
  // flash the wrong theme and the wrong language before settling.
  final settingsRepo = await PrefsSettingsRepository.open();
  final settings = await settingsRepo.load();

  // Copy any bundled ML models out of the APK into the docs dir so
  // ML Kit's LocalLabelerOptions can read them by absolute path.
  await AssetBootstrap().ensureBundledAssets();

  runApp(
    ProviderScope(
      overrides: [
        // Auth + profile + subscriptions
        authRepositoryProvider.overrideWith((_) => FirebaseAuthRepository()),
        profileRepositoryProvider
            .overrideWith((_) => FirestoreProfileRepository()),
        subscriptionRepositoryProvider
            .overrideWith((_) => FirestoreSubscriptionRepository()),
        stripeCheckoutServiceProvider
            .overrideWith((_) => CloudFunctionsStripeService()),

        // Workouts
        workoutLogRepositoryProvider
            .overrideWith((_) => FirestoreWorkoutLogRepository()),
        scheduledSessionRepositoryProvider
            .overrideWith((_) => FirestoreScheduledSessionRepository()),
        offlineVideoCacheProvider
            .overrideWith((_) => FileOfflineVideoCache()),

        // Equipment
        equipmentReportServiceProvider
            .overrideWith((_) => CloudFunctionsEquipmentReportService()),

        // Donor wall (server-side write via Cloud Function)
        donorWallRepositoryProvider
            .overrideWith((_) => CloudDonorWallRepository()),

        // Health Connect (Android) / HealthKit (iOS) — falls back to
        // unsupported gracefully on web/desktop.
        healthServiceProvider
            .overrideWith((_) => PlatformHealthService()),

        // Form check — bind ML Kit pose detector. The page calls
        // start()/stop() in initState/dispose; defaults to mock for
        // tests so widget tests don't need a real camera.
        poseDetectorServiceProvider
            .overrideWith((_) => MlKitPoseDetectorService()),

        // Spoken form cues. Defaults to MockVoiceCoach so widget tests never
        // open a TTS MethodChannel; the throttling policy is identical in
        // both, it lives in the shared CueGate.
        voiceCoachProvider.overrideWith((ref) {
          final coach = TtsVoiceCoach();
          ref.onDispose(() => coach.dispose());
          return coach;
        }),

        // Visual equipment recognition — ML Kit image labeler with
        // bundled TFLite model.
        visualEquipmentServiceProvider
            .overrideWith((_) => MlKitVisualEquipmentService()),

        // Live (continuous) recognition. Same model, camera stream instead
        // of a single shot; the service holds the camera only while the
        // Scan tab's Live switch is on.
        liveEquipmentServiceProvider.overrideWith((ref) {
          final svc = MlKitLiveEquipmentService();
          ref.onDispose(svc.dispose);
          return svc;
        }),

        // Every machine the user identifies is remembered (one row per
        // machine, newest sighting wins).
        recognitionHistoryRepositoryProvider
            .overrideWith((_) => FirestoreRecognitionHistoryRepository()),

        // Marketplace — Stripe Connect via Cloud Functions.
        coachMarketplaceServiceProvider
            .overrideWith((_) => CloudCoachMarketplaceService()),

        // Wear OS — phone-side bridge to the watch APK.
        wearSyncServiceProvider
            .overrideWith((_) => MethodChannelWearSyncService()),

        // Nurture moments + notifications.
        momentRepositoryProvider.overrideWithValue(momentRepo),
        notificationServiceProvider.overrideWithValue(notifications),

        // Device preferences (theme, language, reminders).
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        initialSettingsProvider.overrideWithValue(settings),
      ],
      child: const FitnessApp(),
    ),
  );
}

class FitnessApp extends ConsumerStatefulWidget {
  const FitnessApp({super.key});

  @override
  ConsumerState<FitnessApp> createState() => _FitnessAppState();
}

/// Stateful only to observe [didChangeLocales].
///
/// Without it, changing the device language while the app is running would move
/// the interface but not the bundled exercise text, because the content side
/// reads a cached device-locale list. That is the same half-translated failure
/// `resolvedLocaleCode` exists to prevent, just triggered at runtime.
class _FitnessAppState extends ConsumerState<FitnessApp>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeLocales(List<Locale>? locales) {
    ref.read(deviceLocalesProvider.notifier).state =
        List<Locale>.unmodifiable(locales ?? const <Locale>[]);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final settings = ref.watch(settingsControllerProvider);
    // Resolved, never nullable: one source of truth shared with the exercise
    // catalog. Passing `null` here would hand resolution to Flutter alone and
    // leave the content layer guessing what it decided.
    final localeCode = ref.watch(effectiveLanguageCodeProvider);
    return MaterialApp.router(
      // NOT localised, on purpose twice over: it is the brand name, and
      // this widget builds the MaterialApp, so there is no Localizations
      // ancestor here yet — AppLocalizations.of(context) returns null and
      // the non-nullable getter crashes on launch. Use onGenerateTitle if a
      // translated title is ever wanted.
      title: 'Fitness App',
      // Russian is the product default (the launch market is RU/CIS), but the
      // user can override it in Settings; "system" is resolved against the
      // device locales by `effectiveLanguageCodeProvider`.
      locale: Locale(localeCode),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales:
          kSupportedLocaleCodes.map((c) => Locale(c)).toList(growable: false),
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: settings.themeMode.material,
      routerConfig: router,
      debugShowCheckedModeBanner: false,
      scrollBehavior: const _GlassScrollBehavior(),
      builder: (context, child) =>
          AuroraBackground(child: child ?? const SizedBox.shrink()),
    );
  }
}

class _GlassScrollBehavior extends ScrollBehavior {
  const _GlassScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) =>
      const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics());

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) =>
      child;
}
