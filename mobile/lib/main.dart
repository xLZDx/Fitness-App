import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/notifications/local_notification_service.dart';
import 'core/notifications/notification_providers.dart';
import 'core/notifications/notification_service.dart';
import 'core/router/app_router.dart';
import 'core/theme/app_theme.dart';
import 'features/auth/data/firebase_auth_repository.dart';
import 'features/auth/state/auth_providers.dart';
import 'features/profile/data/firestore_profile_repository.dart';
import 'features/profile/state/profile_providers.dart';
import 'features/subscription/data/cloud_functions_stripe_service.dart';
import 'features/subscription/data/firestore_subscription_repository.dart';
import 'features/subscription/state/subscription_providers.dart';
import 'features/workouts/data/firestore_scheduled_session_repository.dart';
import 'features/workouts/data/firestore_workout_log_repository.dart';
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

  runApp(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWith((_) => FirebaseAuthRepository()),
        profileRepositoryProvider
            .overrideWith((_) => FirestoreProfileRepository()),
        workoutLogRepositoryProvider
            .overrideWith((_) => FirestoreWorkoutLogRepository()),
        scheduledSessionRepositoryProvider
            .overrideWith((_) => FirestoreScheduledSessionRepository()),
        subscriptionRepositoryProvider
            .overrideWith((_) => FirestoreSubscriptionRepository()),
        stripeCheckoutServiceProvider
            .overrideWith((_) => CloudFunctionsStripeService()),
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
