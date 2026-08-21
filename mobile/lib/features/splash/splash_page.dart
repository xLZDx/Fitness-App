import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/material.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_palette.dart';
import '../../core/theme/app_semantic_colors.dart';
import '../../core/theme/hud_tokens.dart' show HudMotionX;
import '../../shared/widgets/glass.dart';
import '../auth/data/auth_user.dart';
import '../auth/state/auth_providers.dart';

class SplashPage extends ConsumerStatefulWidget {
  const SplashPage({super.key});

  @override
  ConsumerState<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends ConsumerState<SplashPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );

  /// Guards the `didChangeDependencies` start below so it fires exactly once
  /// -- that callback can run again later for unrelated `MediaQuery` changes
  /// (a rotation, a text-scale change), and re-starting the entrance then
  /// would replay it over an already-settled splash screen.
  bool _entranceStarted = false;

  /// Bounds how long the splash waits for `authUserProvider`'s real first
  /// emission before proceeding anyway -- a broken/hung auth stream must not
  /// strand the user on a black splash screen forever. Local session restore
  /// is a disk/keychain read, not a network call, so this is a generous
  /// safety margin, not an expected wait.
  static const _maxAuthWait = Duration(seconds: 5);

  /// Minimum time the branded splash stays up, independent of how fast auth
  /// resolves -- this used to be the only gate; now it runs alongside the
  /// auth wait rather than instead of it.
  static const _minDwell = Duration(milliseconds: 1300);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _proceed());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    // Purely decorative logo fade/scale -- reduce motion jumps straight to
    // the settled end state (`_proceed`'s own dwell timer is unaffected, so
    // this does not change how long the splash stays up).
    if (context.reduceMotion) {
      _ctrl.value = 1;
    } else {
      _ctrl.forward();
    }
  }

  Future<void> _proceed() async {
    // The router's redirect (`app_router.dart`) reads `authRepo.currentUser`,
    // a synchronous getter with the same cold-start ambiguity
    // `authUserProvider` had before the MVP-1 provider-layer fix -- null both
    // while restoring and when genuinely signed out. A fixed timer here raced
    // that restore; waiting for the real first emission before ever leaving
    // /splash (exempt from the redirect) keeps a real signed-in user from
    // being bounced to /login mid-restore.
    //
    // Both fallback branches (an outright stream error, and the timeout)
    // proceed to /home exactly as before -- the router's own redirect still
    // makes the final signed-in/signed-out call -- but each is now logged and
    // reported rather than silently discarded: an unexpectedly-bounced
    // returning user would otherwise be indistinguishable from one who was
    // never signed in, in every piece of telemetry the app has.
    final authWait = ref.read(authUserProvider.future).then<AuthUser?>(
      (user) => user,
      onError: (Object e, StackTrace st) {
        _reportAuthWaitFailure('auth-restore stream error', e, st);
        return null;
      },
    ).timeout(_maxAuthWait, onTimeout: () {
      _reportAuthWaitFailure(
        'auth-restore wait exceeded $_maxAuthWait',
        TimeoutException('splash auth wait'),
        StackTrace.current,
      );
      return null;
    });
    await Future.wait([authWait, Future<void>.delayed(_minDwell)]);
    if (!mounted) return;
    // Hand off to /home — the router's auth-aware redirect rewrites
    // to /login when no one is signed in yet.
    context.go('/home');
  }

  /// Crashlytics itself can fail to report (not yet initialised in a test
  /// harness, a real device with reporting disabled) -- matching
  /// `main.dart`'s own "this diagnostic call might itself fail" caution, the
  /// debugPrint (the actually load-bearing signal for local debugging) never
  /// depends on it succeeding.
  void _reportAuthWaitFailure(String reason, Object error, StackTrace st) {
    debugPrint('MVP-3: $reason, proceeding to /home anyway: $error');
    try {
      FirebaseCrashlytics.instance.recordError(error, st, fatal: false);
    } catch (_) {
      // Deliberate: see doc comment above.
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic);
    final scale = Tween<double>(begin: 0.92, end: 1.0).animate(fade);

    return FrostedScaffold(
      body: Center(
        child: FadeTransition(
          opacity: fade,
          child: ScaleTransition(
            scale: scale,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _LogoOrb(),
                const SizedBox(height: 28),
                Text(
                  l10n.appTitle,
                  style:
                      Theme.of(context).textTheme.headlineMedium?.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                ),
                const SizedBox(height: 6),
                Text(
                  l10n.splashTagline,
                  style:
                      Theme.of(context).textTheme.bodyLarge?.copyWith(
                            color: context.colors.textSecondary,
                          ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LogoOrb extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 116,
      height: 116,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(36),
        // R9: first frame the app shows, moved off the pre-R9 pink/violet
        // logo mark onto the design's lime family.
        gradient: const LinearGradient(
          colors: [AppPalette.auroraLime, AppPalette.auroraLimeDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: AppPalette.auroraLime.withValues(alpha: 0.45),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: const Icon(Icons.fitness_center, size: 60, color: AppSemanticColors.onGradientInk),
    );
  }
}
