import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/auth/login_page.dart';
import '../../features/home/home_page.dart';
import '../../features/profile/profile_page.dart';
import '../../features/progress/progress_page.dart';
import '../../features/scanner/scanner_page.dart';
import '../../features/splash/splash_page.dart';
import '../../features/workouts/workouts_page.dart';
import '../../shared/widgets/main_shell.dart';

final _rootKey = GlobalKey<NavigatorState>();
final _shellKey = GlobalKey<NavigatorState>();

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

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: '/splash',
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
