import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/assets/asset_bootstrap.dart';
import 'core/health/platform_health_service.dart';
import 'core/health/state/health_providers.dart';
import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
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
import 'features/visual_equipment/data/mlkit_visual_equipment_service.dart';
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

        // Visual equipment recognition — ML Kit image labeler with
        // bundled TFLite model.
        visualEquipmentServiceProvider
            .overrideWith((_) => MlKitVisualEquipmentService()),

        // Marketplace — Stripe Connect via Cloud Functions.
        coachMarketplaceServiceProvider
            .overrideWith((_) => CloudCoachMarketplaceService()),

        // Wear OS — phone-side bridge to the watch APK.
        wearSyncServiceProvider
            .overrideWith((_) => MethodChannelWearSyncService()),

        // Nurture moments + notifications.
        momentRepositoryProvider.overrideWithValue(momentRepo),
        notificationServiceProvider.overrideWithValue(notifications),
      ],
      child: const FitnessApp(),
    ),
  );
}

class FitnessApp extends ConsumerWidget {
  const FitnessApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(appRouterProvider);
    return MaterialApp.router(
      title: 'Fitness App',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeMode.system,
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
