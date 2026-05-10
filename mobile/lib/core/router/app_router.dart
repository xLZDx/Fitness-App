import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/about/about_page.dart';
import '../../features/auth/data/auth_user.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/state/auth_providers.dart';
import '../../features/donor_wall/donor_wall_page.dart';
import '../../features/equipment/equipment_detail_page.dart';
import '../../features/equipment/workout_player_page.dart';
import '../../features/home/home_page.dart';
import '../../features/onboarding/onboarding_page.dart';
import '../../features/profile/data/profile_repository.dart';
import '../../features/profile/profile_page.dart';
import '../../features/profile/state/profile_providers.dart';
import '../../features/progress/progress_page.dart';
import '../../features/scanner/scanner_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/subscription/subscription_page.dart';
import '../../features/workouts/workouts_page.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

const _publicPaths = {'/splash', '/login', '/about', '/donors'};

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
  // /equipment/:id and /workout/:id are gated but accessible without
  // onboarding so a freshly scanned QR isn't dead-ended on its way back
  // from the camera.
  final isEquipmentOrWorkout = location.startsWith('/equipment/') ||
      location.startsWith('/workout/');
  if (isSignedIn &&
      !isOnboarded &&
      location != '/onboarding' &&
      !isEquipmentOrWorkout) {
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
Stream<dynamic> _profileWatchOf(
  dynamic authRepo,
  ProfileRepository profileRepo,
) async* {
  Stream<dynamic> currentProfileStream = const Stream.empty();
  StreamSubscription<dynamic>? sub;
  await for (final user in authRepo.authStateChanges()) {
    await sub?.cancel();
    if (user == null) {
      yield null;
      currentProfileStream = const Stream.empty();
      continue;
    }
    currentProfileStream = profileRepo.watch(user.uid);
    sub = currentProfileStream.listen((p) {});
    yield* currentProfileStream;
  }
}

/// The application router. Reads auth state via Riverpod and redirects
/// users away from gated routes when they aren't signed in.
final appRouterProvider = Provider<GoRouter>((ref) {
  final authRepo = ref.watch(authRepositoryProvider);
  final profileRepo = ref.watch(profileRepositoryProvider);
  final authListenable = _StreamListenable(authRepo.authStateChanges());
  final profileListenable = _MultiSourceListenable([
    authRepo.authStateChanges(),
    _profileWatchOf(authRepo, profileRepo),
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
        path: '/donors',
        pageBuilder: (_, __) => _fadeThrough(const DonorWallPage()),
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
