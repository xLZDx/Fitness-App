import 'dart:async';


import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_page.dart';
import '../../features/account_deletion/account_deletion_page.dart';
import '../../features/legal/privacy_page.dart';
import '../../features/legal/terms_page.dart';
import '../../features/licences/licences_page.dart';
import '../../features/ai_planner/ai_planner_page.dart';
import '../../features/auth/data/auth_user.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/state/auth_providers.dart';
import '../../features/catalog/contribute_video_page.dart';
import '../../features/catalog/moderation_page.dart';
import '../../features/celebrity_plans/celebrity_plans_page.dart';
import '../../features/community/team_feed_page.dart';
import '../../features/donor_wall/donor_wall_page.dart';
import '../../features/equipment/equipment_detail_page.dart';
import '../../features/equipment/exercise_page.dart';
import '../../features/equipment/workout_player_page.dart';
import '../../features/workouts/workout_summary_page.dart';
import '../../features/form_check/form_check_page.dart';
import '../../features/home/home_page.dart';
import '../../features/marketplace/marketplace_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/data_export/backup_page.dart';
import '../../features/progress_photos/progress_photos_page.dart';
import '../../features/social_feed/social_feed_page.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/injuries_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/profile/state/profile_providers.dart';
import '../../features/progress/progress_page.dart';
import '../../features/scanner/scanner_page.dart';
import '../../features/settings/settings_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/subscription/subscription_page.dart';
import '../../features/workouts/workouts_page.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

// /licences is public: an attribution surface that requires a login is not a
// usable attribution surface.
const _publicPaths = {'/splash', '/login', '/about', '/donors', '/licences', '/terms', '/privacy'};

/// Pure redirect resolution. Exposed for tests so the routing logic can be
/// validated without spinning up the full widget tree.
String? resolveRedirect({
  required bool isSignedIn,
  required bool isOnboarded,
  required String location,
}) {
  if (location == '/splash') return null;
  final isPublic = _publicPaths.contains(location);
  if (!isSignedIn && !isPublic) return '/login';
  if (isSignedIn && location == '/login') {
    return isOnboarded ? '/home' : '/onboarding';
  }
  // /equipment/:id, /exercise/:id and /workout/:id are gated but accessible
  // without onboarding so a freshly scanned QR isn't dead-ended on its way
  // back from the camera.
  //
  // `/exercise/:id` joined this list the moment it existed (R3.2). It is the
  // route the machine page now opens, i.e. the first thing after a scan —
  // leaving it out would have bounced exactly the journey this exemption was
  // written for, and it would have looked like the scanner was broken.
  final isEquipmentOrWorkout = location.startsWith('/equipment/') ||
      location.startsWith('/exercise/') ||
      location.startsWith('/workout/');
  // A public path is public regardless of sign-in state, and this exclusion
  // is what makes that actually true rather than true-until-signed-in. Before
  // this, `/terms`/`/privacy`/`/about`/`/donors`/`/licences` were all listed
  // as public in `_publicPaths` but a signed-in, not-yet-onboarded user who
  // deep-linked to any of them was silently bounced to `/onboarding` anyway —
  // caught reviewing L0a, where it directly contradicted this file's own
  // "linked from Settings and login" claim for the new legal routes, and
  // equally true of the four routes that were already public.
  if (isSignedIn &&
      !isOnboarded &&
      location != '/onboarding' &&
      !isEquipmentOrWorkout &&
      !isPublic) {
    return '/onboarding';
  }
  if (isSignedIn && isOnboarded && location == '/onboarding') {
    return '/home';
  }
  return null;
}

CustomTransitionPage<void> _fadeThrough(Widget child) {
  return CustomTransitionPage<void>(
    child: child,
    transitionDuration: const Duration(milliseconds: 360),
    reverseTransitionDuration: const Duration(milliseconds: 240),
    transitionsBuilder: (context, animation, secondary, child) {
      final curved =
          CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
      final outgoing =
          CurvedAnimation(parent: secondary, curve: Curves.easeInCubic);
      return FadeTransition(
        opacity: curved,
        child: FadeTransition(
          opacity: ReverseAnimation(outgoing),
          child: SlideTransition(
            position: Tween<Offset>(
              begin: const Offset(0, 0.02),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}

/// Bridges a [Stream] to a [Listenable] so go_router can refresh redirects
/// whenever the source stream emits.
class _StreamListenable extends ChangeNotifier {
  _StreamListenable(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

/// Bridges multiple streams into a single [Listenable].
class _MultiSourceListenable extends ChangeNotifier {
  _MultiSourceListenable(List<Stream<dynamic>> streams) {
    for (final s in streams) {
      _subs.add(s.listen((_) => notifyListeners()));
    }
  }
  final List<StreamSubscription<dynamic>> _subs = [];

  @override
  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
    super.dispose();
  }
}

/// Lifts the active user's profile stream into a single broadcast stream that
/// keeps emitting through sign-in/sign-out cycles. Used by the router's
/// refresh listenable so `/onboarding` redirects fire when the profile
/// is created or completed.
@visibleForTesting
Stream<dynamic> profileWatchOf(
  dynamic authRepo,
  ProfileRepository profileRepo,
) {
  // Forwarded into a controller rather than delegated with `yield*`.
  //
  // The `yield*` version parked here forever. A Firestore snapshot stream
  // never completes, so delegating to it meant the `await for` over
  // `authStateChanges()` never received another event: after the first
  // sign-in, no later auth change was ever processed and the previous
  // account's profile subscription was never cancelled. Sign out and in as
  // someone else and the router kept watching the old uid — a listener that
  // then fails the security rules and retries, while the new user's profile
  // was never watched at all, so `/onboarding` redirects stopped firing for
  // them.
  //
  // It also subscribed twice to the same stream, once for `sub` and once for
  // the delegation. That part cost nothing — `cloud_firestore` builds its
  // snapshot stream on a broadcast controller whose `onListen` fires only on
  // the transition from no subscribers to one, so both Dart subscriptions
  // shared a single native listener. Worth writing down because it looks like
  // a doubled read and is not.
  late StreamController<dynamic> out;
  StreamSubscription<dynamic>? authSub;
  StreamSubscription<dynamic>? profileSub;

  Future<void> stopWatchingProfile() async {
    await profileSub?.cancel();
    profileSub = null;
  }

  out = StreamController<dynamic>.broadcast(
    onListen: () {
      authSub = authRepo.authStateChanges().listen((dynamic user) async {
        await stopWatchingProfile();
        if (user == null) {
          out.add(null);
          return;
        }
        profileSub = profileRepo.watch(user.uid as String).listen(
              out.add,
              onError: out.addError,
            );
      });
    },
    onCancel: () async {
      await authSub?.cancel();
      await stopWatchingProfile();
    },
  );
  return out.stream;
}

/// The application router. Reads auth state via Riverpod and redirects
/// users away from gated routes when they aren't signed in.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final authListenable = _StreamListenable(authRepo.authStateChanges());
  final profileListenable = _MultiSourceListenable([
    authRepo.authStateChanges(),
    profileWatchOf(authRepo, profileRepo),
  ]);
  ref.onDispose(authListenable.dispose);
  ref.onDispose(profileListenable.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: profileListenable,
    redirect: (context, state) {
      final user = authRepo.currentUser;
      final profile = user == null ? null : profileRepo.cached(user.uid);
      return resolveRedirect(
        isSignedIn: user != null,
        isOnboarded: profile?.hasCompletedOnboarding ?? false,
        location: state.matchedLocation,
      );
    },
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, __) => _fadeThrough(const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _fadeThrough(const LoginPage()),
      ),
      GoRoute(
        path: '/onboarding',
        pageBuilder: (_, __) => _fadeThrough(const OnboardingPage()),
      ),
      GoRoute(
        path: '/equipment/:id',
        pageBuilder: (_, state) => _fadeThrough(
          EquipmentDetailPage(equipmentId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/exercise/:id',
        builder: (context, state) =>
            ExercisePage(exerciseId: state.pathParameters['id']!),
      ),
      // No `:id`: the summary is of the DAY, not of one session. The app
      // writes one exercise per session (`workout_player_page.dart:265`), so a
      // per-session summary would say "1 упражнение" after every exercise —
      // see the note at the top of `day_result.dart`.
      GoRoute(
        path: '/workout-summary',
        builder: (context, state) => const WorkoutSummaryPage(),
      ),
      GoRoute(
        path: '/workout/:id',
        pageBuilder: (_, state) => _fadeThrough(
          WorkoutPlayerPage(exerciseId: state.pathParameters['id']!),
        ),
      ),
      GoRoute(
        path: '/subscription',
        pageBuilder: (_, __) => _fadeThrough(const SubscriptionPage()),
      ),
      GoRoute(
        path: '/about',
        pageBuilder: (_, __) => _fadeThrough(const AboutPage()),
      ),
      GoRoute(
        path: '/licences',
        pageBuilder: (_, __) => _fadeThrough(const LicencesPage()),
      ),
      GoRoute(
        path: '/terms',
        pageBuilder: (_, __) => _fadeThrough(const TermsPage()),
      ),
      GoRoute(
        path: '/privacy',
        pageBuilder: (_, __) => _fadeThrough(const PrivacyPage()),
      ),
      GoRoute(
        // Gated, and deliberately outside the shell: it is reached from
        // Profile and returns there, so the nav bar stays out of a form's way.
        path: '/injuries',
        pageBuilder: (_, __) => _fadeThrough(const InjuriesPage()),
      ),
      GoRoute(
        path: '/settings',
        pageBuilder: (_, __) => _fadeThrough(const SettingsPage()),
      ),
      GoRoute(
        // L0b. Reached from Settings, outside the shell for the same reason
        // /injuries is: it is a form-like flow, not a tab.
        path: '/delete-account',
        pageBuilder: (_, __) => _fadeThrough(const AccountDeletionPage()),
      ),
      GoRoute(
        path: '/donors',
        pageBuilder: (_, __) => _fadeThrough(const DonorWallPage()),
      ),
      GoRoute(
        path: '/plan',
        pageBuilder: (_, __) => _fadeThrough(const AiPlannerPage()),
      ),
      GoRoute(
        path: '/celebrity-plans',
        pageBuilder: (_, __) => _fadeThrough(const CelebrityPlansPage()),
      ),
      GoRoute(
        path: '/photos',
        pageBuilder: (_, __) => _fadeThrough(const ProgressPhotosPage()),
      ),
      GoRoute(
        path: '/backup',
        pageBuilder: (_, __) => _fadeThrough(const BackupPage()),
      ),
      GoRoute(
        path: '/community',
        pageBuilder: (_, __) => _fadeThrough(const SocialFeedPage()),
      ),
      GoRoute(
        path: '/team/:teamId',
        pageBuilder: (_, state) => _fadeThrough(
          TeamFeedPage(teamId: state.pathParameters['teamId']!),
        ),
      ),
      GoRoute(
        path: '/form-check',
        pageBuilder: (_, __) => _fadeThrough(const FormCheckPage()),
      ),
      GoRoute(
        path: '/contribute',
        pageBuilder: (_, __) => _fadeThrough(const ContributeVideoPage()),
      ),
      GoRoute(
        path: '/moderate',
        pageBuilder: (_, __) => _fadeThrough(const CatalogModerationPage()),
      ),
      GoRoute(
        path: '/coaches',
        pageBuilder: (_, __) => _fadeThrough(const MarketplacePage()),
      ),
      ShellRoute(
        navigatorKey: _shellKey,
        builder: (context, state, child) => MainShell(child: child),
        routes: [
          GoRoute(
            path: '/home',
            pageBuilder: (_, __) => _fadeThrough(const HomePage()),
          ),
          GoRoute(
            path: '/scan',
            pageBuilder: (_, __) => _fadeThrough(const ScannerPage()),
          ),
          GoRoute(
            path: '/workouts',
            pageBuilder: (_, __) => _fadeThrough(const WorkoutsPage()),
          ),
          GoRoute(
            path: '/progress',
            pageBuilder: (_, __) => _fadeThrough(const ProgressPage()),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (_, __) => _fadeThrough(const ProfilePage()),
          ),
        ],
      ),
    ],
  );
});

// Compatibility export so existing tests that imported the top-level
// `appRouter` keep working — they rebuild a fresh router via the provider.
GoRouter get appRouter => _legacyContainer.read(appRouterProvider);
final _legacyContainer = ProviderContainer();

/// Used to route the auth user type without forcing every consumer to
/// pull in the full provider file.
typedef AuthSnapshot = AuthUser?;
