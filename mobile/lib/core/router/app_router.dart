import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/data/auth_user.dart';
import '../../features/auth/login_page.dart';
import '../../features/auth/state/auth_providers.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/progress/progress_page.dart';
import '../../features/scanner/scanner_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/workouts/workouts_page.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

const _publicPaths = {'/splash', '/login'};

/// Pure redirect resolution. Exposed for tests so the routing logic can be
/// validated without spinning up the full widget tree.
String? resolveRedirect({required bool isSignedIn, required String location}) {
  if (location == '/splash') return null;
  final isPublic = _publicPaths.contains(location);
  if (!isSignedIn && !isPublic) return '/login';
  if (isSignedIn && location == '/login') return '/home';
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

/// The application router. Reads auth state via Riverpod and redirects
/// users away from gated routes when they aren't signed in.
final appRouterProvider = Provider<GoRouter>((ref) {
  final repo = ref.watch(authRepositoryProvider);
  final listenable = _StreamListenable(repo.authStateChanges());
  ref.onDispose(listenable.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/splash',
    refreshListenable: listenable,
    redirect: (context, state) => resolveRedirect(
      isSignedIn: repo.currentUser != null,
      location: state.matchedLocation,
    ),
    routes: [
      GoRoute(
        path: '/splash',
        pageBuilder: (_, __) => _fadeThrough(const SplashPage()),
      ),
      GoRoute(
        path: '/login',
        pageBuilder: (_, __) => _fadeThrough(const LoginPage()),
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
